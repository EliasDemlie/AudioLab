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
    final isRecording = status == RecorderStatus.recording;
    final accent = switch (status) {
      RecorderStatus.recording => colors.error,
      RecorderStatus.paused => colors.tertiary,
      _ => colors.primary,
    };

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.12),
            border: Border.all(color: accent, width: isRecording ? 4 : 2),
          ),
          child: Icon(
            switch (status) {
              RecorderStatus.recording => Icons.mic,
              RecorderStatus.paused => Icons.pause,
              _ => Icons.mic_none,
            },
            size: 56,
            color: accent,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          formatDuration(elapsed),
          style: theme.textTheme.displaySmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          switch (status) {
            RecorderStatus.recording => 'Recording… you can close the app',
            RecorderStatus.paused => 'Paused',
            RecorderStatus.stopping => 'Saving…',
            RecorderStatus.idle => 'Press Start to record',
          },
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        if (micSilenced) ...[
          const SizedBox(height: 8),
          Text(
            'Microphone is in use by another app',
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
          ),
        ],
      ],
    );
  }
}
