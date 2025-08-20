package com.example.voicerec.backup

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import com.example.voicerec.BuildConfig
import com.example.voicerec.contacts.ContactsBackup
import com.example.voicerec.recorder.RecordingFiles
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * Entry point for Telegram backup: queues finalized recordings and contacts
 * backups, and schedules their upload with WorkManager. Independent of
 * recording: nothing here can block or fail a recording.
 *
 * Local files are never deleted by backup.
 */
object TelegramBackup {
    private const val WORK_PREFIX = "telegram-upload-"
    private const val BACKOFF_SECONDS = 30L

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var store: SqliteUploadStore? = null

    /** Called on the main thread with an upload's map whenever it changes. */
    var listener: ((Map<String, Any?>) -> Unit)? = null

    val isConfigured: Boolean
        get() = BuildConfig.TELEGRAM_BOT_TOKEN.isNotBlank() && BuildConfig.TELEGRAM_CHAT_ID.isNotBlank()

    fun recordingId(file: File): String = file.nameWithoutExtension

    /** Queues a finalized recording. Safe to call more than once for the same file. */
    fun enqueue(context: Context, file: File) {
        if (!isConfigured) return
        if (store(context).insertIfAbsent(recordingId(file), file.absolutePath)) {
            schedule(context, recordingId(file))
        }
    }

    /** Re-queues a failed upload, or queues a recording that was never backed up. */
    fun retry(context: Context, file: File) {
        if (!isConfigured) return
        val store = store(context)
        val id = recordingId(file)
        when (store.get(id)?.status) {
            null -> store.insertIfAbsent(id, file.absolutePath)
            UploadStatus.FAILED -> store.resetForRetry(id)
            // Already queued, running or uploaded: never start a second upload.
            else -> return
        }
        schedule(context, id)
    }

    /** Cancels and forgets the upload of a recording the user deleted. */
    fun forget(context: Context, file: File) {
        val id = recordingId(file)
        WorkManager.getInstance(context).cancelUniqueWork(WORK_PREFIX + id)
        store(context).delete(id)
    }

    /** Upload maps keyed by file path, for the recordings list. */
    fun uploadsByPath(context: Context): Map<String, Map<String, Any?>> =
        store(context).all().associate { it.filePath to it.toMap() }

    fun get(context: Context, file: File): UploadRecord? = store(context).get(recordingId(file))

    /** Uploads whose ID starts with [prefix] (e.g. contacts backups), newest first. */
    fun uploadsWithPrefix(context: Context, prefix: String): List<UploadRecord> =
        store(context).findByPrefix(prefix)

    fun processor(context: Context, source: UploadSource? = null) = UploadProcessor(
        store = store(context),
        sender = TelegramClient(BuildConfig.TELEGRAM_BOT_TOKEN, BuildConfig.TELEGRAM_CHAT_ID),
        captionFor = ::caption,
        source = source,
    )

    /** The shared upload queue, for features that manage their own scheduling (photos). */
    fun uploadStore(context: Context): SqliteUploadStore = store(context)

    private fun schedule(context: Context, recordingId: String) {
        val request = OneTimeWorkRequest.Builder(TelegramUploadWorker::class.java)
            .setInputData(Data.Builder().putString(TelegramUploadWorker.KEY_RECORDING_ID, recordingId).build())
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, BACKOFF_SECONDS, TimeUnit.SECONDS)
            .build()
        // KEEP: if this recording's upload is already scheduled or running, don't start another.
        WorkManager.getInstance(context)
            .enqueueUniqueWork(WORK_PREFIX + recordingId, ExistingWorkPolicy.KEEP, request)
    }

    private fun store(context: Context): SqliteUploadStore =
        store ?: synchronized(this) {
            store ?: SqliteUploadStore(context.applicationContext, ::notifyChanged).also { store = it }
        }

    private fun notifyChanged(recordingId: String) {
        val record = store?.get(recordingId)?.toMap() ?: return
        mainHandler.post { listener?.invoke(record) }
    }

    private fun caption(file: File): String =
        if (ContactsBackup.isBackupFile(file)) ContactsBackup.caption(file) else recordingCaption(file)

    private fun recordingCaption(file: File): String {
        val saved = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date(file.lastModified()))
        val duration = RecordingFiles.durationMillis(file)?.let { millis ->
            val seconds = millis / 1000
            String.format(Locale.US, "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return buildString {
            append("Voice recording ").append(file.nameWithoutExtension)
            append("\nSaved: ").append(saved)
            duration?.let { append("\nDuration: ").append(it) }
            append("\nDevice: ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL)
        }
    }
}
