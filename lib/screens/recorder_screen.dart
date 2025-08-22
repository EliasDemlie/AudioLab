import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/recorder_controller.dart';
import '../models/recording.dart';
import '../widgets/record_controls.dart';
import '../widgets/recording_status.dart';
import '../widgets/recordings_list.dart';
import '../utils/formatters.dart';
import '../widgets/live_waveform.dart';

class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  final _controller = RecorderController();
  late final StreamSubscription<String> _errorSub;
  bool _controlsLocked = false;

  @override
  void initState() {
    super.initState();
    _errorSub = _controller.errors.listen(_showError);
    _controller.init();
  }

  @override
  void dispose() {
    _errorSub.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete(Recording recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recording?'),
        content: Text(recording.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await _controller.delete(recording);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'VoicePro',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: Column(
                  children: [
                    RecordingStatus(
                      status: _controller.status,
                      elapsed: _controller.elapsed,
                      micSilenced: _controller.micSilenced,
                    ),
                    const SizedBox(height: 4),
                    LiveWaveform(level: _controller.audioLevel),
                    ValueListenableBuilder<double>(
                      valueListenable: _controller.audioLevel,
                      builder: (context, level, _) =>
                          AudioLevelMeter(level: level),
                    ),
                    const SizedBox(height: 14),
                    RecordControls(
                      status: _controller.status,
                      isBusy: _controller.isBusy || _controlsLocked,
                      onStart: _controller.start,
                      onPause: _controller.pause,
                      onResume: _controller.resume,
                      onStop: _controller.stop,
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
                          onPressed: _controller.isActive
                              ? () => setState(
                                  () => _controlsLocked = !_controlsLocked,
                                )
                              : null,
                        ),
                        const SizedBox(width: 44),
                        _SecondaryAction(
                          icon: Icons.bookmark_add_outlined,
                          label: 'Bookmark',
                          onPressed: !_controlsLocked && _controller.isActive
                              ? _controller.addBookmark
                              : null,
                        ),
                      ],
                    ),
                    if (_controller.bookmarks.isNotEmpty)
                      SizedBox(
                        height: 34,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _controller.bookmarks.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (context, index) => Chip(
                            avatar: const Icon(Icons.bookmark, size: 15),
                            label: Text(
                              formatDuration(_controller.bookmarks[index]),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recent recordings',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              Expanded(
                child: RecordingsList(
                  recordings: _controller.recordings,
                  onShare: _controller.share,
                  onDelete: _confirmDelete,
                  onRefresh: _controller.refreshRecordings,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
