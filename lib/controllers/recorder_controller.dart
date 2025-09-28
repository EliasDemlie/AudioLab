import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/recorder_state.dart';
import '../models/recording.dart';
import '../models/recording_waveform.dart';
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
  Timer? _transitionTimer;
  Completer<void>? _stopCompleter;
  Future<Recording?>? _stopFuture;
  bool _disposed = false;
  bool _isReadingLevel = false;
  bool _recorderTabVisible = true;
  RecorderStatus? _pendingStatus;
  final ValueNotifier<double> audioLevel = ValueNotifier(0);
  final ValueNotifier<List<Recording>> recordingsListenable =
      ValueNotifier<List<Recording>>(const []);
  final ValueNotifier<List<Recording>> draftRecordingsListenable =
      ValueNotifier<List<Recording>>(const []);
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

  /// True while a request or native state transition is still in flight.
  bool get isBusy => _isBusy || _pendingStatus != null;
  bool get isStopPending => _pendingStatus == RecorderStatus.stopping;

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
    await refreshDrafts();
  }

  Future<void> start() async {
    if (isBusy || status != RecorderStatus.idle || _disposed) return;
    _bookmarks.clear();
    await _runTransition(RecorderStatus.recording, _service.start);
  }

  Future<void> pause() async {
    if (isBusy || status != RecorderStatus.recording || _disposed) return;
    await _runTransition(RecorderStatus.paused, _service.pause);
  }

  Future<void> resume() async {
    if (isBusy || status != RecorderStatus.paused || _disposed) return;
    await _runTransition(RecorderStatus.recording, _service.resume);
  }

  Future<Recording?> stopAndWait() {
    final activeStop = _stopFuture;
    if (activeStop != null) return activeStop;

    late final Future<Recording?> operation;
    operation = _stopAndWait().whenComplete(() {
      if (identical(_stopFuture, operation)) _stopFuture = null;
    });
    _stopFuture = operation;
    return operation;
  }

  Future<Recording?> _stopAndWait() async {
    if (!isActive || _disposed || _isBusy) return null;
    if (_pendingStatus != null && _pendingStatus != RecorderStatus.stopping) {
      return null;
    }

    final activePath = _state.filePath;
    final completion = _stopCompleter ?? Completer<void>();
    _stopCompleter = completion;

    if (status != RecorderStatus.stopping) {
      _setPendingStatus(RecorderStatus.stopping);
      final stopSent = await _run(_service.stop);
      if (!stopSent) {
        _clearPendingStatus();
        if (identical(_stopCompleter, completion)) _stopCompleter = null;
        return null;
      }
    }

    if (!_state.isActive && !completion.isCompleted) completion.complete();
    try {
      await completion.future.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      _errors.add('Recording is taking longer than expected to finish.');
      return null;
    } finally {
      if (identical(_stopCompleter, completion)) _stopCompleter = null;
    }

    await refreshDrafts();
    final drafts = draftRecordingsListenable.value;
    if (drafts.isEmpty) return null;
    if (activePath == null) return drafts.first;
    final activeBase = _baseName(activePath);
    for (final recording in drafts) {
      if (_baseName(recording.file.path) == activeBase) return recording;
    }
    return null;
  }

  Future<Recording> rename(Recording recording, String title) async {
    final renamed = await _service.rename(recording, title);
    await refreshRecordings();
    return renamed;
  }

  Future<Recording> saveDraft(Recording recording, String title) async {
    final saved = await _service.saveRecording(recording, title);
    _removeDraft(recording);
    if (!_disposed) {
      _recordings = [
        saved,
        ..._recordings.where((item) => item.id != saved.id),
      ];
      recordingsListenable.value = _recordings;
    }
    await refreshRecordings();
    await refreshDrafts();
    return saved;
  }

  Future<void> discardDraft(Recording recording) async {
    await _service.discardDraftRecording(recording);
    _removeDraft(recording);
    await refreshDrafts();
  }

  void _removeDraft(Recording recording) {
    if (_disposed) return;
    draftRecordingsListenable.value = draftRecordingsListenable.value
        .where((draft) => draft.file.path != recording.file.path)
        .toList(growable: false);
  }

  Future<void> refreshDrafts() async {
    try {
      final drafts = await _service.loadDraftRecordings();
      if (!_disposed) draftRecordingsListenable.value = drafts;
    } on PlatformException catch (e) {
      if (!_disposed) {
        _errors.add(e.message ?? 'Could not load unsaved recordings');
      }
    }
  }

  Future<Recording> trimAudio(
    Recording recording, {
    required Duration start,
    required Duration end,
  }) async {
    final path = await _service.trimAudio(recording, start: start, end: end);
    await refreshRecordings();
    for (final edited in _recordings) {
      if (edited.file.path == path) return edited;
    }
    final file = File(path);
    return Recording(
      file: file,
      createdAt: DateTime.now(),
      sizeBytes: await file.length(),
      duration: end - start,
    );
  }

  Future<void> play(Recording recording) => _service.play(recording);

  Future<void> pausePlayback() => _service.pausePlayback();

  Future<void> resumePlayback() => _service.resumePlayback();

  Future<void> stopPlayback() => _service.stopPlayback();

  Future<void> seekPlayback(Duration position) =>
      _service.seekPlayback(position);

  Future<PlaybackState> getPlaybackState() => _service.getPlaybackState();

  Future<RecordingWaveform> loadWaveform(Recording recording) =>
      _service.loadWaveform(recording);

  Future<void> setPlaybackEqualizer(List<double> gains) =>
      _service.setPlaybackEqualizer(gains);

  /// Pauses recorder-screen timers while that tab is offscreen.
  void setRecorderTabVisible(bool visible) {
    if (_recorderTabVisible == visible || _disposed) return;
    _recorderTabVisible = visible;
    if (status == RecorderStatus.recording && visible) {
      _ticker ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
      _startLevelTicker();
    } else {
      _ticker?.cancel();
      _ticker = null;
      _levelTicker?.cancel();
      _levelTicker = null;
      if (!visible) audioLevel.value = 0;
    }
    if (visible) notifyListeners();
  }

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
      recordingsListenable.value = recordings;
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
      if (_recorderTabVisible) {
        _ticker ??= Timer.periodic(
          const Duration(seconds: 1),
          (_) => notifyListeners(),
        );
        _startLevelTicker();
      }
    } else {
      _ticker?.cancel();
      _ticker = null;
      _levelTicker?.cancel();
      _levelTicker = null;
      audioLevel.value = 0;
    }
    // A recording just finished (from the app or the notification).
    if (_pendingStatus == state.status || !state.isActive) {
      _clearPendingStatus(notify: false);
    }

    if (wasActive && !state.isActive) {
      final completion = _stopCompleter;
      if (completion != null && !completion.isCompleted) completion.complete();
      if (completion == null) unawaited(refreshDrafts());
    }
    notifyListeners();
  }

  void _startLevelTicker() {
    _levelTicker ??= Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => _readAudioLevel(),
    );
  }

  String _baseName(String path) =>
      File(path).uri.pathSegments.last.replaceFirst(RegExp(r'\.[^.]+$'), '');

  Future<void> _readAudioLevel() async {
    if (_isReadingLevel) return;
    _isReadingLevel = true;
    try {
      final peak = await _service.readPeakAmplitude();
      if (_disposed ||
          !_recorderTabVisible ||
          status != RecorderStatus.recording) {
        return;
      }
      audioLevel.value = (peak / 32767).clamp(0.0, 1.0);
    } on PlatformException {
      // Meter failures must never interrupt the recording itself.
    } catch (_) {
      // Ignore transient meter failures; the recording remains active.
    } finally {
      _isReadingLevel = false;
    }
  }

  Future<void> _runTransition(
    RecorderStatus expectedStatus,
    Future<void> Function() action,
  ) async {
    _setPendingStatus(expectedStatus);
    final succeeded = await _run(action);
    if (!succeeded) _clearPendingStatus();
  }

  void _setPendingStatus(RecorderStatus expectedStatus) {
    _transitionTimer?.cancel();
    _pendingStatus = expectedStatus;
    _transitionTimer = Timer(const Duration(seconds: 5), _clearPendingStatus);
    notifyListeners();
  }

  void _clearPendingStatus({bool notify = true}) {
    _transitionTimer?.cancel();
    _transitionTimer = null;
    if (_pendingStatus == null) return;
    _pendingStatus = null;
    if (notify && !_disposed) notifyListeners();
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_isBusy || _disposed) return false;
    _isBusy = true;
    notifyListeners();
    try {
      await action();
      return true;
    } on PlatformException catch (e) {
      _errors.add(e.message ?? 'Something went wrong');
      return false;
    } catch (e) {
      _errors.add('Could not complete the recording action: $e');
      return false;
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
    _transitionTimer?.cancel();
    audioLevel.dispose();
    recordingsListenable.dispose();
    draftRecordingsListenable.dispose();
    _errors.close();
    super.dispose();
  }
}
