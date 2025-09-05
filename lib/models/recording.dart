import 'dart:io';

/// A finished recording file on disk.
class Recording {
  const Recording({
    required this.file,
    required this.createdAt,
    required this.sizeBytes,
    this.duration,
  });

  factory Recording.fromMap(Map<dynamic, dynamic> map) {
    final durationMillis = map['durationMillis'] as int?;
    return Recording(
      file: File(map['path'] as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['modifiedAtMillis'] as int,
      ),
      sizeBytes: map['sizeBytes'] as int,
      duration: durationMillis == null
          ? null
          : Duration(milliseconds: durationMillis),
    );
  }

  final File file;
  final DateTime createdAt;
  final int sizeBytes;

  /// Null if the file's duration couldn't be read.
  final Duration? duration;

  String get name => file.uri.pathSegments.last;
}
