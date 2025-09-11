package com.example.voicerec.recorder

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.io.File
import java.util.Locale
import java.util.UUID

/** Persistent catalog metadata for real audio files in the recordings directory. */
class RecordingLibraryDatabase(context: Context) :
    SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    override fun onConfigure(db: SQLiteDatabase) {
        db.setForeignKeyConstraintsEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE folders (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL COLLATE NOCASE UNIQUE,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )""".trimIndent(),
        )
        db.execSQL(
            """CREATE TABLE tags (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL COLLATE NOCASE UNIQUE,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            )""".trimIndent(),
        )
        db.execSQL(
            """CREATE TABLE recordings (
                id TEXT PRIMARY KEY NOT NULL,
                file_path TEXT NOT NULL UNIQUE,
                title TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                file_size INTEGER NOT NULL DEFAULT 0,
                duration_ms INTEGER,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                note TEXT NOT NULL DEFAULT '',
                folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL,
                deleted_at INTEGER
            )""".trimIndent(),
        )
        db.execSQL(
            """CREATE TABLE recording_tags (
                recording_id TEXT NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
                tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
                PRIMARY KEY (recording_id, tag_id)
            )""".trimIndent(),
        )
        db.execSQL("CREATE INDEX recordings_created_at ON recordings(created_at)")
        db.execSQL("CREATE INDEX recordings_deleted_at ON recordings(deleted_at)")
        db.execSQL("CREATE INDEX recordings_folder_id ON recordings(folder_id)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Schema changes will be added here as the recording library grows.
    }

    /** Adds actual audio files to the catalog without overwriting user metadata. */
    fun synchronize(files: List<Map<String, Any?>>): List<Map<String, Any?>> {
        val db = writableDatabase
        db.beginTransaction()
        try {
            files.forEach { file ->
                val path = file["path"] as? String ?: return@forEach
                val modifiedAt = (file["modifiedAtMillis"] as? Number)?.toLong()
                    ?: System.currentTimeMillis()
                val duration = (file["durationMillis"] as? Number)?.toLong()
                val size = (file["sizeBytes"] as? Number)?.toLong() ?: 0L
                val existingId = db.query(
                    TABLE_RECORDINGS,
                    arrayOf("id"),
                    "file_path = ?",
                    arrayOf(path),
                    null,
                    null,
                    null,
                    "1",
                ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }

                if (existingId == null) {
                    val source = File(path)
                    val title = source.nameWithoutExtension.ifBlank { source.name }
                    val measuredDuration = duration ?: RecordingFiles.durationMillis(source)
                    db.insertOrThrow(
                        TABLE_RECORDINGS,
                        null,
                        ContentValues().apply {
                            put("id", UUID.randomUUID().toString())
                            put("file_path", path)
                            put("title", title)
                            put("created_at", modifiedAt)
                            put("updated_at", modifiedAt)
                            put("file_size", size)
                            if (measuredDuration == null) {
                                putNull("duration_ms")
                            } else {
                                put("duration_ms", measuredDuration)
                            }
                        },
                    )
                } else {
                    db.update(
                        TABLE_RECORDINGS,
                        ContentValues().apply {
                            put("file_size", size)
                            if (duration != null) put("duration_ms", duration)
                        },
                        "id = ?",
                        arrayOf(existingId),
                    )
                }
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        return listAll()
    }

    /** Keeps a stable catalog ID when a recording file is renamed. */
    fun updateFilePath(oldPath: String, newPath: String, title: String) {
        val db = writableDatabase
        val oldId = db.query(
            TABLE_RECORDINGS,
            arrayOf("id"),
            "file_path = ?",
            arrayOf(oldPath),
            null,
            null,
            null,
            "1",
        ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }

        if (oldId == null) {
            val alreadyCataloged = db.query(
                TABLE_RECORDINGS,
                arrayOf("id"),
                "file_path = ?",
                arrayOf(newPath),
                null,
                null,
                null,
                "1",
            ).use { cursor -> cursor.moveToFirst() }
            if (!alreadyCataloged) {
                synchronize(
                    listOf(
                        mapOf(
                            "path" to newPath,
                            "modifiedAtMillis" to File(newPath).lastModified(),
                            "sizeBytes" to File(newPath).length(),
                            "durationMillis" to RecordingFiles.durationMillis(File(newPath)),
                        ),
                    ),
                )
            }
        } else {
            db.beginTransaction()
            try {
                // A concurrent library refresh can discover the new path before
                // this update arrives. Keep the original UUID and its metadata.
                db.delete(
                    TABLE_RECORDINGS,
                    "file_path = ? AND id != ?",
                    arrayOf(newPath, oldId),
                )
                db.update(
                    TABLE_RECORDINGS,
                    ContentValues().apply {
                        put("file_path", newPath)
                        put("title", title)
                        put("updated_at", System.currentTimeMillis())
                    },
                    "id = ?",
                    arrayOf(oldId),
                )
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        }
        db.update(
            TABLE_RECORDINGS,
            ContentValues().apply {
                put("title", title)
                put("updated_at", System.currentTimeMillis())
            },
            "file_path = ?",
            arrayOf(newPath),
        )
    }

    fun removeByPath(path: String) {
        writableDatabase.delete(TABLE_RECORDINGS, "file_path = ?", arrayOf(path))
    }

    /** Includes unavailable files so the library can offer an explicit recovery/removal state. */
    fun listAll(): List<Map<String, Any?>> {
        val db = readableDatabase
        val tagsByRecording = mutableMapOf<String, MutableList<String>>()
        db.rawQuery(
            """SELECT recording_tags.recording_id, tags.name
               FROM recording_tags INNER JOIN tags ON tags.id = recording_tags.tag_id
               ORDER BY tags.name COLLATE NOCASE""".trimIndent(),
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                tagsByRecording.getOrPut(cursor.getString(0)) { mutableListOf() }
                    .add(cursor.getString(1))
            }
        }

        val recordings = mutableListOf<Map<String, Any?>>()
        db.query(
            TABLE_RECORDINGS,
            arrayOf(
                "id", "file_path", "title", "created_at", "updated_at", "file_size",
                "duration_ms", "is_favorite", "note", "folder_id", "deleted_at",
            ),
            null,
            null,
            null,
            null,
            "created_at DESC, id ASC",
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val path = cursor.getString(1)
                val file = File(path)
                recordings += mapOf(
                    "id" to cursor.getString(0),
                    "path" to path,
                    "title" to cursor.getString(2),
                    "createdAtMillis" to cursor.getLong(3),
                    "updatedAtMillis" to cursor.getLong(4),
                    "sizeBytes" to cursor.getLong(5),
                    "durationMillis" to if (cursor.isNull(6)) null else cursor.getLong(6),
                    "isFavorite" to (cursor.getInt(7) != 0),
                    "note" to cursor.getString(8),
                    "folderId" to if (cursor.isNull(9)) null else cursor.getString(9),
                    "deletedAtMillis" to if (cursor.isNull(10)) null else cursor.getLong(10),
                    "format" to file.extension.uppercase(Locale.US),
                    "audioAvailable" to file.isFile,
                    "tags" to tagsByRecording[cursor.getString(0)].orEmpty(),
                )
            }
        }
        return recordings
    }

    companion object {
        private const val DATABASE_NAME = "recording_library.db"
        private const val DATABASE_VERSION = 1
        private const val TABLE_RECORDINGS = "recordings"
    }
}
