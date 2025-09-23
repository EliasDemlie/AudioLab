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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final isPaused = status == RecorderStatus.paused;
    final canControl =
        !isBusy &&
        !isLocked &&
        (status == RecorderStatus.recording || status == RecorderStatus.paused);
    final Widget content;
    if (status == RecorderStatus.idle || status == RecorderStatus.stopping) {
      content = Center(
        key: const ValueKey('idle-controls'),
        child: SizedBox.square(
          key: const ValueKey('recorder-primary-control'),
          dimension: 112,
          child: IconButton.filled(
            tooltip: 'Record',
            onPressed: status == RecorderStatus.idle && !isBusy && !isLocked
                ? onStart
                : null,
            icon: isBusy || status == RecorderStatus.stopping
                ? SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onPrimary,
                    ),
                  )
                : const Icon(Icons.mic_rounded, size: 42),
            style: IconButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              disabledBackgroundColor: colors.primary,
              disabledForegroundColor: colors.onPrimary,
            ),
          ),
        ),
      );
    } else {
      content = SizedBox(
        key: const ValueKey('active-controls'),
        width: double.infinity,
        height: 136,
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
                color: dark
                    ? const Color(0xFF17304A)
                    : colors.secondaryContainer,
                foreground: colors.onSurface,
                onPressed: canControl ? onStop : null,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 136,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: SizedBox.square(
              dimension: 136,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: dark ? 0.04 : 0.035),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.14),
                  ),
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: content,
          ),
        ],
      ),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final foreground = dark
        ? Colors.white
        : isRecording
        ? colors.onPrimary
        : colors.primary;
    return Tooltip(
      message: isRecording ? 'Pause recording' : 'Resume recording',
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: isRecording ? 'Pause recording' : 'Resume recording',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              key: const ValueKey('recorder-primary-control'),
              duration: const Duration(milliseconds: 250),
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark
                    ? null
                    : isRecording
                    ? colors.primary
                    : colors.primaryContainer,
                gradient: dark
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isRecording
                            ? const [Color(0xFF28E3D0), Color(0xFF00B7B8)]
                            : const [Color(0xFF164A5A), Color(0xFF10384D)],
                      )
                    : null,
                border: dark
                    ? null
                    : Border.all(color: colors.primary.withValues(alpha: 0.12)),
                boxShadow: isRecording
                    ? [
                        BoxShadow(
                          color:
                              (dark ? const Color(0xFF00D5C6) : colors.primary)
                                  .withValues(alpha: dark ? 0.24 : 0.14),
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
                    isRecording
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: foreground,
                    size: 48,
                  ),
                  if (isBusy && !isStopPending)
                    SizedBox.square(
                      dimension: 82,
                      child: CircularProgressIndicator(
                        color: foreground.withValues(alpha: 0.7),
                        strokeWidth: 2,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
