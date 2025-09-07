import 'package:flutter/services.dart';

import '../models/recording.dart';
import '../models/upload_status.dart';

/// Talks to the native Telegram backup queue (Android WorkManager).
///
/// Uploads run natively and continue when the app is closed; this only
/// observes them and requests retries.
class BackupService {
  static const _methods = MethodChannel('com.example.voicerec/backup');
  static const _events = EventChannel('com.example.voicerec/backup_events');

  /// One shared platform subscription: a second `receiveBroadcastStream` on
  /// the same channel would replace the first listener natively.
  static final Stream<UploadStatus> _updates = _events
      .receiveBroadcastStream()
      .map((event) => UploadStatus.fromMap(event as Map));

  /// Upload status changes (queued, progress, uploaded, failed) for
  /// recordings and contacts backups.
  Stream<UploadStatus> get updates => _updates;

  /// False if no bot token / channel ID was provided at build time.
  Future<bool> isConfigured() async =>
      await _methods.invokeMethod<bool>('isConfigured') ?? false;

  /// Re-queues a failed upload, or backs up a recording never queued.
  Future<void> retry(Recording recording) =>
      _methods.invokeMethod<void>('retryUpload', {'path': recording.file.path});
}
