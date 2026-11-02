package com.example.voicerec.photos

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.example.voicerec.backup.TelegramBackup
import com.example.voicerec.backup.UploadProcessor

/** Looks for new photos. Runs when images change on the device, and periodically. */
class PhotoScanWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        PhotoBackup.scan(applicationContext)
        // The content-trigger job is one-shot: arm it again while backup is on.
        if (PhotoSettings(applicationContext).enabled) {
            PhotoBackup.scheduleTrigger(applicationContext, ExistingWorkPolicy.APPEND_OR_REPLACE)
        }
        return Result.success()
    }
}

/**
 * Uploads queued photos one at a time (Telegram limits how fast a bot can post
 * to a chat). Stops, leaving items pending, when uploads aren't allowed.
 */
class PhotoUploadWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val context = applicationContext
        val store = TelegramBackup.uploadStore(context)
        val processor = TelegramBackup.processor(context, PhotoSource(context))
        val deadline = System.currentTimeMillis() + RUN_BUDGET_MS

        while (!isStopped) {
            val next = store.nextRunnable(PhotoRules.ID_PREFIX) ?: return Result.success()
            if (System.currentTimeMillis() > deadline) {
                // WorkManager limits a run to ~10 minutes: continue in a fresh run.
                PhotoBackup.scheduleDrain(context, append = true)
                return Result.success()
            }
            when (processor.process(next.recordingId)) {
                UploadProcessor.Outcome.DONE -> try {
                    Thread.sleep(PACING_MS)
                } catch (e: InterruptedException) {
                    return Result.retry()
                }
                UploadProcessor.Outcome.FAILED -> Unit // marked failed; move on to the next photo
                UploadProcessor.Outcome.RETRY -> return Result.retry() // network/server trouble: back off
                UploadProcessor.Outcome.BLOCKED -> return Result.success() // paused/disabled/revoked
            }
        }
        return Result.retry()
    }

    private companion object {
        const val RUN_BUDGET_MS = 8 * 60 * 1000L

        /** Keeps well under Telegram's ~20 messages/minute limit for one chat. */
        const val PACING_MS = 3_000L
    }
}
