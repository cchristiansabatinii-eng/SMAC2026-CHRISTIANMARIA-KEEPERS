import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/data/voice_capture_adapter.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:record/record.dart';

void main() {
  late Directory root;
  late FakeRecorderClient client;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('voice-adapter-');
    client = FakeRecorderClient();
  });
  tearDown(() async => root.delete(recursive: true));

  test('starts AAC-LC mono in the owned capture directory', () async {
    final adapter = RecordVoiceCaptureAdapter(
      recorder: client,
      temporaryDirectory: root,
      recordingId: () => 'voice-1',
    );
    await adapter.start();
    expect(client.config!.encoder, AudioEncoder.aacLc);
    expect(client.config!.numChannels, 1);
    expect(
      client.path,
      '${root.path}${Platform.pathSeparator}keepers-capture${Platform.pathSeparator}voice-1.m4a',
    );
  });

  test('fails with typed microphone denial before starting', () async {
    client.permission = false;
    final adapter = RecordVoiceCaptureAdapter(
      recorder: client,
      temporaryDirectory: root,
      recordingId: () => 'voice-1',
    );
    await expectLater(
      adapter.start(),
      throwsA(isA<CapturePermissionException>()),
    );
    expect(client.starts, 0);
  });

  test('clamps amplitude and returns elapsed recording', () async {
    final clock = FakeStopwatch();
    final adapter = RecordVoiceCaptureAdapter(
      recorder: client,
      temporaryDirectory: root,
      recordingId: () => 'voice-1',
      stopwatch: clock,
    );
    expect(await adapter.amplitudes.take(2).toList(), [-60.0, 0.0]);
    await adapter.start();
    clock.elapsedValue = const Duration(milliseconds: 1250);
    client.stopPath = client.path;
    final recording = await adapter.stop();
    expect(recording!.path, client.path);
    expect(recording.duration, const Duration(milliseconds: 1250));
  });

  test('cancel removes a remaining temporary recording', () async {
    final adapter = RecordVoiceCaptureAdapter(
      recorder: client,
      temporaryDirectory: root,
      recordingId: () => 'voice-1',
    );
    await adapter.start();
    File(client.path!).writeAsBytesSync([1]);
    await adapter.cancel();
    expect(File(client.path!).existsSync(), isFalse);
  });

  test(
    'cancel and dispose delete plaintext even when plugin cancel fails',
    () async {
      client.cancelError = StateError('plugin cancel failed');
      final adapter = RecordVoiceCaptureAdapter(
        recorder: client,
        temporaryDirectory: root,
        recordingId: () => 'voice-1',
      );
      await adapter.start();
      File(client.path!).writeAsBytesSync([1]);
      await expectLater(adapter.dispose(), throwsA(isA<VoiceCleanupFailure>()));
      expect(File(client.path!).existsSync(), isFalse);
      expect(client.disposes, 1);
    },
  );

  test('failed delete retains the exact plaintext path for retry', () async {
    client.cancelError = StateError('plugin cancel failed');
    final adapter = RecordVoiceCaptureAdapter(
      recorder: client,
      temporaryDirectory: root,
      recordingId: () => 'voice-1',
    );
    await adapter.start();
    final path = client.path!;
    await Directory(path).create();

    await expectLater(adapter.cancel(), throwsA(isA<VoiceCleanupFailure>()));
    await Directory(path).delete();
    await File(path).writeAsBytes([1, 2, 3]);
    client.cancelError = null;
    await adapter.dispose();

    expect(File(path).existsSync(), isFalse);
  });

  test('cancel waits for an in-flight native start', () async {
    final serialClient = BlockingStartRecorderClient();
    final adapter = RecordVoiceCaptureAdapter(
      recorder: serialClient,
      temporaryDirectory: root,
      recordingId: () => 'voice-1',
    );
    final starting = adapter.start();
    await serialClient.entered.future;
    final cancelling = adapter.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(serialClient.cancelEntered, isFalse);
    serialClient.release.complete();
    await Future.wait([starting, cancelling]);
    expect(serialClient.maximumConcurrentCalls, 1);
  });

  test('dispose waits for an in-flight native start', () async {
    final serialClient = BlockingStartRecorderClient();
    final adapter = RecordVoiceCaptureAdapter(
      recorder: serialClient,
      temporaryDirectory: root,
      recordingId: () => 'voice-1',
    );
    final starting = adapter.start();
    await serialClient.entered.future;
    final disposing = adapter.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(serialClient.disposeEntered, isFalse);
    serialClient.release.complete();
    await Future.wait([starting, disposing]);
    expect(serialClient.maximumConcurrentCalls, 1);
    expect(serialClient.disposeEntered, isTrue);
  });

  test('null stop retains ownership and rejects a second start', () async {
    var nextId = 0;
    final adapter = RecordVoiceCaptureAdapter(
      recorder: client,
      temporaryDirectory: root,
      recordingId: () => 'voice-${++nextId}',
    );
    await adapter.start();
    final original = File(client.path!)..writeAsBytesSync([1, 2, 3]);

    expect(await adapter.stop(), isNull);
    expect(adapter.ownsPlaintext, isTrue);
    await expectLater(adapter.start(), throwsA(isA<StateError>()));

    await adapter.cancel();
    expect(original.existsSync(), isFalse);
    expect(client.starts, 1);
  });

  test('mismatched stop retains the originally allocated path', () async {
    final adapter = RecordVoiceCaptureAdapter(
      recorder: client,
      temporaryDirectory: root,
      recordingId: () => 'voice-1',
    );
    await adapter.start();
    final original = File(client.path!)..writeAsBytesSync([1, 2, 3]);
    client.stopPath = '${root.path}${Platform.pathSeparator}different.m4a';

    final result = await adapter.stop();

    expect(result!.path, client.stopPath);
    expect(adapter.ownsPlaintext, isTrue);
    await adapter.cancel();
    expect(original.existsSync(), isFalse);
  });
}

final class FakeRecorderClient implements VoiceRecorderClient {
  bool permission = true;
  int starts = 0;
  RecordConfig? config;
  String? path;
  String? stopPath;
  Object? cancelError;
  int disposes = 0;

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      Stream.fromIterable([
        Amplitude(current: -90, max: -10),
        Amplitude(current: 4, max: 4),
      ]);
  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    starts++;
    this.config = config;
    this.path = path;
  }

  @override
  Future<String?> stop() async => stopPath;
  @override
  Future<void> cancel() async {
    if (cancelError != null) throw cancelError!;
  }

  @override
  Future<void> dispose() async => disposes++;
}

final class FakeStopwatch implements Stopwatch {
  Duration elapsedValue = Duration.zero;
  bool running = false;
  @override
  Duration get elapsed => elapsedValue;
  @override
  int get elapsedMicroseconds => elapsedValue.inMicroseconds;
  @override
  int get elapsedMilliseconds => elapsedValue.inMilliseconds;
  @override
  int get elapsedTicks => elapsedValue.inMicroseconds;
  @override
  int get frequency => Duration.microsecondsPerSecond;
  @override
  bool get isRunning => running;
  @override
  void reset() => elapsedValue = Duration.zero;
  @override
  void start() => running = true;
  @override
  void stop() => running = false;
}

final class BlockingStartRecorderClient implements VoiceRecorderClient {
  final entered = Completer<void>();
  final release = Completer<void>();
  var cancelEntered = false;
  var disposeEntered = false;
  var concurrentCalls = 0;
  var maximumConcurrentCalls = 0;

  void _enter() {
    concurrentCalls++;
    if (concurrentCalls > maximumConcurrentCalls) {
      maximumConcurrentCalls = concurrentCalls;
    }
  }

  void _leave() => concurrentCalls--;

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      const Stream.empty();
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    _enter();
    entered.complete();
    await release.future;
    _leave();
  }

  @override
  Future<String?> stop() async => null;
  @override
  Future<void> cancel() async {
    _enter();
    cancelEntered = true;
    _leave();
  }

  @override
  Future<void> dispose() async {
    _enter();
    disposeEntered = true;
    _leave();
  }
}
