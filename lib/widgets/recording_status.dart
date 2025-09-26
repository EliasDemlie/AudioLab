import 'package:flutter/material.dart';

import '../models/recorder_state.dart';
import '../utils/formatters.dart';

/// Elapsed recording timer and microphone status warnings.
class RecordingStatus extends StatelessWidget {
  const RecordingStatus({
    super.key,
    required this.elapsed,
    required this.micSilenced,
    this.status = RecorderStatus.idle,
    this.isStopPending = false,
    this.compact = false,
  });

  final Duration elapsed;
  final bool micSilenced;
  final RecorderStatus status;
  final bool isStopPending;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = isStopPending
        ? colors.secondary
        : switch (status) {
            RecorderStatus.idle => colors.onSurfaceVariant,
            RecorderStatus.recording => colors.primary,
            RecorderStatus.paused => colors.tertiary,
            RecorderStatus.stopping => colors.secondary,
          };
    final label = isStopPending
        ? 'Saving recording'
        : switch (status) {
            RecorderStatus.idle => 'Ready to record',
            RecorderStatus.recording => 'Recording',
            RecorderStatus.paused => 'Recording paused',
            RecorderStatus.stopping => 'Saving recording',
          };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 12,
                    height: 1.25,
                    color: statusColor,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 8 : 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            formatDuration(elapsed),
            key: const ValueKey('recording-elapsed'),
            style: theme.textTheme.displayMedium?.copyWith(
              fontSize: compact ? 36 : 44,
              height: 1.15,
              color: colors.onSurface,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.6,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (micSilenced) ...[
          const SizedBox(height: 8),
          Text(
            'Microphone is being used by another app',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              height: 1.3,
              color: colors.error,
            ),
          ),
        ],
      ],
    );
  }
}
