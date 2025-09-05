package com.example.voicerec.recorder

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import java.io.File

/**
 * Foreground service that owns the [MediaRecorder] and the recording lifecycle.
 *
 * Recording lives here, not in the Activity or Flutter engine, so it keeps
 * running when the UI is closed, the app is swiped from Recents
 * (`android:stopWithTask="false"`), another app is opened, or the screen locks.
 * Only an explicit Stop, a recorder error, or the system ends it.
 */
class RecordingService : Service() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var notification: RecordingNotification
    private var recorder: MediaRecorder? = null
    private var micCallback: AudioManager.AudioRecordingCallback? = null

    override fun onCreate() {
        super.onCreate()
        notification = RecordingNotification(this)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startRecording()
            ACTION_PAUSE -> pauseRecording()
            ACTION_RESUME -> resumeRecording()
            ACTION_STOP -> stopRecording()
            else -> if (!state.isActive) stopSelf()
        }
        // Never restart on our own: the microphone may only be opened from a user action.
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // The UI was swiped away. Intentionally keep recording.
        Log.i(TAG, "Task removed; recording continues (status=${state.status})")
    }

    override fun onDestroy() {
        // Destroyed by the system mid-recording: close the recorder so the
        // .aac stays valid. It is converted to .m4a on the next listing.
        recorder?.let { releaseRecorder(it) }
        recorder = null
        unwatchMicrophone()
        if (state.isActive) updateState(RecorderState(error = "Recording was interrupted by the system."))
        super.onDestroy()
    }

    private fun startRecording() {
        if (state.isActive) return

        val startedAt = System.currentTimeMillis()
        val starting = RecorderState(
            status = RecorderStatus.RECORDING,
            startedAtMillis = startedAt,
            segmentStartedAtMillis = startedAt,
        )
        // startForegroundService() requires startForeground() promptly, even if we then fail.
        try {
            startInForeground(starting)
        } catch (e: Exception) {
            Log.e(TAG, "Could not enter foreground", e)
            finish(RecorderState(error = "Could not start recording: ${e.message}"))
            return
        }

        if (!RecordingFiles.hasFreeSpace(this)) {
            finish(RecorderState(error = "Not enough storage space to record."))
            return
        }

        val file = RecordingFiles.newRawFile(this, startedAt)
        var newRecorder: MediaRecorder? = null
        try {
            newRecorder = createMediaRecorder().apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                // ADTS has no index written at stop(), so the file stays playable
                // even if the process is killed mid-recording. Converted to .m4a on stop.
                setOutputFormat(MediaRecorder.OutputFormat.AAC_ADTS)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioChannels(1)
                setAudioSamplingRate(44_100)
                setAudioEncodingBitRate(128_000)
                setOutputFile(file.absolutePath)
                setOnErrorListener { _, what, extra -> onRecorderError(what, extra) }
                prepare()
                start()
            }
        } catch (e: Exception) {
            // Typically: microphone permission revoked or mic held exclusively by another app.
            Log.e(TAG, "Failed to start recording", e)
            newRecorder?.release()
            file.delete()
            finish(RecorderState(error = "Could not start recording. Is the microphone in use?"))
            return
        }

        recorder = newRecorder
        updateState(starting.copy(filePath = file.absolutePath))
        watchMicrophone()
    }

    private fun pauseRecording() {
        val active = recorder ?: return
        if (state.status != RecorderStatus.RECORDING) return
        try {
            active.pause()
        } catch (e: IllegalStateException) {
            Log.e(TAG, "Pause failed", e)
            return
        }
        updateState(
            state.copy(
                status = RecorderStatus.PAUSED,
                accumulatedMillis = state.elapsedMillis(),
                segmentStartedAtMillis = null,
            ),
        )
        notification.update(state)
    }

    private fun resumeRecording() {
        val active = recorder ?: return
        if (state.status != RecorderStatus.PAUSED) return
        try {
            active.resume()
        } catch (e: IllegalStateException) {
            Log.e(TAG, "Resume failed", e)
            return
        }
        updateState(state.copy(status = RecorderStatus.RECORDING, segmentStartedAtMillis = System.currentTimeMillis()))
        notification.update(state)
    }

    /** Stops capture, then finalizes the file off the main thread before leaving the foreground. */
    private fun stopRecording(error: String? = null) {
        val active = recorder
        if (active == null) {
            if (!state.isActive) stopSelf() // stray Stop (e.g. old notification): nothing to do
            return
        }
        recorder = null
        unwatchMicrophone()

        val raw = state.filePath?.let(::File)
        val captured = releaseRecorder(active)
        updateState(
            state.copy(
                status = RecorderStatus.STOPPING,
                accumulatedMillis = state.elapsedMillis(),
                segmentStartedAtMillis = null,
            ),
        )
        notification.update(state)

        RecordingFiles.io.execute {
            if (raw != null) {
                if (captured) RecordingFiles.finalize(raw) else raw.delete()
            }
            mainHandler.post { finish(RecorderState(error = error)) }
        }
    }

    /** Stops and releases [active]. Returns false if it captured no audio. */
    private fun releaseRecorder(active: MediaRecorder): Boolean = try {
        active.stop()
        true
    } catch (e: RuntimeException) {
        // Thrown when stop() is called right after start() with no data captured.
        Log.w(TAG, "Recording was empty", e)
        false
    } finally {
        active.release()
    }

    private fun onRecorderError(what: Int, extra: Int) {
        Log.e(TAG, "MediaRecorder error what=$what extra=$extra")
        stopRecording(error = "Recording stopped because of a microphone error.")
    }

    private fun finish(finalState: RecorderState) {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        updateState(finalState)
    }

    private fun startInForeground(state: RecorderState) {
        val built = notification.build(state)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(RecordingNotification.ID, built, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(RecordingNotification.ID, built)
        }
    }

    @Suppress("DEPRECATION")
    private fun createMediaRecorder(): MediaRecorder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(this) else MediaRecorder()

    // region Microphone contention (Android 10+)

    /** Android silences our capture while another app (e.g. a call) holds the mic. */
    private fun watchMicrophone() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val callback = object : AudioManager.AudioRecordingCallback() {
            override fun onRecordingConfigChanged(configs: List<AudioRecordingConfiguration>) {
                checkMicSilenced()
            }
        }
        getSystemService(AudioManager::class.java).registerAudioRecordingCallback(callback, mainHandler)
        micCallback = callback
    }

    private fun unwatchMicrophone() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        micCallback?.let { getSystemService(AudioManager::class.java).unregisterAudioRecordingCallback(it) }
        micCallback = null
    }

    private fun checkMicSilenced() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val silenced = recorder?.activeRecordingConfiguration?.isClientSilenced ?: return
        if (silenced == state.micSilenced) return
        updateState(state.copy(micSilenced = silenced))
        notification.update(state)
    }

    // endregion

    companion object {
        private const val TAG = "RecordingService"
        const val ACTION_START = "com.example.voicerec.action.START_RECORDING"
        const val ACTION_PAUSE = "com.example.voicerec.action.PAUSE_RECORDING"
        const val ACTION_RESUME = "com.example.voicerec.action.RESUME_RECORDING"
        const val ACTION_STOP = "com.example.voicerec.action.STOP_RECORDING"

        /** Current state; lives as long as the process, so a reopened UI can read it. */
        @Volatile
        var state = RecorderState()
            private set

        /** Called on the main thread whenever [state] changes. */
        var listener: ((RecorderState) -> Unit)? = null

        fun intent(context: Context, action: String): Intent =
            Intent(context, RecordingService::class.java).setAction(action)

        /** Must be called from a user action while the app is visible. */
        fun start(context: Context) {
            if (state.isActive) return
            val intent = intent(context, ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun pause(context: Context) = sendIfActive(context, ACTION_PAUSE)

        fun resume(context: Context) = sendIfActive(context, ACTION_RESUME)

        fun stop(context: Context) = sendIfActive(context, ACTION_STOP)

        private fun sendIfActive(context: Context, action: String) {
            if (state.isActive) context.startService(intent(context, action))
        }

        private fun updateState(newState: RecorderState) {
            state = newState.copy(error = null)
            listener?.invoke(newState)
        }
    }
}
