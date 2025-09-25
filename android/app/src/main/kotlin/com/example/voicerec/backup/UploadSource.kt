package com.example.voicerec.backup

import java.io.File

/**
 * Optional hook that lets [UploadProcessor] upload things that aren't plain
 * files on disk (e.g. photos behind a content URI). Records it doesn't
 * [handle] use their `filePath` directly, exactly as before.
 */
interface UploadSource {
    fun handles(record: UploadRecord): Boolean

    /** Called right before each upload attempt. */
    fun open(record: UploadRecord): Resolved

    sealed interface Resolved {
        /** A local file ready to send. [release] is always called afterwards. */
        class Ready(
            val file: File,
            val caption: String? = null,
            val release: () -> Unit = {},
        ) : Resolved

        /** Uploads aren't allowed right now (paused, disabled, access revoked). Not an error. */
        data class Blocked(val message: String) : Resolved

        /** The item can never be uploaded (deleted, too large…). */
        data class Unavailable(val message: String) : Resolved
    }
}
