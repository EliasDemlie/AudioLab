String _twoDigits(int n) => n.toString().padLeft(2, '0');

/// `65s` -> `00:01:05`.
String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  return '${_twoDigits(hours)}:${_twoDigits(minutes)}:${_twoDigits(seconds)}';
}

/// `1536` -> `1.5 KB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

/// `2026-10-12 16:05`.
String formatDateTime(DateTime date) =>
    '${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)} '
    '${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';
