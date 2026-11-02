package com.example.voicerec.photos

import android.content.Context
import android.content.SharedPreferences

/** User choices and scan position for automatic photo backup. Off until the user turns it on. */
class PhotoSettings(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("photo_backup", Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = prefs.getBoolean("enabled", false)
        set(value) = prefs.edit().putBoolean("enabled", value).apply()

    /** The one-time home-screen offer was shown, so it isn't repeated. */
    var promptShown: Boolean
        get() = prefs.getBoolean("promptShown", false)
        set(value) = prefs.edit().putBoolean("promptShown", value).apply()

    var paused: Boolean
        get() = prefs.getBoolean("paused", false)
        set(value) = prefs.edit().putBoolean("paused", value).apply()

    /** Existing photos are included by default; the app no longer offers a way to turn this off. */
    var includeExisting: Boolean
        get() = prefs.getBoolean("includeExisting", true)
        set(value) = prefs.edit().putBoolean("includeExisting", value).apply()

    var wifiOnly: Boolean
        get() = prefs.getBoolean("wifiOnly", true)
        set(value) = prefs.edit().putBoolean("wifiOnly", value).apply()

    var maxFileMb: Int
        get() = PhotoRules.clampMaxFileMb(prefs.getInt("maxFileMb", PhotoRules.DEFAULT_MAX_FILE_MB))
        set(value) = prefs.edit().putInt("maxFileMb", PhotoRules.clampMaxFileMb(value)).apply()

    /** "New photos only" floor: the newest photo ID at the time it was established; -1 = not yet known. */
    var baselineId: Long
        get() = prefs.getLong("baselineId", -1L)
        set(value) = prefs.edit().putLong("baselineId", value).apply()

    /** Highest photo ID already examined (full access only), so scans only look at newer ones. */
    var scannedId: Long
        get() = prefs.getLong("scannedId", 0L)
        set(value) = prefs.edit().putLong("scannedId", value).apply()

    /** Access level seen by the last scan; a change means the authorized set may have changed. */
    var lastAccess: String?
        get() = prefs.getString("lastAccess", null)
        set(value) = prefs.edit().putString("lastAccess", value).apply()

    var lastScanAtMillis: Long
        get() = prefs.getLong("lastScanAt", 0L)
        set(value) = prefs.edit().putLong("lastScanAt", value).apply()

    /** Forgets the scan position so the next scan starts over (the queue prevents duplicates). */
    fun resetScanPosition() {
        prefs.edit()
            .putLong("baselineId", if (includeExisting) 0L else -1L)
            .putLong("scannedId", 0L)
            .remove("lastAccess")
            .apply()
    }
}
