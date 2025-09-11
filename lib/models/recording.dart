import 'dart:io';

/// A saved voice recording on disk.
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

  /// Audio length, or null if it couldn't be read.
  final Duration? duration;

  String get name => file.uri.pathSegments.last;

  String get title => name.replaceFirst(RegExp(r'\.[^.]+$'), '');

  Recording copyWith({File? file}) => Recording(
    file: file ?? this.file,
    createdAt: createdAt,
    sizeBytes: sizeBytes,
    duration: duration,
  );
}

class PlaybackState {
  const PlaybackState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
  });

  factory PlaybackState.fromMap(Map<dynamic, dynamic>? map) => PlaybackState(
    position: Duration(milliseconds: map?['positionMillis'] as int? ?? 0),
    duration: Duration(milliseconds: map?['durationMillis'] as int? ?? 0),
    isPlaying: map?['isPlaying'] as bool? ?? false,
  );

  final Duration position;
  final Duration duration;
  final bool isPlaying;
}
