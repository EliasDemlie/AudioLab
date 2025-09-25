import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/photo_backup_state.dart';
import '../services/backup_service.dart';
import '../services/photo_backup_service.dart';

/// State for the Automatic Photo Backup screen.
class PhotoBackupController extends ChangeNotifier {
  PhotoBackupController({PhotoBackupService? service, BackupService? backup})
    : _service = service ?? PhotoBackupService(),
      _backup = backup ?? BackupService();

  final PhotoBackupService _service;
  final BackupService _backup;
  final _messages = StreamController<String>.broadcast();

  StreamSubscription<dynamic>? _uploadSub;
  Timer? _refreshTimer;
  bool _disposed = false;

  PhotoBackupState _state = const PhotoBackupState();
  bool _isBusy = false;
  bool _permanentlyDenied = false;

  PhotoBackupState get state => _state;

  /// A change is being applied (permission dialog, scan…).
  bool get isBusy => _isBusy;

  /// The permission dialog won't show again; the user must use Settings.
  bool get permanentlyDenied =>
      _permanentlyDenied && _state.access == PhotoAccess.none;

  Stream<String> get messages => _messages.stream;

  Future<void> init() async {
    // Photo uploads are the only ones whose path is a content:// URI.
    // Coalesce bursts of progress events into one refresh.
    _uploadSub = _backup.updates
        .where((u) => u.filePath.startsWith('content://'))
        .listen((_) {
          _refreshTimer?.cancel();
          _refreshTimer = Timer(const Duration(milliseconds: 600), refresh);
        });
    await refresh();
  }

  Future<void> refresh() => _apply(_service.getState);

  /// Picks up new photos now (when the app is opened or the user asks).
  Future<void> scanNow() => _apply(_service.scanNow);

  Future<void> enable({required bool includeExisting}) async {
    if (_isBusy) return;
    _isBusy = true;
    notifyListeners();
    try {
      await _apply(() => _service.enable(includeExisting: includeExisting));
      _permanentlyDenied = false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> disable({required bool clearPending}) =>
      _apply(() => _service.disable(clearPending: clearPending));

  Future<void> setPaused(bool paused) =>
      _apply(() => _service.setPaused(paused));

  Future<void> setWifiOnly(bool value) =>
      _apply(() => _service.updateSettings(wifiOnly: value));

  Future<void> setMaxFileMb(int value) =>
      _apply(() => _service.updateSettings(maxFileMb: value));

  Future<void> setIncludeExisting(bool value) =>
      _apply(() => _service.updateSettings(includeExisting: value));

  Future<void> retryFailed() => _apply(_service.retryFailed);

  /// Lets the user change which photos are shared; falls back to Settings.
  Future<void> manageAccess() async {
    if (!_state.canManageSelection) return openAppSettings();
    await _apply(_service.manageAccess);
  }

  Future<void> openAppSettings() => _service.openAppSettings();

  Future<void> _apply(Future<PhotoBackupState> Function() action) async {
    try {
      final state = await action();
      if (_disposed) return;
      _state = state;
      notifyListeners();
    } on PlatformException catch (e) {
      _permanentlyDenied = e.code == 'PERMISSION_PERMANENTLY_DENIED';
      if (e.code == 'USE_SETTINGS') {
        await openAppSettings();
        return;
      }
      _messages.add(e.message ?? 'Photo backup failed');
      if (!_disposed) await _refreshQuietly();
    }
  }

  Future<void> _refreshQuietly() async {
    try {
      _state = await _service.getState();
      notifyListeners();
    } on PlatformException {
      // Keep the last known state.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _uploadSub?.cancel();
    _messages.close();
    super.dispose();
  }
}
