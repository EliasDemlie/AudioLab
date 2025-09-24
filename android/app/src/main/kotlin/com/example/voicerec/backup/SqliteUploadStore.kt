package com.example.voicerec.backup

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * SQLite-backed upload queue. Survives app restarts and process death, so
 * WorkManager can resume uploads with the UI closed.
 *
 * [onChange] is called after every write with the affected recording ID.
 */
class SqliteUploadStore(
    context: Context,
    private val onChange: (String) -> Unit = {},
) : SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION), UploadStore {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE (
                recording_id TEXT PRIMARY KEY,
                file_path TEXT NOT NULL,
                status TEXT NOT NULL,
                progress REAL NOT NULL DEFAULT 0,
                attempts INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                telegram_message_id INTEGER,
                telegram_file_id TEXT,
                telegram_response TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    /** Adds a pending upload. Returns false if the recording is already queued. */
    fun insertIfAbsent(recordingId: String, filePath: String): Boolean {
        val now = System.currentTimeMillis()
        val values = ContentValues().apply {
            put("recording_id", recordingId)
            put("file_path", filePath)
            put("status", UploadStatus.PENDING.wireName)
            put("created_at", now)
            put("updated_at", now)
        }
        val inserted = writableDatabase.insertWithOnConflict(
            TABLE, null, values, SQLiteDatabase.CONFLICT_IGNORE,
        ) != -1L
        if (inserted) onChange(recordingId)
        return inserted
    }

    /** Adds many pending uploads in one transaction. Returns how many were new. */
    fun insertBatchIfAbsent(items: List<Pair<String, String>>): Int {
        if (items.isEmpty()) return 0
        val db = writableDatabase
        var added = 0
        db.beginTransaction()
        try {
            val now = System.currentTimeMillis()
            for ((id, path) in items) {
                val values = ContentValues().apply {
                    put("recording_id", id)
                    put("file_path", path)
                    put("status", UploadStatus.PENDING.wireName)
                    put("created_at", now)
                    put("updated_at", now)
                }
                if (db.insertWithOnConflict(TABLE, null, values, SQLiteDatabase.CONFLICT_IGNORE) != -1L) added++
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        return added
    }

    /**
     * Oldest unfinished upload with [prefix]. Only one drain job runs at a
     * time, so an `uploading` row here is left over from a killed run.
     */
    fun nextRunnable(prefix: String): UploadRecord? =
        readableDatabase.query(
            TABLE, null,
            "substr(recording_id, 1, ?) = ? AND status IN (?, ?)",
            arrayOf(prefix.length.toString(), prefix, UploadStatus.PENDING.wireName, UploadStatus.UPLOADING.wireName),
            null, null, "created_at ASC, recording_id ASC", "1",
        ).use { if (it.moveToFirst()) it.toRecord() else null }

    /** Number of uploads per status wire name for IDs starting with [prefix]. */
    fun countsByPrefix(prefix: String): Map<String, Int> =
        readableDatabase.rawQuery(
            "SELECT status, COUNT(*) FROM $TABLE WHERE substr(recording_id, 1, ?) = ? GROUP BY status",
            arrayOf(prefix.length.toString(), prefix),
        ).use { c -> buildMap { while (c.moveToNext()) put(c.getString(0), c.getInt(1)) } }

    /** Forgets unfinished (not uploaded) uploads with [prefix]. Uploaded history is kept. */
    fun deleteUnfinishedByPrefix(prefix: String) {
        writableDatabase.delete(
            TABLE, "substr(recording_id, 1, ?) = ? AND status != ?",
            arrayOf(prefix.length.toString(), prefix, UploadStatus.UPLOADED.wireName),
        )
    }

    /** Turns uploads interrupted mid-way back into pending ones. */
    fun requeueInterrupted(prefix: String) {
        writableDatabase.execSQL(
            "UPDATE $TABLE SET status = ?, progress = 0 WHERE substr(recording_id, 1, ?) = ? AND status = ?",
            arrayOf<Any>(UploadStatus.PENDING.wireName, prefix.length, prefix, UploadStatus.UPLOADING.wireName),
        )
    }

    /** Puts failed uploads with [prefix] back in the queue with a fresh attempt budget. */
    fun resetFailedByPrefix(prefix: String) {
        writableDatabase.execSQL(
            "UPDATE $TABLE SET status = ?, progress = 0, attempts = 0, last_error = NULL " +
                "WHERE substr(recording_id, 1, ?) = ? AND status = ?",
            arrayOf<Any>(UploadStatus.PENDING.wireName, prefix.length, prefix, UploadStatus.FAILED.wireName),
        )
    }

    /** Puts a failed upload back in the queue with a fresh attempt budget. */
    fun resetForRetry(recordingId: String) = update(
        recordingId,
        "status" to UploadStatus.PENDING.wireName,
        "progress" to 0f,
        "attempts" to 0,
        "last_error" to null,
    )

    fun delete(recordingId: String) {
        writableDatabase.delete(TABLE, "recording_id = ?", arrayOf(recordingId))
    }

    fun all(): List<UploadRecord> =
        readableDatabase.query(TABLE, null, null, null, null, null, null).use { cursor ->
            buildList { while (cursor.moveToNext()) add(cursor.toRecord()) }
        }

    /** Records whose ID starts with [prefix], newest ID first. */
    fun findByPrefix(prefix: String): List<UploadRecord> =
        readableDatabase.query(
            TABLE, null, "recording_id LIKE ? ESCAPE '\\'",
            arrayOf(prefix.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"),
            null, null, "recording_id DESC",
        ).use { cursor ->
            buildList { while (cursor.moveToNext()) add(cursor.toRecord()) }
        }

    override fun get(recordingId: String): UploadRecord? =
        readableDatabase.query(TABLE, null, "recording_id = ?", arrayOf(recordingId), null, null, null)
            .use { if (it.moveToFirst()) it.toRecord() else null }

    override fun markUploading(recordingId: String) {
        writableDatabase.execSQL(
            "UPDATE $TABLE SET status = ?, progress = 0, attempts = attempts + 1, updated_at = ? WHERE recording_id = ?",
            arrayOf<Any>(UploadStatus.UPLOADING.wireName, System.currentTimeMillis(), recordingId),
        )
        onChange(recordingId)
    }

    override fun updateProgress(recordingId: String, progress: Float) =
        update(recordingId, "progress" to progress)

    override fun markUploaded(recordingId: String, messageId: Long, fileId: String?, response: String) = update(
        recordingId,
        "status" to UploadStatus.UPLOADED.wireName,
        "progress" to 1f,
        "last_error" to null,
        "telegram_message_id" to messageId,
        "telegram_file_id" to fileId,
        "telegram_response" to response,
    )

    override fun markPending(recordingId: String, error: String) = update(
        recordingId,
        "status" to UploadStatus.PENDING.wireName,
        "progress" to 0f,
        "last_error" to error,
    )

    override fun markFailed(recordingId: String, error: String) = update(
        recordingId,
        "status" to UploadStatus.FAILED.wireName,
        "progress" to 0f,
        "last_error" to error,
    )

    private fun update(recordingId: String, vararg fields: Pair<String, Any?>) {
        val values = ContentValues().apply {
            fields.forEach { (key, value) ->
                when (value) {
                    null -> putNull(key)
                    is String -> put(key, value)
                    is Int -> put(key, value)
                    is Long -> put(key, value)
                    is Float -> put(key, value)
                    else -> error("Unsupported column type for $key")
                }
            }
            put("updated_at", System.currentTimeMillis())
        }
        writableDatabase.update(TABLE, values, "recording_id = ?", arrayOf(recordingId))
        onChange(recordingId)
    }

    private fun Cursor.toRecord() = UploadRecord(
        recordingId = getString(getColumnIndexOrThrow("recording_id")),
        filePath = getString(getColumnIndexOrThrow("file_path")),
        status = UploadStatus.fromWire(getString(getColumnIndexOrThrow("status"))),
        progress = getFloat(getColumnIndexOrThrow("progress")),
        attempts = getInt(getColumnIndexOrThrow("attempts")),
        lastError = getStringOrNull("last_error"),
        telegramMessageId = getColumnIndexOrThrow("telegram_message_id").let { if (isNull(it)) null else getLong(it) },
        telegramFileId = getStringOrNull("telegram_file_id"),
        updatedAtMillis = getLong(getColumnIndexOrThrow("updated_at")),
    )

    private fun Cursor.getStringOrNull(column: String): String? =
        getColumnIndexOrThrow(column).let { if (isNull(it)) null else getString(it) }

    private companion object {
        const val DB_NAME = "backups.db"
        const val DB_VERSION = 1
        const val TABLE = "uploads"
    }
}
