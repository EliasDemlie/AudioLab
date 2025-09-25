package com.example.voicerec.photos

import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import com.example.voicerec.backup.UploadRecord
import com.example.voicerec.backup.UploadSource
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Turns a queued photo (content URI) into a temporary file for upload.
 * The original in the gallery is only read, never modified or deleted.
 *
 * Authorization is re-checked before every photo, so nothing is uploaded
 * after the user pauses, disables, or revokes access.
 */
class PhotoSource(private val context: Context) : UploadSource {

    override fun handles(record: UploadRecord) = record.recordingId.startsWith(PhotoRules.ID_PREFIX)

    override fun open(record: UploadRecord): UploadSource.Resolved {
        val settings = PhotoSettings(context)
        if (!settings.enabled) return blocked("Automatic photo backup is turned off.")
        if (settings.paused) return blocked("Photo backup is paused.")
        if (PhotoAccess.current(context) == PhotoAccess.NONE) return blocked("Photo access was revoked.")

        val uri = Uri.parse(record.filePath)
        val id = record.recordingId.removePrefix(PhotoRules.ID_PREFIX).toLongOrNull()
            ?: return UploadSource.Resolved.Unavailable("Unknown photo.")

        var staged: File? = null
        try {
            val meta = context.contentResolver.query(
                uri,
                arrayOf(
                    MediaStore.Images.Media.DISPLAY_NAME,
                    MediaStore.Images.Media.MIME_TYPE,
                    MediaStore.Images.Media.SIZE,
                    MediaStore.Images.Media.DATE_TAKEN,
                    MediaStore.Images.Media.DATE_ADDED,
                ),
                null, null, null,
            )?.use { if (it.moveToFirst()) Meta(it.getString(0), it.getString(1), it.getLong(2), it.getLong(3), it.getLong(4)) else null }
                ?: return UploadSource.Resolved.Unavailable("The photo was deleted from the device.")

            if (!PhotoRules.isEligible(meta.mimeType, meta.size, PhotoRules.maxBytes(settings.maxFileMb))) {
                return UploadSource.Resolved.Unavailable(
                    "The photo is larger than the ${settings.maxFileMb} MB limit or isn't a supported image.",
                )
            }

            val dir = File(context.cacheDir, STAGING_DIR).resolve(record.recordingId).apply { mkdirs() }
            val target = File(dir, PhotoRules.safeFileName(meta.name, id, meta.mimeType))
            staged = target
            val input = context.contentResolver.openInputStream(uri)
                ?: return UploadSource.Resolved.Unavailable("The photo was deleted from the device.")
            input.use { src -> target.outputStream().use { src.copyTo(it) } }

            val taken = if (meta.dateTaken > 0) meta.dateTaken else meta.dateAdded * 1000
            return UploadSource.Resolved.Ready(target, caption(target.name, taken)) { dir.deleteRecursively() }
        } catch (e: SecurityException) {
            // Outside the authorized set (e.g. no longer in the user's selection).
            staged?.parentFile?.deleteRecursively()
            return blocked("This photo is outside the access you granted.")
        } catch (e: FileNotFoundException) {
            staged?.parentFile?.deleteRecursively()
            return UploadSource.Resolved.Unavailable("The photo was deleted from the device.")
        } catch (e: IOException) {
            staged?.parentFile?.deleteRecursively()
            return UploadSource.Resolved.Unavailable("Could not read the photo: ${e.javaClass.simpleName}.")
        }
    }

    private fun blocked(message: String) = UploadSource.Resolved.Blocked(message)

    private fun caption(name: String, takenMillis: Long) = buildString {
        append("Photo ").append(name)
        if (takenMillis > 0) {
            append("\nTaken: ").append(SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date(takenMillis)))
        }
        append("\nDevice: ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL)
    }

    private class Meta(val name: String?, val mimeType: String?, val size: Long, val dateTaken: Long, val dateAdded: Long)

    companion object {
        const val STAGING_DIR = "photo_upload"

        /** Removes staged copies left behind by a killed upload. */
        fun clearStaging(context: Context) {
            File(context.cacheDir, STAGING_DIR).deleteRecursively()
        }
    }
}
