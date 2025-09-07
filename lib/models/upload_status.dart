enum UploadState {
  pending,
  uploading,
  uploaded,
  failed;

  static UploadState fromName(String? name) => UploadState.values.firstWhere(
    (s) => s.name == name,
    orElse: () => UploadState.pending,
  );
}

/// Telegram backup status of one recording, owned by the native upload queue.
class UploadStatus {
  const UploadStatus({
    required this.filePath,
    required this.state,
    this.progress = 0,
    this.attempts = 0,
    this.error,
  });

  factory UploadStatus.fromMap(Map<dynamic, dynamic> map) => UploadStatus(
    filePath: map['filePath'] as String,
    state: UploadState.fromName(map['status'] as String?),
    progress: (map['progress'] as num?)?.toDouble() ?? 0,
    attempts: map['attempts'] as int? ?? 0,
    error: map['error'] as String?,
  );

  final String filePath;
  final UploadState state;

  /// 0.0–1.0 while uploading.
  final double progress;
  final int attempts;

  /// Last failure reason; also set while waiting to retry.
  final String? error;
}
