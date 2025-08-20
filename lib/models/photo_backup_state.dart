/// How much of the photo library the user has authorized.
enum PhotoAccess {
  none,

  /// Android 14+ "Select photos": only the photos the user picked.
  partial,
  full;

  static PhotoAccess fromName(String? name) => PhotoAccess.values.firstWhere(
    (a) => a.name == name,
    orElse: () => PhotoAccess.none,
  );
}

/// Automatic photo backup status as reported by the native photo module.
class PhotoBackupState {
  const PhotoBackupState({
    this.configured = false,
    this.enabled = false,
    this.paused = false,
    this.access = PhotoAccess.none,
    this.includeExisting = false,
    this.wifiOnly = true,
    this.maxFileMb = 20,
    this.maxFileMbLimit = 50,
    this.lastScanAt,
    this.pending = 0,
    this.uploading = 0,
    this.uploaded = 0,
    this.failed = 0,
    this.sdkInt = 0,
    this.promptShown = false,
  });

  factory PhotoBackupState.fromMap(Map<dynamic, dynamic> map) {
    final lastScan = map['lastScanAtMillis'] as int?;
    return PhotoBackupState(
      configured: map['configured'] as bool? ?? false,
      enabled: map['enabled'] as bool? ?? false,
      paused: map['paused'] as bool? ?? false,
      access: PhotoAccess.fromName(map['access'] as String?),
      includeExisting: map['includeExisting'] as bool? ?? false,
      wifiOnly: map['wifiOnly'] as bool? ?? true,
      maxFileMb: map['maxFileMb'] as int? ?? 20,
      maxFileMbLimit: map['maxFileMbLimit'] as int? ?? 50,
      lastScanAt: lastScan == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastScan),
      pending: map['pending'] as int? ?? 0,
      uploading: map['uploading'] as int? ?? 0,
      uploaded: map['uploaded'] as int? ?? 0,
      failed: map['failed'] as int? ?? 0,
      sdkInt: map['sdkInt'] as int? ?? 0,
      promptShown: map['promptShown'] as bool? ?? false,
    );
  }

  /// Telegram bot token and chat were provided at build time.
  final bool configured;
  final bool enabled;
  final bool paused;
  final PhotoAccess access;

  /// Also back up photos that existed before backup was turned on.
  final bool includeExisting;
  final bool wifiOnly;
  final int maxFileMb;
  final int maxFileMbLimit;
  final DateTime? lastScanAt;

  final int pending;
  final int uploading;
  final int uploaded;
  final int failed;
  final int sdkInt;

  /// The one-time home-screen offer has already been shown.
  final bool promptShown;

  /// Backup is on but Android access was removed, so nothing is scanned or uploaded.
  bool get accessRevoked => enabled && access == PhotoAccess.none;

  /// Only some photos are shared (Android 14+ "Select photos").
  bool get isPartial => enabled && access == PhotoAccess.partial;

  /// The system photo picker can be reopened to change the selection.
  bool get canManageSelection => sdkInt >= 34;

  /// Scanning and uploading are actually happening.
  bool get isActive => enabled && !paused && access != PhotoAccess.none;

  int get queued => pending + uploading;
}
