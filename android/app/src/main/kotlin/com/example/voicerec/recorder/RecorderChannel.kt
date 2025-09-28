package com.example.voicerec.recorder

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.audiofx.Equalizer
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Bridge between Flutter and [RecordingService].
 *
 * - Method channel: `startRecording`, `pauseRecording`, `resumeRecording`,
 *   `stopRecording`, `getRecordingState`, `listRecordings`, `listDraftRecordings`,
 *   `saveRecording`, `discardDraftRecording`, `deleteRecording`.
 * - Event channel: streams [RecorderState] maps, starting with the current state.
 *
 * Only the UI depends on this class; the service records without it.
 */
class RecorderChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val libraryDatabase = RecordingLibraryDatabase(activity.applicationContext)

    /** Result of a `startRecording` call that is waiting for the permission dialog. */
    private var pendingStart: MethodChannel.Result? = null
    private var player: MediaPlayer? = null
    private var equalizer: Equalizer? = null
    private var equalizerGains = listOf(0.0, 0.0, 0.0)

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        // If the process was killed mid-recording, the task may still be hidden.
        if (!RecordingService.state.isActive) RecentsVisibility.setHidden(activity, false)
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        RecordingService.listener = null
        releasePlayer()
        pendingStart = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startRecording" -> start(result)
            "pauseRecording" -> {
                RecordingService.pause(activity)
                result.success(null)
            }
            "resumeRecording" -> {
                RecordingService.resume(activity)
                result.success(null)
            }
            "stopRecording" -> {
                RecordingService.stop(activity)
                result.success(null)
            }
            "readPeakAmplitude" -> result.success(RecordingService.readPeakAmplitude())
            "playRecording" -> playRecording(call.argument<String>("path"), result)
            "pausePlayback" -> {
                player?.takeIf { it.isPlaying }?.pause()
                result.success(null)
            }
            "resumePlayback" -> {
                player?.let { active ->
                    if (!active.isPlaying) {
                        if (active.currentPosition >= active.duration) active.seekTo(0)
                        active.start()
                    }
                }
                result.success(null)
            }
            "seekPlayback" -> {
                val position = call.argument<Int>("positionMillis") ?: 0
                player?.seekTo(position.coerceAtLeast(0))
                result.success(null)
            }
            "getPlaybackState" -> result.success(playbackState())
            "getRecordingWaveform" -> getRecordingWaveform(call, result)
            "setPlaybackEqualizer" -> setPlaybackEqualizer(call, result)
            "stopPlayback" -> {
                releasePlayer()
                result.success(null)
            }
            "getRecordingState" -> result.success(RecordingService.state.toMap())
            "listRecordings" -> listRecordings(result)
            "listLibraryRecordings" -> listLibraryRecordings(result)
            "listDraftRecordings" -> listDraftRecordings(result)
            "saveRecording" -> saveRecording(call, result)
            "discardDraftRecording" -> discardDraftRecording(call, result)
            "updateRecordingPath" -> updateRecordingPath(call, result)
            "trimRecording" -> trimRecording(call, result)
            "deleteRecording" -> deleteRecording(call.argument<String>("path"), result)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        RecordingService.listener = { events.success(it.toMap()) }
        events.success(RecordingService.state.toMap())
    }

    override fun onCancel(arguments: Any?) {
        RecordingService.listener = null
    }

    fun onRequestPermissionsResult(requestCode: Int) {
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val result = pendingStart ?: return
        pendingStart = null

        if (isGranted(Manifest.permission.RECORD_AUDIO)) {
            RecordingService.start(activity)
            result.success(null)
        } else {
            result.error("PERMISSION_DENIED", "Microphone permission is required to record.", null)
        }
    }

    private fun start(result: MethodChannel.Result) {
        if (pendingStart != null) {
            result.error("BUSY", "Already waiting for permission.", null)
            return
        }

        val missing = requiredPermissions().filterNot(::isGranted)
        if (missing.isEmpty()) {
            RecordingService.start(activity)
            result.success(null)
            return
        }

        pendingStart = result
        activity.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    /**
     * Recovers interrupted recordings, then lists saved recordings off the main thread.
     */
    private fun listRecordings(result: MethodChannel.Result) {
        loadLibrary(result, includeDeleted = false, includeUnavailable = false)
    }

    private fun listLibraryRecordings(result: MethodChannel.Result) {
        loadLibrary(result, includeDeleted = true, includeUnavailable = true)
    }

    private fun listDraftRecordings(result: MethodChannel.Result) {
        val context = activity.applicationContext
        RecordingFiles.io.execute {
            try {
                val state = RecordingService.state
                val activePath = if (state.isActive) state.filePath else null
                val drafts = RecordingFiles.listDrafts(context, activePath)
                activity.runOnUiThread { result.success(drafts) }
            } catch (error: Exception) {
                activity.runOnUiThread { result.error("DRAFT_LIST_FAILED", error.message, null) }
            }
        }
    }

    private fun saveRecording(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val title = call.argument<String>("title")
        if (path == null || title == null) {
            result.error("BAD_ARGS", "Missing recording draft or file name.", null)
            return
        }
        val context = activity.applicationContext
        RecordingFiles.io.execute {
            try {
                checkDraftIsInactive(path)
                val saved = RecordingFiles.saveDraft(
                    RecordingFiles.draftsDir(context),
                    RecordingFiles.dir(context),
                    path,
                    title,
                ) { file, safeTitle ->
                    libraryDatabase.registerSavedDraft(path, file.absolutePath, safeTitle)
                }
                activity.runOnUiThread { result.success(saved) }
            } catch (error: Exception) {
                activity.runOnUiThread { result.error("SAVE_FAILED", error.message, null) }
            }
        }
    }

    private fun discardDraftRecording(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("BAD_ARGS", "Missing recording draft.", null)
            return
        }
        val context = activity.applicationContext
        RecordingFiles.io.execute {
            try {
                checkDraftIsInactive(path)
                RecordingFiles.discardDraft(RecordingFiles.draftsDir(context), path)
                activity.runOnUiThread { result.success(null) }
            } catch (error: Exception) {
                activity.runOnUiThread { result.error("DISCARD_FAILED", error.message, null) }
            }
        }
    }

    private fun checkDraftIsInactive(path: String) {
        val state = RecordingService.state
        check(!state.isActive || !RecordingFiles.isActiveDraft(path, state.filePath)) {
            "Stop the recording before saving or discarding it."
        }
    }

    private fun loadLibrary(
        result: MethodChannel.Result,
        includeDeleted: Boolean,
        includeUnavailable: Boolean,
    ) {
        val context = activity.applicationContext
        RecordingFiles.io.execute {
            val state = RecordingService.state
            val activePath = if (state.isActive) state.filePath else null
            val recordings = try {
                RecordingFiles.recoverInterrupted(context, activePath)
                val files = RecordingFiles.list(
                    context,
                    activePath,
                    includeDuration = false,
                )
                libraryDatabase.synchronize(files).filter { recording ->
                    (includeDeleted || recording["deletedAtMillis"] == null) &&
                        (includeUnavailable || recording["audioAvailable"] == true)
                }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("LIST_FAILED", e.message, null) }
                return@execute
            }
            activity.runOnUiThread { result.success(recordings) }
        }
    }

    private fun updateRecordingPath(call: MethodCall, result: MethodChannel.Result) {
        val oldPath = call.argument<String>("oldPath")
        val newPath = call.argument<String>("newPath")
        val title = call.argument<String>("title")
        if (oldPath == null || newPath == null || title == null) {
            result.error("BAD_ARGS", "Missing recording path or title", null)
            return
        }
        RecordingFiles.io.execute {
            try {
                libraryDatabase.updateFilePath(oldPath, newPath, title)
                activity.runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    result.error("METADATA_UPDATE_FAILED", e.message, null)
                }
            }
        }
    }

    private fun trimRecording(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val startMillis = call.argument<Number>("startMillis")?.toLong()
        val endMillis = call.argument<Number>("endMillis")?.toLong()
        if (path == null || startMillis == null || endMillis == null) {
            result.error("BAD_ARGS", "Missing recording range", null)
            return
        }
        RecordingFiles.io.execute {
            try {
                val edited = RecordingFiles.trim(
                    activity.applicationContext,
                    File(path),
                    startMillis,
                    endMillis,
                )
                activity.runOnUiThread { result.success(edited.absolutePath) }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    result.error("EDIT_FAILED", e.message ?: "Could not edit recording.", null)
                }
            }
        }
    }

    private fun getRecordingWaveform(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("BAD_ARGS", "Missing recording path", null)
            return
        }
        val sampleCount = (call.argument<Number>("sampleCount")?.toInt() ?: 160)
            .coerceIn(32, 512)
        RecordingFiles.io.execute {
            try {
                val waveform = RecordingWaveform.extract(File(path), sampleCount)
                activity.runOnUiThread { result.success(waveform) }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    result.error(
                        "WAVEFORM_FAILED",
                        e.message ?: "Could not read the recording waveform.",
                        null,
                    )
                }
            }
        }
    }

    /** Deletes a saved recording at the user's request. */
    private fun deleteRecording(path: String?, result: MethodChannel.Result) {
        if (path == null) {
            result.error("BAD_ARGS", "Missing path", null)
            return
        }
        RecordingFiles.io.execute {
            try {
                val file = File(path)
                val deleted = !file.exists() || file.delete()
                if (!deleted) {
                    activity.runOnUiThread {
                        result.error("DELETE_FAILED", "Could not delete file", null)
                    }
                    return@execute
                }
                libraryDatabase.removeByPath(path)
                activity.runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    result.error("DELETE_FAILED", e.message, null)
                }
            }
        }
    }

    private fun playRecording(path: String?, result: MethodChannel.Result) {
        if (path == null || !File(path).isFile) {
            result.error("PLAYBACK_FAILED", "Recording file was not found.", null)
            return
        }
        releasePlayer()
        try {
            val mediaPlayer = MediaPlayer()
            player = mediaPlayer
            mediaPlayer.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            mediaPlayer.setDataSource(path)
            mediaPlayer.setOnPreparedListener { prepared ->
                if (player !== prepared) {
                    prepared.release()
                    return@setOnPreparedListener
                }
                try {
                    // EQ is optional on some devices; never prevent playback if
                    // the platform audio effect cannot be created.
                    runCatching { attachEqualizer(prepared.audioSessionId) }
                    prepared.start()
                    result.success(null)
                } catch (_: IllegalStateException) {
                    result.error("PLAYBACK_FAILED", "Could not start playback.", null)
                }
            }
            mediaPlayer.setOnErrorListener { failed, what, extra ->
                if (player === failed) player = null
                failed.release()
                result.error("PLAYBACK_FAILED", "Could not play this recording.", mapOf("what" to what, "extra" to extra))
                true
            }
            mediaPlayer.setOnCompletionListener { completed -> completed.seekTo(0) }
            mediaPlayer.prepareAsync()
        } catch (e: Exception) {
            releasePlayer()
            result.error("PLAYBACK_FAILED", e.message ?: "Could not play this recording.", null)
        }
    }

    private fun setPlaybackEqualizer(call: MethodCall, result: MethodChannel.Result) {
        val gains = call.argument<List<Number>>("gains")
        if (gains == null || gains.size != 3) {
            result.error("BAD_ARGS", "Expected three equalizer values.", null)
            return
        }
        equalizerGains = gains.map { it.toDouble().coerceIn(-1.0, 1.0) }
        val active = player
        if (active != null) {
            try {
                attachEqualizer(active.audioSessionId)
            } catch (e: Exception) {
                result.error("EFFECT_UNAVAILABLE", "Audio effects are not available on this device.", null)
                return
            }
        }
        result.success(null)
    }

    private fun attachEqualizer(sessionId: Int) {
        val effect = equalizer ?: Equalizer(0, sessionId).also { equalizer = it }
        effect.enabled = true
        val bands = effect.numberOfBands.toInt()
        if (bands == 0) return
        val range = effect.bandLevelRange
        val targets = listOf(100.0, 1000.0, 8000.0)
        val selected = targets.map { target ->
            (0 until bands).minByOrNull { index ->
                val center = effect.getCenterFreq(index.toShort()).toDouble().coerceAtLeast(1.0)
                kotlin.math.abs(kotlin.math.ln(center / target))
            }
        }
        selected.forEachIndexed { index, band ->
            if (band != null) {
                val level = (equalizerGains[index] * range[1]).toInt()
                    .coerceIn(range[0].toInt(), range[1].toInt())
                effect.setBandLevel(band.toShort(), level.toShort())
            }
        }
    }

    private fun playbackState(): Map<String, Any> {
        val active = player
        if (active == null) {
            return mapOf("positionMillis" to 0, "durationMillis" to 0, "isPlaying" to false)
        }
        return try {
            mapOf(
                "positionMillis" to active.currentPosition,
                "durationMillis" to active.duration,
                "isPlaying" to active.isPlaying,
            )
        } catch (_: IllegalStateException) {
            mapOf("positionMillis" to 0, "durationMillis" to 0, "isPlaying" to false)
        }
    }

    private fun releasePlayer() {
        equalizer?.runCatching { release() }
        equalizer = null
        player?.runCatching { release() }
        player = null
    }

    private fun requiredPermissions(): List<String> = buildList {
        add(Manifest.permission.RECORD_AUDIO)
        // Optional: lets the "Recording…" notification with its Stop button be shown.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            add(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    private fun isGranted(permission: String): Boolean =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    companion object {
        const val METHOD_CHANNEL = "com.example.voicerec/recorder"
        const val EVENT_CHANNEL = "com.example.voicerec/recorder_state"
        private const val PERMISSION_REQUEST_CODE = 4201
    }
}
