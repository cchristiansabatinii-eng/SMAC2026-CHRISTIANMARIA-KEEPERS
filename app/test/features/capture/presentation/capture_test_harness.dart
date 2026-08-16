import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/capture/application/capture_providers.dart';
import 'package:keepers/features/capture/data/audio_playback_adapter.dart';
import 'package:keepers/features/capture/data/photo_capture_adapter.dart';
import 'package:keepers/features/capture/data/voice_capture_adapter.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/capture/presentation/capture_sheet.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';

const captureIdentity = LocalIdentity(
  familyId: 'family-1',
  familyName: 'Sabati',
  familyKeyRef: 'family-key',
  memberId: 'member-1',
  memberName: 'Chris',
  memberKeyRef: 'member-key',
  colorToken: 'sea',
  avatar: AvatarConfig.defaults(seed: 'member-1'),
);

final class CaptureTestHarness {
  CaptureTestHarness({
    FakePhotoCaptureAdapter? photo,
    FakeVoiceCaptureAdapter? voice,
    FakeAudioPlaybackAdapter? playback,
    FakeCaptureFileAccess? files,
    EntrySave? save,
  }) : photo = photo ?? FakePhotoCaptureAdapter(),
       voice = voice ?? FakeVoiceCaptureAdapter(),
       playback = playback ?? FakeAudioPlaybackAdapter(),
       files = files ?? FakeCaptureFileAccess(),
       _save = save ?? _successfulSave {
    container = ProviderContainer(
      overrides: [
        photoCaptureAdapterProvider.overrideWithValue(this.photo),
        voiceCaptureAdapterProvider.overrideWithValue(this.voice),
        audioPlaybackAdapterProvider.overrideWithValue(this.playback),
        captureFileAccessProvider.overrideWithValue(this.files),
        entrySaveProvider.overrideWithValue(_save),
        localIdentityProvider.overrideWithValue(
          const AsyncValue.data(captureIdentity),
        ),
        idFactoryProvider.overrideWithValue(() => 'entry-1'),
        utcNowProvider.overrideWithValue(() => DateTime.utc(2026, 9, 1)),
      ],
    );
  }

  final FakePhotoCaptureAdapter photo;
  final FakeVoiceCaptureAdapter voice;
  final FakeAudioPlaybackAdapter playback;
  final FakeCaptureFileAccess files;
  final EntrySave _save;
  late final ProviderContainer container;

  Widget sheet({MediaQueryData? mediaQuery}) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: KeepersTheme.dark(),
      home: Scaffold(
        body: mediaQuery == null
            ? const CaptureSheet()
            : MediaQuery(data: mediaQuery, child: const CaptureSheet()),
      ),
    ),
  );

  Widget launcher() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: KeepersTheme.dark(),
      home: const CaptureLauncher(),
    ),
  );

  void dispose() => container.dispose();
}

final class CaptureLauncher extends StatefulWidget {
  const CaptureLauncher({super.key});

  @override
  State<CaptureLauncher> createState() => _CaptureLauncherState();
}

final class _CaptureLauncherState extends State<CaptureLauncher> {
  EntryMetadata? _result;
  var _completionCount = 0;

  Future<void> _open() async {
    final result = await CaptureSheet.show(context);
    if (!mounted) return;
    setState(() {
      _result = result;
      _completionCount += 1;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(onPressed: _open, child: const Text('Add a memory')),
          Text('Completions: $_completionCount'),
          if (_result != null) Text('Saved: ${_result!.id}'),
        ],
      ),
    ),
  );
}

class FakePhotoCaptureAdapter implements PhotoCaptureAdapter {
  FakePhotoCaptureAdapter({this.result, this.error});

  String? result;
  Object? error;
  final pickedSources = <PhotoSource>[];

  @override
  Future<String?> pick(PhotoSource source) async {
    pickedSources.add(source);
    if (error case final error?) throw error;
    return result;
  }

  @override
  Future<String?> recoverLostPhoto() async => null;
}

final class BlockingPhotoCaptureAdapter extends FakePhotoCaptureAdapter {
  final pickResult = Completer<String?>();

  @override
  Future<String?> pick(PhotoSource source) => pickResult.future;

  @override
  Future<String?> recoverLostPhoto() async => null;
}

final class BlockingRecoveryPhotoCaptureAdapter
    extends FakePhotoCaptureAdapter {
  final recoveryResult = Completer<String?>();

  @override
  Future<String?> recoverLostPhoto() => recoveryResult.future;
}

final class FakeVoiceCaptureAdapter implements VoiceCaptureAdapter {
  FakeVoiceCaptureAdapter({this.permission = true});

  bool permission;
  final amplitudesController = StreamController<double>.broadcast();
  var starts = 0;
  var stops = 0;
  var cancels = 0;
  var recording = false;

  @override
  Stream<double> get amplitudes => amplitudesController.stream;

  @override
  bool get ownsPlaintext => recording;

  @override
  Future<void> cancel() async {
    cancels += 1;
    recording = false;
  }

  @override
  Future<void> dispose() async {
    await amplitudesController.close();
  }

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start() async {
    starts += 1;
    recording = true;
  }

  @override
  Future<VoiceRecording?> stop() async {
    stops += 1;
    recording = false;
    return const VoiceRecording(
      path: '/tmp/voice.m4a',
      duration: Duration(seconds: 7),
    );
  }
}

final class FakeAudioPlaybackAdapter implements AudioPlaybackAdapter {
  final playedFiles = <String>[];
  var stops = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> playBytes(Uint8List bytes) async {}

  @override
  Future<void> playFile(String path) async => playedFiles.add(path);

  @override
  Future<void> stop() async {
    stops += 1;
  }
}

final class FakeCaptureFileAccess implements CaptureFileAccess {
  FakeCaptureFileAccess({
    this.deleteError,
    this.deleteFailures = 0,
    this.readFailuresWithPendingCleanup = 0,
    this.pendingCleanupFailures = 0,
    this.releaseFailures = 0,
    this.releaseGate,
    this.retryReleaseGate,
  });

  Object? deleteError;
  int deleteFailures;
  int readFailuresWithPendingCleanup;
  int pendingCleanupFailures;
  int releaseFailures;
  final Completer<void>? releaseGate;
  final Completer<void>? retryReleaseGate;
  final deletedPaths = <String>[];
  var releaseCalls = 0;
  var successfulReleases = 0;
  var retryPendingCalls = 0;
  var pendingCleanup = false;

  @override
  Future<void> deleteAll(Iterable<String> paths) async {
    deletedPaths.addAll(paths);
    if (deleteFailures > 0) {
      deleteFailures -= 1;
      throw StateError('draft cleanup failed');
    }
    if (deleteError case final error?) throw error;
  }

  @override
  Future<CaptureMedia> read(String path) async {
    if (readFailuresWithPendingCleanup > 0) {
      readFailuresWithPendingCleanup -= 1;
      pendingCleanup = true;
      throw StateError('snapshot read failed after retaining cleanup');
    }
    return CaptureMedia(
      bytes: Uint8List.fromList([1, 2, 3]),
      extension: 'jpg',
      plaintextRef: 'keepers-capture/photo.jpg',
      release: () async {
        releaseCalls += 1;
        if (releaseGate case final gate?) await gate.future;
        if (releaseCalls == 2) {
          if (retryReleaseGate case final gate?) await gate.future;
        }
        if (releaseFailures > 0) {
          releaseFailures -= 1;
          throw StateError('snapshot cleanup failed');
        }
        successfulReleases += 1;
      },
    );
  }

  @override
  Future<void> retryPendingCleanup() async {
    retryPendingCalls += 1;
    if (!pendingCleanup) return;
    if (pendingCleanupFailures > 0) {
      pendingCleanupFailures -= 1;
      throw StateError('retained snapshot cleanup failed');
    }
    pendingCleanup = false;
  }
}

Future<EntryMetadata> _successfulSave(EntrySaveRequest request) async =>
    request.metadata.copyWith(blobRef: 'entries/blobs/entry-1.keeper');
