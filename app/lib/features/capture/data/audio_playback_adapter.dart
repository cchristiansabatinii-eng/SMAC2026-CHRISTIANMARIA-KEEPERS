import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

abstract interface class AudioPlaybackAdapter {
  Future<void> playFile(String path);
  Future<void> playBytes(Uint8List bytes);
  Future<void> stop();
  Future<void> dispose();
}

final class AudioplayersPlaybackAdapter implements AudioPlaybackAdapter {
  AudioplayersPlaybackAdapter(this._player);
  final AudioPlayer _player;
  @override
  Future<void> playFile(String path) => _player.play(DeviceFileSource(path));
  @override
  Future<void> playBytes(Uint8List bytes) => _player.play(BytesSource(bytes));
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() => _player.dispose();
}
