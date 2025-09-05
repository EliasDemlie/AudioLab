enum RecorderStatus {
  idle,
  recording,
  paused,

  /// Recorder stopped; the file is being saved.
  stopping;

  static RecorderStatus fromName(String? name) => RecorderStatus.values
      .firstWhere((s) => s.name == name, orElse: () => RecorderStatus.idle);
}

/// Recorder status as reported by the native Android service, which is the
/// source of truth while recording.
class RecorderState {
  const RecorderState({
    required this.status,
    this.filePath,
    this.startedAt,
    this.elapsed = Duration.zero,
    this.capturedAt,
    this.micSilenced = false,
    this.error,
  });

  const RecorderState.idle() : this(status: RecorderStatus.idle);

  factory RecorderState.fromMap(Map<dynamic, dynamic> map) {
    DateTime? time(String key) {
      final millis = map[key] as int?;
      return millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis);
    }

    return RecorderState(
      status: RecorderStatus.fromName(map['status'] as String?),
      filePath: map['filePath'] as String?,
      startedAt: time('startedAtMillis'),
      elapsed: Duration(milliseconds: map['elapsedMillis'] as int? ?? 0),
      capturedAt: time('capturedAtMillis'),
      micSilenced: map['micSilenced'] as bool? ?? false,
      error: map['error'] as String?,
    );
  }

  final RecorderStatus status;
  final String? filePath;
  final DateTime? startedAt;

  /// Recorded duration (pauses excluded) at [capturedAt].
  final Duration elapsed;
  final DateTime? capturedAt;

  /// Another app is using the microphone, so silence is being recorded.
  final bool micSilenced;

  /// Set only on the single event that reports a failure.
  final String? error;

  bool get isActive => status != RecorderStatus.idle;

  /// Recorded duration at [now], extrapolated from the native snapshot.
  Duration elapsedAt(DateTime now) {
    final captured = capturedAt;
    if (status != RecorderStatus.recording || captured == null) return elapsed;
    return elapsed + now.difference(captured);
  }
}
