import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/controllers/recorder_controller.dart';
import 'package:voicerec/models/recording.dart';
import 'package:voicerec/services/recorder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.beamlinetech.audiolab/recorder');
  final recording = Recording(
    file: File('/recordings/Meeting.m4a'),
    createdAt: DateTime(2026),
    sizeBytes: 1024,
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'loads the recording envelope and duration through the controller',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return {
              'durationMillis': 3200,
              'peaks': [0, 0.75, 1.0, 0.2],
            };
          });
      final controller = RecorderController();
      addTearDown(controller.dispose);

      final waveform = await controller.loadWaveform(recording);

      expect(calls.single.method, 'getRecordingWaveform');
      expect(calls.single.arguments, {
        'path': recording.file.path,
        'sampleCount': 160,
      });
      expect(waveform.duration, const Duration(milliseconds: 3200));
      expect(waveform.peaks, [0.0, 0.75, 1.0, 0.2]);
      expect(() => waveform.peaks.add(0), throwsUnsupportedError);
    },
  );

  test(
    'reports unavailable waveform data instead of inventing samples',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);

      await expectLater(
        RecorderService().loadWaveform(recording),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'WAVEFORM_FAILED',
          ),
        ),
      );
    },
  );
}
