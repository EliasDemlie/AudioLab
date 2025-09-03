import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/recorder_controller.dart';
import '../models/recorder_state.dart';
import '../utils/formatters.dart';
import '../widgets/live_waveform.dart';
import '../widgets/record_controls.dart';
import '../widgets/recording_status.dart';

/// Recorder page. Its controller listener stays within the recorder tab.
class RecorderTab extends StatefulWidget {
  const RecorderTab({
    super.key,
    required this.controller,
    required this.onStop,
  });

  final RecorderController controller;
  final VoidCallback onStop;

  @override
  State<RecorderTab> createState() => _RecorderTabState();
}

class _RecorderTabState extends State<RecorderTab> {
  bool _controlsLocked = false;

  String get _controlLabel {
    if (widget.controller.isStopPending) return 'Saving…';
    return switch (widget.controller.status) {
      RecorderStatus.idle => 'Record',
      RecorderStatus.recording => 'Pause',
      RecorderStatus.paused => 'Resume',
      RecorderStatus.stopping => 'Saving…',
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => LayoutBuilder(
      key: const ValueKey('recorder-home-body'),
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final textScaler = MediaQuery.textScalerOf(context);
        final compact = constraints.maxHeight < 600;
        final waveformHeight = compact ? 36.0 : 80.0;
        final timerSize = compact ? 36.0 : 44.0;
        final verticalPadding = compact ? 12.0 : 16.0;
        final statusHeight =
            textScaler.scale(timerSize) * 1.15 +
            textScaler.scale(12) * 1.25 +
            (compact ? 8 : 10) +
            (widget.controller.micSilenced
                ? textScaler.scale(14) * 1.3 * 3 + 8
                : 0);
        final upperHeight =
            (statusHeight + 8 + waveformHeight + 27 + 12).ceilToDouble() + 2;
        final actionHeight = math.max(48.0, textScaler.scale(14) * 1.3 + 24);
        final largeText = textScaler.scale(14) > 18;
        final bookmarkHeight = textScaler.scale(12) * 1.4 + 24;
        final lowerHeight =
            (12 +
                    textScaler.scale(16) * 1.3 +
                    14 +
                    actionHeight * (largeText ? 2 : 1) +
                    (largeText ? 8 : 0) +
                    (widget.controller.bookmarks.isNotEmpty
                        ? bookmarkHeight + 16
                        : 0))
                .ceilToDouble() +
            2;
        final contentHeight = math
            .max(
              constraints.maxHeight,
              136 +
                  2 * math.max(upperHeight, lowerHeight) +
                  2 * verticalPadding,
            )
            .toDouble();

        return SingleChildScrollView(
          key: const ValueKey('recorder-home-scroll'),
          primary: false,
          child: SizedBox(
            height: contentHeight,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: verticalPadding,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RecordingStatus(
                            elapsed: widget.controller.elapsed,
                            micSilenced: widget.controller.micSilenced,
                            status: widget.controller.status,
                            isStopPending: widget.controller.isStopPending,
                            compact: compact,
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: waveformHeight,
                            child: LiveWaveform(
                              level: widget.controller.audioLevel,
                            ),
                          ),
                          ValueListenableBuilder<double>(
                            valueListenable: widget.controller.audioLevel,
                            builder: (context, level, _) =>
                                AudioLevelMeter(level: level),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  RecordControls(
                    status: widget.controller.status,
                    isBusy: widget.controller.isBusy,
                    isLocked: _controlsLocked,
                    isStopPending: widget.controller.isStopPending,
                    onStart: widget.controller.start,
                    onPause: widget.controller.pause,
                    onResume: widget.controller.resume,
                    onStop: widget.onStop,
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 12),
                          Text(
                            _controlsLocked ? 'Controls locked' : _controlLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colors.onSurface,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              _SecondaryAction(
                                icon: _controlsLocked
                                    ? Icons.lock_open_rounded
                                    : Icons.lock_outline_rounded,
                                label: _controlsLocked ? 'Unlock' : 'Lock',
                                onPressed: widget.controller.isActive
                                    ? () => setState(
                                        () =>
                                            _controlsLocked = !_controlsLocked,
                                      )
                                    : null,
                              ),
                              _SecondaryAction(
                                icon: Icons.bookmark_add_outlined,
                                label: 'Bookmark',
                                onPressed:
                                    !_controlsLocked &&
                                        widget.controller.isActive
                                    ? widget.controller.addBookmark
                                    : null,
                              ),
                            ],
                          ),
                          if (widget.controller.bookmarks.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            SizedBox(
                              height: bookmarkHeight,
                              child: ListView.separated(
                                primary: false,
                                scrollDirection: Axis.horizontal,
                                itemCount: widget.controller.bookmarks.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) => Chip(
                                  avatar: const Icon(
                                    Icons.bookmark_outline_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    formatDuration(
                                      widget.controller.bookmarks[index],
                                    ),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        foregroundColor: colors.onSurfaceVariant,
        shape: const StadiumBorder(),
      ),
      icon: Icon(icon, size: 19),
      label: Text(label),
    );
  }
}
