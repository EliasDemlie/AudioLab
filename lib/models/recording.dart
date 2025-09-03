import 'dart:io';

/// A saved voice recording on disk.
class Recording {
  const Recording({
    required this.file,
    required this.createdAt,
    required this.sizeBytes,
    this.duration,
    this.catalogId,
    this.metadataTitle,
    this.updatedAt,
    this.isFavorite = false,
    this.note = '',
    this.tags = const [],
    this.folderId,
    this.deletedAt,
    this.audioAvailable = true,
  });

  factory Recording.fromMap(Map<dynamic, dynamic> map) {
    final durationMillis = map['durationMillis'] as int?;
    final path = map['path'] as String;
    final createdAtMillis =
        map['createdAtMillis'] as int? ?? map['modifiedAtMillis'] as int? ?? 0;
    final tags = (map['tags'] as List<dynamic>?)
        ?.map((tag) => tag.toString())
        .toList(growable: false);
    return Recording(
      file: File(path),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
      sizeBytes: map['sizeBytes'] as int,
      duration: durationMillis == null
          ? null
          : Duration(milliseconds: durationMillis),
      catalogId: map['id'] as String?,
      metadataTitle: map['title'] as String?,
      updatedAt: map['updatedAtMillis'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAtMillis'] as int)
          : null,
      isFavorite: map['isFavorite'] as bool? ?? false,
      note: map['note'] as String? ?? '',
      tags: tags ?? const [],
      folderId: map['folderId'] as String?,
      deletedAt: map['deletedAtMillis'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['deletedAtMillis'] as int)
          : null,
      audioAvailable: map['audioAvailable'] as bool? ?? true,
    );
  }

  final File file;
  final String? catalogId;
  final String? metadataTitle;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int sizeBytes;

  /// Audio length, or null if it couldn't be read.
  final Duration? duration;
  final bool isFavorite;
  final String note;
  final List<String> tags;
  final String? folderId;
  final DateTime? deletedAt;
  final bool audioAvailable;

  /// Catalog identity is independent of the editable title and file name.
  String get id => catalogId ?? file.absolute.path;

  String get name => file.uri.pathSegments.last;

  String get title =>
      metadataTitle ?? name.replaceFirst(RegExp(r'\.[^.]+$'), '');

  String get format => file.path.split('.').last.toUpperCase();

  Recording copyWith({
    File? file,
    String? catalogId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? sizeBytes,
    Duration? duration,
    bool? isFavorite,
    String? note,
    List<String>? tags,
    String? folderId,
    bool clearFolderId = false,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    bool? audioAvailable,
  }) => Recording(
    file: file ?? this.file,
    catalogId: catalogId ?? this.catalogId,
    metadataTitle: title ?? metadataTitle,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    duration: duration ?? this.duration,
    isFavorite: isFavorite ?? this.isFavorite,
    note: note ?? this.note,
    tags: tags ?? this.tags,
    folderId: clearFolderId ? null : folderId ?? this.folderId,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    audioAvailable: audioAvailable ?? this.audioAvailable,
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
