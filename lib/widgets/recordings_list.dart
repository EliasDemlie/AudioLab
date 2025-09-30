import 'package:flutter/material.dart';

import '../models/recording.dart';
import '../utils/formatters.dart';

/// Saved recordings, with pull-to-refresh and file actions.
class RecordingsList extends StatelessWidget {
  const RecordingsList({
    super.key,
    required this.recordings,
    required this.onOpen,
    required this.onRename,
    required this.onShare,
    required this.onDelete,
    required this.onRefresh,
  });

  final List<Recording> recordings;
  final ValueChanged<Recording> onOpen;
  final ValueChanged<Recording> onRename;
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
        padding: const EdgeInsets.only(bottom: 20),
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
            onTap: () => onOpen(recording),
            contentPadding: const EdgeInsets.only(left: 16, right: 4),
            minVerticalPadding: 10,
            leading: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.music_note_rounded,
                color: colors.onPrimaryContainer,
                size: 24,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    recording.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatBytes(recording.sizeBytes),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Wrap(
                spacing: 10,
                runSpacing: 3,
                children: [
                  _FileDetail(label: formatDate(recording.createdAt)),
                  if (recording.duration != null)
                    _FileDetail(label: formatDuration(recording.duration!)),
                ],
              ),
            ),
            trailing: PopupMenuButton<String>(
              tooltip: 'Recording actions',
              padding: EdgeInsets.zero,
              iconSize: 22,
              onSelected: (action) {
                if (action == 'rename') onRename(recording);
                if (action == 'share') onShare(recording);
                if (action == 'delete') onDelete(recording);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
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
  const _FileDetail({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
