import 'dart:io';

import 'upload_status.dart';

/// What a list entry is: an audio recording or an exported contacts backup.
enum RecordingKind {
  audio,
  contacts;

  static RecordingKind fromName(String? name) =>
      name == 'contacts' ? RecordingKind.contacts : RecordingKind.audio;
}

/// A finished recording or contacts backup file on disk.
class Recording {
  const Recording({
    required this.file,
    required this.createdAt,
    required this.sizeBytes,
    this.kind = RecordingKind.audio,
    this.duration,
    this.contactCount,
    this.upload,
  });

  factory Recording.fromMap(Map<dynamic, dynamic> map) {
    final durationMillis = map['durationMillis'] as int?;
    final upload = map['upload'] as Map?;
    return Recording(
      file: File(map['path'] as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['modifiedAtMillis'] as int,
      ),
      sizeBytes: map['sizeBytes'] as int,
      kind: RecordingKind.fromName(map['kind'] as String?),
      duration: durationMillis == null
          ? null
          : Duration(milliseconds: durationMillis),
      contactCount: map['contactCount'] as int?,
      upload: upload == null ? null : UploadStatus.fromMap(upload),
    );
  }

  final File file;
  final DateTime createdAt;
  final int sizeBytes;
  final RecordingKind kind;

  /// Audio length; null for a contacts backup or if it couldn't be read.
  final Duration? duration;

  /// Number of contacts in a contacts backup; null for an audio recording.
  final int? contactCount;

  /// Telegram backup status; null if the file was never queued.
  final UploadStatus? upload;

  String get name => file.uri.pathSegments.last;

  Recording copyWith({UploadStatus? upload}) => Recording(
    file: file,
    createdAt: createdAt,
    sizeBytes: sizeBytes,
    kind: kind,
    duration: duration,
    contactCount: contactCount,
    upload: upload ?? this.upload,
  );
}
