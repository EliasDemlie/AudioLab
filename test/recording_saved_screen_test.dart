import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/app_theme.dart';
import 'package:voicerec/controllers/recorder_controller.dart';
import 'package:voicerec/models/recording.dart';
import 'package:voicerec/models/recording_waveform.dart';
import 'package:voicerec/screens/audio_effects_screen.dart';
import 'package:voicerec/screens/audio_editor_screen.dart';
import 'package:voicerec/screens/recording_saved_screen.dart';
import 'package:voicerec/services/recorder_service.dart';
import 'package:voicerec/widgets/audio_preset_selector.dart';
import 'package:voicerec/widgets/circular_eq_dial.dart';

void main() {
  testWidgets('effects controls match the dark app theme', (tester) async {
    _setViewport(tester, const Size(320, 568));
    final service = _PlaybackService();
    final controller = RecorderController(service: service);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: AudioEffectsScreen(controller: controller),
      ),
    );

    final dials = find.byType(CircularEqDial);
    expect(dials, findsNWidgets(3));
    final presetChips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(presetChips, hasLength(4));
    final selectorBounds = tester.getRect(find.byType(AudioPresetSelector));
    for (final chip in presetChips) {
      expect(chip.showCheckmark, isFalse);
      final chipFinder = find.byWidget(chip);
      final label = tester.widget<Text>(
        find.descendant(of: chipFinder, matching: find.byType(Text)),
      );
      expect(label.maxLines, 1);
      expect(label.softWrap, isFalse);
      final bounds = tester.getRect(chipFinder);
      expect(
        bounds.top,
        tester.getTopLeft(find.widgetWithText(ChoiceChip, 'Flat')).dy,
      );
      expect(bounds.left, greaterThanOrEqualTo(selectorBounds.left - 0.1));
      expect(bounds.right, lessThanOrEqualTo(selectorBounds.right + 0.1));
      expect(chipFinder.hitTestable(), findsOneWidget);
    }
    final heading = tester.widget<Text>(find.text('Shape your sound'));
    final description = tester.widget<Text>(
      find.text('Adjust playback EQ for a clearer voice preview.'),
    );
    final screenTheme = Theme.of(tester.element(dials.first));
    expect(screenTheme.brightness, Brightness.dark);
    expect(
      screenTheme.colorScheme.surfaceContainerHigh.computeLuminance(),
      lessThan(0.5),
    );
    tester.widget<CircularEqDial>(dials.first).onChanged(0.5);
    await tester.pump();
    expect(tester.widget<Text>(find.text('Shape your sound')), same(heading));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Voice'));
    await tester.pump();
    expect(tester.widget<Text>(find.text('Shape your sound')), same(heading));
    expect(
      tester.widget<Text>(
        find.text('Adjust playback EQ for a clearer voice preview.'),
      ),
      same(description),
    );
    expect(service.equalizerUpdates, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('player toggles playback without offering rename actions', (
    tester,
  ) async {
    final service = _PlaybackService(
      waveformPeaks: List.generate(80, (index) => index / 79),
    );
    await _showPlayer(tester, service);

    expect(find.byTooltip('Rename recording'), findsNothing);
    expect(find.byTooltip('More options'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.byTooltip('Share recording'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Effect'), findsOneWidget);
    expect(find.byType(CircularEqDial), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Effects'), findsNothing);
    expect(service.calls, isEmpty);
    final waveform = find.byKey(const ValueKey('playback-waveform'));
    expect(tester.getSize(waveform).width, greaterThan(300));
    final quietBarHeight = tester
        .getSize(find.byKey(const ValueKey('playback-waveform-bar-0')))
        .height;
    final loudBarHeight = tester
        .getSize(find.byKey(const ValueKey('playback-waveform-bar-30')))
        .height;
    expect(quietBarHeight, lessThan(loudBarHeight));

    await _tapControl(tester, 'Play');
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsNothing);
    expect(find.byKey(const ValueKey('playback-waveform')), findsOneWidget);
    expect(service.calls, ['play']);

    await _tapControl(tester, 'Pause');
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(service.calls, ['play', 'pause']);

    await _tapControl(tester, 'Play');
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(service.calls, ['play', 'pause', 'resume']);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(service.calls.last, 'stop');
  });

  testWidgets('scrubbing before playback preserves the chosen start position', (
    tester,
  ) async {
    final service = _PlaybackService();
    await _showPlayer(tester, service);
    final slider = find.byType(Slider);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final track = tester.getRect(slider);

    await tester.tapAt(Offset(track.left + track.width * 0.7, track.center.dy));
    await tester.pumpAndSettle();
    final selectedProgress = tester.widget<Slider>(slider).value;
    expect(selectedProgress, greaterThan(0.5));
    expect(service.calls, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Slider>(slider).value, selectedProgress);
    await _tapControl(tester, 'Play');

    expect(service.calls, ['play', 'seek']);
    expect(
      service.seeks.single.inMilliseconds,
      closeTo(service.duration.inMilliseconds * selectedProgress, 1),
    );
    expect(
      tester.widget<Slider>(slider).value,
      closeTo(selectedProgress, 0.001),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'ten-second skip controls clamp seeking to the recording bounds',
    (tester) async {
      final service = _PlaybackService(
        initialPosition: const Duration(seconds: 5),
      );
      await _showPlayer(tester, service);
      await _tapControl(tester, 'Play');

      await _tapControl(tester, 'Back 10 seconds');
      expect(service.seeks.last, Duration.zero);
      await _tapControl(tester, 'Forward 10 seconds');
      expect(service.seeks.last, const Duration(seconds: 10));
      await _tapControl(tester, 'Forward 10 seconds');
      expect(service.seeks.last, service.duration);
      await _tapControl(tester, 'Forward 10 seconds');
      expect(service.seeks.last, service.duration);
      expect(service.seeks.every((seek) => seek >= Duration.zero), isTrue);
      expect(service.seeks.every((seek) => seek <= service.duration), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('playback polling does not move the slider during a scrub', (
    tester,
  ) async {
    final service = _PlaybackService();
    await _showPlayer(tester, service);
    await _tapControl(tester, 'Play');
    final slider = find.byType(Slider);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final track = tester.getRect(slider);
    final gesture = await tester.startGesture(track.center);
    await gesture.moveTo(
      Offset(track.left + track.width * 0.75, track.center.dy),
    );
    await tester.pump();
    final chosenProgress = tester.widget<Slider>(slider).value;
    expect(chosenProgress, greaterThan(0.5));

    service._position = const Duration(seconds: 3);
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<Slider>(slider).value, chosenProgress);
    expect(service.seeks, isEmpty);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      service.seeks.single.inMilliseconds,
      closeTo(chosenProgress * service.duration.inMilliseconds, 1),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('player can edit in the editor screen and resume playback', (
    tester,
  ) async {
    final service = _PlaybackService(failTrim: true);
    await _showPlayer(tester, service);
    await _tapControl(tester, 'Play');
    final editAction = find.text('Edit');
    await tester.ensureVisible(editAction);
    await tester.pumpAndSettle();
    await tester.tap(editAction);
    await tester.pumpAndSettle();
    expect(find.byType(AudioEditorScreen), findsOneWidget);
    await tester.ensureVisible(find.text('Save copy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save copy'));
    await tester.pumpAndSettle();

    expect(find.text('The edited copy could not be saved.'), findsOneWidget);
    expect(find.byType(AudioEditorScreen), findsOneWidget);
    expect(service.calls, containsAllInOrder(['play', 'stop', 'trim']));
    await _tapControl(tester, 'Back to player');
    await tester.pumpAndSettle();
    expect(find.byType(AudioEditorScreen), findsNothing);
    await _tapControl(tester, 'Play');
    expect(service.calls.last, 'play');
    expect(service.calls.where((call) => call == 'play'), hasLength(2));
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('player toggles effects and retains gains during playback', (
    tester,
  ) async {
    final service = _PlaybackService();
    await _showPlayer(tester, service);

    expect(find.byType(RecordingSavedScreen), findsOneWidget);
    expect(find.byType(AudioEffectsScreen), findsNothing);
    expect(find.byType(CircularEqDial), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    await _tapControl(tester, 'Play');
    service._position = const Duration(seconds: 7);
    await tester.pump(const Duration(milliseconds: 350));
    await _tapControl(tester, 'Show effects');

    expect(find.byType(CircularEqDial), findsNWidgets(3));
    final presetChips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(presetChips, hasLength(4));
    expect(find.text('Effects'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Voice'));
    await tester.pumpAndSettle();
    expect(service.equalizerUpdates, hasLength(1));
    expect(service.equalizerUpdates.single, [-0.12, 0.22, 0.18]);
    await _tapControl(tester, 'Hide effects');
    expect(find.byType(CircularEqDial), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await _tapControl(tester, 'Show effects');

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Voice'))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widgetList<CircularEqDial>(find.byType(CircularEqDial))
          .map((dial) => dial.value),
      [-0.12, 0.22, 0.18],
    );
    expect(service.equalizerUpdates, hasLength(1));
    expect(service.calls, ['play']);
    expect(service._position, const Duration(seconds: 7));
    expect(find.byType(AudioEffectsScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'player supports small screens, larger text, and back navigation in $brightness',
      (tester) async {
        final service = _PlaybackService();
        final controller = RecorderController(service: service);
        addTearDown(controller.dispose);
        _setViewport(tester, const Size(320, 568));
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.light
                ? VoiceRecTheme.light
                : VoiceRecTheme.dark,
            builder: (context, child) => VoiceRecBackdrop(
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.8)),
                child: child!,
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => RecordingSavedScreen(
                          recording: _recording,
                          controller: controller,
                        ),
                      ),
                    ),
                    child: const Text('Open recording'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open recording'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await _tapControl(tester, 'Play');
        expect(find.byTooltip('Pause'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await _tapControl(tester, 'Show effects');
        final selectorBounds = tester.getRect(find.byType(AudioPresetSelector));
        final presetTop = tester
            .getTopLeft(find.widgetWithText(ChoiceChip, 'Flat'))
            .dy;
        for (final preset in ['Flat', 'Voice', 'Warm', 'Bright']) {
          final chip = find.widgetWithText(ChoiceChip, preset);
          final bounds = tester.getRect(chip);
          expect(bounds.top, closeTo(presetTop, 1));
          expect(bounds.left, greaterThanOrEqualTo(selectorBounds.left - 0.1));
          expect(bounds.right, lessThanOrEqualTo(selectorBounds.right + 0.1));
          final labelBounds = tester.getRect(find.text(preset));
          expect(labelBounds.left, greaterThanOrEqualTo(bounds.left - 0.1));
          expect(labelBounds.right, lessThanOrEqualTo(bounds.right + 0.1));
          expect(chip.hitTestable(), findsOneWidget);
          await tester.tap(chip);
          await tester.pumpAndSettle();
          expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
        }
        expect(service.equalizerUpdates.last, [-0.12, 0.12, 0.32]);
        await tester.ensureVisible(find.byType(CircularEqDial).last);
        await tester.pumpAndSettle();
        expect(find.byType(CircularEqDial), findsNWidgets(3));
        expect(tester.takeException(), isNull);
        await _tapControl(tester, 'Hide effects');

        await _tapControl(tester, 'Back to library');
        expect(find.byType(RecordingSavedScreen), findsNothing);
        expect(find.text('Open recording'), findsOneWidget);
        expect(service.calls.last, 'stop');
        expect(tester.takeException(), isNull);
      },
    );
  }
}

final _recording = Recording(
  file: File('/recordings/voice-note.m4a'),
  createdAt: DateTime(2026, 10, 29),
  sizeBytes: 1024,
  duration: const Duration(seconds: 20),
);

Future<void> _showPlayer(WidgetTester tester, _PlaybackService service) async {
  final controller = RecorderController(service: service);
  addTearDown(controller.dispose);
  _setViewport(tester, const Size(390, 844));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: RecordingSavedScreen(recording: _recording, controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _tapControl(WidgetTester tester, String tooltip) async {
  final control = find.byTooltip(tooltip);
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

class _PlaybackService extends RecorderService {
  _PlaybackService({
    this.initialPosition = Duration.zero,
    this.failTrim = false,
    this.waveformPeaks,
  });

  final Duration initialPosition;
  final bool failTrim;
  final List<double>? waveformPeaks;
  final Duration duration = const Duration(seconds: 20);
  final List<String> calls = [];
  final List<Duration> seeks = [];
  final List<List<double>> equalizerUpdates = [];
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  @override
  Future<RecordingWaveform> loadWaveform(Recording recording) async =>
      RecordingWaveform(
        duration: duration,
        peaks: waveformPeaks ?? List.filled(80, 0.5),
      );

  @override
  Future<void> play(Recording recording) async {
    calls.add('play');
    _position = initialPosition;
    _isPlaying = true;
  }

  @override
  Future<void> pausePlayback() async {
    calls.add('pause');
    _isPlaying = false;
  }

  @override
  Future<void> resumePlayback() async {
    calls.add('resume');
    _isPlaying = true;
  }

  @override
  Future<void> stopPlayback() async {
    calls.add('stop');
    _isPlaying = false;
  }

  @override
  Future<void> seekPlayback(Duration position) async {
    calls.add('seek');
    seeks.add(position);
    _position = position;
  }

  @override
  Future<PlaybackState> getPlaybackState() async => PlaybackState(
    position: _position,
    duration: duration,
    isPlaying: _isPlaying,
  );

  @override
  Future<void> setPlaybackEqualizer(List<double> gains) async {
    equalizerUpdates.add(List<double>.of(gains));
  }

  @override
  Future<String> trimAudio(
    Recording recording, {
    required Duration start,
    required Duration end,
  }) async {
    calls.add('trim');
    if (failTrim) {
      throw PlatformException(
        code: 'EDIT_FAILED',
        message: 'The edited copy could not be saved.',
      );
    }
    return recording.file.path;
  }
}
