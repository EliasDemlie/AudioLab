import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/widgets/audio_crop_waveform.dart';

void main() {
  testWidgets('waveform taps seek relative to the audio timeline', (
    tester,
  ) async {
    double? selectedPosition;
    await _showWaveform(tester, onSeek: (value) => selectedPosition = value);
    final area = tester.getRect(find.byType(AudioCropWaveform));

    await tester.tapAt(Offset(area.center.dx, area.center.dy));
    expect(selectedPosition, closeTo(0.5, 0.001));
    await tester.tapAt(Offset(area.left + 2, area.center.dy));
    expect(selectedPosition, 0);
    await tester.tapAt(Offset(area.right - 2, area.center.dy));
    expect(selectedPosition, 1);
  });

  testWidgets('crop handles respect timeline bounds and minimum duration', (
    tester,
  ) async {
    var selection = const RangeValues(0.2, 0.8);
    await _showWaveform(
      tester,
      selection: selection,
      minimumSelection: 0.2,
      onSelectionChanged: (value) => selection = value,
    );

    await tester.drag(
      find.byKey(const ValueKey('crop-start-handle')),
      const Offset(400, 0),
    );
    await tester.pump();
    expect(selection.start, closeTo(0.6, 0.001));
    expect(selection.end, 0.8);
    await tester.drag(
      find.byKey(const ValueKey('crop-end-handle')),
      const Offset(-400, 0),
    );
    await tester.pump();
    expect(selection.end - selection.start, closeTo(0.2, 0.001));
    await tester.drag(
      find.byKey(const ValueKey('crop-start-handle')),
      const Offset(-400, 0),
    );
    await tester.pump();
    expect(selection.start, 0);
    await tester.drag(
      find.byKey(const ValueKey('crop-end-handle')),
      const Offset(400, 0),
    );
    await tester.pump();
    expect(selection.end, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crop handles support accessible adjustment actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var selection = const RangeValues(0.2, 0.8);
      await _showWaveform(
        tester,
        selection: selection,
        minimumSelection: 0.2,
        onSelectionChanged: (value) => selection = value,
      );

      final handle = tester.getSemantics(
        find.byKey(const ValueKey('crop-start-handle')),
      );
      expect(handle.label, 'Crop start');
      expect(
        handle.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        handle.id,
        SemanticsAction.increase,
      );
      await tester.pump();
      expect(selection.start, greaterThan(0.2));
      expect(selection.end, 0.8);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('disabled or missing waveform data ignores editing input', (
    tester,
  ) async {
    var calls = 0;
    await _showWaveform(
      tester,
      enabled: false,
      onSeek: (_) => calls++,
      onSelectionChanged: (_) => calls++,
    );
    await tester.tap(find.byType(AudioCropWaveform));
    await tester.drag(
      find.byKey(const ValueKey('crop-start-handle')),
      const Offset(80, 0),
    );
    expect(calls, 0);

    await _showWaveform(
      tester,
      peaks: const [],
      onSeek: (_) => calls++,
      onSelectionChanged: (_) => calls++,
    );
    expect(find.text('Waveform unavailable'), findsOneWidget);
    await tester.tap(find.byType(AudioCropWaveform));
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _showWaveform(
  WidgetTester tester, {
  List<double> peaks = const [0, 0.2, 0.4, 0.8, 1, 0.6, 0.3, 0.1],
  RangeValues selection = const RangeValues(0.2, 0.8),
  double minimumSelection = 0,
  bool enabled = true,
  ValueChanged<double>? onSeek,
  ValueChanged<RangeValues>? onSelectionChanged,
}) async {
  var currentSelection = selection;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: StatefulBuilder(
              builder: (context, setState) => AudioCropWaveform(
                peaks: peaks,
                selection: currentSelection,
                position: 0.5,
                minimumSelection: minimumSelection,
                enabled: enabled,
                onSelectionChanged: (value) {
                  setState(() => currentSelection = value);
                  onSelectionChanged?.call(value);
                },
                onSeek: onSeek ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
