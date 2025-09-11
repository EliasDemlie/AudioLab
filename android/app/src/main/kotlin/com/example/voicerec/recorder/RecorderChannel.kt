package com.example.voicerec.recorder

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.MediaPlayer
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
 *   `stopRecording`, `getRecordingState`, `listRecordings`, `deleteRecording`.
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

    /** Result of a `startRecording` call that is waiting for the permission dialog. */
    private var pendingStart: MethodChannel.Result? = null
    private var player: MediaPlayer? = null

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
            "stopPlayback" -> {
                releasePlayer()
                result.success(null)
            }
            "getRecordingState" -> result.success(RecordingService.state.toMap())
            "listRecordings" -> listRecordings(result)
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
        val context = activity.applicationContext
        RecordingFiles.io.execute {
            val state = RecordingService.state
            val activePath = if (state.isActive) state.filePath else null
            val recordings = try {
                RecordingFiles.recoverInterrupted(context, activePath)
                RecordingFiles.list(context, activePath)
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("LIST_FAILED", e.message, null) }
                return@execute
            }
            activity.runOnUiThread { result.success(recordings) }
        }
    }

    /** Deletes a saved recording at the user's request. */
    private fun deleteRecording(path: String?, result: MethodChannel.Result) {
        if (path == null) {
            result.error("BAD_ARGS", "Missing path", null)
            return
        }
        RecordingFiles.io.execute {
            val file = File(path)
            val deleted = !file.exists() || file.delete()
            activity.runOnUiThread {
                if (deleted) result.success(null) else result.error("DELETE_FAILED", "Could not delete file", null)
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
