import 'package:flutter/material.dart';

import '../models/upload_status.dart';

/// One-line Telegram backup status for a recording, with Retry when it failed.
class BackupStatus extends StatelessWidget {
  const BackupStatus({super.key, required this.upload, required this.onRetry});

  /// Null when the recording was never queued (e.g. recorded before backup
  /// was configured).
  final UploadStatus? upload;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final upload = this.upload;
    final small = theme.textTheme.bodySmall;

    if (upload == null) {
      return _Line(
        icon: Icons.cloud_upload_outlined,
        color: colors.onSurfaceVariant,
        text: 'Not backed up',
        action: TextButton(onPressed: onRetry, child: const Text('Back up')),
      );
    }

    return switch (upload.state) {
      UploadState.pending => _Line(
        icon: Icons.cloud_queue,
        color: colors.onSurfaceVariant,
        text: upload.error == null
            ? 'Waiting to upload'
            : 'Will retry: ${upload.error}',
      ),
      UploadState.uploading => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: upload.progress > 0 ? upload.progress : null,
              ),
            ),
            const SizedBox(width: 8),
            Text('${(upload.progress * 100).round()}%', style: small),
          ],
        ),
      ),
      UploadState.uploaded => _Line(
        icon: Icons.cloud_done,
        color: colors.primary,
        text: 'Backed up to Telegram',
      ),
      UploadState.failed => _Line(
        icon: Icons.cloud_off,
        color: colors.error,
        text: upload.error ?? 'Upload failed',
        action: TextButton(onPressed: onRetry, child: const Text('Retry')),
      ),
    };
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.color,
    required this.text,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
        ?action,
      ],
    );
  }
}
