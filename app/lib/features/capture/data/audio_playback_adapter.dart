import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;

const _playbackDirectoryName = 'keepers-playback';

/// Removes plaintext playback files left behind by a previous process.
///
/// The directory is dedicated to short-lived decrypted audio. It is deleted
/// as one validated child of the platform temporary directory so unrelated
/// temporary files are never touched.
Future<void> purgeAbandonedAudioPlaybackPlaintext(
  Future<Directory> Function() temporaryDirectory,
) async {
  final root = await temporaryDirectory();
  final rootPath = p.absolute(p.normalize(root.path));
  final playbackPath = p.absolute(
    p.normalize(p.join(rootPath, _playbackDirectoryName)),
  );
  if (p.dirname(playbackPath) != rootPath ||
      p.basename(playbackPath) != _playbackDirectoryName) {
    throw StateError('Invalid playback cleanup directory.');
  }

  final entityType = await FileSystemEntity.type(
    playbackPath,
    followLinks: false,
  );
  switch (entityType) {
    case FileSystemEntityType.notFound:
      return;
    case FileSystemEntityType.directory:
      await Directory(playbackPath).delete(recursive: true);
    case FileSystemEntityType.link:
      await Link(playbackPath).delete();
    default:
      await File(playbackPath).delete();
  }
}

abstract interface class AudioPlaybackAdapter {
  Future<void> playFile(String path);
  Future<void> playBytes(Uint8List bytes);
  Future<void> stop();
  Future<void> dispose();
}

abstract interface class DeviceFileAudioPlayer {
  Stream<void> get completions;
  Future<void> playDeviceFile(String path);
  Future<void> stop();
  Future<void> dispose();
}

final class AudioplayersDeviceFileAudioPlayer implements DeviceFileAudioPlayer {
  AudioplayersDeviceFileAudioPlayer(this._player);

  final AudioPlayer _player;

  @override
  Stream<void> get completions => _player.onPlayerComplete;

  @override
  Future<void> playDeviceFile(String path) =>
      _player.play(DeviceFileSource(path));

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

final class AudioplayersPlaybackAdapter implements AudioPlaybackAdapter {
  factory AudioplayersPlaybackAdapter({
    required DeviceFileAudioPlayer player,
    required Future<Directory> Function() temporaryDirectory,
    required String Function() idFactory,
  }) => AudioplayersPlaybackAdapter._(player, temporaryDirectory, idFactory);

  AudioplayersPlaybackAdapter._(
    this._player,
    this._temporaryDirectory,
    this._idFactory,
  ) {
    _completionSubscription = _player.completions.listen((_) {
      unawaited(_serialize(_deleteOwnedPlaintext).catchError((Object _) {}));
    });
  }

  final DeviceFileAudioPlayer _player;
  final Future<Directory> Function() _temporaryDirectory;
  final String Function() _idFactory;
  late final StreamSubscription<void> _completionSubscription;
  File? _ownedPlaintext;
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<void> playFile(String path) => _serialize(() async {
    if (_ownedPlaintext != null) await _stop();
    await _player.playDeviceFile(path);
  });

  @override
  Future<void> playBytes(Uint8List bytes) => _serialize(() async {
    if (_ownedPlaintext != null) await _stop();
    final root = await _temporaryDirectory();
    final directory = Directory(p.join(root.path, _playbackDirectoryName));
    await directory.create(recursive: true);
    final plaintext = File(p.join(directory.path, _idFactory()));
    _ownedPlaintext = plaintext;
    try {
      await plaintext.writeAsBytes(bytes, flush: true);
      await _player.playDeviceFile(plaintext.path);
    } on Object {
      await _deleteOwnedPlaintext();
      rethrow;
    }
  });

  @override
  Future<void> stop() => _serialize(_stop);

  Future<void> _stop() async {
    try {
      await _player.stop();
    } finally {
      await _deleteOwnedPlaintext();
    }
  }

  @override
  Future<void> dispose() => _serialize(_dispose);

  Future<void> _dispose() async {
    try {
      try {
        await _completionSubscription.cancel();
      } finally {
        await _player.dispose();
      }
    } finally {
      await _deleteOwnedPlaintext();
    }
  }

  Future<void> _deleteOwnedPlaintext() async {
    final plaintext = _ownedPlaintext;
    if (plaintext == null) return;
    _ownedPlaintext = null;
    try {
      await plaintext.delete();
    } on Object {
      _ownedPlaintext ??= plaintext;
      rethrow;
    }
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
