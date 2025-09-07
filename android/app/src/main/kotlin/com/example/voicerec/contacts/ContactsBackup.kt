package com.example.voicerec.contacts

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.example.voicerec.backup.TelegramBackup
import com.example.voicerec.backup.UploadStatus
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Exports contacts to a `.vcf` file and hands it to the existing Telegram
 * upload queue ([TelegramBackup]), which uploads it with WorkManager.
 *
 * Runs only when the user asks. Uses its own thread, separate from
 * recording, so exporting can never delay or interrupt a recording.
 */
object ContactsBackup {
    private const val TAG = "ContactsBackup"
    const val ID_PREFIX = "contacts_"
    private const val EXTENSION = "vcf"

    /** Newest backups always kept on the device; older ones are deleted once uploaded. */
    private const val KEEP_LATEST = 3

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    sealed interface Result {
        data class Queued(val contactCount: Int) : Result
        data class Error(val code: String, val message: String) : Result
    }

    fun isBackupFile(file: File) = file.extension == EXTENSION && file.name.startsWith(ID_PREFIX)

    /**
     * Queues any contacts backup on disk that has no upload record yet — e.g. a
     * `.vcf` restored or copied in outside the normal export path — so it
     * uploads like any other. Idempotent: files already in the queue (pending,
     * uploading, failed or uploaded) are left untouched by [TelegramBackup.enqueue].
     */
    fun enqueuePending(context: Context) {
        if (!TelegramBackup.isConfigured) return
        dir(context).listFiles()
            .orEmpty()
            .filter { it.isFile && isBackupFile(it) }
            .forEach { TelegramBackup.enqueue(context, it) }
    }

    /** Saved contact backups, newest first, shaped like [RecordingFiles.list] entries. */
    fun list(context: Context): List<Map<String, Any?>> =
        dir(context).listFiles()
            .orEmpty()
            .filter { it.isFile && isBackupFile(it) }
            .sortedByDescending { it.lastModified() }
            .map { file ->
                mapOf(
                    "path" to file.absolutePath,
                    "sizeBytes" to file.length(),
                    "modifiedAtMillis" to file.lastModified(),
                    "contactCount" to countContacts(file),
                    "kind" to "contacts",
                )
            }

    fun hasPermission(context: Context) =
        context.checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED

    /** Exports and queues a backup on a background thread; [callback] runs on that thread. */
    fun backUpNow(context: Context, callback: (Result) -> Unit) {
        val appContext = context.applicationContext
        executor.execute { callback(runBackup(appContext)) }
    }

    /**
     * Backs up contacts automatically when a recording is backed up, so the
     * address book rides along without the user asking. Exports and queues a
     * `.vcf` only when contacts are not already backed up; it is a no-op when
     * Telegram is not configured, contacts permission has never been granted,
     * or a backup is already uploaded or in flight.
     *
     * Runs on the contacts thread so it never delays recording or its backup.
     * Silent by design: a missing permission or a failed export must never
     * disturb a recording that just finished.
     */
    fun ensureBackedUp(context: Context) {
        val appContext = context.applicationContext
        executor.execute {
            if (!TelegramBackup.isConfigured || !hasPermission(appContext)) return@execute
            when (TelegramBackup.uploadsWithPrefix(appContext, ID_PREFIX).firstOrNull()?.status) {
                // Already backed up, or an upload is already queued/running: leave it.
                UploadStatus.UPLOADED, UploadStatus.PENDING, UploadStatus.UPLOADING -> Unit
                // Never backed up, or the last attempt failed: export a fresh copy.
                else -> runBackup(appContext)
            }
        }
    }

    /** Status for the UI: configuration, permission, latest backup and last success. */
    fun state(context: Context): Map<String, Any?> {
        val uploads = TelegramBackup.uploadsWithPrefix(context, ID_PREFIX)
        val latest = uploads.firstOrNull()
        val lastSuccess = uploads.filter { it.status == UploadStatus.UPLOADED }.maxOfOrNull { it.updatedAtMillis }
        return mapOf(
            "configured" to TelegramBackup.isConfigured,
            "permissionGranted" to hasPermission(context),
            "lastSuccessAtMillis" to lastSuccess,
            "latest" to latest?.toMap()?.plus("contactCount" to countContacts(File(latest.filePath))),
        )
    }

    /** Retries the latest backup's upload if it failed. Returns false if there is nothing to retry. */
    fun retryLatest(context: Context): Boolean {
        val latest = TelegramBackup.uploadsWithPrefix(context, ID_PREFIX).firstOrNull() ?: return false
        val file = File(latest.filePath)
        if (latest.status != UploadStatus.FAILED || !file.isFile) return false
        TelegramBackup.retry(context, file)
        return true
    }

    fun caption(file: File): String {
        val created = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date(file.lastModified()))
        return buildString {
            append("Contacts backup")
            countContacts(file)?.let { append("\nContacts: ").append(it) }
            append("\nCreated: ").append(created)
            append("\nDevice: ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL)
        }
    }

    private fun runBackup(context: Context): Result {
        if (!TelegramBackup.isConfigured) {
            return Result.Error("NOT_CONFIGURED", "Telegram backup is not configured.")
        }
        val latest = TelegramBackup.uploadsWithPrefix(context, ID_PREFIX).firstOrNull()
        if (latest?.status == UploadStatus.PENDING || latest?.status == UploadStatus.UPLOADING) {
            return Result.Error("IN_PROGRESS", "A contacts backup is already being uploaded.")
        }

        return try {
            val cards = ContactCards.normalize(ContactsReader(context.contentResolver).read())
            if (cards.isEmpty()) {
                return Result.Error("NO_CONTACTS", "No contacts with a name, phone number or email were found.")
            }
            val file = writeFile(context, cards)
            TelegramBackup.enqueue(context, file)
            prune(context)
            Result.Queued(cards.size)
        } catch (e: SecurityException) {
            Result.Error("PERMISSION_DENIED", "Contacts permission is required to back up contacts.")
        } catch (e: Exception) {
            Log.e(TAG, "Contacts export failed", e)
            Result.Error("EXPORT_FAILED", "Could not export contacts.")
        }
    }

    /** Writes to a temp file first, so a failed export never leaves a partial .vcf behind. */
    private fun writeFile(context: Context, cards: List<ContactCard>): File {
        val dir = dir(context)
        val base = ID_PREFIX + SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        var target = File(dir, "$base.$EXTENSION")
        var suffix = 1
        while (target.exists()) target = File(dir, "${base}_${suffix++}.$EXTENSION")

        val temp = File(dir, "${target.name}.tmp")
        try {
            temp.bufferedWriter(Charsets.UTF_8).use { VCardWriter.write(cards, it) }
            if (!temp.renameTo(target)) throw IOException("Could not save ${target.name}")
        } finally {
            temp.delete()
        }
        return target
    }

    /**
     * Retention: keep the newest [KEEP_LATEST] backups. Older ones are deleted
     * only after Telegram confirmed their upload; failed ones are kept for retry.
     */
    private fun prune(context: Context) {
        dir(context).listFiles()
            .orEmpty()
            .filter { isBackupFile(it) }
            .sortedByDescending { it.name }
            .drop(KEEP_LATEST)
            .filter { TelegramBackup.get(context, it)?.status == UploadStatus.UPLOADED }
            .forEach { it.delete() }
    }

    private fun countContacts(file: File): Int? = try {
        file.useLines { lines -> lines.count { it == "BEGIN:VCARD" } }
    } catch (e: IOException) {
        null
    }

    private fun dir(context: Context) = File(context.filesDir, "contacts_backups").apply { mkdirs() }
}
