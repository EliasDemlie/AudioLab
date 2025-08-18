/// Local contacts backup information reported by the native contacts module.
class ContactsBackupState {
  const ContactsBackupState({
    this.permissionGranted = false,
    this.latestAt,
    this.contactCount,
  });

  factory ContactsBackupState.fromMap(Map<dynamic, dynamic> map) {
    final latest = map['latest'] as Map?;
    final modifiedAt = latest?['modifiedAtMillis'] as int?;
    return ContactsBackupState(
      permissionGranted: map['permissionGranted'] as bool? ?? false,
      latestAt: modifiedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(modifiedAt),
      contactCount: latest?['contactCount'] as int?,
    );
  }

  final bool permissionGranted;
  final DateTime? latestAt;
  final int? contactCount;
}
