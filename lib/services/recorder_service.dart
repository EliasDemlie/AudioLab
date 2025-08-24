import 'dart:io';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

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

  Future<Recording> rename(Recording recording, String title) async {
    final cleanedTitle = title
        .trim()
        .replaceAll(RegExp(r'[/\\\u0000-\u001F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    final safeTitle = String.fromCharCodes(cleanedTitle.runes.take(80));
    if (safeTitle.isEmpty) {
      throw PlatformException(
        code: 'INVALID_TITLE',
        message: 'Enter a name for this recording.',
      );
    }

    final extension = recording.file.uri.pathSegments.last.split('.').last;
    var target = File('${recording.file.parent.path}/$safeTitle.$extension');
    var suffix = 1;
    while (await target.exists() && target.path != recording.file.path) {
      target = File(
        '${recording.file.parent.path}/$safeTitle (${suffix++}).$extension',
      );
    }
    final oldPath = recording.file.path;
    final renamed = await recording.file.rename(target.path);
    try {
      await _methods.invokeMethod<void>('updateRecordingPath', {
        'oldPath': oldPath,
        'newPath': renamed.path,
        'title': safeTitle,
      });
    } catch (_) {
      await renamed.rename(oldPath);
      rethrow;
    }
    return recording.copyWith(
      file: renamed,
      title: safeTitle,
      updatedAt: DateTime.now(),
    );
  }

  /// Peak microphone amplitude since the previous read, normalized by the
  /// Android recorder to its 16-bit PCM range (0–32767).
  Future<int> readPeakAmplitude() async =>
      await _methods.invokeMethod<int>('readPeakAmplitude') ?? 0;

  Future<void> play(Recording recording) => _methods.invokeMethod<void>(
    'playRecording',
    {'path': recording.file.path},
  );

  Future<void> pausePlayback() => _methods.invokeMethod<void>('pausePlayback');

  Future<void> resumePlayback() =>
      _methods.invokeMethod<void>('resumePlayback');

  Future<void> stopPlayback() => _methods.invokeMethod<void>('stopPlayback');

  Future<void> seekPlayback(Duration position) => _methods.invokeMethod<void>(
    'seekPlayback',
    {'positionMillis': position.inMilliseconds},
  );

  Future<PlaybackState> getPlaybackState() async => PlaybackState.fromMap(
    await _methods.invokeMapMethod<String, dynamic>('getPlaybackState'),
  );

  /// Saved recordings, newest first. Also recovers recordings that were
  /// interrupted (e.g. the app was killed while recording).
  Future<List<Recording>> loadRecordings() async {
    final list = await _methods.invokeListMethod<Map>('listRecordings');
    return [...?list?.map(Recording.fromMap)];
  }

  /// Full catalog, including unavailable and recently deleted audio entries.
  Future<List<Recording>> loadLibraryRecordings() async {
    final list = await _methods.invokeListMethod<Map>('listLibraryRecordings');
    return [...?list?.map(Recording.fromMap)];
  }

  /// Deletes the file natively, which also cancels its pending backup.
  Future<void> delete(Recording recording) => _methods.invokeMethod<void>(
    'deleteRecording',
    {'path': recording.file.path},
  );

  /// Opens the Android share sheet for [recording].
  Future<void> share(Recording recording) => SharePlus.instance.share(
    ShareParams(
      files: [
        XFile(recording.file.path, mimeType: _mimeType(recording.file.path)),
      ],
      subject: recording.name,
    ),
  );

  /// `.m4a` is the normal format; `.aac` is kept only if conversion failed;
  /// `.vcf` is an exported contacts backup.
  static String _mimeType(String path) {
    if (path.endsWith('.vcf')) return 'text/vcard';
    if (path.endsWith('.aac')) return 'audio/aac';
    return 'audio/mp4';
  }
}
