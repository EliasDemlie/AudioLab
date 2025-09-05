import 'package:flutter/material.dart';

import '../models/recorder_state.dart';

/// Start, Pause/Resume and Stop buttons.
class RecordControls extends StatelessWidget {
  const RecordControls({
    super.key,
    required this.status,
    required this.isBusy,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  final RecorderStatus status;
  final bool isBusy;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isPaused = status == RecorderStatus.paused;
    final canControl =
        !isBusy &&
        (status == RecorderStatus.recording || status == RecorderStatus.paused);
    const buttonSize = Size.fromHeight(52);

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: status == RecorderStatus.idle && !isBusy
                ? onStart
                : null,
            icon: const Icon(Icons.fiber_manual_record),
            label: const Text('Start'),
            style: FilledButton.styleFrom(minimumSize: buttonSize),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: canControl ? (isPaused ? onResume : onPause) : null,
            icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
            label: Text(isPaused ? 'Resume' : 'Pause'),
            style: FilledButton.styleFrom(minimumSize: buttonSize),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: canControl ? onStop : null,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
            style: FilledButton.styleFrom(
              minimumSize: buttonSize,
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
          ),
        ),
      ],
    );
  }
}
