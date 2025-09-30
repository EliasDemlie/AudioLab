import 'package:flutter/material.dart';

import '../controllers/recorder_controller.dart';
import '../models/recording.dart';
import '../widgets/recordings_list.dart';

/// Library page. It listens only for recording-list changes, not recorder
/// timer or microphone meter updates.
class RecordingsTab extends StatelessWidget {
  const RecordingsTab({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final RecorderController controller;
  final ValueChanged<Recording> onOpen;
  final ValueChanged<Recording> onRename;
  final ValueChanged<Recording> onDelete;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<Recording>>(
    valueListenable: controller.recordingsListenable,
    builder: (context, recordings, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Text(
            'Your recordings',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
        Expanded(
          child: RecordingsList(
            recordings: recordings,
            onOpen: onOpen,
            onRename: onRename,
            onShare: controller.share,
            onDelete: onDelete,
            onRefresh: controller.refreshRecordings,
          ),
        ),
      ],
    ),
  );
}
