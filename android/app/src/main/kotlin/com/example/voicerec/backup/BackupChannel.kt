package com.example.voicerec.backup

import android.content.Context
import com.example.voicerec.recorder.RecordingFiles
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Bridge between Flutter and [TelegramBackup].
 *
 * - Method channel: `isConfigured`, `retryUpload(path)`.
 * - Event channel: streams upload maps as they change (status, progress, error).
 */
class BackupChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        TelegramBackup.listener = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isConfigured" -> result.success(TelegramBackup.isConfigured)
            "retryUpload" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("BAD_ARGS", "Missing path", null)
                    return
                }
                // Database work stays off the main thread, alongside other file work.
                RecordingFiles.io.execute { TelegramBackup.retry(context, File(path)) }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        TelegramBackup.listener = { events.success(it) }
    }

    override fun onCancel(arguments: Any?) {
        TelegramBackup.listener = null
    }

    companion object {
        const val METHOD_CHANNEL = "com.example.voicerec/backup"
        const val EVENT_CHANNEL = "com.example.voicerec/backup_events"
    }
}
