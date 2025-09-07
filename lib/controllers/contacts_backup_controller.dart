import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/contacts_backup_state.dart';
import '../models/upload_status.dart';
import '../services/backup_service.dart';
import '../services/contacts_backup_service.dart';

/// State for the Contacts Backup screen.
class ContactsBackupController extends ChangeNotifier {
  ContactsBackupController({
    ContactsBackupService? service,
    BackupService? backup,
  }) : _service = service ?? ContactsBackupService(),
       _backup = backup ?? BackupService();

  final ContactsBackupService _service;
  final BackupService _backup;
  final _messages = StreamController<String>.broadcast();

  StreamSubscription<UploadStatus>? _uploadSub;
  bool _disposed = false;

  ContactsBackupState _state = const ContactsBackupState();
  bool _isExporting = false;
  bool _permanentlyDenied = false;

  ContactsBackupState get state => _state;

  /// Reading contacts and writing the `.vcf` (before the upload starts).
  bool get isExporting => _isExporting;

  /// The permission dialog won't show again; the user must use Settings.
  bool get permanentlyDenied => _permanentlyDenied && !_state.permissionGranted;

  /// Success and error messages to show to the user.
  Stream<String> get messages => _messages.stream;

  Future<void> init() async {
    _uploadSub = _backup.updates
        .where((u) => u.filePath.endsWith('.vcf'))
        .listen((_) => refresh());
    await refresh();
  }

  Future<void> refresh() async {
    try {
      final state = await _service.getState();
      if (_disposed) return;
      _state = state;
      notifyListeners();
    } on PlatformException catch (e) {
      _messages.add(e.message ?? 'Could not read backup status');
    }
  }

  Future<void> backUpNow() async {
    if (_isExporting) return;
    _isExporting = true;
    notifyListeners();
    try {
      final count = await _service.backUpNow();
      _permanentlyDenied = false;
      _messages.add('Exported $count contacts. Uploading to Telegram…');
    } on PlatformException catch (e) {
      _permanentlyDenied = e.code == 'PERMISSION_PERMANENTLY_DENIED';
      _messages.add(e.message ?? 'Contacts backup failed');
    } finally {
      _isExporting = false;
      await refresh();
    }
  }

  Future<void> retryUpload() async {
    try {
      await _service.retryUpload();
      await refresh();
    } on PlatformException catch (e) {
      _messages.add(e.message ?? 'Could not retry upload');
    }
  }

  Future<void> openAppSettings() => _service.openAppSettings();

  @override
  void dispose() {
    _disposed = true;
    _uploadSub?.cancel();
    _messages.close();
    super.dispose();
  }
}
