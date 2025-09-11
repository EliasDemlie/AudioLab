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
    final Widget content;
    if (status == RecorderStatus.idle || status == RecorderStatus.stopping) {
      content = Center(
        key: const ValueKey('idle-controls'),
        child: FilledButton.icon(
          onPressed: status == RecorderStatus.idle && !isBusy ? onStart : null,
          icon: status == RecorderStatus.stopping || isBusy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.mic),
          label: Text(
            status == RecorderStatus.stopping
                ? 'Saving…'
                : isBusy
                ? 'Starting…'
                : 'Start recording',
          ),
          style: FilledButton.styleFrom(minimumSize: const Size(190, 56)),
        ),
      );
    } else {
      content = Row(
        key: const ValueKey('active-controls'),
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _RoundControl(
            label: isPaused ? 'Resume' : 'Pause',
            icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            color: const Color(0xFF17304A),
            foreground: Colors.white,
            onPressed: canControl ? (isPaused ? onResume : onPause) : null,
          ),
          _RecordingMicIndicator(
            isRecording: status == RecorderStatus.recording,
            isBusy: isBusy,
          ),
          _RoundControl(
            label: 'Stop',
            icon: Icons.stop_rounded,
            color: const Color(0xFF17304A),
            foreground: colors.onSurface,
            onPressed: canControl ? onStop : null,
          ),
        ],
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
  });

  final bool isRecording;
  final bool isBusy;

  @override
  Widget build(BuildContext context) => Semantics(
    label: isRecording ? 'Recording in progress' : 'Recording paused',
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
          const Icon(Icons.mic_rounded, color: Colors.white, size: 48),
          if (isBusy)
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
  );
}
