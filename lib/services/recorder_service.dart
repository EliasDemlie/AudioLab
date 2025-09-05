import 'package:flutter/services.dart';

import '../models/recorder_state.dart';
import '../models/recording.dart';

/// Talks to the native `RecordingService` (Android) over platform channels.
class RecorderService {
  static const _methods = MethodChannel('com.example.voicerec/recorder');
  static const _events = EventChannel('com.example.voicerec/recorder_state');

  /// Emits the current state right away, then every change.
  ///
  /// Recording keeps going natively even when this stream has no listeners.
  Stream<RecorderState> get states => _events.receiveBroadcastStream().map(
    (event) => RecorderState.fromMap(event as Map),
  );

  Future<RecorderState> getState() async {
    final map = await _methods.invokeMapMethod<String, dynamic>(
      'getRecordingState',
    );
    return map == null
        ? const RecorderState.idle()
        : RecorderState.fromMap(map);
  }

  /// Asks for microphone permission if needed, then starts recording.
  ///
  /// Throws a [PlatformException] if permission is denied.
  Future<void> start() => _methods.invokeMethod<void>('startRecording');

  Future<void> pause() => _methods.invokeMethod<void>('pauseRecording');

  Future<void> resume() => _methods.invokeMethod<void>('resumeRecording');

  Future<void> stop() => _methods.invokeMethod<void>('stopRecording');

  /// Saved recordings, newest first. Also recovers recordings that were
  /// interrupted (e.g. the app was killed while recording).
  Future<List<Recording>> loadRecordings() async {
    final list = await _methods.invokeListMethod<Map>('listRecordings');
    return [...?list?.map(Recording.fromMap)];
  }

  Future<void> delete(Recording recording) => recording.file.delete();

}
