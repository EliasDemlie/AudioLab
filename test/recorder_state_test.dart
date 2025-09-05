import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/models/recorder_state.dart';

void main() {
  final capturedAt = DateTime(2026, 1, 1, 12);

  RecorderState stateWith(String status) => RecorderState.fromMap({
    'status': status,
    'elapsedMillis': 10000,
    'capturedAtMillis': capturedAt.millisecondsSinceEpoch,
  });

  test('elapsed keeps counting while recording', () {
    final later = capturedAt.add(const Duration(seconds: 5));
    expect(
      stateWith('recording').elapsedAt(later),
      const Duration(seconds: 15),
    );
  });

  test('elapsed is frozen while paused', () {
    final later = capturedAt.add(const Duration(minutes: 1));
    expect(stateWith('paused').elapsedAt(later), const Duration(seconds: 10));
  });

  test('unknown status falls back to idle', () {
    expect(stateWith('bogus').status, RecorderStatus.idle);
  });
}
