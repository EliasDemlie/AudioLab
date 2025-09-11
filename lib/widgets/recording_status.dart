import 'package:flutter/material.dart';

import '../utils/formatters.dart';

/// Elapsed recording timer and microphone status warnings.
class RecordingStatus extends StatelessWidget {
  const RecordingStatus({
    super.key,
    required this.elapsed,
    required this.micSilenced,
  });

  final Duration elapsed;
  final bool micSilenced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
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
