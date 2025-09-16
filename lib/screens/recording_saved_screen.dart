import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/recorder_controller.dart';
import '../models/recording.dart';
import '../utils/audio_effect_presets.dart';
import '../utils/formatters.dart';
import '../widgets/circular_eq_dial.dart';
import 'audio_editor_screen.dart';

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
  final ValueNotifier<List<double>> _waveformPeaks = ValueNotifier(const []);
  final ValueNotifier<List<double>> _equalizerGains = ValueNotifier(const [
    0.0,
    0.0,
    0.0,
  ]);
  final ValueNotifier<bool> _equalizerBusy = ValueNotifier(false);
  Timer? _playbackTicker;
  bool _hasStartedPlayback = false;
  bool _editing = false;
  int _playbackRevision = 0;
  int _waveformRevision = 0;

  PlaybackState get _playback => _playbackState.value;
  Duration get _duration => _playback.duration > Duration.zero
      ? _playback.duration
      : _recording.duration ?? Duration.zero;

  @override
  void initState() {
    super.initState();
    unawaited(_loadWaveform(_recording));
  }

  Future<void> _loadWaveform(Recording recording) async {
    final revision = ++_waveformRevision;
    try {
      final waveform = await widget.controller.loadWaveform(recording);
      if (mounted && revision == _waveformRevision) {
        _waveformPeaks.value = waveform.peaks;
      }
    } catch (_) {
      if (mounted && revision == _waveformRevision) {
        _waveformPeaks.value = const [];
      }
    }
  }

  @override
  void dispose() {
    _playbackTicker?.cancel();
    unawaited(widget.controller.stopPlayback());
    _playbackState.dispose();
    _playbackBusy.dispose();
    _waveformPeaks.dispose();
    _equalizerGains.dispose();
    _equalizerBusy.dispose();
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
      await widget.controller.stopPlayback();
      if (!mounted) return;
      if (edited != null) {
        setState(() => _recording = edited);
        _waveformPeaks.value = const [];
        unawaited(_loadWaveform(edited));
        _showMessage('Edited audio saved as a new recording.');
      }
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Could not open the audio editor.');
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _applyEqualizer(List<double> gains) async {
    final appliedGains = List<double>.unmodifiable(gains);
    _equalizerGains.value = appliedGains;
    _equalizerBusy.value = true;
    try {
      await widget.controller.setPlaybackEqualizer(appliedGains);
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Audio effects are unavailable.');
    } finally {
      if (mounted) _equalizerBusy.value = false;
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
                  builder: (context, playback, _) => ValueListenableBuilder(
                    valueListenable: _waveformPeaks,
                    builder: (context, peaks, _) {
                      final durationMillis = _duration.inMilliseconds;
                      final progress = durationMillis > 0
                          ? (playback.position.inMilliseconds / durationMillis)
                                .clamp(0.0, 1.0)
                          : 0.0;
                      return SizedBox(
                        width: double.infinity,
                        height: 124,
                        child: _PlaybackWaveform(
                          peaks: peaks,
                          progress: progress,
                          isPlaying: playback.isPlaying,
                        ),
                      );
                    },
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
                  onEdit: _editAudio,
                  onShare: () => widget.controller.share(_recording),
                  onToggle: _togglePlayback,
                  onSeek: _seek,
                ),
                const SizedBox(height: 12),
                _AlwaysVisibleEffects(
                  gains: _equalizerGains,
                  busy: _equalizerBusy,
                  onChanged: _applyEqualizer,
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
    required this.onEdit,
    required this.onShare,
    required this.onToggle,
    required this.onSeek,
  });

  final ValueNotifier<PlaybackState> state;
  final ValueNotifier<bool> busy;
  final Duration? duration;
  final bool isEditing;
  final VoidCallback onEdit;
  final VoidCallback onShare;
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: 52,
                  child: TextButton(
                    onPressed: isBusy || widget.isEditing
                        ? null
                        : widget.onEdit,
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'Edit',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                    ),
                  ),
                ),
                _SkipButton(
                  tooltip: 'Back 10 seconds',
                  icon: Icons.replay_10_rounded,
                  onPressed: canSeek
                      ? () => widget.onSeek(
                          position - const Duration(seconds: 10),
                        )
                      : null,
                ),
                const SizedBox(width: 4),
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
                      dimension: 56,
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
                                  size: 32,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _SkipButton(
                  tooltip: 'Forward 10 seconds',
                  icon: Icons.forward_10_rounded,
                  onPressed: canSeek
                      ? () => widget.onSeek(
                          position + const Duration(seconds: 10),
                        )
                      : null,
                ),
                IconButton(
                  tooltip: 'Share recording',
                  onPressed: isBusy || widget.isEditing ? null : widget.onShare,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
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
      dimension: 38,
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
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

class _AlwaysVisibleEffects extends StatelessWidget {
  const _AlwaysVisibleEffects({
    required this.gains,
    required this.busy,
    required this.onChanged,
  });

  final ValueListenable<List<double>> gains;
  final ValueListenable<bool> busy;
  final ValueChanged<List<double>> onChanged;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<double>>(
    valueListenable: gains,
    builder: (context, values, _) => Column(
      children: [
        Row(
          children: [
            Text(
              'EQUALIZER',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            ValueListenableBuilder<bool>(
              valueListenable: busy,
              builder: (context, isBusy, _) => isBusy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<bool>(
          valueListenable: busy,
          builder: (context, isBusy, _) => Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final preset in audioEffectPresets.entries)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(preset.key, maxLines: 1, softWrap: false),
                  selected: audioEffectPresetFor(values) == preset.key,
                  onSelected: isBusy ? null : (_) => onChanged(preset.value),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: CircularEqDial(
                label: 'Bass',
                value: values[0],
                onChanged: (value) => onChanged([value, values[1], values[2]]),
              ),
            ),
            Expanded(
              child: CircularEqDial(
                label: 'Presence',
                value: values[1],
                onChanged: (value) => onChanged([values[0], value, values[2]]),
              ),
            ),
            Expanded(
              child: CircularEqDial(
                label: 'Treble',
                value: values[2],
                onChanged: (value) => onChanged([values[0], values[1], value]),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PlaybackWaveform extends StatelessWidget {
  const _PlaybackWaveform({
    required this.peaks,
    required this.progress,
    required this.isPlaying,
  });

  static const _barCount = 31;

  final List<double> peaks;
  final double progress;
  final bool isPlaying;

  double _amplitudeForBar(int barIndex) {
    if (peaks.isEmpty) return 0.12;
    final startIndex = barIndex * peaks.length ~/ _barCount;
    final endIndex = math.max(
      startIndex + 1,
      (barIndex + 1) * peaks.length ~/ _barCount,
    );
    var amplitude = 0.0;
    for (var sampleIndex = startIndex; sampleIndex < endIndex; sampleIndex++) {
      final peak = peaks[sampleIndex];
      if (peak.isFinite && peak > amplitude) {
        amplitude = peak.clamp(0.0, 1.0).toDouble();
      }
    }
    return amplitude;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final activeBar = (progress * _barCount).floor();
    return Semantics(
      key: const ValueKey('playback-waveform'),
      label: isPlaying ? 'Playing waveform' : 'Recording waveform',
      child: SizedBox(
        width: double.infinity,
        height: 124,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var index = 0; index < _barCount; index++)
              AnimatedContainer(
                key: ValueKey('playback-waveform-bar-$index'),
                width: 4,
                height: 5 + _amplitudeForBar(index) * 78,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(
                    alpha: isPlaying && index <= activeBar ? 0.98 : 0.42,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
