package com.example.voicerec.photos

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


class PhotoChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)

    /** A call waiting for the permission dialog. [includeExisting] is null for `manageAccess`. */
    private class PendingRequest(val result: MethodChannel.Result, val includeExisting: Boolean?)

    private var pending: PendingRequest? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pending = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getState" -> reply(result) { PhotoBackup.state(activity) }
            "enable" -> enable(call.argument<Boolean>("includeExisting") ?: false, result)
            "disable" -> reply(result) {
                PhotoBackup.disable(activity, call.argument<Boolean>("clearPending") ?: false)
                PhotoBackup.state(activity)
            }
            "setPaused" -> reply(result) {
                PhotoBackup.setPaused(activity, call.argument<Boolean>("paused") ?: false)
                PhotoBackup.state(activity)
            }
            "updateSettings" -> reply(result) {
                call.argument<Boolean>("wifiOnly")?.let { PhotoBackup.setWifiOnly(activity, it) }
                call.argument<Int>("maxFileMb")?.let { PhotoBackup.setMaxFileMb(activity, it) }
                call.argument<Boolean>("includeExisting")?.let { PhotoBackup.setIncludeExisting(activity, it) }
                PhotoBackup.state(activity)
            }
            "markPromptShown" -> reply(result) {
                PhotoSettings(activity).promptShown = true
                PhotoBackup.state(activity)
            }
            "manageAccess" -> manageAccess(result)
            "scanNow" -> reply(result) {
                PhotoBackup.ensureWatchersIfEnabled(activity)
                PhotoBackup.scan(activity, forceDrain = true)
                PhotoBackup.state(activity)
            }
            "retryFailed" -> reply(result) {
                PhotoBackup.retryFailed(activity)
                PhotoBackup.state(activity)
            }
            "openAppSettings" -> {
                activity.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.fromParts("package", activity.packageName, null)),
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Runs [work] on the photo thread (database / MediaStore) and replies on the UI thread. */
    private fun reply(result: MethodChannel.Result, work: () -> Any?) {
        PhotoBackup.executor.execute {
            val outcome = runCatching(work)
            activity.runOnUiThread {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error("PHOTO_BACKUP_FAILED", it.message ?: "Photo backup failed", null) },
                )
            }
        }
    }

    private fun enable(includeExisting: Boolean, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("BUSY", "Already waiting for permission.", null)
            return
        }
        if (PhotoAccess.current(activity) != PhotoAccess.NONE) {
            finishEnable(includeExisting, result)
            return
        }
        pending = PendingRequest(result, includeExisting)
        activity.requestPermissions(PhotoAccess.permissionsToRequest(), PERMISSION_REQUEST_CODE)
    }

    /** Lets the user change which photos are shared (Android 14+), or opens Settings on older versions. */
    private fun manageAccess(result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT < 34 || pending != null) {
            result.error("USE_SETTINGS", "Change photo access in the system settings.", null)
            return
        }
        pending = PendingRequest(result, null)
        activity.requestPermissions(PhotoAccess.permissionsToRequest(), PERMISSION_REQUEST_CODE)
    }

    fun onRequestPermissionsResult(requestCode: Int) {
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val request = pending ?: return
        pending = null

        val access = PhotoAccess.current(activity)
        when {
            access != PhotoAccess.NONE && request.includeExisting != null ->
                finishEnable(request.includeExisting, request.result)
            access != PhotoAccess.NONE -> {
                PhotoBackup.scanAsync(activity, forceDrain = true)
                reply(request.result) { PhotoBackup.state(activity) }
            }
            // Nothing is scanned or uploaded without access.
            request.includeExisting == null -> reply(request.result) { PhotoBackup.state(activity) }
            // Denied with "Don't ask again": the dialog won't show again.
            !activity.shouldShowRequestPermissionRationale(PhotoAccess.primaryPermission()) -> request.result.error(
                "PERMISSION_PERMANENTLY_DENIED",
                "Photo access is turned off. Allow it in Settings to use automatic photo backup.",
                null,
            )
            else -> request.result.error(
                "PERMISSION_DENIED",
                "Photo access is required for automatic photo backup. Nothing was scanned or uploaded.",
                null,
            )
        }
    }

    private fun finishEnable(includeExisting: Boolean, result: MethodChannel.Result) =
        reply(result) {
            PhotoBackup.enable(activity, includeExisting)
            PhotoBackup.state(activity)
        }

    companion object {
        const val CHANNEL = "com.example.voicerec/photos"
        private const val PERMISSION_REQUEST_CODE = 4203
    }
}
