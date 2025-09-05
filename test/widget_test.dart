import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/utils/formatters.dart';

void main() {
  test('formatDuration pads hours, minutes and seconds', () {
    expect(formatDuration(const Duration(seconds: 65)), '00:01:05');
    expect(formatDuration(const Duration(hours: 1, seconds: 3)), '01:00:03');
  });

  test('formatBytes picks a readable unit', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
  });
}
