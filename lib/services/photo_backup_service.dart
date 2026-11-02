import 'package:flutter/services.dart';

import '../models/photo_backup_state.dart';

/// Talks to the native photo backup module. Photos are uploaded through the
/// shared Telegram upload queue (see `BackupService.updates`).
class PhotoBackupService {
  static const _methods = MethodChannel('com.example.voicerec/photos');

  Future<PhotoBackupState> _state(String method, [Object? arguments]) async {
    final map = await _methods.invokeMapMethod<String, dynamic>(
      method,
      arguments,
    );
    return map == null
        ? const PhotoBackupState()
        : PhotoBackupState.fromMap(map);
  }

  Future<PhotoBackupState> getState() => _state('getState');

  /// Requests photo access if needed, then turns backup on. Nothing is read
  /// unless access is granted.
  ///
  /// Throws a [PlatformException] with `PERMISSION_DENIED` or
  /// `PERMISSION_PERMANENTLY_DENIED` if the user declines.
  Future<PhotoBackupState> enable({required bool includeExisting}) =>
      _state('enable', {'includeExisting': includeExisting});

  /// Stops discovery and scheduling. Pending items are dropped if [clearPending].
  Future<PhotoBackupState> disable({required bool clearPending}) =>
      _state('disable', {'clearPending': clearPending});

  Future<PhotoBackupState> setPaused(bool paused) =>
      _state('setPaused', {'paused': paused});

  Future<PhotoBackupState> updateSettings({
    bool? wifiOnly,
    int? maxFileMb,
    bool? includeExisting,
  }) => _state('updateSettings', {
    'wifiOnly': ?wifiOnly,
    'maxFileMb': ?maxFileMb,
    'includeExisting': ?includeExisting,
  });

  /// Reopens the system photo picker (Android 14+). Throws `USE_SETTINGS` on
  /// older versions, where access is changed in the app's system settings.
  Future<PhotoBackupState> manageAccess() => _state('manageAccess');

  /// Remembers that the one-time home-screen offer was shown.
  Future<PhotoBackupState> markPromptShown() => _state('markPromptShown');

  Future<PhotoBackupState> scanNow() => _state('scanNow');

  Future<PhotoBackupState> retryFailed() => _state('retryFailed');

  Future<void> openAppSettings() =>
      _methods.invokeMethod<void>('openAppSettings');
}
