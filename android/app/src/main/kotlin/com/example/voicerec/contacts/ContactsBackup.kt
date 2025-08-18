package com.example.voicerec.contacts

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import java.io.File
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Exports contacts to a local `.vcf` file.
 *
 * Runs only when the user asks. Uses its own thread, separate from
 * recording, so exporting can never delay or interrupt a recording.
 */
object ContactsBackup {
    private const val TAG = "ContactsBackup"
    const val ID_PREFIX = "contacts_"
    private const val EXTENSION = "vcf"

    /** Keep the three newest local backups. */
    private const val KEEP_LATEST = 3

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    sealed interface Result {
        data class Saved(val contactCount: Int) : Result
        data class Error(val code: String, val message: String) : Result
    }

    fun isBackupFile(file: File) = file.extension == EXTENSION && file.name.startsWith(ID_PREFIX)

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

    /** Exports a local backup on a background thread; [callback] runs on that thread. */
    fun backUpNow(context: Context, callback: (Result) -> Unit) {
        val appContext = context.applicationContext
        executor.execute { callback(runBackup(appContext)) }
    }

    /** Status for the UI: permission and the newest local backup. */
    fun state(context: Context): Map<String, Any?> {
        val latest = dir(context).listFiles()
            .orEmpty()
            .filter { it.isFile && isBackupFile(it) }
            .maxByOrNull { it.lastModified() }
        return mapOf(
            "permissionGranted" to hasPermission(context),
            "latest" to latest?.let { file ->
                mapOf(
                    "path" to file.absolutePath,
                    "modifiedAtMillis" to file.lastModified(),
                    "sizeBytes" to file.length(),
                    "contactCount" to countContacts(file),
                )
            },
        )
    }

    private fun runBackup(context: Context): Result {
        return try {
            val cards = ContactCards.normalize(ContactsReader(context.contentResolver).read())
            if (cards.isEmpty()) {
                return Result.Error("NO_CONTACTS", "No contacts with a name, phone number or email were found.")
            }
            writeFile(context, cards)
            prune(context)
            Result.Saved(cards.size)
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
     * Retention: keep the newest [KEEP_LATEST] local backups.
     */
    private fun prune(context: Context) {
        dir(context).listFiles()
            .orEmpty()
            .filter { isBackupFile(it) }
            .sortedByDescending { it.name }
            .drop(KEEP_LATEST)
            .forEach { it.delete() }
    }

    private fun countContacts(file: File): Int? = try {
        file.useLines { lines -> lines.count { it == "BEGIN:VCARD" } }
    } catch (e: IOException) {
        null
    }

    private fun dir(context: Context) = File(context.filesDir, "contacts_backups").apply { mkdirs() }
}
