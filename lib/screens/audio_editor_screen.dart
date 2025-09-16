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
import '../widgets/circular_eq_dial.dart';

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
  bool _showEffects = false;
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
          leading: IconButton(
            tooltip: 'Back to player',
            onPressed: _saving || _busy
                ? null
                : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('Edit audio'),
          centerTitle: true,
          actions: [
            TextButton(
              onPressed: canSave ? _save : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 40),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(_saving ? 'Saving…' : 'Save copy'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    _loading
                        ? const SizedBox(
                            height: 132,
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
                              ValueListenableBuilder<RangeValues>(
                                valueListenable: _selection,
                                builder: (context, selection, _) =>
                                    AudioCropWaveform(
                                      peaks: _waveform!.peaks,
                                      selection: selection,
                                      position: _positionProgress.value,
                                      positionListenable: _positionProgress,
                                      minimumSelection: _minimumSelection,
                                      enabled: _ready && !_saving,
                                      onSelectionChanged: _changeSelection,
                                      onSeek: (fraction) =>
                                          _seek(_at(fraction)),
                                    ),
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
                    const SizedBox(height: 14),
                    Text(
                      widget.recording.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ValueListenableBuilder<RangeValues>(
                      valueListenable: _selection,
                      builder: (context, selection, _) => Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _BoundaryTime(
                                  label: 'START',
                                  value: _time(
                                    _at(selection.start),
                                    precise: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _BoundaryTime(
                                  label: 'END',
                                  value: _time(
                                    _at(selection.end),
                                    precise: true,
                                  ),
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
                                'Selected ${_time(_at(selection.end - selection.start), precise: true)}',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colors.primary,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: enabled
                                    ? () => _changeSelection(
                                        const RangeValues(0, 1),
                                      )
                                    : null,
                                icon: const Icon(
                                  Icons.restart_alt_rounded,
                                  size: 18,
                                ),
                                label: const Text('Reset selection'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          tooltip: 'Back 5 seconds',
                          onPressed: canPreview
                              ? () => _seek(
                                  _position - const Duration(seconds: 5),
                                )
                              : null,
                          icon: const Icon(Icons.replay_5_rounded, size: 21),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(40, 40),
                            padding: EdgeInsets.zero,
                            shape: const CircleBorder(),
                          ),
                        ),
                        const SizedBox(width: 14),
                        SizedBox.square(
                          dimension: 62,
                          child: IconButton.filled(
                            tooltip: _playing ? 'Pause' : 'Play selection',
                            onPressed: canPreview ? _togglePlayback : null,
                            style: IconButton.styleFrom(
                              shape: const CircleBorder(),
                            ),
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 34,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        IconButton.filledTonal(
                          tooltip: 'Forward 5 seconds',
                          onPressed: canPreview
                              ? () => _seek(
                                  _position + const Duration(seconds: 5),
                                )
                              : null,
                          icon: const Icon(Icons.forward_5_rounded, size: 21),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(40, 40),
                            padding: EdgeInsets.zero,
                            shape: const CircleBorder(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.center,
                      child: Tooltip(
                        message: _showEffects ? 'Hide effects' : 'Show effects',
                        child: TextButton.icon(
                          onPressed: _saving
                              ? null
                              : () => setState(
                                  () => _showEffects = !_showEffects,
                                ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                          ),
                          icon: const Icon(Icons.tune_rounded, size: 17),
                          label: const Text('Effects'),
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOutCubic,
                      alignment: Alignment.topCenter,
                      child: _showEffects
                          ? _InlineEffectsPanel(
                              gains: _equalizerGains,
                              busy: _effectsBusy,
                              onChanged: _applyEqualizer,
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 6),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _InlineEffectsPanel extends StatelessWidget {
  const _InlineEffectsPanel({
    required this.gains,
    required this.busy,
    required this.onChanged,
  });

  final ValueListenable<List<double>> gains;
  final ValueListenable<bool> busy;
  final ValueChanged<List<double>> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Column(
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
        const SizedBox(height: 12),
        ValueListenableBuilder<List<double>>(
          valueListenable: gains,
          builder: (context, values, _) => Row(
            children: [
              Expanded(
                child: CircularEqDial(
                  label: 'Bass',
                  value: values[0],
                  onChanged: (value) =>
                      onChanged([value, values[1], values[2]]),
                ),
              ),
              Expanded(
                child: CircularEqDial(
                  label: 'Presence',
                  value: values[1],
                  onChanged: (value) =>
                      onChanged([values[0], value, values[2]]),
                ),
              ),
              Expanded(
                child: CircularEqDial(
                  label: 'Treble',
                  value: values[2],
                  onChanged: (value) =>
                      onChanged([values[0], values[1], value]),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
