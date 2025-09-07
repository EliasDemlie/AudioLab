package com.example.voicerec.backup

enum class UploadStatus(val wireName: String) {
    PENDING("pending"),
    UPLOADING("uploading"),
    UPLOADED("uploaded"),
    FAILED("failed");

    companion object {
        fun fromWire(value: String?): UploadStatus = entries.firstOrNull { it.wireName == value } ?: PENDING
    }
}

/** One recording's Telegram backup, as stored in the upload queue. */
data class UploadRecord(
    /**
     * Unique per uploaded file: the file name without extension, e.g.
     * `rec_20261012_174451` for a recording or `contacts_20261012_174451` for
     * a contacts backup.
     */
    val recordingId: String,
    val filePath: String,
    val status: UploadStatus,
    /** 0.0–1.0 while uploading. */
    val progress: Float = 0f,
    val attempts: Int = 0,
    val lastError: String? = null,
    val telegramMessageId: Long? = null,
    val telegramFileId: String? = null,
    val updatedAtMillis: Long = 0,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "recordingId" to recordingId,
        "filePath" to filePath,
        "status" to status.wireName,
        "progress" to progress.toDouble(),
        "attempts" to attempts,
        "error" to lastError,
        "telegramMessageId" to telegramMessageId,
        "updatedAtMillis" to updatedAtMillis,
    )
}

/** Persistence used by [UploadProcessor]; an interface so it can be faked in tests. */
interface UploadStore {
    fun get(recordingId: String): UploadRecord?
    fun markUploading(recordingId: String)
    fun updateProgress(recordingId: String, progress: Float)
    fun markUploaded(recordingId: String, messageId: Long, fileId: String?, response: String)
    fun markPending(recordingId: String, error: String)
    fun markFailed(recordingId: String, error: String)
}
