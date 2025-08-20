package com.example.voicerec.photos

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

/** How much of the photo library the user has authorized. */
enum class PhotoAccess(val wireName: String) {
    NONE("none"),

    /** Android 14+ "Select photos": only the photos the user picked. */
    PARTIAL("partial"),
    FULL("full");

    companion object {
        fun current(context: Context): PhotoAccess {
            fun granted(permission: String) =
                context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
            return when {
                Build.VERSION.SDK_INT >= 34 -> when {
                    granted(Manifest.permission.READ_MEDIA_IMAGES) -> FULL
                    granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) -> PARTIAL
                    else -> NONE
                }
                Build.VERSION.SDK_INT >= 33 ->
                    if (granted(Manifest.permission.READ_MEDIA_IMAGES)) FULL else NONE
                else ->
                    if (granted(Manifest.permission.READ_EXTERNAL_STORAGE)) FULL else NONE
            }
        }

        /** Runtime permissions to request. Only images are ever requested, never video or audio. */
        fun permissionsToRequest(): Array<String> = when {
            Build.VERSION.SDK_INT >= 34 -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
            Build.VERSION.SDK_INT >= 33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
            else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

        /** The permission whose rationale state tells us whether the dialog can still be shown. */
        fun primaryPermission(): String =
            if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES
            else Manifest.permission.READ_EXTERNAL_STORAGE
    }
}
