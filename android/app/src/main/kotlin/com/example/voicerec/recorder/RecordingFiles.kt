package com.example.voicerec.recorder

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Storage for recordings in app-specific storage (no storage permission needed).
 *
 * Audio is captured as raw AAC/ADTS (`.aac`), which stays playable even if the
 * process is killed mid-recording. On stop it is remuxed, without re-encoding,
 * into an `.m4a` container. A leftover `.aac` means the recording was
 * interrupted; [recoverInterrupted] converts it on the next listing.
 */
object RecordingFiles {
    private const val TAG = "RecordingFiles"
    private const val RAW_EXTENSION = "aac"
    private const val FINAL_EXTENSION = "m4a"
    private const val MIN_FREE_BYTES = 20L * 1024 * 1024

    /** Serializes all file work so finalizing and listing never touch a file at once. */
    val io: ExecutorService = Executors.newSingleThreadExecutor()

    fun dir(context: Context): File = File(context.filesDir, "recordings").apply { mkdirs() }

    /** Unnamed captures survive process restarts without appearing in the library. */
    fun draftsDir(context: Context): File = File(context.filesDir, "recording_drafts").apply { mkdirs() }

    fun hasFreeSpace(context: Context): Boolean = dir(context).usableSpace >= MIN_FREE_BYTES

    fun newRawFile(context: Context, startedAt: Long): File = newRawFile(draftsDir(context), startedAt)

    internal fun newRawFile(directory: File, startedAt: Long): File {
        val base = SimpleDateFormat("'rec_'yyyyMMdd", Locale.US).format(Date(startedAt))
        var file = File(directory, "$base.$RAW_EXTENSION")
        var suffix = 1
        while (file.exists() || File(directory, "${file.nameWithoutExtension}.$FINAL_EXTENSION").exists()) {
            file = File(directory, "${base}_${suffix++}.$RAW_EXTENSION")
        }
        return file
    }

    /**
     * Converts [raw] to `.m4a` and deletes it. Keeps the `.aac` if conversion
     * fails, so no audio is lost. Call on [io].
     */
    fun finalize(raw: File) {
        if (!raw.exists()) return
        if (raw.length() == 0L) {
            raw.delete()
            return
        }
        val target = File(raw.parentFile, "${raw.nameWithoutExtension}.$FINAL_EXTENSION")
        try {
            remux(raw, target)
            raw.delete()
        } catch (e: Exception) {
            Log.e(TAG, "Could not convert ${raw.name}; keeping the .aac file", e)
            target.delete()
        }

    }

    /** Finalizes `.aac` files left behind by a killed recording. Call on [io]. */
    fun recoverInterrupted(context: Context, activePath: String?) {
        recoverInterrupted(dir(context), activePath)
    }

    private fun recoverInterrupted(directory: File, activePath: String?) {
        directory.listFiles()
            ?.filter { it.extension == RAW_EXTENSION && it.absolutePath != activePath }
            ?.forEach {
                Log.i(TAG, "Recovering interrupted recording ${it.name}")
                finalize(it)
            }
    }

    /** Restores unfinished draft containers while leaving a live capture alone. Call on [io]. */
    fun listDrafts(context: Context, activePath: String?): List<Map<String, Any?>> {
        val directory = draftsDir(context)
        recoverInterrupted(directory, activePath)
        return list(directory, activePath, includeDuration = true).filter { draft ->
            val path = draft["path"] as String
            return@filter !isActiveDraft(path, activePath)
        }
    }

    internal fun isActiveDraft(path: String, activePath: String?): Boolean {
        if (activePath == null) return false
        val file = File(path).canonicalFile
        val active = File(activePath).canonicalFile
        // Finalization changes the suffix before the service posts its idle event.
        return file.parentFile == active.parentFile &&
            file.nameWithoutExtension == active.nameWithoutExtension
    }

    /** Moves a draft only after the user names it, restoring it if catalog persistence fails. */
    internal fun <T> saveDraft(
        draftsDirectory: File,
        savedDirectory: File,
        path: String,
        title: String,
        register: (File, String) -> T,
    ): T {
        val source = validateDraft(draftsDirectory, path)
        require(source.isFile) { "The recording draft was not found." }
        val safeTitle = sanitizeTitle(title)
        require(savedDirectory.isDirectory || savedDirectory.mkdirs()) {
            "Could not create the recordings folder."
        }
        var target = File(savedDirectory, "$safeTitle.${source.extension}")
        var suffix = 1
        while (target.exists()) {
            target = File(savedDirectory, "$safeTitle (${suffix++}).${source.extension}")
        }
        check(source.renameTo(target)) { "Could not save the recording. Please try again." }
        try {
            return register(target, safeTitle)
        } catch (error: Exception) {
            if (!target.renameTo(source)) {
                throw IllegalStateException(
                    "The recording is safe, but its library entry could not be updated. Please reopen the app.",
                    error,
                )
            }
            throw error
        }
    }

    internal fun discardDraft(draftsDirectory: File, path: String) {
        val file = validateDraft(draftsDirectory, path)
        check(!file.exists() || file.delete()) { "Could not discard the recording. Please try again." }
    }

    private fun validateDraft(draftsDirectory: File, path: String): File {
        val file = File(path).canonicalFile
        require(file.parentFile == draftsDirectory.canonicalFile &&
            file.extension.lowercase(Locale.US) in setOf(RAW_EXTENSION, FINAL_EXTENSION)
        ) { "Choose a recording draft from this app." }
        require(!file.isDirectory) { "The recording draft was not found." }
        return file
    }

    private fun sanitizeTitle(title: String): String {
        val cleaned = title.trim()
            .replace(Regex("[/\\\\\\u0000-\\u001F]"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()
        require(cleaned.isNotEmpty()) { "Enter a file name." }
        val count = minOf(cleaned.codePointCount(0, cleaned.length), 80)
        return cleaned.substring(0, cleaned.offsetByCodePoints(0, count))
    }

    /** Saved recordings, newest first, excluding [activePath]. Call on [io]. */
    fun list(
        context: Context,
        activePath: String?,
        includeDuration: Boolean = true,
    ): List<Map<String, Any?>> = list(dir(context), activePath, includeDuration)

    private fun list(
        directory: File,
        activePath: String?,
        includeDuration: Boolean,
    ): List<Map<String, Any?>> =
        directory.listFiles()
            .orEmpty()
            .filter { it.isFile && it.absolutePath != activePath }
            .filter { it.extension == FINAL_EXTENSION || it.extension == RAW_EXTENSION }
            .sortedByDescending { it.lastModified() }
            .map { file ->
                mapOf(
                    "path" to file.absolutePath,
                    "sizeBytes" to file.length(),
                    "modifiedAtMillis" to file.lastModified(),
                    "durationMillis" to if (includeDuration) durationMillis(file) else null,
                )
            }

    fun durationMillis(file: File): Long? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
        } catch (e: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    /** Writes the selected audio segment to a new M4A file without changing the source. */
    fun trim(context: Context, source: File, startMillis: Long, endMillis: Long): File {
        require(source.isFile) { "Recording file was not found." }
        require(startMillis >= 0 && endMillis > startMillis) { "Choose a valid audio range." }
        val directory = dir(context)
        val base = "${source.nameWithoutExtension}_edited"
        var target = File(directory, "$base.$FINAL_EXTENSION")
        var suffix = 1
        while (target.exists()) target = File(directory, "${base}_${suffix++}.$FINAL_EXTENSION")

        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        try {
            extractor.setDataSource(source.absolutePath)
            val inputTrack = (0 until extractor.trackCount).first {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            }
            extractor.selectTrack(inputTrack)
            val startUs = startMillis * 1_000
            val endUs = endMillis * 1_000
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            muxer = MediaMuxer(target.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val outputTrack = muxer.addTrack(extractor.getTrackFormat(inputTrack))
            muxer.start()
            val buffer = ByteBuffer.allocate(256 * 1024)
            val info = MediaCodec.BufferInfo()
            var firstSampleUs = -1L
            var samples = 0
            while (true) {
                val sampleUs = extractor.sampleTime
                if (sampleUs < 0 || sampleUs > endUs) break
                if (sampleUs >= startUs) {
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) break
                    if (firstSampleUs < 0) firstSampleUs = sampleUs
                    info.set(0, size, sampleUs - firstSampleUs, MediaCodec.BUFFER_FLAG_KEY_FRAME)
                    muxer.writeSampleData(outputTrack, buffer, info)
                    samples++
                }
                extractor.advance()
            }
            check(samples > 0) { "No audio found in the selected range." }
            muxer.stop()
            target.setLastModified(System.currentTimeMillis())
            return target
        } catch (e: Exception) {
            target.delete()
            throw e
        } finally {
            muxer?.release()
            extractor.release()
        }
    }

    /** Copies the AAC samples from an ADTS stream into an MP4 container. */
    private fun remux(source: File, target: File) {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        try {
            extractor.setDataSource(source.absolutePath)
            val track = (0 until extractor.trackCount).first {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            }
            extractor.selectTrack(track)

            muxer = MediaMuxer(target.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val outTrack = muxer.addTrack(extractor.getTrackFormat(track))
            muxer.start()

            val buffer = ByteBuffer.allocate(256 * 1024)
            val info = MediaCodec.BufferInfo()
            var samples = 0
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                info.set(0, size, extractor.sampleTime, MediaCodec.BUFFER_FLAG_KEY_FRAME)
                muxer.writeSampleData(outTrack, buffer, info)
                samples++
                extractor.advance()
            }
            check(samples > 0) { "No audio samples in ${source.name}" }
            muxer.stop()
        } finally {
            muxer?.release()
            extractor.release()
        }
    }
}
