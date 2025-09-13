/// A compact envelope decoded from the recording's audio samples.
class RecordingWaveform {
  const RecordingWaveform({required this.duration, required this.peaks});

  factory RecordingWaveform.fromMap(Map<dynamic, dynamic> map) =>
      RecordingWaveform(
        duration: Duration(
          milliseconds: (map['durationMillis'] as num).round(),
        ),
        peaks: List.unmodifiable(
          (map['peaks'] as List<dynamic>).map(
            (value) => (value as num).toDouble().clamp(0.0, 1.0),
          ),
        ),
      );

  final Duration duration;

  /// Peak amplitudes in time order, normalized to the loudest sample.
  final List<double> peaks;
}
