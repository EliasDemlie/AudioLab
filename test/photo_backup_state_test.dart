import 'package:flutter_test/flutter_test.dart';
import 'package:voicerec/models/photo_backup_state.dart';

void main() {
  test('defaults are off and safe', () {
    const state = PhotoBackupState();
    expect(state.enabled, isFalse);
    expect(state.wifiOnly, isTrue);
    expect(state.isActive, isFalse);
  });

  test('parses the native state map', () {
    final state = PhotoBackupState.fromMap({
      'configured': true,
      'enabled': true,
      'paused': false,
      'access': 'partial',
      'includeExisting': true,
      'wifiOnly': false,
      'maxFileMb': 10,
      'pending': 3,
      'uploading': 1,
      'uploaded': 7,
      'failed': 2,
      'sdkInt': 34,
      'lastScanAtMillis': 1000,
    });

    expect(state.access, PhotoAccess.partial);
    expect(state.isPartial, isTrue);
    expect(state.canManageSelection, isTrue);
    expect(state.isActive, isTrue);
    expect(state.queued, 4);
    expect(state.lastScanAt, DateTime.fromMillisecondsSinceEpoch(1000));
  });

  test('revoked access stops activity and is reported', () {
    final state = PhotoBackupState.fromMap({'enabled': true, 'access': 'none'});
    expect(state.accessRevoked, isTrue);
    expect(state.isActive, isFalse);
  });

  test('paused backup is not active', () {
    final state = PhotoBackupState.fromMap({
      'enabled': true,
      'paused': true,
      'access': 'full',
    });
    expect(state.isActive, isFalse);
  });

  test('unknown access falls back to none', () {
    expect(PhotoAccess.fromName('bogus'), PhotoAccess.none);
  });
}
