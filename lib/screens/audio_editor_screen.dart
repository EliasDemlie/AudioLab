import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/recorder_controller.dart';
import '../models/recording.dart';
import '../models/recording_waveform.dart';
import '../utils/formatters.dart';
import '../widgets/audio_crop_waveform.dart';

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
  RangeValues _selection = const RangeValues(0, 1);
  Duration _position = Duration.zero;
  final ValueNotifier<double> _positionProgress = ValueNotifier(0);
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
  Duration get _start => _at(_selection.start);
  Duration get _end => _at(_selection.end);
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
    _positionProgress.dispose();
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
        _selection = const RangeValues(0, 1);
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
    if (!_ready || _busy || _saving) return;
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
    if (!_ready || _busy || _saving) return;
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
    if (!_ready || _busy || _saving) return;
    final start = selection.start.clamp(0.0, 1.0 - _minimumSelection);
    final end = selection.end.clamp(start + _minimumSelection, 1.0);
    final wasPlaying = _playing;
    _revision++;
    _cancelTicker();
    setState(() {
      _selection = RangeValues(start, end);
      _setPosition(_bounded(_position));
      _playing = false;
      _busy = wasPlaying;
    });
    if (!wasPlaying) return;
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
    if (!_ready || _busy || _saving) return;
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

  String _time(Duration duration, {bool precise = false}) {
    final formatted = formatDuration(duration);
    final time = duration.inHours > 0 ? formatted : formatted.substring(3);
    return precise
        ? '$time.${duration.inMilliseconds.remainder(1000) ~/ 100}'
        : time;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = _ready && !_busy && !_saving;
    return PopScope(
      canPop: !_saving && !_busy,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back to player',
            onPressed: _saving || _busy
                ? null
                : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('Edit audio'),
          centerTitle: true,
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: enabled ? _save : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      icon: _saving
                          ? SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onPrimary,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(_saving ? 'Saving copy…' : 'Save copy'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your original recording stays unchanged.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 18),
                    Text(
                      widget.recording.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        letterSpacing: -0.5,
                      ),
                    ),
                    _loading
                        ? const SizedBox(
                            height: 220,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(strokeWidth: 2),
                                  SizedBox(height: 16),
                                  Text('Loading waveform…'),
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
                        : Column(
                            children: [
                              const SizedBox(height: 12),
                              AudioCropWaveform(
                                peaks: _waveform!.peaks,
                                selection: _selection,
                                position: _positionProgress.value,
                                positionListenable: _positionProgress,
                                minimumSelection: _minimumSelection,
                                enabled: enabled,
                                onSelectionChanged: _changeSelection,
                                onSeek: (fraction) => _seek(_at(fraction)),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) => Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _time(Duration.zero),
                                          style: theme.textTheme.labelSmall,
                                        ),
                                      ),
                                      if (constraints.maxWidth >= 320 &&
                                          MediaQuery.textScalerOf(context)
                                                  .scale(12) <=
                                              16)
                                        Expanded(
                                          child: Text(
                                            _time(_at(0.5)),
                                            textAlign: TextAlign.center,
                                            style: theme.textTheme.labelSmall,
                                          ),
                                        ),
                                      Expanded(
                                        child: Text(
                                          _time(_duration),
                                          textAlign: TextAlign.end,
                                          style: theme.textTheme.labelSmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _BoundaryTime(
                            label: 'START',
                            value: _time(_start, precise: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _BoundaryTime(
                            label: 'END',
                            value: _time(_end, precise: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Selected ${_time(_end - _start, precise: true)}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: enabled
                              ? () => _changeSelection(const RangeValues(0, 1))
                              : null,
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: const Text('Reset selection'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Back 5 seconds',
                          onPressed: enabled
                              ? () => _seek(
                                  _position - const Duration(seconds: 5),
                                )
                              : null,
                          icon: const Icon(Icons.replay_5_rounded, size: 28),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(52, 52),
                            shape: const CircleBorder(),
                          ),
                        ),
                        const SizedBox(width: 24),
                        SizedBox.square(
                          dimension: 80,
                          child: IconButton.filled(
                            tooltip: _playing ? 'Pause' : 'Play selection',
                            onPressed: enabled ? _togglePlayback : null,
                            style: IconButton.styleFrom(
                              shape: const CircleBorder(),
                            ),
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 42,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        IconButton.filledTonal(
                          tooltip: 'Forward 5 seconds',
                          onPressed: enabled
                              ? () => _seek(
                                  _position + const Duration(seconds: 5),
                                )
                              : null,
                          icon: const Icon(Icons.forward_5_rounded, size: 28),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(52, 52),
                            shape: const CircleBorder(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ValueListenableBuilder<double>(
                      valueListenable: _positionProgress,
                      builder: (context, progress, _) => Text(
                        '${_time(Duration(milliseconds: (_duration.inMilliseconds * progress).round()), precise: true)} / ${_time(_duration)}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Preview selected section',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoundaryTime extends StatelessWidget {
  const _BoundaryTime({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
