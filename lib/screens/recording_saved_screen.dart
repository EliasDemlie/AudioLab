import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/recorder_controller.dart';
import '../models/recording.dart';
import '../utils/formatters.dart';

class RecordingSavedScreen extends StatefulWidget {
  const RecordingSavedScreen({
    super.key,
    required this.recording,
    required this.controller,
  });

  final Recording recording;
  final RecorderController controller;

  @override
  State<RecordingSavedScreen> createState() => _RecordingSavedScreenState();
}

class _RecordingSavedScreenState extends State<RecordingSavedScreen> {
  late Recording _recording = widget.recording;
  PlaybackState _playback = const PlaybackState();
  Timer? _playbackTicker;
  bool _hasStartedPlayback = false;
  bool _playbackBusy = false;

  @override
  void dispose() {
    _playbackTicker?.cancel();
    unawaited(widget.controller.stopPlayback());
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_playbackBusy) return;
    setState(() => _playbackBusy = true);
    try {
      if (_playback.isPlaying) {
        await widget.controller.pausePlayback();
      } else if (_hasStartedPlayback) {
        await widget.controller.resumePlayback();
      } else {
        await widget.controller.play(_recording);
        _hasStartedPlayback = true;
      }
      await _readPlaybackState();
      if (_playback.isPlaying) {
        _playbackTicker ??= Timer.periodic(
          const Duration(milliseconds: 300),
          (_) => _readPlaybackState(),
        );
      } else {
        _playbackTicker?.cancel();
        _playbackTicker = null;
      }
    } on PlatformException catch (e) {
      _showMessage(e.message ?? 'Could not play this recording.');
    } finally {
      if (mounted) setState(() => _playbackBusy = false);
    }
  }

  Future<void> _readPlaybackState() async {
    try {
      final state = await widget.controller.getPlaybackState();
      if (mounted) {
        setState(() => _playback = state);
        if (!state.isPlaying) {
          _playbackTicker?.cancel();
          _playbackTicker = null;
        }
      }
    } on PlatformException catch (e) {
      if (mounted) _showMessage(e.message ?? 'Could not read playback state.');
    }
  }

  Future<void> _seek(Duration position) async {
    try {
      await widget.controller.seekPlayback(position);
      await _readPlaybackState();
    } on PlatformException catch (e) {
      _showMessage(e.message ?? 'Could not seek in this recording.');
    }
  }

  Future<void> _rename() async {
    final input = TextEditingController(text: _recording.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename recording'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Recording name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    input.dispose();
    if (title == null || !mounted) return;
    try {
      final renamed = await widget.controller.rename(_recording, title);
      if (mounted) setState(() => _recording = renamed);
    } on PlatformException catch (e) {
      _showMessage(e.message ?? 'Could not rename this recording.');
    } on FileSystemException catch (e) {
      _showMessage(e.message);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = _recording.duration ?? _playback.duration;
    final position = _playback.position > duration
        ? duration
        : _playback.position;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : position.inMilliseconds / duration.inMilliseconds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recording details'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          children: [
            Icon(Icons.check_circle, color: colors.primary, size: 54),
            const SizedBox(height: 12),
            Text(
              'Recording Details',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 28),
            Text(
              _recording.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${formatDate(_recording.createdAt)} · ${duration == Duration.zero ? '--:--:--' : formatDuration(duration)}',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 5),
            Text(
              '${_recording.file.path.split('.').last.toUpperCase()} · ${formatBytes(_recording.sizeBytes)}',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 42),
            Row(
              children: [
                Text(formatDuration(position)),
                Expanded(
                  child: Slider(
                    value: progress.clamp(0.0, 1.0),
                    onChanged: duration == Duration.zero
                        ? null
                        : (value) => setState(
                            () => _playback = PlaybackState(
                              position: Duration(
                                milliseconds: (duration.inMilliseconds * value)
                                    .round(),
                              ),
                              duration: duration,
                              isPlaying: _playback.isPlaying,
                            ),
                          ),
                    onChangeEnd: duration == Duration.zero
                        ? null
                        : (value) => _seek(
                            Duration(
                              milliseconds: (duration.inMilliseconds * value)
                                  .round(),
                            ),
                          ),
                  ),
                ),
                Text(formatDuration(duration)),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: IconButton.filled(
                onPressed: _playbackBusy ? null : _togglePlayback,
                icon: Icon(
                  _playback.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
                iconSize: 34,
                style: IconButton.styleFrom(
                  minimumSize: const Size(72, 72),
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                ),
              ),
            ),
            const SizedBox(height: 30),
            OutlinedButton.icon(
              onPressed: _rename,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Rename'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => widget.controller.share(_recording),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share recording'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
