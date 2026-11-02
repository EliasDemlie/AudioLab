package com.example.voicerec.photos

import android.content.ContentResolver
import android.content.ContentUris
import android.net.Uri
import android.provider.MediaStore

/**
 * Reads the image list from MediaStore. MediaStore only returns what the
 * app has been authorized to see (all photos, or the user's selection).
 */
class PhotoLibrary(private val resolver: ContentResolver) {

    data class Image(val id: Long, val mimeType: String?, val sizeBytes: Long)

    /** [lastIdSeen] is the watermark to resume from next time. */
    data class Page(val images: List<Image>, val lastIdSeen: Long)

    /** Images with an ID above [afterId], oldest first. Stops at a photo still being written. */
    fun imagesAfter(afterId: Long): Page {
        val images = mutableListOf<Image>()
        var lastSeen = afterId
        resolver.query(
            COLLECTION,
            arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.MIME_TYPE, MediaStore.Images.Media.SIZE),
            "${MediaStore.Images.Media._ID} > ?",
            arrayOf(afterId.toString()),
            "${MediaStore.Images.Media._ID} ASC",
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                val size = cursor.getLong(2)
                // Size 0: still being written. Leave it (and everything after) for the next scan.
                if (size <= 0) break
                images += Image(id, cursor.getString(1), size)
                lastSeen = id
            }
        }
        return Page(images, lastSeen)
    }

    /** Highest image ID currently visible, or 0 if none. */
    fun maxId(): Long =
        resolver.query(
            COLLECTION, arrayOf(MediaStore.Images.Media._ID), null, null,
            "${MediaStore.Images.Media._ID} DESC",
        )?.use { if (it.moveToFirst()) it.getLong(0) else 0L } ?: 0L

    companion object {
        val COLLECTION: Uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI

        fun uriFor(id: Long): Uri = ContentUris.withAppendedId(COLLECTION, id)
    }
}
