package com.example.voicerec.recorder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.example.voicerec.MainActivity
import com.example.voicerec.R

/** Builds the ongoing "Recording" status notification; tapping it opens the app. */
class RecordingNotification(private val context: Context) {

    private val manager = context.getSystemService(NotificationManager::class.java)

    fun build(state: RecorderState): Notification {
        val builder = newBuilder()
            .setSmallIcon(R.drawable.ic_stat_mic)
            .setContentTitle(title(state))
            .setContentText(text(state))
            .setContentIntent(openAppIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)

        if (state.status == RecorderStatus.RECORDING) {
            // The chronometer counts from `when`, so shift it back by time already recorded.
            builder.setUsesChronometer(true)
                .setShowWhen(true)
                .setWhen(System.currentTimeMillis() - state.elapsedMillis())
        } else {
            builder.setUsesChronometer(false).setShowWhen(false)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    fun update(state: RecorderState) {
        manager.notify(ID, build(state))
    }

    private fun title(state: RecorderState): String = when (state.status) {
        RecorderStatus.PAUSED -> "Recording paused"
        RecorderStatus.STOPPING -> "Saving recording…"
        else -> "Recording audio"
    }

    private fun text(state: RecorderState): String = when {
        state.micSilenced -> "Microphone is in use by another app"
        state.status == RecorderStatus.PAUSED -> "Open Voice Recorder to resume"
        else -> "Tap to open Voice Recorder"
    }

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    @Suppress("DEPRECATION")
    private fun newBuilder(): Notification.Builder {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return Notification.Builder(context)

        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            // Badge settings are fixed once a channel exists, so replace the old one.
            manager.deleteNotificationChannel(LEGACY_CHANNEL_ID)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Recording", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shown while audio is being recorded"
                    setShowBadge(false)
                },
            )
        }
        return Notification.Builder(context, CHANNEL_ID)
    }

    companion object {
        const val ID = 1001
        private const val CHANNEL_ID = "recording_status"
        private const val LEGACY_CHANNEL_ID = "recording"
    }
}
