import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/app_theme.dart';
import 'package:voicerec/controllers/recorder_controller.dart';
import 'package:voicerec/models/recording.dart';
import 'package:voicerec/models/recording_waveform.dart';
import 'package:voicerec/screens/audio_editor_screen.dart';
import 'package:voicerec/services/recorder_service.dart';
import 'package:voicerec/widgets/circular_eq_dial.dart';
import 'package:voicerec/widgets/audio_crop_waveform.dart';

void main() {
  testWidgets(
    'editor keeps crop local and retains toggled preset and EQ gains',
    (tester) async {
      final service = _EditorService();
      await _showEditor(tester, service);

      final save = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save copy'),
      );
      expect(find.text(_recording.title), findsNothing);
      expect(find.text('START'), findsNothing);
      expect(find.text('END'), findsNothing);
      final waveform = tester.widget<AudioCropWaveform>(
        find.byType(AudioCropWaveform),
      );
      waveform.onSelectionChanged(const RangeValues(0.25, 0.75));
      await tester.pump();

      expect(
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save copy')),
        same(save),
      );
      expect(
        tester
            .widget<AudioCropWaveform>(find.byType(AudioCropWaveform))
            .selection,
        const RangeValues(0.25, 0.75),
      );

      expect(find.byType(CircularEqDial), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.widgetWithText(TextButton, 'Effect'), findsOneWidget);
      await _tapControl(tester, 'Show effects');
      expect(find.byType(CircularEqDial), findsNWidgets(3));
      expect(find.byType(ChoiceChip), findsNWidgets(4));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Voice'));
      await tester.pumpAndSettle();
      expect(service.equalizerUpdates, hasLength(1));
      expect(service.equalizerUpdates.single, [-0.12, 0.22, 0.18]);
      await _tapControl(tester, 'Hide effects');
      expect(find.byType(CircularEqDial), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
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
      expect(
        tester
            .widget<AudioCropWaveform>(find.byType(AudioCropWaveform))
            .selection,
        const RangeValues(0.25, 0.75),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('toggling editor effects preserves an active selection preview', (
    tester,
  ) async {
    final service = _EditorService();
    await _showEditor(tester, service);
    await _select(tester, const RangeValues(0.25, 0.75));
    await _tapControl(tester, 'Play selection');
    service.position = const Duration(seconds: 8);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    final previewCalls = List<String>.of(service.calls);

    await _tapControl(tester, 'Show effects');
    expect(find.byType(CircularEqDial), findsNWidgets(3));
    await _tapControl(tester, 'Hide effects');

    expect(find.byType(CircularEqDial), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(service.isPlaying, isTrue);
    expect(service.position, const Duration(seconds: 8));
    expect(service.calls, previewCalls);
    expect(tester.widget<Slider>(_progress).value, closeTo(0.3, 0.001));
    expect(
      tester
          .widget<AudioCropWaveform>(find.byType(AudioCropWaveform))
          .selection,
      const RangeValues(0.25, 0.75),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('editor loads actual waveform data and retries a failed load', (
    tester,
  ) async {
    final service = _EditorService()..failWaveform = true;
    await _showEditor(tester, service);

    expect(find.text('Audio could not be decoded.'), findsOneWidget);
    expect(service.waveformLoads, 1);
    expect(find.byType(AudioCropWaveform), findsNothing);
    service.failWaveform = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(service.waveformLoads, 2);
    final waveform = tester.widget<AudioCropWaveform>(
      find.byType(AudioCropWaveform),
    );
    expect(waveform.peaks, service.peaks);
    expect(waveform.selection, const RangeValues(0, 1));
    expect(find.text('Your original recording stays unchanged.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('known duration allows preview before the waveform is ready', (
    tester,
  ) async {
    final loaded = Completer<RecordingWaveform>();
    final service = _EditorService()..pendingWaveform = loaded.future;
    await _showEditor(tester, service, settle: false);

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(service.calls, isEmpty);
    final save = find.widgetWithText(TextButton, 'Save copy');
    expect(tester.widget<TextButton>(save).onPressed, isNotNull);
    final play = find.byTooltip('Play selection');
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pump();

    expect(service.isPlaying, isTrue);
    expect(service.calls, ['play']);
    loaded.complete(
      RecordingWaveform(duration: service.duration, peaks: service.peaks),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AudioCropWaveform), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(tester.widget<TextButton>(save).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unknown duration keeps editing disabled until metadata loads', (
    tester,
  ) async {
    final loaded = Completer<RecordingWaveform>();
    final service = _EditorService()..pendingWaveform = loaded.future;
    final recording = Recording(
      file: _recording.file,
      createdAt: _recording.createdAt,
      sizeBytes: _recording.sizeBytes,
    );
    await _showEditor(tester, service, recording: recording, settle: false);

    final save = find.widgetWithText(TextButton, 'Save copy');
    expect(tester.widget<TextButton>(save).onPressed, isNull);
    final playButton = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .singleWhere((button) => button.tooltip == 'Play selection');
    expect(playButton.onPressed, isNull);
    loaded.complete(
      RecordingWaveform(duration: service.duration, peaks: service.peaks),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AudioCropWaveform), findsOneWidget);
    expect(tester.widget<TextButton>(save).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late waveform loading preserves playback position', (
    tester,
  ) async {
    final loaded = Completer<RecordingWaveform>();
    final service = _EditorService()..pendingWaveform = loaded.future;
    await _showEditor(tester, service, settle: false);
    final play = find.byTooltip('Play selection');
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pump();
    expect(service.position, Duration.zero);

    service.position = const Duration(seconds: 8);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    loaded.complete(
      RecordingWaveform(duration: service.duration, peaks: service.peaks),
    );
    await tester.pumpAndSettle();

    final waveform = tester.widget<AudioCropWaveform>(
      find.byType(AudioCropWaveform),
    );
    expect(waveform.selection, const RangeValues(0, 1));
    expect(waveform.positionListenable!.value, closeTo(0.4, 0.001));
    expect(service.isPlaying, isTrue);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(service.calls.where((call) => call == 'play'), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'playback ticks update the progress without rebuilding editor content',
    (tester) async {
      final service = _EditorService();
      await _showEditor(tester, service);
      await _tapControl(tester, 'Play selection');
      final save = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save copy'),
      );
      final waveform = tester.widget<AudioCropWaveform>(
        find.byType(AudioCropWaveform),
      );

      for (var second = 1; second <= 3; second++) {
        service.position = Duration(seconds: second);
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump();
        expect(
          tester.widget<TextButton>(
            find.widgetWithText(TextButton, 'Save copy'),
          ),
          same(save),
        );
        expect(
          tester.widget<AudioCropWaveform>(find.byType(AudioCropWaveform)),
          same(waveform),
        );
        expect(waveform.positionListenable!.value, closeTo(second / 20, 0.001));
        expect(
          tester.widget<Slider>(_progress).value,
          closeTo(second / 20, 0.001),
        );
      }
      expect(tester.widget<Text>(_positionLabel).data, '00:03.0');
      expect(tester.widget<Text>(_endLabel).data, '00:20.0');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('progress previews only the selected range and its end time', (
    tester,
  ) async {
    final service = _EditorService();
    await _showEditor(tester, service);
    await _select(tester, const RangeValues(0.25, 0.75));

    expect(tester.widget<Slider>(_progress).value, 0);
    expect(tester.widget<Text>(_positionLabel).data, '00:05.0');
    expect(tester.widget<Text>(_endLabel).data, '00:15.0');
    expect(
      tester.getCenter(_positionLabel).dx,
      lessThan(tester.getCenter(_endLabel).dx),
    );
    await _tapControl(tester, 'Play selection');
    service.position = const Duration(seconds: 8);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();

    expect(tester.widget<Slider>(_progress).value, closeTo(0.3, 0.001));
    expect(tester.widget<Text>(_positionLabel).data, '00:08.0');
    expect(tester.widget<Text>(_endLabel).data, '00:15.0');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('playback polling preserves a scrub until seeking on release', (
    tester,
  ) async {
    final service = _EditorService();
    await _showEditor(tester, service);
    await _select(tester, const RangeValues(0.25, 0.75));
    await _tapControl(tester, 'Play selection');
    final seekCount = service.calls.where((call) => call == 'seek').length;

    var progress = tester.widget<Slider>(_progress);
    progress.onChangeStart!(0);
    progress.onChanged!(0.6);
    await tester.pump();
    service.position = const Duration(seconds: 6);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();

    expect(tester.widget<Slider>(_progress).value, closeTo(0.6, 0.001));
    expect(tester.widget<Text>(_positionLabel).data, '00:11.0');
    expect(service.calls.where((call) => call == 'seek'), hasLength(seekCount));
    progress = tester.widget<Slider>(_progress);
    progress.onChangeEnd!(0.6);
    await tester.pumpAndSettle();

    expect(service.position, const Duration(seconds: 11));
    expect(service.isPlaying, isTrue);
    expect(
      service.calls.where((call) => call == 'seek'),
      hasLength(seekCount + 1),
    );
    expect(tester.widget<Slider>(_progress).value, closeTo(0.6, 0.001));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('preview plays and pauses inside the selected section', (
    tester,
  ) async {
    final service = _EditorService();
    await _showEditor(tester, service);
    await _select(tester, const RangeValues(0.25, 0.75));
    await _tapControl(tester, 'Play selection');

    expect(service.position, const Duration(seconds: 5));
    expect(service.isPlaying, isTrue);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await _tapControl(tester, 'Pause');
    expect(service.isPlaying, isFalse);

    await _tapControl(tester, 'Play selection');
    service.position = const Duration(seconds: 16);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(service.isPlaying, isFalse);
    expect(find.byTooltip('Play selection'), findsOneWidget);

    await _tapControl(tester, 'Play selection');
    expect(service.position, const Duration(seconds: 5));
    expect(service.isPlaying, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(service.calls.last, 'stop');
  });

  testWidgets('waveform seeking and skip controls stay inside the crop', (
    tester,
  ) async {
    final service = _EditorService();
    await _showEditor(tester, service);
    await _select(tester, const RangeValues(0.25, 0.75));
    await _tapControl(tester, 'Play selection');

    tester
        .widget<AudioCropWaveform>(find.byType(AudioCropWaveform))
        .onSeek(0.9);
    await tester.pumpAndSettle();
    expect(service.position, const Duration(seconds: 15));
    await _tapControl(tester, 'Back 5 seconds');
    expect(service.position, const Duration(seconds: 10));
    await _tapControl(tester, 'Back 5 seconds');
    expect(service.position, const Duration(seconds: 5));
    await _tapControl(tester, 'Back 5 seconds');
    expect(service.position, const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('saving uses the selected range and returns the new copy', (
    tester,
  ) async {
    final service = _EditorService();
    await _showEditor(tester, service);
    await _select(tester, const RangeValues(0.2, 0.8));
    await _tapText(tester, 'Save copy');

    expect(service.trimStart, const Duration(seconds: 4));
    expect(service.trimEnd, const Duration(seconds: 16));
    expect(
      service.calls.indexOf('stop'),
      lessThan(service.calls.indexOf('trim')),
    );
    expect(find.byType(AudioEditorScreen), findsNothing);
    expect(find.text('Saved Cropped voice'), findsOneWidget);
    expect(_recording.file.path, '/recordings/voice-note.m4a');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed crop save keeps the selection and permits replay', (
    tester,
  ) async {
    final service = _EditorService()..failTrim = true;
    await _showEditor(tester, service);
    await _select(tester, const RangeValues(0.2, 0.8));
    await _tapControl(tester, 'Play selection');
    await _tapText(tester, 'Save copy');

    expect(find.text('The edited copy could not be saved.'), findsOneWidget);
    expect(find.byType(AudioEditorScreen), findsOneWidget);
    expect(
      tester
          .widget<AudioCropWaveform>(find.byType(AudioCropWaveform))
          .selection,
      const RangeValues(0.2, 0.8),
    );
    await _tapControl(tester, 'Play selection');
    expect(service.isPlaying, isTrue);
    expect(service.calls.where((call) => call == 'play'), hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'failed initial crop seek stops audio and allows another preview',
    (tester) async {
      final service = _EditorService()..failSeek = true;
      await _showEditor(tester, service);
      await _select(tester, const RangeValues(0.25, 0.75));
      await _tapControl(tester, 'Play selection');

      expect(find.text('The preview could not seek.'), findsOneWidget);
      expect(service.calls, ['play', 'seek', 'stop']);
      expect(service.isPlaying, isFalse);
      expect(find.byTooltip('Play selection'), findsOneWidget);

      service.failSeek = false;
      await _tapControl(tester, 'Play selection');
      expect(service.calls.where((call) => call == 'play'), hasLength(2));
      expect(service.position, const Duration(seconds: 5));
      expect(service.isPlaying, isTrue);
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'crop editor supports narrow screens and enlarged text in $brightness',
      (tester) async {
        final service = _EditorService();
        await _showEditor(
          tester,
          service,
          size: const Size(320, 568),
          textScale: 1.8,
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        await _tapControl(tester, 'Play selection');
        expect(service.isPlaying, isTrue);
        await _tapControl(tester, 'Pause');
        await _select(tester, const RangeValues(0.1, 0.9));
        await _tapControl(tester, 'Reset selection');
        expect(
          tester
              .widget<AudioCropWaveform>(find.byType(AudioCropWaveform))
              .selection,
          const RangeValues(0, 1),
        );
        await _tapControl(tester, 'Show effects');
        await tester.ensureVisible(find.byType(CircularEqDial).last);
        await tester.pumpAndSettle();
        expect(find.byType(CircularEqDial), findsNWidgets(3));
        await _tapControl(tester, 'Hide effects');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('editor fits a narrow screen without vertical scrolling', (
    tester,
  ) async {
    final service = _EditorService();
    await _showEditor(tester, service, size: const Size(320, 568));
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(AudioEditorScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.maxScrollExtent, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final _progress = find.byKey(const ValueKey('editor-playback-progress'));
final _positionLabel = find.byKey(const ValueKey('editor-playback-position'));
final _endLabel = find.byKey(const ValueKey('editor-playback-end'));

final _recording = Recording(
  file: File('/recordings/voice-note.m4a'),
  createdAt: DateTime(2026, 10, 29),
  sizeBytes: 1024,
  duration: const Duration(seconds: 20),
);

Future<void> _showEditor(
  WidgetTester tester,
  _EditorService service, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Brightness brightness = Brightness.dark,
  bool settle = true,
  Recording? recording,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = RecorderController(service: service);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light
          ? VoiceRecTheme.light
          : VoiceRecTheme.dark,
      builder: (context, child) => VoiceRecBackdrop(
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: _EditorLauncher(
        controller: controller,
        recording: recording ?? _recording,
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<void> _select(WidgetTester tester, RangeValues selection) async {
  await _reveal(tester, find.byType(AudioCropWaveform), delta: -200);
  tester
      .widget<AudioCropWaveform>(find.byType(AudioCropWaveform))
      .onSelectionChanged(selection);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final target = find.text(text);
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _tapControl(WidgetTester tester, String tooltip) async {
  final target = find.byTooltip(tooltip);
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  double delta = 200,
}) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      delta,
      scrollable: find
          .descendant(
            of: find.byType(AudioEditorScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

class _EditorLauncher extends StatefulWidget {
  const _EditorLauncher({required this.controller, required this.recording});
  final RecorderController controller;
  final Recording recording;

  @override
  State<_EditorLauncher> createState() => _EditorLauncherState();
}

class _EditorLauncherState extends State<_EditorLauncher> {
  Recording? _saved;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () async {
              final saved = await Navigator.of(context).push<Recording>(
                MaterialPageRoute(
                  builder: (_) => AudioEditorScreen(
                    recording: widget.recording,
                    controller: widget.controller,
                  ),
                ),
              );
              if (mounted) setState(() => _saved = saved);
            },
            child: const Text('Open editor'),
          ),
          if (_saved != null) Text('Saved ${_saved!.title}'),
        ],
      ),
    ),
  );
}

class _EditorService extends RecorderService {
  final Duration duration = const Duration(seconds: 20);
  final List<double> peaks = List.generate(80, (i) => (i % 10 + 1) / 10);
  Future<RecordingWaveform>? pendingWaveform;
  bool failWaveform = false;
  bool failTrim = false;
  bool failSeek = false;
  int waveformLoads = 0;
  final List<List<double>> equalizerUpdates = [];
  Duration position = Duration.zero;
  bool isPlaying = false;
  Duration? trimStart;
  Duration? trimEnd;
  Recording? _edited;
  final calls = <String>[];

  @override
  Future<RecordingWaveform> loadWaveform(Recording recording) async {
    waveformLoads++;
    if (pendingWaveform != null) return pendingWaveform!;
    if (failWaveform) {
      throw PlatformException(
        code: 'WAVEFORM_FAILED',
        message: 'Audio could not be decoded.',
      );
    }
    return RecordingWaveform(duration: duration, peaks: peaks);
  }

  @override
  Future<void> play(Recording recording) async {
    calls.add('play');
    position = Duration.zero;
    isPlaying = true;
  }

  @override
  Future<void> pausePlayback() async {
    calls.add('pause');
    isPlaying = false;
  }

  @override
  Future<void> resumePlayback() async {
    calls.add('resume');
    isPlaying = true;
  }

  @override
  Future<void> stopPlayback() async {
    calls.add('stop');
    position = Duration.zero;
    isPlaying = false;
  }

  @override
  Future<void> seekPlayback(Duration target) async {
    calls.add('seek');
    if (failSeek) {
      throw PlatformException(
        code: 'SEEK_FAILED',
        message: 'The preview could not seek.',
      );
    }
    position = target;
  }

  @override
  Future<PlaybackState> getPlaybackState() async => PlaybackState(
    position: position,
    duration: duration,
    isPlaying: isPlaying,
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
    trimStart = start;
    trimEnd = end;
    if (failTrim) {
      throw PlatformException(
        code: 'EDIT_FAILED',
        message: 'The edited copy could not be saved.',
      );
    }
    _edited = Recording(
      file: File('/recordings/voice-note-cropped.m4a'),
      metadataTitle: 'Cropped voice',
      createdAt: recording.createdAt,
      sizeBytes: 700,
      duration: end - start,
    );
    return _edited!.file.path;
  }

  @override
  Future<List<Recording>> loadRecordings() async => [_recording, ?_edited];
}
