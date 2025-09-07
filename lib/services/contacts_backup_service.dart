import 'package:flutter/services.dart';

import '../models/contacts_backup_state.dart';

/// Talks to the native contacts backup module. The `.vcf` upload itself goes
/// through the shared Telegram upload queue (see `BackupService.updates`).
class ContactsBackupService {
  static const _methods = MethodChannel('com.example.voicerec/contacts');

  Future<ContactsBackupState> getState() async {
    final map = await _methods.invokeMapMethod<String, dynamic>('getState');
    return map == null
        ? const ContactsBackupState()
        : ContactsBackupState.fromMap(map);
  }

  /// Asks for contacts permission if needed, exports a `.vcf` and queues it.
  /// Returns the number of contacts exported.
  ///
  /// Throws a [PlatformException] with codes such as `PERMISSION_DENIED`,
  /// `PERMISSION_PERMANENTLY_DENIED`, `NO_CONTACTS`, `IN_PROGRESS`,
  /// `NOT_CONFIGURED` or `EXPORT_FAILED`.
  Future<int> backUpNow() async {
    final result = await _methods.invokeMapMethod<String, dynamic>('backUpNow');
    return result?['contactCount'] as int? ?? 0;
  }

  Future<void> retryUpload() => _methods.invokeMethod<void>('retryUpload');

  Future<void> openAppSettings() =>
      _methods.invokeMethod<void>('openAppSettings');
}
