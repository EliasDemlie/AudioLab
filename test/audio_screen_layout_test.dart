import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/app_theme.dart';
import 'package:voicerec/controllers/recorder_controller.dart';
import 'package:voicerec/models/recording.dart';
import 'package:voicerec/models/recording_waveform.dart';
import 'package:voicerec/screens/audio_editor_screen.dart';
import 'package:voicerec/screens/recording_saved_screen.dart';
import 'package:voicerec/services/recorder_service.dart';
import 'package:voicerec/widgets/audio_crop_waveform.dart';
import 'package:voicerec/widgets/circular_eq_dial.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final (viewport, bottomInset) in [
      (const Size(390, 844), 0.0),
      (const Size(320, 568), 0.0),
      (const Size(430, 932), 0.0),
      (const Size(390, 844), 34.0),
    ]) {
      for (final effectsVisible in [false, true]) {
        testWidgets(
          'opening the editor preserves controls in $brightness at $viewport with effects $effectsVisible and bottom inset $bottomInset',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = viewport;
            tester.view.padding = FakeViewPadding(bottom: bottomInset);
            tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetPadding);
            addTearDown(tester.view.resetViewPadding);
            final controller = RecorderController(service: _LayoutService());
            addTearDown(controller.dispose);
            await tester.pumpWidget(
              MaterialApp(
                theme: brightness == Brightness.light
                    ? VoiceRecTheme.light
                    : VoiceRecTheme.dark,
                builder: (context, child) => VoiceRecBackdrop(child: child!),
                home: RecordingSavedScreen(
                  recording: _recording,
                  controller: controller,
                ),
              ),
            );
            await tester.pumpAndSettle();

            _expectBackArrow('Back to library');
            expect(find.byType(CircularEqDial), findsNothing);
            final playerEffect = _expectBottomEffectButton(
              tester,
              viewport,
              bottomInset,
            );
            if (effectsVisible) {
              await tester.tap(find.byTooltip('Show effects'));
              await tester.pumpAndSettle();
              _expectDialSpacing(tester);
              expect(
                _expectBottomEffectButton(tester, viewport, bottomInset),
                playerEffect,
                reason: 'Showing effects must preserve the bottom button',
              );
            }
            final player = _sharedControlRects(
              tester,
              editing: false,
              effectsVisible: effectsVisible,
            );
            expect(player['play']!.center.dx, closeTo(viewport.width / 2, 1));
            _expectAvailableHeightUsed(
              player,
              viewport,
              effectsVisible: effectsVisible,
            );
            await tester.tap(find.text('Edit'));
            await tester.pumpAndSettle();

            expect(find.byType(AudioEditorScreen), findsOneWidget);
            _expectBackArrow('Back to player');
            expect(find.byType(CircularEqDial), findsNothing);
            final editorEffect = _expectBottomEffectButton(
              tester,
              viewport,
              bottomInset,
            );
            if (effectsVisible) {
              await tester.tap(find.byTooltip('Show effects'));
              await tester.pumpAndSettle();
              _expectDialSpacing(tester);
              expect(
                _expectBottomEffectButton(tester, viewport, bottomInset),
                editorEffect,
              );
            }
            final editor = _sharedControlRects(
              tester,
              editing: true,
              effectsVisible: effectsVisible,
            );
            _expectAvailableHeightUsed(
              editor,
              viewport,
              effectsVisible: effectsVisible,
            );
            for (final entry in player.entries) {
              final actual = editor[entry.key]!;
              expect(
                actual.left,
                closeTo(entry.value.left, 1),
                reason:
                    '${entry.key} shifts horizontally when opening the editor',
              );
              expect(
                actual.top,
                closeTo(entry.value.top, 1),
                reason:
                    '${entry.key} shifts vertically when opening the editor',
              );
              expect(
                actual.size,
                entry.value.size,
                reason: '${entry.key} changes size when opening the editor',
              );
            }
            expect(tester.takeException(), isNull);

            if (effectsVisible) {
              final lastDial = find.byType(CircularEqDial).last;
              await tester.ensureVisible(lastDial);
              await tester.pumpAndSettle();
              expect(
                _expectBottomEffectButton(tester, viewport, bottomInset),
                editorEffect,
                reason: 'Scrolling the effects must preserve the bottom button',
              );
              expect(
                tester.getRect(lastDial).bottom,
                lessThanOrEqualTo(editorEffect.top),
                reason: 'All effect dials must be reachable above the footer',
              );
            }

            await tester.tap(find.byTooltip('Back to player'));
            await tester.pumpAndSettle();
            expect(find.byType(AudioEditorScreen), findsNothing);
            expect(find.byType(RecordingSavedScreen), findsOneWidget);
            final returned = _sharedControlRects(
              tester,
              editing: false,
              effectsVisible: effectsVisible,
            );
            expect(returned, player);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}

Rect _expectBottomEffectButton(
  WidgetTester tester,
  Size viewport,
  double bottomInset,
) {
  final button = find.widgetWithText(TextButton, 'Effect');
  expect(button.hitTestable(), findsOneWidget);
  final bounds = tester.getRect(button);
  final safeBottom = viewport.height - bottomInset;
  expect(bounds.center.dx, closeTo(viewport.width / 2, 1));
  expect(bounds.bottom, inInclusiveRange(safeBottom - 32, safeBottom));
  return bounds;
}

void _expectAvailableHeightUsed(
  Map<String, Rect> controls,
  Size viewport, {
  required bool effectsVisible,
}) {
  if (viewport.height < 844) return;
  final footer = controls['effect button']!;
  if (effectsVisible) {
    expect(
      controls['Treble knob']!.bottom,
      inInclusiveRange(footer.top - 64, footer.top),
      reason: 'The effects panel should extend into the lower available space',
    );
  } else {
    expect(
      controls['waveform']!.height,
      greaterThan(124),
      reason: 'The waveform should expand into the available screen height',
    );
    expect(
      controls['play']!.bottom,
      inInclusiveRange(footer.top - 48, footer.top),
      reason: 'Playback controls should use the lower available screen space',
    );
  }
}

Map<String, Rect> _sharedControlRects(
  WidgetTester tester, {
  required bool editing,
  required bool effectsVisible,
}) => {
  'waveform': tester.getRect(
    editing
        ? find.byType(AudioCropWaveform)
        : find.byKey(const ValueKey('playback-waveform')),
  ),
  'progress': tester.getRect(find.byType(Slider)),
  'play': tester.getRect(find.byTooltip(editing ? 'Play selection' : 'Play')),
  'skip back': tester.getRect(
    find.byTooltip(editing ? 'Back 5 seconds' : 'Back 10 seconds'),
  ),
  'skip forward': tester.getRect(
    find.byTooltip(editing ? 'Forward 5 seconds' : 'Forward 10 seconds'),
  ),
  'effect button': tester.getRect(find.widgetWithText(TextButton, 'Effect')),
  if (effectsVisible)
    'equalizer heading': tester.getRect(find.text('EQUALIZER')),
  for (final preset
      in effectsVisible ? ['Flat', 'Voice', 'Warm', 'Bright'] : <String>[])
    '$preset preset': tester.getRect(find.widgetWithText(ChoiceChip, preset)),
  for (final band
      in effectsVisible ? ['Bass', 'Presence', 'Treble'] : <String>[])
    '$band knob': tester.getRect(find.byKey(ValueKey('eq-dial-$band'))),
};

void _expectBackArrow(String tooltip) {
  expect(
    find.descendant(
      of: find.byTooltip(tooltip),
      matching: find.byIcon(Icons.arrow_back_rounded),
    ),
    findsOneWidget,
  );
  expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
}

void _expectDialSpacing(WidgetTester tester) {
  final presetBottom = tester
      .getRect(find.widgetWithText(ChoiceChip, 'Bright'))
      .bottom;
  final dialTop = tester.getRect(find.byType(CircularEqDial).first).top;
  final minimumGap = tester.view.physicalSize.height < 640 ? 28 : 40;
  expect(dialTop - presetBottom, greaterThanOrEqualTo(minimumGap));
}

final _recording = Recording(
  file: File('/recordings/voice-note.m4a'),
  createdAt: DateTime(2026, 11, 3),
  sizeBytes: 1024,
  duration: const Duration(seconds: 20),
);

class _LayoutService extends RecorderService {
  @override
  Future<RecordingWaveform> loadWaveform(Recording recording) async =>
      RecordingWaveform(
        duration: const Duration(seconds: 20),
        peaks: List<double>.filled(80, 0.5),
      );

  @override
  Future<void> stopPlayback() async {}
}
