import 'package:flutter/material.dart';

import '../controllers/recorder_controller.dart';
import '../utils/formatters.dart';
import '../widgets/live_waveform.dart';
import '../widgets/record_controls.dart';
import '../widgets/recording_status.dart';

/// Recorder page. Its controller listener is kept inside this tab so updates
/// to recording state never rebuild the library page.
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
          child: Column(
            children: [
              RecordingStatus(
                elapsed: widget.controller.elapsed,
                micSilenced: widget.controller.micSilenced,
              ),
              const SizedBox(height: 4),
              LiveWaveform(level: widget.controller.audioLevel),
              ValueListenableBuilder<double>(
                valueListenable: widget.controller.audioLevel,
                builder: (context, level, _) => AudioLevelMeter(level: level),
              ),
              const SizedBox(height: 14),
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
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SecondaryAction(
                    icon: _controlsLocked
                        ? Icons.lock_open
                        : Icons.lock_outline,
                    label: _controlsLocked ? 'Unlock' : 'Lock',
                    onPressed: widget.controller.isActive
                        ? () =>
                              setState(() => _controlsLocked = !_controlsLocked)
                        : null,
                  ),
                  const SizedBox(width: 44),
                  _SecondaryAction(
                    icon: Icons.bookmark_add_outlined,
                    label: 'Bookmark',
                    onPressed: !_controlsLocked && widget.controller.isActive
                        ? widget.controller.addBookmark
                        : null,
                  ),
                ],
              ),
              if (widget.controller.bookmarks.isNotEmpty)
                SizedBox(
                  height: 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.controller.bookmarks.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, index) => Chip(
                      avatar: const Icon(Icons.bookmark, size: 15),
                      label: Text(
                        formatDuration(widget.controller.bookmarks[index]),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
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
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 19),
    label: Text(label),
  );
}
