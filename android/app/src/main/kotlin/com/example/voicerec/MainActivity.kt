package com.example.voicerec

import com.example.voicerec.backup.BackupChannel
import com.example.voicerec.contacts.ContactsChannel
import com.example.voicerec.recorder.RecorderChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var recorderChannel: RecorderChannel? = null
    private var backupChannel: BackupChannel? = null
    private var contactsChannel: ContactsChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        recorderChannel = RecorderChannel(this, messenger)
        backupChannel = BackupChannel(applicationContext, messenger)
        contactsChannel = ContactsChannel(this, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // The UI is going away; recording and uploads continue on their own.
        recorderChannel?.dispose()
        recorderChannel = null
        backupChannel?.dispose()
        backupChannel = null
        contactsChannel?.dispose()
        contactsChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        recorderChannel?.onRequestPermissionsResult(requestCode)
        contactsChannel?.onRequestPermissionsResult(requestCode)
    }
}
