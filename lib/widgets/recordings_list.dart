import 'package:flutter/material.dart';

import '../models/recording.dart';
import '../utils/formatters.dart';

/// Saved recordings, with pull-to-refresh and file actions.
class RecordingsList extends StatelessWidget {
  const RecordingsList({
    super.key,
    required this.recordings,
    required this.onShare,
    required this.onDelete,
    required this.onRefresh,
  });

  final List<Recording> recordings;
  final ValueChanged<Recording> onShare;
  final ValueChanged<Recording> onDelete;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (recordings.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [SizedBox(height: 220, child: _EmptyRecordings())],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 12, 20),
        itemCount: recordings.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          indent: 58,
          color: Theme.of(context).colorScheme.outlineVariant
              .withValues(alpha: 0.35),
        ),
        itemBuilder: (context, index) {
          final recording = recordings[index];
          final colors = Theme.of(context).colorScheme;

          return ListTile(
            contentPadding: const EdgeInsets.only(left: 2, right: 4),
            minVerticalPadding: 10,
            leading: Icon(
              Icons.graphic_eq_rounded,
              color: colors.primary,
              size: 27,
            ),
            title: Text(
              recording.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Wrap(
                spacing: 10,
                runSpacing: 3,
                children: [
                  _FileDetail(
                    icon: Icons.schedule_outlined,
                    label: formatDateTime(recording.createdAt),
                  ),
                  if (recording.duration != null)
                    _FileDetail(
                      icon: Icons.timelapse_outlined,
                      label: formatDuration(recording.duration!),
                    ),
                  _FileDetail(
                    icon: Icons.storage_outlined,
                    label: formatBytes(recording.sizeBytes),
                  ),
                ],
              ),
            ),
            trailing: PopupMenuButton<String>(
              tooltip: 'Recording actions',
              onSelected: (action) {
                if (action == 'share') onShare(recording);
                if (action == 'delete') onDelete(recording);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FileDetail extends StatelessWidget {
  const _FileDetail({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _EmptyRecordings extends StatelessWidget {
  const _EmptyRecordings();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.audio_file_outlined, size: 48, color: color),
            const SizedBox(height: 12),
            Text('No recordings yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Your saved voice recordings will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
