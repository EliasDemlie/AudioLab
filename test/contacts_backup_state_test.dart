import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/models/contacts_backup_state.dart';

void main() {
  test('parses the latest local contacts backup', () {
    final state = ContactsBackupState.fromMap({
      'permissionGranted': true,
      'latest': {
        'path': '/data/contacts_1.vcf',
        'modifiedAtMillis': 1000,
        'contactCount': 42,
      },
    });

    expect(state.permissionGranted, isTrue);
    expect(state.latestAt, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(state.contactCount, 42);
  });

  test('parses an account with no local backups', () {
    final state = ContactsBackupState.fromMap({'permissionGranted': false});

    expect(state.permissionGranted, isFalse);
    expect(state.latestAt, isNull);
    expect(state.contactCount, isNull);
  });
}
