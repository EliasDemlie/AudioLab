package com.example.voicerec.recorder

import android.app.ActivityManager
import android.content.Context
import android.util.Log

/**
 * Hides the app's card from Recents while recording.
 *
 * Some OEM ROMs (e.g. TECNO/Infinix HiOS "Swipe-up clean") kill the whole app,
 * foreground service included, when its card is swiped away. With no card,
 * there is nothing to swipe; the user returns via the launcher icon or the
 * recording notification. The card comes back when recording ends.
 */
object RecentsVisibility {
    private const val TAG = "RecentsVisibility"

    fun setHidden(context: Context, hidden: Boolean) {
        try {
            context.getSystemService(ActivityManager::class.java)
                .appTasks
                .forEach { it.setExcludeFromRecents(hidden) }
        } catch (e: Exception) {
            // A task can disappear while we iterate; visibility is best-effort.
            Log.w(TAG, "Could not update Recents visibility", e)
        }
    }
}
