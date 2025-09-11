import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/recorder_state.dart';
import '../models/recording.dart';
import '../services/recorder_service.dart';

/// Holds the recorder UI state and turns user actions into service calls.
///
/// The native service is the source of truth; this only mirrors it.
class RecorderController extends ChangeNotifier {
  RecorderController({RecorderService? service})
    : _service = service ?? RecorderService();

  final RecorderService _service;
  final _errors = StreamController<String>.broadcast();

  StreamSubscription<RecorderState>? _stateSub;
  Timer? _ticker;
  Timer? _levelTicker;
  Completer<void>? _stopCompleter;
  bool _disposed = false;
  final ValueNotifier<double> audioLevel = ValueNotifier(0);
  final List<Duration> _bookmarks = [];

  RecorderState _state = const RecorderState.idle();
  List<Recording> _recordings = const [];
  bool _isBusy = false;

  RecorderStatus get status => _state.status;
  bool get isActive => _state.isActive;
  bool get micSilenced => _state.micSilenced;
  Duration get elapsed => _state.elapsedAt(DateTime.now());
  List<Recording> get recordings => _recordings;
  List<Duration> get bookmarks => List.unmodifiable(_bookmarks);

  /// True while a request is in flight (e.g. permission dialog open).
  bool get isBusy => _isBusy;

  /// Error messages to show to the user.
  Stream<String> get errors => _errors.stream;

  /// Restores a recording that kept running while the UI was closed, then
  /// follows live updates.
  Future<void> init() async {
    try {
      _onState(await _service.getState());
    } on PlatformException catch (e) {
      _errors.add(e.message ?? 'Could not read recorder state');
    }
    _stateSub = _service.states.listen(
      _onState,
      onError: (Object e) => _errors.add('Recorder error: $e'),
    );
    await refreshRecordings();
  }

  Future<void> start() async {
    _bookmarks.clear();
    await _run(_service.start);
  }

  Future<void> pause() => _run(_service.pause);

  Future<void> resume() => _run(_service.resume);

  Future<Recording?> stopAndWait() async {
    if (!isActive) return null;
    final activePath = _state.filePath;
    final completion = Completer<void>();
    _stopCompleter = completion;
    await _run(_service.stop);

    if (!_state.isActive && !completion.isCompleted) completion.complete();
    try {
      await completion.future.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      _errors.add('Recording is taking longer than expected to save.');
      return null;
    } finally {
      if (identical(_stopCompleter, completion)) _stopCompleter = null;
    }

    await refreshRecordings();
    if (_recordings.isEmpty) return null;
    if (activePath == null) return _recordings.first;
    final activeBase = _baseName(activePath);
    for (final recording in _recordings) {
      if (_baseName(recording.file.path) == activeBase) return recording;
    }
    return null;
  }

  Future<Recording> rename(Recording recording, String title) async {
    final renamed = await _service.rename(recording, title);
    await refreshRecordings();
    return renamed;
  }

  Future<void> play(Recording recording) => _service.play(recording);

  Future<void> pausePlayback() => _service.pausePlayback();

  Future<void> resumePlayback() => _service.resumePlayback();

  Future<void> stopPlayback() => _service.stopPlayback();

  Future<void> seekPlayback(Duration position) =>
      _service.seekPlayback(position);

  Future<PlaybackState> getPlaybackState() => _service.getPlaybackState();

  void addBookmark() {
    if (status != RecorderStatus.recording && status != RecorderStatus.paused) {
      return;
    }
    _bookmarks.add(elapsed);
    notifyListeners();
  }

  Future<void> refreshRecordings() async {
    try {
      final recordings = await _service.loadRecordings();
      if (_disposed) return;
      _recordings = recordings;
      notifyListeners();
    } on PlatformException catch (e) {
      _errors.add(e.message ?? 'Could not load recordings');
    }
  }

  Future<void> delete(Recording recording) async {
    await _service.delete(recording);
    await refreshRecordings();
  }

  Future<void> share(Recording recording) async {
    try {
      await _service.share(recording);
    } on PlatformException catch (e) {
      _errors.add(e.message ?? 'Could not share recording');
    }
  }

  void _onState(RecorderState state) {
    if (_disposed) return;
    final wasActive = _state.isActive;
    _state = state;

    if (state.error != null) _errors.add(state.error!);

    // Tick only while the clock is actually running; paused shows a fixed time.
    if (state.status == RecorderStatus.recording) {
      _ticker ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
      _levelTicker ??= Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => _readAudioLevel(),
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
      _levelTicker?.cancel();
      _levelTicker = null;
      audioLevel.value = 0;
    }
    notifyListeners();

    // A recording just finished (from the app or the notification).
    if (wasActive && !state.isActive) {
      final completion = _stopCompleter;
      if (completion != null && !completion.isCompleted) completion.complete();
      refreshRecordings();
    }
  }

  String _baseName(String path) =>
      File(path).uri.pathSegments.last.replaceFirst(RegExp(r'\.[^.]+$'), '');

  Future<void> _readAudioLevel() async {
    try {
      final peak = await _service.readPeakAmplitude();
      if (_disposed || status != RecorderStatus.recording) return;
      audioLevel.value = (peak / 32767).clamp(0.0, 1.0);
    } on PlatformException {
      // Meter failures must never interrupt the recording itself.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_isBusy) return;
    _isBusy = true;
    notifyListeners();
    try {
      await action();
    } on PlatformException catch (e) {
      _errors.add(e.message ?? 'Something went wrong');
    } finally {
      _isBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    // Only the UI goes away here; the native service keeps recording.
    _disposed = true;
    _stateSub?.cancel();
    _ticker?.cancel();
    _levelTicker?.cancel();
    audioLevel.dispose();
    _errors.close();
    super.dispose();
  }
}
