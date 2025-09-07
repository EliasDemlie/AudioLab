import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/recorder_state.dart';
import '../models/recording.dart';
import '../models/upload_status.dart';
import '../services/backup_service.dart';
import '../services/recorder_service.dart';

/// Holds the recorder UI state and turns user actions into service calls.
///
/// The native service is the source of truth; this only mirrors it.
class RecorderController extends ChangeNotifier {
  RecorderController({RecorderService? service, BackupService? backup})
    : _service = service ?? RecorderService(),
      _backup = backup ?? BackupService();

  final RecorderService _service;
  final BackupService _backup;
  final _errors = StreamController<String>.broadcast();

  StreamSubscription<RecorderState>? _stateSub;
  StreamSubscription<UploadStatus>? _uploadSub;
  Timer? _ticker;
  bool _disposed = false;

  RecorderState _state = const RecorderState.idle();
  List<Recording> _recordings = const [];
  bool _isBusy = false;
  bool _backupConfigured = false;

  /// Whether a Telegram bot token and channel were provided at build time.
  bool get backupConfigured => _backupConfigured;

  RecorderStatus get status => _state.status;
  bool get isActive => _state.isActive;
  bool get micSilenced => _state.micSilenced;
  Duration get elapsed => _state.elapsedAt(DateTime.now());
  List<Recording> get recordings => _recordings;

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
    _uploadSub = _backup.updates.listen(_onUpload);
    try {
      _backupConfigured = await _backup.isConfigured();
    } on PlatformException {
      _backupConfigured = false;
    }
    await refreshRecordings();
  }

  Future<void> start() => _run(_service.start);

  Future<void> pause() => _run(_service.pause);

  Future<void> resume() => _run(_service.resume);

  Future<void> stop() => _run(_service.stop);

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

  Future<void> retryUpload(Recording recording) async {
    try {
      await _backup.retry(recording);
    } on PlatformException catch (e) {
      _errors.add(e.message ?? 'Could not retry upload');
    }
  }

  /// Applies a live upload update to the matching recording.
  void _onUpload(UploadStatus upload) {
    if (_disposed) return;
    final index = _recordings.indexWhere((r) => r.file.path == upload.filePath);
    if (index < 0) return;
    _recordings = [..._recordings]
      ..[index] = _recordings[index].copyWith(upload: upload);
    notifyListeners();
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
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
    notifyListeners();

    // A recording just finished (from the app or the notification).
    if (wasActive && !state.isActive) refreshRecordings();
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
    _uploadSub?.cancel();
    _ticker?.cancel();
    _errors.close();
    super.dispose();
  }
}
