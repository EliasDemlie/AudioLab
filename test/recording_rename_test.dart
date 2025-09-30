import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/models/recording.dart';
import 'package:voicerec/services/recorder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.beamlinetech.audiolab/recorder');
  final calls = <MethodCall>[];
  var failCatalogUpdate = false;

  setUp(() {
    calls.clear();
    failCatalogUpdate = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'updateRecordingPath') {
            throw MissingPluginException('Unexpected method: ${call.method}');
          }
          calls.add(call);
          if (failCatalogUpdate) {
            throw PlatformException(
              code: 'CATALOG_FAILED',
              message: 'Could not update the recording library.',
            );
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('renames a recording safely and preserves its audio file', () async {
    final directory = await Directory.systemTemp.createTemp('voice-rec-');
    addTearDown(() => directory.delete(recursive: true));
    final originalFile = File('${directory.path}/rec_test.m4a');
    await originalFile.writeAsBytes([1, 2, 3]);
    final original = Recording(
      file: originalFile,
      createdAt: DateTime(2025),
      sizeBytes: 3,
      duration: const Duration(seconds: 4),
    );

    final renamed = await RecorderService().rename(original, r'Team/meeting');

    expect(renamed.file.path, '${directory.path}/Team meeting.m4a');
    expect(await renamed.file.exists(), isTrue);
    expect(await originalFile.exists(), isFalse);
    expect(renamed.duration, const Duration(seconds: 4));
    expect(renamed.title, 'Team meeting');
    expect(await renamed.file.readAsBytes(), [1, 2, 3]);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'updateRecordingPath');
    expect(calls.single.arguments, {
      'oldPath': originalFile.path,
      'newPath': renamed.file.path,
      'title': 'Team meeting',
    });
  });

  test('rejects a recording name with no safe characters', () async {
    final directory = await Directory.systemTemp.createTemp('voice-rec-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/rec_test.m4a');
    await file.writeAsBytes([1]);
    final recording = Recording(
      file: file,
      createdAt: DateTime(2025),
      sizeBytes: 1,
    );

    await expectLater(
      RecorderService().rename(recording, r'///'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'INVALID_TITLE',
        ),
      ),
    );
    expect(calls, isEmpty);
    expect(await file.readAsBytes(), [1]);
  });

  test('restores the original file when the catalog update fails', () async {
    final directory = await Directory.systemTemp.createTemp('voice-rec-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/rec_test.m4a');
    await file.writeAsBytes([1, 2, 3]);
    final recording = Recording(
      file: file,
      createdAt: DateTime(2025),
      sizeBytes: 3,
    );
    failCatalogUpdate = true;

    await expectLater(
      RecorderService().rename(recording, 'Meeting'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'CATALOG_FAILED',
        ),
      ),
    );

    expect(calls, hasLength(1));
    expect(await file.readAsBytes(), [1, 2, 3]);
    expect(await File('${directory.path}/Meeting.m4a').exists(), isFalse);
  });
}
