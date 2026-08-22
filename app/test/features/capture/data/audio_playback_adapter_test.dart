import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/data/audio_playback_adapter.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'audio-playback-adapter-',
    );
  });

  tearDown(() async {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'startup scavenging removes abandoned playback plaintext only',
    () async {
      final playbackDirectory = Directory(
        p.join(temporaryDirectory.path, 'keepers-playback'),
      );
      await playbackDirectory.create();
      final abandoned = File(p.join(playbackDirectory.path, 'voice-abandoned'));
      final unrelated = File(p.join(temporaryDirectory.path, 'keep-me'));
      await abandoned.writeAsBytes([1, 2, 3]);
      await unrelated.writeAsBytes([4, 5, 6]);

      await purgeAbandonedAudioPlaybackPlaintext(
        () async => temporaryDirectory,
      );

      expect(playbackDirectory.existsSync(), isFalse);
      expect(await unrelated.readAsBytes(), [4, 5, 6]);
    },
  );

  test(
    'startup scavenging is safe when no playback directory exists',
    () async {
      await purgeAbandonedAudioPlaybackPlaintext(
        () async => temporaryDirectory,
      );

      expect(temporaryDirectory.existsSync(), isTrue);
    },
  );

  test(
    'stop removes adapter-owned plaintext created for byte playback',
    () async {
      final player = _FakeDeviceFileAudioPlayer();
      final adapter = AudioplayersPlaybackAdapter(
        player: player,
        temporaryDirectory: () async => temporaryDirectory,
        idFactory: () => 'voice-preview-1',
      );
      addTearDown(adapter.dispose);

      await adapter.playBytes(Uint8List.fromList([1, 2, 3, 4]));
      final plaintext = File(
        p.join(temporaryDirectory.path, 'keepers-playback', 'voice-preview-1'),
      );
      expect(await plaintext.readAsBytes(), [1, 2, 3, 4]);

      await adapter.stop();

      expect(plaintext.existsSync(), isFalse);
    },
  );

  test('player completion removes adapter-owned byte plaintext', () async {
    final player = _FakeDeviceFileAudioPlayer();
    final adapter = AudioplayersPlaybackAdapter(
      player: player,
      temporaryDirectory: () async => temporaryDirectory,
      idFactory: () => 'voice-preview-2',
    );
    addTearDown(adapter.dispose);
    await adapter.playBytes(Uint8List.fromList([5, 6, 7, 8]));
    final plaintext = File(
      p.join(temporaryDirectory.path, 'keepers-playback', 'voice-preview-2'),
    );
    expect(plaintext.existsSync(), isTrue);

    player.complete();
    await pumpEventQueue();

    expect(plaintext.existsSync(), isFalse);
  });

  test('failed playback removes the adapter-owned byte plaintext', () async {
    final player = _FakeDeviceFileAudioPlayer(
      playError: StateError('player unavailable'),
    );
    final adapter = AudioplayersPlaybackAdapter(
      player: player,
      temporaryDirectory: () async => temporaryDirectory,
      idFactory: () => 'voice-preview-3',
    );
    addTearDown(adapter.dispose);
    final plaintext = File(
      p.join(temporaryDirectory.path, 'keepers-playback', 'voice-preview-3'),
    );

    await expectLater(
      adapter.playBytes(Uint8List.fromList([9, 10, 11, 12])),
      throwsStateError,
    );

    expect(plaintext.existsSync(), isFalse);
  });

  test('dispose removes adapter-owned byte plaintext', () async {
    final player = _FakeDeviceFileAudioPlayer();
    final adapter = AudioplayersPlaybackAdapter(
      player: player,
      temporaryDirectory: () async => temporaryDirectory,
      idFactory: () => 'voice-preview-4',
    );
    await adapter.playBytes(Uint8List.fromList([13, 14, 15, 16]));
    final plaintext = File(
      p.join(temporaryDirectory.path, 'keepers-playback', 'voice-preview-4'),
    );
    expect(plaintext.existsSync(), isTrue);

    await adapter.dispose();

    expect(plaintext.existsSync(), isFalse);
  });

  test('new byte playback removes the previous owned plaintext', () async {
    final player = _FakeDeviceFileAudioPlayer();
    final ids = ['voice-preview-5a', 'voice-preview-5b'].iterator;
    final adapter = AudioplayersPlaybackAdapter(
      player: player,
      temporaryDirectory: () async => temporaryDirectory,
      idFactory: () {
        ids.moveNext();
        return ids.current;
      },
    );
    addTearDown(adapter.dispose);
    final first = File(
      p.join(temporaryDirectory.path, 'keepers-playback', 'voice-preview-5a'),
    );
    final second = File(
      p.join(temporaryDirectory.path, 'keepers-playback', 'voice-preview-5b'),
    );

    await adapter.playBytes(Uint8List.fromList([17, 18]));
    expect(first.existsSync(), isTrue);
    await adapter.playBytes(Uint8List.fromList([19, 20]));

    expect(first.existsSync(), isFalse);
    expect(await second.readAsBytes(), [19, 20]);
  });

  test('file playback removes previous adapter-owned byte plaintext', () async {
    final player = _FakeDeviceFileAudioPlayer();
    final adapter = AudioplayersPlaybackAdapter(
      player: player,
      temporaryDirectory: () async => temporaryDirectory,
      idFactory: () => 'voice-preview-6',
    );
    addTearDown(adapter.dispose);
    await adapter.playBytes(Uint8List.fromList([21, 22]));
    final plaintext = File(
      p.join(temporaryDirectory.path, 'keepers-playback', 'voice-preview-6'),
    );
    expect(plaintext.existsSync(), isTrue);

    await adapter.playFile(p.join(temporaryDirectory.path, 'capture.m4a'));

    expect(plaintext.existsSync(), isFalse);
  });

  test(
    'stop waits for pending byte playback before removing plaintext',
    () async {
      final player = _FakeDeviceFileAudioPlayer();
      final directory = Completer<Directory>();
      final adapter = AudioplayersPlaybackAdapter(
        player: player,
        temporaryDirectory: () => directory.future,
        idFactory: () => 'voice-preview-7',
      );
      addTearDown(adapter.dispose);
      final playback = adapter.playBytes(Uint8List.fromList([23, 24]));

      final stopping = adapter.stop();
      directory.complete(temporaryDirectory);
      await playback;
      await stopping;

      final plaintext = File(
        p.join(temporaryDirectory.path, 'keepers-playback', 'voice-preview-7'),
      );
      expect(plaintext.existsSync(), isFalse);
    },
  );
}

final class _FakeDeviceFileAudioPlayer implements DeviceFileAudioPlayer {
  _FakeDeviceFileAudioPlayer({this.playError});

  final Object? playError;
  final StreamController<void> _completions = StreamController<void>.broadcast(
    sync: true,
  );

  @override
  Stream<void> get completions => _completions.stream;

  void complete() => _completions.add(null);

  @override
  Future<void> dispose() => _completions.close();

  @override
  Future<void> playDeviceFile(String path) async {
    if (playError case final error?) throw error;
  }

  @override
  Future<void> stop() async {}
}
