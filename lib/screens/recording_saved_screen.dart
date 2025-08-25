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
  final ValueNotifier<PlaybackState> _playbackState = ValueNotifier(
    const PlaybackState(),
  );
  final ValueNotifier<bool> _playbackBusy = ValueNotifier(false);
  Timer? _playbackTicker;
  bool _hasStartedPlayback = false;
  bool _editing = false;

  PlaybackState get _playback => _playbackState.value;

  @override
  void dispose() {
    _playbackTicker?.cancel();
    unawaited(widget.controller.stopPlayback());
    _playbackState.dispose();
    _playbackBusy.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_playbackBusy.value) return;
    _playbackBusy.value = true;
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
      if (mounted) _playbackBusy.value = false;
    }
  }

  Future<void> _readPlaybackState() async {
    try {
      final state = await widget.controller.getPlaybackState();
      if (mounted) {
        _playbackState.value = state;
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
    final duration = _recording.duration ?? _playback.duration;
    final target = Duration(
      milliseconds: position.inMilliseconds
          .clamp(0, duration.inMilliseconds)
          .toInt(),
    );
    try {
      await widget.controller.seekPlayback(target);
      await _readPlaybackState();
    } on PlatformException catch (e) {
      _showMessage(e.message ?? 'Could not seek in this recording.');
    }
  }

  Future<void> _rename() async {
    final input = TextEditingController(text: _recording.title);
    final title = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rename file',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: input,
                autofocus: true,
                maxLength: 80,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'File name',
                  suffixText: '.${_recording.format.toLowerCase()}',
                  border: const UnderlineInputBorder(),
                ),
                onSubmitted: (_) => FocusScope.of(sheetContext).unfocus(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(sheetContext).pop<String>(null),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, input.text),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save name'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
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

  Future<void> _editAudio() async {
    final duration = _recording.duration ?? _playback.duration;
    if (duration.inMilliseconds < 1000) {
      _showMessage('Audio length is unavailable, so it cannot be trimmed yet.');
      return;
    }
    final selected = await showDialog<RangeValues>(
      context: context,
      builder: (context) => _TrimDialog(duration: duration),
    );
    if (selected == null || !mounted) return;

    final start = Duration(
      milliseconds: (duration.inMilliseconds * selected.start).round(),
    );
    final end = Duration(
      milliseconds: (duration.inMilliseconds * selected.end).round(),
    );
    if (end - start < const Duration(seconds: 1)) {
      _showMessage('Select at least one second of audio.');
      return;
    }

    setState(() => _editing = true);
    try {
      await widget.controller.stopPlayback();
      final edited = await widget.controller.trimAudio(
        _recording,
        start: start,
        end: end,
      );
      if (!mounted) return;
      setState(() {
        _recording = edited;
        _playbackState.value = const PlaybackState();
        _hasStartedPlayback = false;
      });
      _showMessage('Edited audio saved as a new recording.');
    } on PlatformException catch (e) {
      _showMessage(e.message ?? 'Could not edit this recording.');
    } on FileSystemException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _editing = false);
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to library',
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          children: [
            Text(
              'NOW PLAYING',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.5,
                color: colors.onSurfaceVariant,
              ),
            ),
            const Text('VoicePro'),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'More options',
            onPressed: _rename,
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          children: [
            _RecordingArtwork(color: colors.primary),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _recording.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Voice recording · ${formatDate(_recording.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Rename recording',
                  onPressed: _rename,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _PlaybackControls(
              state: _playbackState,
              busy: _playbackBusy,
              duration: _recording.duration,
              isEditing: _editing,
              onToggle: _togglePlayback,
              onSeek: _seek,
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _editing ? null : _editAudio,
              icon: _editing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.content_cut_rounded),
              label: Text(_editing ? 'Saving edited copy…' : 'Edit audio'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => widget.controller.share(_recording),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share recording'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.state,
    required this.busy,
    required this.duration,
    required this.isEditing,
    required this.onToggle,
    required this.onSeek,
  });

  final ValueNotifier<PlaybackState> state;
  final ValueNotifier<bool> busy;
  final Duration? duration;
  final bool isEditing;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PlaybackState>(
    valueListenable: state,
    builder: (context, playback, _) {
      final total = duration ?? playback.duration;
      final position = playback.position > total ? total : playback.position;
      final progress = total.inMilliseconds == 0
          ? 0.0
          : position.inMilliseconds / total.inMilliseconds;

      return Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: total == Duration.zero
                  ? null
                  : (value) => state.value = PlaybackState(
                      position: Duration(
                        milliseconds: (total.inMilliseconds * value).round(),
                      ),
                      duration: total,
                      isPlaying: playback.isPlaying,
                    ),
              onChangeEnd: total == Duration.zero
                  ? null
                  : (value) => onSeek(
                      Duration(
                        milliseconds: (total.inMilliseconds * value).round(),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDuration(position)),
                Text(formatDuration(total)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: 'Back 10 seconds',
                onPressed: total == Duration.zero
                    ? null
                    : () => onSeek(position - const Duration(seconds: 10)),
                icon: const Icon(Icons.replay_10_rounded),
                iconSize: 34,
              ),
              ValueListenableBuilder<bool>(
                valueListenable: busy,
                builder: (context, isBusy, _) => IconButton.filled(
                  tooltip: playback.isPlaying ? 'Pause' : 'Play',
                  onPressed: isBusy || isEditing ? null : onToggle,
                  icon: Icon(
                    playback.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  iconSize: 38,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(78, 78),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Forward 10 seconds',
                onPressed: total == Duration.zero
                    ? null
                    : () => onSeek(position + const Duration(seconds: 10)),
                icon: const Icon(Icons.forward_10_rounded),
                iconSize: 34,
              ),
            ],
          ),
        ],
      );
    },
  );
}

class _RecordingArtwork extends StatelessWidget {
  const _RecordingArtwork({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.9), const Color(0xFF172A43)],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 32,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.graphic_eq_rounded,
            size: 162,
            color: Colors.white.withValues(alpha: 0.12),
          ),
          Container(
            width: 126,
            height: 126,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.25),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.24),
                width: 1.5,
              ),
            ),
            child: const Icon(Icons.mic_rounded, size: 58, color: Colors.white),
          ),
          Positioned(
            bottom: 20,
            child: Text(
              'VOICE RECORDING',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.82),
                letterSpacing: 2.2,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TrimDialog extends StatefulWidget {
  const _TrimDialog({required this.duration});

  final Duration duration;

  @override
  State<_TrimDialog> createState() => _TrimDialogState();
}

class _TrimDialogState extends State<_TrimDialog> {
  RangeValues _range = const RangeValues(0, 1);

  Duration _at(double fraction) => Duration(
    milliseconds: (widget.duration.inMilliseconds * fraction).round(),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Trim audio'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Drag the handles to choose the part to keep.'),
          const SizedBox(height: 18),
          RangeSlider(
            values: _range,
            min: 0,
            max: 1,
            divisions: 1000,
            labels: RangeLabels(
              formatDuration(_at(_range.start)),
              formatDuration(_at(_range.end)),
            ),
            onChanged: (value) => setState(() => _range = value),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(_at(_range.start))),
              Text(formatDuration(_at(_range.end))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Keep ${formatDuration(_at(_range.end) - _at(_range.start))}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.pop(context, _range),
        icon: const Icon(Icons.save_outlined),
        label: const Text('Save copy'),
      ),
    ],
  );
}
