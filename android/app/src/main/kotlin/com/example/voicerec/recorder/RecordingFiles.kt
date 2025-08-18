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

    fun hasFreeSpace(context: Context): Boolean = dir(context).usableSpace >= MIN_FREE_BYTES

    fun newRawFile(context: Context, startedAt: Long): File {
        val base = SimpleDateFormat("'rec_'yyyyMMdd_HHmmss", Locale.US).format(Date(startedAt))
        val dir = dir(context)
        var file = File(dir, "$base.$RAW_EXTENSION")
        var suffix = 1
        while (file.exists() || File(dir, "$base.$FINAL_EXTENSION").exists()) {
            file = File(dir, "${base}_${suffix++}.$RAW_EXTENSION")
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
        dir(context).listFiles()
            ?.filter { it.extension == RAW_EXTENSION && it.absolutePath != activePath }
            ?.forEach {
                Log.i(TAG, "Recovering interrupted recording ${it.name}")
                finalize(it)
            }
    }

    /** Saved recordings, newest first, excluding [activePath]. Call on [io]. */
    fun list(context: Context, activePath: String?): List<Map<String, Any?>> =
        dir(context).listFiles()
            .orEmpty()
            .filter { it.isFile && it.absolutePath != activePath }
            .filter { it.extension == FINAL_EXTENSION || it.extension == RAW_EXTENSION }
            .sortedByDescending { it.lastModified() }
            .map { file ->
                mapOf(
                    "path" to file.absolutePath,
                    "sizeBytes" to file.length(),
                    "modifiedAtMillis" to file.lastModified(),
                    "durationMillis" to durationMillis(file),
                    "kind" to "recording",
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
