import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/widgets/live_waveform.dart';

void main() {
  testWidgets('live waveform redraws as microphone levels arrive', (
    tester,
  ) async {
    final level = ValueNotifier<double>(0);
    addTearDown(level.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LiveWaveform(level: level)),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(LiveWaveform),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );

    for (final sample in [0.02, 0.18, 0.04, 0.32, 0.01]) {
      level.value = sample;
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.takeException(), isNull);
    }
  });
}
