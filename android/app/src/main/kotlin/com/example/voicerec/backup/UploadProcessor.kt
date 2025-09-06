package com.example.voicerec.backup

import java.io.File
import java.util.Locale

/**
 * One upload attempt for one recording. Pure logic over [UploadStore] and
 * [DocumentSender], so it is unit-testable without Android.
 */
class UploadProcessor(
    private val store: UploadStore,
    private val sender: DocumentSender,
    private val maxAttempts: Int = DEFAULT_MAX_ATTEMPTS,
    private val maxFileBytes: Long = TelegramClient.MAX_FILE_BYTES,
    private val captionFor: (File) -> String = { it.nameWithoutExtension },
) {
    enum class Outcome { DONE, RETRY, FAILED }

    fun process(recordingId: String): Outcome {
        // Deleted by the user since it was queued: nothing to do.
        val record = store.get(recordingId) ?: return Outcome.DONE
        // Never send twice: a retried or duplicated job finds the saved Telegram result.
        if (record.status == UploadStatus.UPLOADED) return Outcome.DONE

        val file = File(record.filePath)
        if (!file.isFile) return fail(recordingId, "The recording file no longer exists.")
        if (file.length() > maxFileBytes) {
            return fail(
                recordingId,
                String.format(
                    Locale.US,
                    "File is %.1f MB; Telegram bots can upload at most %d MB.",
                    file.length() / 1_000_000.0,
                    maxFileBytes / 1_000_000,
                ),
            )
        }

        store.markUploading(recordingId)
        val attempt = record.attempts + 1

        var reported = 0f
        val result = sender.send(file, captionFor(file)) { progress ->
            if (progress - reported >= PROGRESS_STEP) {
                reported = progress
                store.updateProgress(recordingId, progress)
            }
        }

        return when (result) {
            is SendResult.Sent -> {
                store.markUploaded(recordingId, result.messageId, result.fileId, result.rawResponse)
                Outcome.DONE
            }
            is SendResult.Permanent -> fail(recordingId, result.message)
            is SendResult.Retryable ->
                if (attempt >= maxAttempts) {
                    fail(recordingId, "Gave up after $attempt attempts: ${result.message}")
                } else {
                    store.markPending(recordingId, result.message)
                    Outcome.RETRY
                }
        }
    }

    private fun fail(recordingId: String, message: String): Outcome {
        store.markFailed(recordingId, message)
        return Outcome.FAILED
    }

    companion object {
        const val DEFAULT_MAX_ATTEMPTS = 8
        private const val PROGRESS_STEP = 0.02f
    }
}
