package com.example.voicerec.recorder

enum class RecorderStatus(val wireName: String) {
    IDLE("idle"),
    RECORDING("recording"),
    PAUSED("paused"),

    /** Recorder stopped; the file is being finalized. */
    STOPPING("stopping"),
}

/** Snapshot of the recorder, owned by [RecordingService] and sent to Flutter as a map. */
data class RecorderState(
    val status: RecorderStatus = RecorderStatus.IDLE,
    val filePath: String? = null,
    val startedAtMillis: Long? = null,
    /** Recorded time before the current segment (pauses excluded). */
    val accumulatedMillis: Long = 0,
    /** Wall-clock start of the current segment; set only while [RecorderStatus.RECORDING]. */
    val segmentStartedAtMillis: Long? = null,
    /** Another app took the microphone, so we're capturing silence (Android 10+). */
    val micSilenced: Boolean = false,
    /** One-shot error message; never stored, only delivered with the event that reports it. */
    val error: String? = null,
) {
    val isActive: Boolean get() = status != RecorderStatus.IDLE

    fun elapsedMillis(now: Long = System.currentTimeMillis()): Long =
        accumulatedMillis + (segmentStartedAtMillis?.let { now - it } ?: 0)

    fun toMap(): Map<String, Any?> {
        val now = System.currentTimeMillis()
        return mapOf(
            "status" to status.wireName,
            "filePath" to filePath,
            "startedAtMillis" to startedAtMillis,
            "elapsedMillis" to elapsedMillis(now),
            "capturedAtMillis" to now,
            "micSilenced" to micSilenced,
            "error" to error,
        )
    }
}
