package com.example.voicerec.contacts

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge between Flutter and [ContactsBackup].
 *
 * Methods: `getState`, `backUpNow`, `retryUpload`, `openAppSettings`.
 * Upload progress arrives on the existing backup event channel.
 */
class ContactsChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)

    /** `backUpNow` call waiting for the permission dialog. */
    private var pendingBackup: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingBackup = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getState" -> result.success(ContactsBackup.state(activity))
            "backUpNow" -> backUpNow(result)
            "retryUpload" -> result.success(ContactsBackup.retryLatest(activity))
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

    fun onRequestPermissionsResult(requestCode: Int) {
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val result = pendingBackup ?: return
        pendingBackup = null

        when {
            ContactsBackup.hasPermission(activity) -> runBackup(result)
            // Denied with "Don't ask again" (or denied twice): the dialog won't show again.
            !activity.shouldShowRequestPermissionRationale(Manifest.permission.READ_CONTACTS) -> result.error(
                "PERMISSION_PERMANENTLY_DENIED",
                "Contacts permission is turned off. Allow it in Settings to back up contacts.",
                null,
            )
            else -> result.error("PERMISSION_DENIED", "Contacts permission is required to back up contacts.", null)
        }
    }

    private fun backUpNow(result: MethodChannel.Result) {
        if (pendingBackup != null) {
            result.error("BUSY", "Already waiting for permission.", null)
            return
        }
        if (ContactsBackup.hasPermission(activity)) {
            runBackup(result)
            return
        }
        pendingBackup = result
        activity.requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS), PERMISSION_REQUEST_CODE)
    }

    private fun runBackup(result: MethodChannel.Result) {
        ContactsBackup.backUpNow(activity) { outcome ->
            activity.runOnUiThread {
                when (outcome) {
                    is ContactsBackup.Result.Queued -> result.success(mapOf("contactCount" to outcome.contactCount))
                    is ContactsBackup.Result.Error -> result.error(outcome.code, outcome.message, null)
                }
            }
        }
    }

    companion object {
        const val CHANNEL = "com.example.voicerec/contacts"
        private const val PERMISSION_REQUEST_CODE = 4202
    }
}
