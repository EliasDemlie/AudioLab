import 'dart:io';

import 'upload_status.dart';

/// A finished recording file on disk.
class Recording {
  const Recording({
    required this.file,
    required this.createdAt,
    required this.sizeBytes,
    this.duration,
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
      duration: durationMillis == null
          ? null
          : Duration(milliseconds: durationMillis),
      upload: upload == null ? null : UploadStatus.fromMap(upload),
    );
  }

  final File file;
  final DateTime createdAt;
  final int sizeBytes;

  /// Null if the file's duration couldn't be read.
  final Duration? duration;

  /// Telegram backup status; null if the recording was never queued.
  final UploadStatus? upload;

  String get name => file.uri.pathSegments.last;

  Recording copyWith({UploadStatus? upload}) => Recording(
    file: file,
    createdAt: createdAt,
    sizeBytes: sizeBytes,
    duration: duration,
    upload: upload ?? this.upload,
  );
}
