package com.example.voicerec.photos

/** Pure rules for which photos are queued; no Android dependencies. */
object PhotoRules {
    const val ID_PREFIX = "photo_"

    /** Telegram bots can upload at most 50 MB. */
    const val MAX_FILE_MB_LIMIT = 50
    const val DEFAULT_MAX_FILE_MB = 20

    /**
     * Queue ID for a MediaStore image. MediaStore IDs are unique and never
     * reused on a device, unlike file names (many cameras repeat `IMG_0001`).
     */
    fun queueId(mediaStoreId: Long) = "$ID_PREFIX$mediaStoreId"

    fun clampMaxFileMb(mb: Int) = mb.coerceIn(1, MAX_FILE_MB_LIMIT)

    fun maxBytes(mb: Int) = clampMaxFileMb(mb) * 1_000_000L

    /** JPEG, PNG, WebP, HEIC, GIF… any image except vector SVG. */
    fun isSupportedImage(mimeType: String?) =
        mimeType != null && mimeType.startsWith("image/") && !mimeType.startsWith("image/svg")

    fun isEligible(mimeType: String?, sizeBytes: Long, maxBytes: Long) =
        isSupportedImage(mimeType) && sizeBytes in 1..maxBytes

    fun safeFileName(displayName: String?, mediaStoreId: Long, mimeType: String?): String {
        val cleaned = displayName.orEmpty().replace(Regex("[^A-Za-z0-9._-]"), "_").trim('.', '_')
        if (cleaned.isNotEmpty() && '.' in cleaned) return cleaned
        val extension = when (mimeType) {
            "image/jpeg" -> "jpg"
            "image/png" -> "png"
            "image/webp" -> "webp"
            "image/gif" -> "gif"
            "image/heic" -> "heic"
            "image/heif" -> "heif"
            else -> "img"
        }
        return (cleaned.ifEmpty { "photo_$mediaStoreId" }) + "." + extension
    }
}
