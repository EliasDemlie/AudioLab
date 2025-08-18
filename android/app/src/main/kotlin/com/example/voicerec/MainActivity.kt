package com.example.voicerec

import com.example.voicerec.contacts.ContactsChannel
import com.example.voicerec.recorder.RecorderChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var recorderChannel: RecorderChannel? = null
    private var contactsChannel: ContactsChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        recorderChannel = RecorderChannel(this, messenger)
        contactsChannel = ContactsChannel(this, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Recording continues on its own when the UI goes away.
        recorderChannel?.dispose()
        recorderChannel = null
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
