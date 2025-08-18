import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/contacts_backup_state.dart';
import '../services/contacts_backup_service.dart';

/// State for the local Contacts Backup screen.
class ContactsBackupController extends ChangeNotifier {
  ContactsBackupController({ContactsBackupService? service})
    : _service = service ?? ContactsBackupService();

  final ContactsBackupService _service;
  final _messages = StreamController<String>.broadcast();

  ContactsBackupState _state = const ContactsBackupState();
  bool _isExporting = false;
  bool _permanentlyDenied = false;
  bool _disposed = false;

  ContactsBackupState get state => _state;
  bool get isExporting => _isExporting;
  bool get permanentlyDenied => _permanentlyDenied && !_state.permissionGranted;
  Stream<String> get messages => _messages.stream;

  Future<void> init() => refresh();

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
      _messages.add('Saved $count contacts to this device.');
    } on PlatformException catch (e) {
      _permanentlyDenied = e.code == 'PERMISSION_PERMANENTLY_DENIED';
      _messages.add(e.message ?? 'Contacts backup failed');
    } finally {
      _isExporting = false;
      await refresh();
    }
  }

  Future<void> openAppSettings() => _service.openAppSettings();

  @override
  void dispose() {
    _disposed = true;
    _messages.close();
    super.dispose();
  }
}
