package com.beamlinetech.audiolab.recorder

import android.app.ActivityManager
import android.content.Context
import android.util.Log

/**
 * Hides the app's card from Recents while recording.
 *

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
