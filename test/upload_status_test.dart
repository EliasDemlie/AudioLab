import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/models/recording.dart';
import 'package:voicerec/models/upload_status.dart';

void main() {
  test('parses an upload map from the native queue', () {
    final upload = UploadStatus.fromMap({
      'filePath': '/data/rec_1.m4a',
      'status': 'uploading',
      'progress': 0.5,
      'attempts': 2,
      'error': null,
    });

    expect(upload.state, UploadState.uploading);
    expect(upload.progress, 0.5);
    expect(upload.attempts, 2);
  });

  test('unknown status falls back to pending', () {
    final upload = UploadStatus.fromMap({'filePath': 'x', 'status': 'bogus'});
    expect(upload.state, UploadState.pending);
  });

  test('recording includes its upload status', () {
    final recording = Recording.fromMap({
      'path': '/data/rec_1.m4a',
      'sizeBytes': 10,
      'modifiedAtMillis': 0,
      'durationMillis': 1000,
      'upload': {
        'filePath': '/data/rec_1.m4a',
        'status': 'failed',
        'error': 'Bot token is invalid or revoked.',
      },
    });

    expect(recording.upload?.state, UploadState.failed);
    expect(recording.upload?.error, 'Bot token is invalid or revoked.');
  });

  test('recording without upload was never queued', () {
    final recording = Recording.fromMap({
      'path': '/data/rec_1.m4a',
      'sizeBytes': 10,
      'modifiedAtMillis': 0,
    });
    expect(recording.upload, isNull);
  });
}
