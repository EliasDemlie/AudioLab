import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/recorder_controller.dart';
import '../models/recording.dart';
import 'audio_effects_screen.dart';
import 'audio_editor_screen.dart';
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
  int _playbackRevision = 0;

  PlaybackState get _playback => _playbackState.value;
  Duration get _duration => _playback.duration > Duration.zero
      ? _playback.duration
      : _recording.duration ?? Duration.zero;

  @override
  void dispose() {
    _playbackTicker?.cancel();
    unawaited(widget.controller.stopPlayback());
    _playbackState.dispose();
    _playbackBusy.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_playbackBusy.value || _editing) return;
    _playbackBusy.value = true;
    _playbackRevision++;
    try {
      if (_playback.isPlaying) {
        await widget.controller.pausePlayback();
      } else if (_hasStartedPlayback) {
        await widget.controller.resumePlayback();
      } else {
        final startPosition = _playback.position;
        await widget.controller.play(_recording);
        if (!mounted) return;
        _hasStartedPlayback = true;
        if (startPosition > Duration.zero) {
          await widget.controller.seekPlayback(startPosition);
        }
      }
      await _readPlaybackState();
      if (!mounted) return;
      if (_playback.isPlaying) {
        _playbackTicker ??= Timer.periodic(const Duration(milliseconds: 300), (
          _,
        ) {
          if (!_playbackBusy.value) unawaited(_readPlaybackState());
        });
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
    final revision = _playbackRevision;
    try {
      final state = await widget.controller.getPlaybackState();
      if (mounted && revision == _playbackRevision) {
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
    if (_playbackBusy.value || _editing) return;
    final duration = _duration;
    if (duration <= Duration.zero) return;
    final target = Duration(
      milliseconds: position.inMilliseconds
          .clamp(0, duration.inMilliseconds)
          .toInt(),
    );
    _playbackRevision++;
    _playbackState.value = PlaybackState(
      position: target,
      duration: duration,
      isPlaying: _playback.isPlaying,
    );
    if (!_hasStartedPlayback) return;
    _playbackBusy.value = true;
    try {
      await widget.controller.seekPlayback(target);
      await _readPlaybackState();
    } on PlatformException catch (e) {
      _showMessage(e.message ?? 'Could not seek in this recording.');
    } finally {
      if (mounted) _playbackBusy.value = false;
    }
  }

  Future<void> _editAudio() async {
    if (_playbackBusy.value || _editing) return;
    final duration = _duration;
    setState(() => _editing = true);
    _playbackTicker?.cancel();
    _playbackTicker = null;
    _playbackRevision++;
    try {
      await widget.controller.stopPlayback();
      if (!mounted) return;
      _hasStartedPlayback = false;
      _playbackState.value = const PlaybackState();
      final route = MaterialPageRoute<Recording>(
        builder: (_) => AudioEditorScreen(
          recording: _recording,
          controller: widget.controller,
          duration: duration > Duration.zero ? duration : null,
        ),
      );
      final edited = await Navigator.of(context).push(route);
      await route.completed;
      // Finish releasing the editor's shared player before enabling playback.
      await widget.controller.stopPlayback();
      if (!mounted) return;
      if (edited != null) {
        setState(() => _recording = edited);
        _showMessage('Edited audio saved as a new recording.');
      }
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Could not open the audio editor.');
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 76,
        leading: Center(
          child: IconButton.filledTonal(
            tooltip: 'Back to library',
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              backgroundColor: colors.onSurface.withValues(alpha: 0.06),
              foregroundColor: colors.onSurface,
              shape: const CircleBorder(),
              side: BorderSide(color: colors.onSurface.withValues(alpha: 0.08)),
            ),
          ),
        ),
        title: Column(
          children: [
            Text(
              'NOW PLAYING',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 2,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Text('VoicePro', style: theme.textTheme.titleMedium),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
              children: [
                ValueListenableBuilder<PlaybackState>(
                  valueListenable: _playbackState,
                  builder: (context, playback, _) => SizedBox(
                    width: double.infinity,
                    height: 124,
                    child: _PlaybackWaveform(isPlaying: playback.isPlaying),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _recording.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                _PlaybackControls(
                  state: _playbackState,
                  busy: _playbackBusy,
                  duration: _recording.duration,
                  isEditing: _editing,
                  onToggle: _togglePlayback,
                  onSeek: _seek,
                ),
                const SizedBox(height: 28),
                ValueListenableBuilder<bool>(
                  valueListenable: _playbackBusy,
                  builder: (context, isBusy, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: 0.035),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: colors.onSurface.withValues(alpha: 0.07),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _PlayerAction(
                              label: _editing ? 'Saving…' : 'Edit audio',
                              icon: Icons.content_cut_rounded,
                              isBusy: _editing,
                              onPressed: _editing || isBusy ? null : _editAudio,
                            ),
                          ),
                          Expanded(
                            child: _PlayerAction(
                              label: 'Effects',
                              icon: Icons.tune_rounded,
                              onPressed: _editing
                                  ? null
                                  : () => Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => AudioEffectsScreen(
                                          controller: widget.controller,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          Expanded(
                            child: _PlayerAction(
                              label: 'Share',
                              icon: Icons.ios_share_rounded,
                              onPressed: _editing
                                  ? null
                                  : () => widget.controller.share(_recording),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackControls extends StatefulWidget {
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
  State<_PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<_PlaybackControls> {
  double? _scrubProgress;

  String _timeLabel(Duration duration) {
    final formatted = formatDuration(duration);
    return duration.inHours > 0 ? formatted : formatted.substring(3);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PlaybackState>(
    valueListenable: widget.state,
    builder: (context, playback, _) => ValueListenableBuilder<bool>(
      valueListenable: widget.busy,
      builder: (context, isBusy, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final total = playback.duration > Duration.zero
            ? playback.duration
            : widget.duration ?? Duration.zero;
        final totalMillis = total.inMilliseconds.clamp(0, 1 << 53);
        final progress =
            _scrubProgress ??
            (totalMillis == 0
                ? 0.0
                : (playback.position.inMilliseconds / totalMillis).clamp(
                    0.0,
                    1.0,
                  ));
        final position = Duration(
          milliseconds: (progress * totalMillis).round(),
        );
        final canSeek = totalMillis > 0 && !isBusy && !widget.isEditing;
        final timeStyle = theme.textTheme.labelMedium?.copyWith(
          color: colors.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

        return Column(
          children: [
            Semantics(
              label: 'Playback position',
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 5,
                  activeTrackColor: colors.primary,
                  inactiveTrackColor: colors.onSurface.withValues(alpha: 0.1),
                  disabledActiveTrackColor: colors.primary.withValues(
                    alpha: 0.4,
                  ),
                  disabledInactiveTrackColor: colors.onSurface.withValues(
                    alpha: 0.08,
                  ),
                  thumbColor: colors.primary,
                  overlayColor: colors.primary.withValues(alpha: 0.12),
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: _scrubProgress == null ? 6 : 8,
                    elevation: 0,
                    pressedElevation: 0,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 18,
                  ),
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: Slider(
                  value: progress,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  semanticFormatterCallback: (value) =>
                      '${_timeLabel(Duration(milliseconds: (value * totalMillis).round()))} of ${_timeLabel(total)}',
                  onChanged: canSeek
                      ? (value) => setState(() => _scrubProgress = value)
                      : null,
                  onChangeEnd: canSeek
                      ? (value) {
                          widget.onSeek(
                            Duration(
                              milliseconds: (totalMillis * value).round(),
                            ),
                          );
                          setState(() => _scrubProgress = null);
                        }
                      : null,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _timeLabel(position),
                  style: timeStyle?.copyWith(color: colors.primary),
                ),
                Text(_timeLabel(total), style: timeStyle),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SkipButton(
                  tooltip: 'Back 10 seconds',
                  icon: Icons.replay_10_rounded,
                  onPressed: canSeek
                      ? () => widget.onSeek(
                          position - const Duration(seconds: 10),
                        )
                      : null,
                ),
                const SizedBox(width: 18),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(
                          alpha: playback.isPlaying ? 0.2 : 0.1,
                        ),
                        blurRadius: 30,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.primary,
                          Color.lerp(colors.primary, colors.tertiary, 0.3)!,
                        ],
                      ),
                    ),
                    child: SizedBox.square(
                      dimension: 68,
                      child: IconButton(
                        tooltip: playback.isPlaying ? 'Pause' : 'Play',
                        onPressed: isBusy || widget.isEditing
                            ? null
                            : widget.onToggle,
                        style: IconButton.styleFrom(
                          shape: const CircleBorder(),
                          foregroundColor: colors.onPrimary,
                          disabledForegroundColor: colors.onPrimary,
                        ),
                        icon: isBusy
                            ? SizedBox.square(
                                dimension: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: colors.onPrimary,
                                ),
                              )
                            : AnimatedSwitcher(
                                duration: const Duration(milliseconds: 160),
                                child: Icon(
                                  playback.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  key: ValueKey(playback.isPlaying),
                                  size: 38,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                _SkipButton(
                  tooltip: 'Forward 10 seconds',
                  icon: Icons.forward_10_rounded,
                  onPressed: canSeek
                      ? () => widget.onSeek(
                          position + const Duration(seconds: 10),
                        )
                      : null,
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 44,
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        style: IconButton.styleFrom(
          backgroundColor: colors.onSurface.withValues(alpha: 0.05),
          foregroundColor: colors.onSurface,
          shape: const CircleBorder(),
          side: BorderSide(color: colors.onSurface.withValues(alpha: 0.08)),
        ),
      ),
    );
  }
}

class _PlayerAction extends StatelessWidget {
  const _PlayerAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isBusy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isBusy;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isBusy)
          const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(icon, size: 22),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _PlaybackWaveform extends StatelessWidget {
  const _PlaybackWaveform({required this.isPlaying});

  static const _amplitudes = [
    0.12,
    0.20,
    0.36,
    0.22,
    0.45,
    0.70,
    0.35,
    0.17,
    0.31,
    0.56,
    0.88,
    0.51,
    0.28,
    0.42,
    0.72,
    0.96,
    0.63,
    0.34,
    0.19,
    0.45,
    0.76,
    0.57,
    0.28,
    0.49,
    0.83,
    0.56,
    0.31,
    0.46,
    0.68,
    0.39,
    0.20,
  ];

  final bool isPlaying;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('playback-waveform'),
    label: isPlaying ? 'Playing waveform' : 'Recording waveform',
    child: SizedBox(
      width: double.infinity,
      height: 124,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < _amplitudes.length; index++)
            AnimatedContainer(
              key: ValueKey('playback-waveform-bar-$index'),
              width: 4,
              height: isPlaying
                  ? 18 + _amplitudes[index] * 70
                  : 8 + _amplitudes[index] * 28,
              duration: Duration(milliseconds: 380 + index * 45),
              curve: Curves.easeInOutCubic,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: isPlaying ? 0.98 : 0.64),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    ),
  );
}
