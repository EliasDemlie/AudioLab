import 'package:flutter/material.dart';

import '../models/recording.dart';
import '../utils/formatters.dart';

/// Saved recordings, or an empty state when there are none.
class RecordingsList extends StatelessWidget {
  const RecordingsList({
    super.key,
    required this.recordings,
    required this.onShare,
    required this.onDelete,
  });

  final List<Recording> recordings;
  final ValueChanged<Recording> onShare;
  final ValueChanged<Recording> onDelete;

  @override
  Widget build(BuildContext context) {
    if (recordings.isEmpty) return const _EmptyRecordings();

    return ListView.separated(
      itemCount: recordings.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final recording = recordings[index];
        final isContacts = recording.kind == RecordingKind.contacts;
        return ListTile(
          leading: Icon(
            isContacts ? Icons.contacts_outlined : Icons.audio_file_outlined,
          ),
          title: Text(recording.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  formatDateTime(recording.createdAt),
                  if (recording.duration != null)
                    formatDuration(recording.duration!),
                  if (recording.contactCount != null)
                    '${recording.contactCount} contacts',
                  formatBytes(recording.sizeBytes),
                ].join(' · '),
              ),
            ],
          ),
          onTap: () => onShare(recording),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.share_outlined),
                onPressed: () => onShare(recording),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(recording),
              ),
            ],
          ),
        );
      },
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.voice_over_off_outlined, size: 48, color: color),
          const SizedBox(height: 12),
          Text('No recordings yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Your voice recordings will appear here.',
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
