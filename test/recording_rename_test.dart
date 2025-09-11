import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/models/recording.dart';
import 'package:voicerec/services/recorder_service.dart';

void main() {
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
      throwsA(isA<PlatformException>()),
    );
  });
}
