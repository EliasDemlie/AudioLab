package com.example.voicerec.backup

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * Runs one upload attempt. WorkManager handles scheduling: it waits for a
 * network connection, retries with exponential backoff, and survives app
 * restarts and reboots.
 */
class TelegramUploadWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val recordingId = inputData.getString(KEY_RECORDING_ID) ?: return Result.failure()
        return when (TelegramBackup.processor(applicationContext).process(recordingId)) {
            UploadProcessor.Outcome.DONE -> Result.success()
            UploadProcessor.Outcome.RETRY -> Result.retry()
            UploadProcessor.Outcome.FAILED -> Result.failure()
        }
    }

    companion object {
        const val KEY_RECORDING_ID = "recordingId"
    }
}
