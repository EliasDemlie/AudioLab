import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/recorder_controller.dart';
import '../models/recording.dart';
import '../models/recording_waveform.dart';
import '../utils/formatters.dart';
import '../widgets/audio_crop_waveform.dart';
import '../widgets/audio_equalizer_panel.dart';
import '../widgets/audio_playback_layout.dart';
import '../widgets/audio_transport_controls.dart';

class AudioEditorScreen extends StatefulWidget {
  const AudioEditorScreen({
    super.key,
    required this.recording,
    required this.controller,
    this.duration,
  });

  final Recording recording;
  final RecorderController controller;
  final Duration? duration;

  @override
  State<AudioEditorScreen> createState() => _AudioEditorScreenState();
}

class _AudioEditorScreenState extends State<AudioEditorScreen> {
  RecordingWaveform? _waveform;
  final ValueNotifier<RangeValues> _selection = ValueNotifier(
    const RangeValues(0, 1),
  );
  Duration _position = Duration.zero;
  final ValueNotifier<double> _positionProgress = ValueNotifier(0);
  final ValueNotifier<List<double>> _equalizerGains = ValueNotifier(const [
    0.0,
    0.0,
    0.0,
  ]);
  final ValueNotifier<bool> _effectsBusy = ValueNotifier(false);
  Timer? _ticker;
  String? _loadError;
  bool _loading = true;
  bool _busy = false;
  bool _saving = false;
  bool _playing = false;
  bool _prepared = false;
  bool _reading = false;
  int _revision = 0;

  Duration get _duration =>
      _waveform?.duration ??
      widget.duration ??
      widget.recording.duration ??
      Duration.zero;
  bool get _ready =>
      !_loading && _waveform != null && _duration > Duration.zero;
  int get _minimumMillis => _duration.inMilliseconds.clamp(0, 1000);
  double get _minimumSelection => _duration.inMilliseconds > 0
      ? _minimumMillis / _duration.inMilliseconds
      : 1;
  Duration _at(double fraction) =>
      Duration(milliseconds: (_duration.inMilliseconds * fraction).round());
  Duration get _start => _at(_selection.value.start);
  Duration get _end => _at(_selection.value.end);
  Duration _bounded(Duration position) => Duration(
    milliseconds: position.inMilliseconds.clamp(
      _start.inMilliseconds,
      _end.inMilliseconds,
    ),
  );

  void _setPosition(Duration position) {
    _position = position;
    final durationMillis = _duration.inMilliseconds;
    _positionProgress.value = durationMillis > 0
        ? (position.inMilliseconds / durationMillis).clamp(0.0, 1.0)
        : 0;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadWaveform());
  }

  @override
  void dispose() {
    _revision++;
    _ticker?.cancel();
    _selection.dispose();
    _positionProgress.dispose();
    _equalizerGains.dispose();
    _effectsBusy.dispose();
    unawaited(widget.controller.stopPlayback());
    super.dispose();
  }

  Future<void> _loadWaveform() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final waveform = await widget.controller.loadWaveform(widget.recording);
      if (!mounted) return;
      if (waveform.duration <= Duration.zero || waveform.peaks.isEmpty) {
        throw const FormatException('Audio waveform is unavailable.');
      }
      setState(() {
        _waveform = waveform;
        _selection.value = const RangeValues(0, 1);
        _setPosition(Duration.zero);
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _loadError = _errorMessage(
            error,
            'Could not load this recording. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _cancelTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _startTicker() {
    _cancelTicker();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_busy && !_reading) unawaited(_readPlayback());
    });
  }

  Future<void> _releasePreview() async {
    _cancelTicker();
    try {
      await widget.controller.stopPlayback();
    } catch (error) {
      debugPrint('Could not stop audio preview: $error');
    } finally {
      _prepared = false;
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _togglePlayback() async {
    if (_duration <= Duration.zero || _busy || _saving) return;
    setState(() => _busy = true);
    _revision++;
    try {
      if (_playing) {
        await widget.controller.pausePlayback();
        _cancelTicker();
        if (mounted) setState(() => _playing = false);
      } else {
        final target = _position < _start || _position >= _end
            ? _start
            : _position;
        if (!_prepared) {
          await widget.controller.play(widget.recording);
          if (!mounted) return;
          _prepared = true;
          if (target > Duration.zero) {
            await widget.controller.seekPlayback(target);
          }
        } else {
          await widget.controller.seekPlayback(target);
          await widget.controller.resumePlayback();
        }
        if (!mounted) return;
        setState(() {
          _setPosition(target);
          _playing = true;
        });
        _startTicker();
      }
    } catch (error) {
      await _releasePreview();
      _showError(error, 'Could not preview this recording.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readPlayback() async {
    _reading = true;
    final revision = _revision;
    try {
      final state = await widget.controller.getPlaybackState();
      if (!mounted || revision != _revision) return;
      if (state.position >= _end || !state.isPlaying) {
        _cancelTicker();
        setState(() => _busy = true);
        if (state.isPlaying) await widget.controller.pausePlayback();
        if (!mounted || revision != _revision) return;
        setState(() {
          // Native playback can return to zero when the original file ends.
          _setPosition(_end);
          _playing = false;
        });
      } else {
        _setPosition(_bounded(state.position));
      }
    } catch (error) {
      _cancelTicker();
      if (mounted && revision == _revision) {
        setState(() => _busy = true);
        // Stop playback if its position cannot be monitored at the crop edge.
        await _releasePreview();
        _showError(error, 'Could not read the playback position.');
      }
    } finally {
      _reading = false;
      if (mounted && revision == _revision && _busy) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _seek(Duration position) async {
    if (_duration <= Duration.zero || _busy || _saving) return;
    final target = _bounded(position);
    _revision++;
    setState(() => _setPosition(target));
    if (!_prepared) return;
    setState(() => _busy = true);
    try {
      await widget.controller.seekPlayback(target);
      if (target >= _end && _playing) {
        await widget.controller.pausePlayback();
        _cancelTicker();
        if (mounted) setState(() => _playing = false);
      }
    } catch (error) {
      await _releasePreview();
      _showError(error, 'Could not seek in this recording.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeSelection(RangeValues selection) async {
    if (!_ready || _saving) return;
    final start = selection.start.clamp(0.0, 1.0 - _minimumSelection);
    final end = selection.end.clamp(start + _minimumSelection, 1.0);
    final wasPlaying = _playing;
    _revision++;
    _cancelTicker();
    _selection.value = RangeValues(start, end);
    _setPosition(_bounded(_position));
    if (!wasPlaying) return;
    setState(() {
      _playing = false;
      _busy = true;
    });
    try {
      await widget.controller.pausePlayback();
    } catch (error) {
      await _releasePreview();
      _showError(error, 'Could not pause the preview.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_duration <= Duration.zero ||
        _busy ||
        _saving ||
        (!_loading && _waveform == null)) {
      return;
    }
    final start = _start;
    final end = _end;
    if ((end - start).inMilliseconds < _minimumMillis) return;
    _revision++;
    _cancelTicker();
    setState(() {
      _saving = true;
      _playing = false;
    });
    try {
      await widget.controller.stopPlayback();
      _prepared = false;
      if (!mounted) return;
      final recording = await widget.controller.trimAudio(
        widget.recording,
        start: start,
        end: end,
      );
      if (mounted) Navigator.of(context).pop(recording);
    } catch (error) {
      _showError(
        error,
        'Could not save the cropped recording. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyEqualizer(List<double> gains) async {
    final appliedGains = List<double>.unmodifiable(gains);
    _equalizerGains.value = appliedGains;
    _effectsBusy.value = true;
    try {
      await widget.controller.setPlaybackEqualizer(appliedGains);
    } on PlatformException catch (error) {
      _showError(error, 'Audio effects are unavailable.');
    } finally {
      if (mounted) _effectsBusy.value = false;
    }
  }

  String _errorMessage(Object error, String fallback) {
    if (error is PlatformException && error.message?.isNotEmpty == true) {
      return error.message!;
    }
    if (error is FileSystemException && error.message.isNotEmpty) {
      return error.message;
    }
    return fallback;
  }

  void _showError(Object error, String fallback) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_errorMessage(error, fallback))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = _ready && !_busy && !_saving;
    final canPreview = _duration > Duration.zero && !_busy && !_saving;
    final canSave =
        _duration > Duration.zero &&
        !_busy &&
        !_saving &&
        (_loading || _waveform != null);
    return PopScope(
      canPop: !_saving && !_busy,
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: 76,
          leading: Center(
            child: IconButton.filledTonal(
              tooltip: 'Back to player',
              onPressed: _saving || _busy
                  ? null
                  : () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 28),
              style: IconButton.styleFrom(
                backgroundColor: colors.onSurface.withValues(alpha: 0.06),
                foregroundColor: colors.onSurface,
                shape: const CircleBorder(),
                side: BorderSide(
                  color: colors.onSurface.withValues(alpha: 0.08),
                ),
              ),
            ),
          ),
          title: Text('Edit audio', style: theme.textTheme.titleMedium),
          centerTitle: true,
          actions: [
            TextButton(
              onPressed: canSave ? _save : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                backgroundColor: colors.primary.withValues(alpha: 0.1),
                shape: const StadiumBorder(),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(_saving ? 'Saving…' : 'Save copy'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: AudioPlaybackLayout(
          title: 'Trim selection',
          waveformBuilder: (height) => _loading
              ? SizedBox(
                  height: height,
                  child: const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Flexible(child: Text('Loading waveform…')),
                      ],
                    ),
                  ),
                )
              : _loadError != null
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Icon(
                        Icons.multitrack_audio_rounded,
                        size: 40,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(_loadError!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _loadWaveform,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ValueListenableBuilder<RangeValues>(
                  valueListenable: _selection,
                  builder: (context, selection, _) => AudioCropWaveform(
                    peaks: _waveform!.peaks,
                    selection: selection,
                    position: _positionProgress.value,
                    positionListenable: _positionProgress,
                    height: height,
                    minimumSelection: _minimumSelection,
                    enabled: _ready && !_saving,
                    onSelectionChanged: _changeSelection,
                    onSeek: (fraction) => _seek(_at(fraction)),
                  ),
                ),
          controls: Column(
            children: [
              ValueListenableBuilder<RangeValues>(
                valueListenable: _selection,
                builder: (context, selection, _) => _EditorPlaybackProgress(
                  position: _positionProgress,
                  duration: _duration,
                  selection: selection,
                  enabled: canPreview,
                  onSeek: _seek,
                ),
              ),
              SizedBox(height: AudioPlaybackLayout.controlSpacing(context)),
              AudioTransportControls(
                playing: _playing,
                busy: _busy,
                playTooltip: _playing ? 'Pause' : 'Play selection',
                onToggle: canPreview ? _togglePlayback : null,
                backTooltip: 'Back 5 seconds',
                forwardTooltip: 'Forward 5 seconds',
                backIcon: Icons.replay_5_rounded,
                forwardIcon: Icons.forward_5_rounded,
                onBack: canPreview
                    ? () => _seek(_position - const Duration(seconds: 5))
                    : null,
                onForward: canPreview
                    ? () => _seek(_position + const Duration(seconds: 5))
                    : null,
                leading: _PreviewSkipButton(
                  tooltip: 'Reset selection',
                  onPressed: enabled
                      ? () => _changeSelection(const RangeValues(0, 1))
                      : null,
                  icon: Icons.restart_alt_rounded,
                ),
                trailing: const SizedBox.shrink(),
              ),
            ],
          ),
          effects: AudioEqualizerPanel(
            gains: _equalizerGains,
            busy: _effectsBusy,
            onChanged: _applyEqualizer,
          ),
        ),
      ),
    );
  }
}

class _EditorPlaybackProgress extends StatefulWidget {
  const _EditorPlaybackProgress({
    required this.position,
    required this.duration,
    required this.selection,
    required this.enabled,
    required this.onSeek,
  });

  final ValueListenable<double> position;
  final Duration duration;
  final RangeValues selection;
  final bool enabled;
  final ValueChanged<Duration> onSeek;

  @override
  State<_EditorPlaybackProgress> createState() =>
      _EditorPlaybackProgressState();
}

class _EditorPlaybackProgressState extends State<_EditorPlaybackProgress> {
  double? _scrubProgress;

  @override
  void didUpdateWidget(covariant _EditorPlaybackProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled ||
        oldWidget.selection != widget.selection ||
        oldWidget.duration != widget.duration) {
      _scrubProgress = null;
    }
  }

  String _time(Duration duration) {
    final formatted = formatDuration(duration);
    final time = duration.inHours > 0 ? formatted : formatted.substring(3);
    return '$time.${duration.inMilliseconds.remainder(1000) ~/ 100}';
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: widget.position,
    builder: (context, position, _) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final start = (widget.duration.inMilliseconds * widget.selection.start)
          .round();
      final end = (widget.duration.inMilliseconds * widget.selection.end)
          .round();
      final length = end - start;
      final progress =
          _scrubProgress ??
          (length > 0
              ? ((position * widget.duration.inMilliseconds - start) / length)
                    .clamp(0.0, 1.0)
              : 0.0);
      Duration at(double value) =>
          Duration(milliseconds: start + (length * value).round());
      final canSeek = widget.enabled && length > 0;
      final timeStyle = theme.textTheme.labelMedium?.copyWith(
        color: colors.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      return Column(
        children: [
          Semantics(
            label: 'Selection playback position',
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                activeTrackColor: colors.primary,
                inactiveTrackColor: colors.onSurface.withValues(alpha: 0.1),
                disabledActiveTrackColor: colors.primary.withValues(alpha: 0.4),
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
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                key: const ValueKey('editor-playback-progress'),
                value: progress,
                padding: const EdgeInsets.symmetric(vertical: 16),
                semanticFormatterCallback: (value) =>
                    '${_time(at(value))} of ${_time(Duration(milliseconds: end))}',
                onChangeStart: canSeek
                    ? (value) => setState(() => _scrubProgress = value)
                    : null,
                onChanged: canSeek
                    ? (value) => setState(() => _scrubProgress = value)
                    : null,
                onChangeEnd: canSeek
                    ? (value) {
                        widget.onSeek(at(value));
                        setState(() => _scrubProgress = null);
                      }
                    : null,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _time(at(progress)),
                    key: const ValueKey('editor-playback-position'),
                    style: timeStyle?.copyWith(color: colors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    _time(Duration(milliseconds: end)),
                    key: const ValueKey('editor-playback-end'),
                    style: timeStyle,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class _PreviewSkipButton extends StatelessWidget {
  const _PreviewSkipButton({
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
