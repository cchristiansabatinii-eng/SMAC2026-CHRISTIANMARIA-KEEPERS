// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

abstract interface class VoiceCaptureAdapter {
  Stream<double> get amplitudes;
  bool get ownsPlaintext;
  Future<bool> hasPermission();
  Future<void> start();
  Future<VoiceRecording?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

final class VoiceRecording {
  const VoiceRecording({required this.path, required this.duration});
  final String path;
  final Duration duration;
}

final class VoiceCleanupFailure implements Exception {
  VoiceCleanupFailure(Iterable<Object> causes)
    : causes = List<Object>.unmodifiable(causes);
  final List<Object> causes;
}

abstract interface class VoiceRecorderClient {
  Stream<Amplitude> onAmplitudeChanged(Duration interval);
  Future<bool> hasPermission();
  Future<void> start(RecordConfig config, {required String path});
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

final class AudioRecorderClient implements VoiceRecorderClient {
  AudioRecorderClient(this.recorder);
  final AudioRecorder recorder;
  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      recorder.onAmplitudeChanged(interval);
  @override
  Future<bool> hasPermission() => recorder.hasPermission();
  @override
  Future<void> start(RecordConfig config, {required String path}) =>
      recorder.start(config, path: path);
  @override
  Future<String?> stop() => recorder.stop();
  @override
  Future<void> cancel() => recorder.cancel();
  @override
  Future<void> dispose() => recorder.dispose();
}

final class RecordVoiceCaptureAdapter implements VoiceCaptureAdapter {
  RecordVoiceCaptureAdapter({
    required VoiceRecorderClient recorder,
    Directory? temporaryDirectory,
    Future<Directory> Function()? temporaryDirectoryFactory,
    required String Function() recordingId,
    Stopwatch? stopwatch,
  }) : _recorder = recorder,
       _directory = temporaryDirectory,
       _directoryFactory = temporaryDirectoryFactory,
       _recordingId = recordingId,
       _stopwatch = stopwatch ?? Stopwatch();

  final VoiceRecorderClient _recorder;
  final Directory? _directory;
  final Future<Directory> Function()? _directoryFactory;
  final String Function() _recordingId;
  final Stopwatch _stopwatch;
  String? _path;
  Future<void> _operationTail = Future<void>.value();
  bool _disposeStarted = false;
  bool _recorderDisposed = false;

  @override
  Stream<double> get amplitudes => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((amplitude) => amplitude.current.clamp(-60.0, 0.0).toDouble());

  @override
  bool get ownsPlaintext => _path != null;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() => _serialize(_start);

  Future<void> _start() async {
    if (_disposeStarted) {
      throw StateError('Voice capture adapter is disposed');
    }
    if (_path != null) {
      throw StateError(
        'Voice capture adapter still owns plaintext from an earlier recording',
      );
    }
    if (!await hasPermission()) {
      throw const CapturePermissionException(
        CapturePermissionSource.microphone,
      );
    }
    final root = _directory ?? await _directoryFactory!();
    final directory = Directory(p.join(root.path, 'keepers-capture'));
    await directory.create(recursive: true);
    _path = p.join(directory.path, '${_recordingId()}.m4a');
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
      path: _path!,
    );
    _stopwatch
      ..reset()
      ..start();
  }

  @override
  Future<VoiceRecording?> stop() => _serialize(_stop);

  Future<VoiceRecording?> _stop() async {
    final path = await _recorder.stop();
    _stopwatch.stop();
    if (path != null && path == _path) _path = null;
    return path == null
        ? null
        : VoiceRecording(path: path, duration: _stopwatch.elapsed);
  }

  @override
  Future<void> cancel() => _serialize(_cancel);

  Future<void> _cancel() async {
    _stopwatch.stop();
    final failures = <Object>[];
    final path = _path;
    try {
      await _recorder.cancel();
    } on Object catch (error) {
      failures.add(error);
    }
    try {
      if (path != null) {
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.file) {
          await File(path).delete();
          if (await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.notFound) {
            throw FileSystemException(
              'Voice plaintext deletion could not be confirmed',
              path,
            );
          }
          _path = null;
        } else if (type == FileSystemEntityType.notFound) {
          _path = null;
        } else {
          throw FileSystemException(
            'Voice plaintext path is not a regular file',
            path,
          );
        }
      }
    } on Object catch (error) {
      failures.add(error);
    }
    if (failures.isNotEmpty) throw VoiceCleanupFailure(failures);
  }

  @override
  Future<void> dispose() => _serialize(_dispose);

  Future<void> _dispose() async {
    _disposeStarted = true;
    final failures = <Object>[];
    try {
      await _cancel();
    } on VoiceCleanupFailure catch (error) {
      failures.addAll(error.causes);
    } on Object catch (error) {
      failures.add(error);
    }
    if (!_recorderDisposed) {
      try {
        await _recorder.dispose();
        _recorderDisposed = true;
      } on Object catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) throw VoiceCleanupFailure(failures);
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final previous = _operationTail;
    final result = Completer<T>();
    _operationTail = () async {
      await previous;
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    }();
    return result.future;
  }
}
