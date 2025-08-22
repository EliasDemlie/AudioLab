import 'package:flutter/material.dart';

import '../models/recorder_state.dart';
import '../utils/formatters.dart';

/// Big mic indicator with the running timer.
class RecordingStatus extends StatelessWidget {
  const RecordingStatus({
    super.key,
    required this.status,
    required this.elapsed,
    required this.micSilenced,
  });

  final RecorderStatus status;
  final Duration elapsed;
  final bool micSilenced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
        Text(
          switch (status) {
            RecorderStatus.recording => 'Recording',
            RecorderStatus.paused => 'Recording Paused',
            RecorderStatus.stopping => 'Saving Recording',
            RecorderStatus.idle => 'Ready to Record',
          },
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
            letterSpacing: 0.2,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          formatDuration(elapsed),
          style: theme.textTheme.displayMedium?.copyWith(
            fontSize: 40,
            fontWeight: FontWeight.w300,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (micSilenced) ...[
          const SizedBox(height: 5),
          Text(
            'Microphone is being used by another app',
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
          ),
        ],
      ],
    );
  }
}
