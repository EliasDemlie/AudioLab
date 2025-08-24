import 'package:flutter/material.dart';

import '../models/recorder_state.dart';

/// Start, Pause/Resume and Stop buttons.
class RecordControls extends StatelessWidget {
  const RecordControls({
    super.key,
    required this.status,
    required this.isBusy,
    required this.isLocked,
    required this.isStopPending,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  final RecorderStatus status;
  final bool isBusy;
  final bool isLocked;
  final bool isStopPending;
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
        !isLocked &&
        (status == RecorderStatus.recording || status == RecorderStatus.paused);
    final Widget content;
    if (status == RecorderStatus.idle || status == RecorderStatus.stopping) {
      content = Center(
        key: const ValueKey('idle-controls'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 92,
              child: IconButton.filled(
                tooltip: 'Record',
                onPressed: status == RecorderStatus.idle && !isBusy && !isLocked
                    ? onStart
                    : null,
                icon: const Icon(Icons.mic_rounded, size: 38),
                style: IconButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  disabledBackgroundColor: colors.primary,
                  disabledForegroundColor: colors.onPrimary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              status == RecorderStatus.stopping
                  ? 'Saving…'
                  : 'Record',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
      );
    } else {
      content = SizedBox(
        key: const ValueKey('active-controls'),
        width: double.infinity,
        height: 112,
        child: Stack(
          alignment: Alignment.center,
          children: [
            _RecordingMicIndicator(
              isRecording: status == RecorderStatus.recording,
              isBusy: isBusy,
              isStopPending: isStopPending,
              onPressed: canControl ? (isPaused ? onResume : onPause) : null,
            ),
            Positioned(
              right: 0,
              child: _RoundControl(
                label: 'Stop',
                icon: Icons.stop_rounded,
                color: const Color(0xFF17304A),
                foreground: colors.onSurface,
                onPressed: canControl ? onStop : null,
              ),
            ),
          ],
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: content,
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.label,
    required this.icon,
    required this.color,
    required this.foreground,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final Color color;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        width: 64,
        height: 64,
        child: IconButton.filled(
          tooltip: label,
          onPressed: onPressed,
          icon: Icon(icon, size: 26),
          style: IconButton.styleFrom(
            backgroundColor: color,
            foregroundColor: foreground,
            padding: EdgeInsets.zero,
            disabledBackgroundColor: color.withValues(alpha: 0.08),
          ),
        ),
      ),
    ],
  );
}

class _RecordingMicIndicator extends StatelessWidget {
  const _RecordingMicIndicator({
    required this.isRecording,
    required this.isBusy,
    required this.isStopPending,
    required this.onPressed,
  });

  final bool isRecording;
  final bool isBusy;
  final bool isStopPending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: isRecording ? 'Pause recording' : 'Resume recording',
    child: Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isRecording
                  ? const [Color(0xFF28E3D0), Color(0xFF00B7B8)]
                  : const [Color(0xFF164A5A), Color(0xFF10384D)],
            ),
            boxShadow: isRecording
                ? [
                    BoxShadow(
                      color: const Color(0xFF00D5C6).withValues(alpha: 0.24),
                      blurRadius: 26,
                      spreadRadius: 2,
                    ),
                  ]
                : const [],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                isRecording ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 48,
              ),
              if (isBusy && !isStopPending)
                const SizedBox.square(
                  dimension: 82,
                  child: CircularProgressIndicator(
                    color: Colors.white70,
                    strokeWidth: 2,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
