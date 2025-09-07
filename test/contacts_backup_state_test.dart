import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/models/contacts_backup_state.dart';
import 'package:voicerec/models/upload_status.dart';

void main() {
  test('parses state with a failed latest backup', () {
    final state = ContactsBackupState.fromMap({
      'configured': true,
      'permissionGranted': true,
      'lastSuccessAtMillis': 1000,
      'latest': {
        'filePath': '/data/contacts_1.vcf',
        'status': 'failed',
        'error': 'Bot token is invalid or revoked.',
        'contactCount': 42,
      },
    });

    expect(state.configured, isTrue);
    expect(state.lastSuccessAt, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(state.latest?.state, UploadState.failed);
    expect(state.contactCount, 42);
    expect(state.isBusy, isFalse);
  });

  test('never backed up', () {
    final state = ContactsBackupState.fromMap({'configured': true});
    expect(state.lastSuccessAt, isNull);
    expect(state.latest, isNull);
    expect(state.isBusy, isFalse);
  });

  test('pending upload is busy', () {
    final state = ContactsBackupState.fromMap({
      'latest': {'filePath': 'x.vcf', 'status': 'pending'},
    });
    expect(state.isBusy, isTrue);
  });
}
