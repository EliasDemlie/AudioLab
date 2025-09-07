import 'upload_status.dart';

/// Contacts backup status as reported by the native contacts module.
class ContactsBackupState {
  const ContactsBackupState({
    this.configured = false,
    this.permissionGranted = false,
    this.lastSuccessAt,
    this.latest,
    this.contactCount,
  });

  factory ContactsBackupState.fromMap(Map<dynamic, dynamic> map) {
    final lastSuccess = map['lastSuccessAtMillis'] as int?;
    final latest = map['latest'] as Map?;
    return ContactsBackupState(
      configured: map['configured'] as bool? ?? false,
      permissionGranted: map['permissionGranted'] as bool? ?? false,
      lastSuccessAt: lastSuccess == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastSuccess),
      latest: latest == null ? null : UploadStatus.fromMap(latest),
      contactCount: latest?['contactCount'] as int?,
    );
  }

  /// Telegram bot token and chat were provided at build time.
  final bool configured;
  final bool permissionGranted;
  final DateTime? lastSuccessAt;

  /// Upload of the most recent backup file.
  final UploadStatus? latest;

  /// Contacts in the most recent backup file.
  final int? contactCount;

  bool get isBusy =>
      latest?.state == UploadState.pending ||
      latest?.state == UploadState.uploading;
}
