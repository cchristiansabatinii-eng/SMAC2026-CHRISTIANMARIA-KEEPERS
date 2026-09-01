// ignore_for_file: unawaited_futures

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/application/capture_controller.dart';
import 'package:keepers/features/capture/application/capture_providers.dart';
import 'package:keepers/features/capture/data/audio_playback_adapter.dart';
import 'package:keepers/features/capture/data/encrypted_blob_store.dart';
import 'package:keepers/features/capture/data/photo_capture_adapter.dart';
import 'package:keepers/features/capture/data/voice_capture_adapter.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:record/record.dart';

import '../data/test_secure_blob_file_system.dart';

const identity = LocalIdentity(
  familyId: 'family-1',
  familyName: 'Family',
  familyKeyRef: 'family-key',
  memberId: 'member-1',
  memberName: 'Member',
  memberKeyRef: 'member-key',
  colorToken: 'ember',
);

void main() {
  test('draft defaults to photo and Weekly Reveal', () {
    final container = captureContainer();
    addTearDown(container.dispose);
    final state = container.read(captureControllerProvider);
    expect(state.format, MemoryFormat.photo);
    expect(state.privacy, PrivacyTier.reveal);
    expect(state.canSave, isFalse);
  });

  test('exactly one primary format survives switching', () async {
    final container = captureContainer();
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    await controller.acceptPhoto('/tmp/photo.jpg');
    await controller.selectFormat(MemoryFormat.text);
    controller.updateText('A small memory');
    final state = container.read(captureControllerProvider);
    expect(state.photoPath, isNull);
    expect(state.voicePath, isNull);
    expect(state.text, 'A small memory');
    expect(state.caption, isEmpty);
  });

  test('optional caption survives format switching', () {
    final container = captureContainer();
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    controller.updateCaption('Sunday morning');
    controller.selectFormat(MemoryFormat.text);
    expect(container.read(captureControllerProvider).caption, 'Sunday morning');
  });

  test('privacy transitions clear an error without changing content', () async {
    var calls = 0;
    final container = captureContainer(
      save: (request) async {
        calls++;
        throw StateError('offline');
      },
    );
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    controller.selectFormat(MemoryFormat.text);
    controller.updateText('Private note');
    await controller.save();
    controller.setPrivacy(PrivacyTier.journal);
    final state = container.read(captureControllerProvider);
    expect(calls, 1);
    expect(state.privacy, PrivacyTier.journal);
    expect(state.text, 'Private note');
    expect(state.errorMessage, isNull);
  });

  test('voice uses tap start then tap stop', () async {
    final recorder = FakeVoiceCaptureAdapter();
    final container = captureContainer(recorder: recorder);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    controller.selectFormat(MemoryFormat.voice);

    await controller.toggleRecording();
    expect(container.read(captureControllerProvider).isRecording, isTrue);
    await controller.toggleRecording();
    final state = container.read(captureControllerProvider);
    expect(state.isRecording, isFalse);
    expect(state.voicePath, '/tmp/voice.m4a');
    expect(state.voiceDuration, const Duration(seconds: 2));
  });

  test(
    'null native stop cleans adapter-owned plaintext before discard',
    () async {
      final root = await Directory.systemTemp.createTemp('null-stop-');
      final support = await Directory.systemTemp.createTemp(
        'null-stop-support-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        if (await support.exists()) await support.delete(recursive: true);
      });
      final client = StopResultRecorderClient();
      final recorder = RecordVoiceCaptureAdapter(
        recorder: client,
        temporaryDirectory: root,
        recordingId: () => 'voice-1',
      );
      final files = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'snapshot',
        blobStore: () async => testEncryptedBlobStore(support, root),
      );
      final container = captureContainer(recorder: recorder, files: files);
      addTearDown(container.dispose);
      final controller = container.read(captureControllerProvider.notifier);
      await controller.selectFormat(MemoryFormat.voice);
      await controller.toggleRecording();
      final original = File(client.path!);

      await controller.toggleRecording();
      await controller.discard();

      expect(original.existsSync(), isFalse);
      expect(client.cancels, 1);
      expect(container.read(captureControllerProvider), const CaptureDraft());
    },
  );

  test('null stop derives ownership after plugin cancel failure', () async {
    final root = await Directory.systemTemp.createTemp('null-stop-cancel-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final client = StopResultRecorderClient(
      cancelError: StateError('plugin cancel failed'),
    );
    final recorder = RecordVoiceCaptureAdapter(
      recorder: client,
      temporaryDirectory: root,
      recordingId: () => 'voice-1',
    );
    final container = captureContainer(recorder: recorder);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    await controller.selectFormat(MemoryFormat.voice);
    await controller.toggleRecording();
    final original = File(client.path!);

    await controller.toggleRecording();

    expect(original.existsSync(), isFalse);
    expect(recorder.ownsPlaintext, isFalse);
    expect(container.read(captureControllerProvider).recordingActive, isFalse);
  });

  test('mismatched native stop cleans both untrusted paths', () async {
    final root = await Directory.systemTemp.createTemp('mismatch-stop-');
    final support = await Directory.systemTemp.createTemp(
      'mismatch-stop-support-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
      if (await support.exists()) await support.delete(recursive: true);
    });
    final client = StopResultRecorderClient();
    final recorder = RecordVoiceCaptureAdapter(
      recorder: client,
      temporaryDirectory: root,
      recordingId: () => 'voice-1',
    );
    final files = OwnedCaptureFileAccess(
      temporaryDirectory: () async => root,
      idFactory: () => 'snapshot',
      blobStore: () async => testEncryptedBlobStore(support, root),
    );
    final container = captureContainer(recorder: recorder, files: files);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    await controller.selectFormat(MemoryFormat.voice);
    await controller.toggleRecording();
    final original = File(client.path!);
    final returned = File(
      '${original.parent.path}${Platform.pathSeparator}different.m4a',
    )..writeAsBytesSync([9, 9]);
    client.stopResult = returned.path;

    await controller.toggleRecording();

    expect(original.existsSync(), isFalse);
    expect(returned.existsSync(), isFalse);
    expect(client.cancels, 1);
    expect(
      container.read(captureControllerProvider).phase,
      CapturePhase.editing,
    );
  });

  test(
    'mismatched stop still removes the returned file when plugin cancel fails',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mismatch-cancel-success-',
      );
      final support = await Directory.systemTemp.createTemp(
        'mismatch-cancel-success-support-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        if (await support.exists()) await support.delete(recursive: true);
      });
      final client = StopResultRecorderClient(
        cancelError: StateError('plugin cancel failed'),
      );
      final recorder = RecordVoiceCaptureAdapter(
        recorder: client,
        temporaryDirectory: root,
        recordingId: () => 'voice-${client.starts + 1}',
      );
      final files = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'snapshot',
        blobStore: () async => testEncryptedBlobStore(support, root),
      );
      final container = captureContainer(recorder: recorder, files: files);
      addTearDown(container.dispose);
      final controller = container.read(captureControllerProvider.notifier);
      await controller.selectFormat(MemoryFormat.voice);
      await controller.toggleRecording();
      final original = File(client.path!);
      final returned = File(
        '${original.parent.path}${Platform.pathSeparator}different.m4a',
      )..writeAsBytesSync([9, 9]);
      client.stopResult = returned.path;

      await controller.toggleRecording();

      expect(original.existsSync(), isFalse);
      expect(returned.existsSync(), isFalse);
      expect(recorder.ownsPlaintext, isFalse);
      client.cancelError = null;
      await controller.toggleRecording();
      expect(client.starts, 2);
    },
  );

  test(
    'combined mismatched-stop failures retain the returned file until retry',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mismatch-cancel-retry-',
      );
      final support = await Directory.systemTemp.createTemp(
        'mismatch-cancel-retry-support-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        if (await support.exists()) await support.delete(recursive: true);
      });
      final secure = TestSecureBlobFileSystem(
        supportDirectory: support,
        captureTemporaryDirectory: root,
        failPlaintextDeletes: 1,
      );
      final store = EncryptedBlobStore(
        support,
        captureTemporaryDirectory: root,
        fileSystem: secure,
      );
      final client = StopResultRecorderClient(
        cancelError: StateError('plugin cancel failed'),
      );
      final recorder = RecordVoiceCaptureAdapter(
        recorder: client,
        temporaryDirectory: root,
        recordingId: () => 'voice-${client.starts + 1}',
      );
      final files = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'snapshot',
        blobStore: () async => store,
      );
      final container = captureContainer(recorder: recorder, files: files);
      addTearDown(container.dispose);
      final controller = container.read(captureControllerProvider.notifier);
      await controller.selectFormat(MemoryFormat.voice);
      await controller.toggleRecording();
      final original = File(client.path!);
      final returned = File(
        '${original.parent.path}${Platform.pathSeparator}different.m4a',
      )..writeAsBytesSync([9, 9]);
      client.stopResult = returned.path;

      await controller.toggleRecording();
      await controller.toggleRecording();

      expect(original.existsSync(), isFalse);
      expect(returned.existsSync(), isTrue);
      expect(client.starts, 1);
      client.cancelError = null;
      await controller.discard();
      expect(returned.existsSync(), isFalse);
      expect(container.read(captureControllerProvider), const CaptureDraft());
    },
  );

  test('failed mismatched-stop cleanup blocks restart until discard retries', () async {
    final root = await Directory.systemTemp.createTemp('mismatch-retry-');
    final support = await Directory.systemTemp.createTemp(
      'mismatch-retry-support-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
      if (await support.exists()) await support.delete(recursive: true);
    });
    final secure = TestSecureBlobFileSystem(
      supportDirectory: support,
      captureTemporaryDirectory: root,
    );
    final store = EncryptedBlobStore(
      support,
      captureTemporaryDirectory: root,
      fileSystem: secure,
    );
    final client = StopResultRecorderClient();
    final recorder = RecordVoiceCaptureAdapter(
      recorder: client,
      temporaryDirectory: root,
      recordingId: () => 'voice-${client.starts + 1}',
    );
    final files = OwnedCaptureFileAccess(
      temporaryDirectory: () async => root,
      idFactory: () => 'snapshot',
      blobStore: () async => store,
    );
    final container = captureContainer(recorder: recorder, files: files);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    await controller.selectFormat(MemoryFormat.voice);
    await controller.toggleRecording();
    final returned = File(
      '${File(client.path!).parent.path}${Platform.pathSeparator}different.m4a',
    )..writeAsBytesSync([9, 9]);
    client.stopResult = returned.path;
    secure.failPlaintextDeletes = 1;

    await controller.toggleRecording();
    await controller.toggleRecording();

    expect(client.starts, 1);
    expect(returned.existsSync(), isTrue);
    await controller.discard();
    expect(returned.existsSync(), isFalse);
    expect(container.read(captureControllerProvider), const CaptureDraft());
  });

  test('recording interruption cancels recorder plaintext', () async {
    final recorder = FakeVoiceCaptureAdapter(
      stopError: StateError('lost input'),
    );
    final container = captureContainer(recorder: recorder);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    controller.selectFormat(MemoryFormat.voice);
    await controller.toggleRecording();
    await controller.toggleRecording();
    expect(recorder.cancels, 1);
    expect(
      container.read(captureControllerProvider).phase,
      CapturePhase.failed,
    );
  });

  test('partial start failure cancels recorder plaintext', () async {
    final recorder = FakeVoiceCaptureAdapter(
      startError: StateError('interrupted'),
    );
    final container = captureContainer(recorder: recorder);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    controller.selectFormat(MemoryFormat.voice);
    await controller.toggleRecording();
    expect(recorder.cancels, 1);
    expect(
      container.read(captureControllerProvider).phase,
      CapturePhase.failed,
    );
  });

  test('typed permission denials use source-specific copy', () async {
    for (final source in PhotoSource.values) {
      final photo = FakePhotoCaptureAdapter(
        error: CapturePermissionException(source.permissionSource),
      );
      final container = captureContainer(photo: photo);
      addTearDown(container.dispose);
      await container
          .read(captureControllerProvider.notifier)
          .pickPhoto(source);
      expect(
        container.read(captureControllerProvider).errorMessage,
        source == PhotoSource.camera
            ? 'Camera access is needed to take a photo.'
            : 'Photo library access is needed to choose a photo.',
      );
    }

    final recorder = FakeVoiceCaptureAdapter(permission: false);
    final container = captureContainer(recorder: recorder);
    addTearDown(container.dispose);
    container
        .read(captureControllerProvider.notifier)
        .selectFormat(MemoryFormat.voice);
    await container.read(captureControllerProvider.notifier).toggleRecording();
    final state = container.read(captureControllerProvider);
    expect(state.phase, CapturePhase.failed);
    expect(
      state.errorMessage,
      'Microphone access is needed to record a memory.',
    );
  });

  test('cancelled photo selection leaves the draft unchanged', () async {
    final container = captureContainer(photo: FakePhotoCaptureAdapter());
    addTearDown(container.dispose);
    final before = container.read(captureControllerProvider);
    await container
        .read(captureControllerProvider.notifier)
        .pickPhoto(PhotoSource.library);
    expect(container.read(captureControllerProvider), same(before));
  });

  test('recovered photo becomes the selected primary', () async {
    final container = captureContainer(
      photo: FakePhotoCaptureAdapter(recovered: '/tmp/recovered.jpg'),
    );
    addTearDown(container.dispose);
    await container.read(captureControllerProvider.notifier).recoverLostPhoto();
    expect(
      container.read(captureControllerProvider).photoPath,
      '/tmp/recovered.jpg',
    );
  });

  test('voice playback and replacement use the selected draft file', () async {
    final playback = FakePlaybackAdapter();
    final files = FakeCaptureFileAccess();
    final container = captureContainer(playback: playback, files: files);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    controller.selectFormat(MemoryFormat.voice);
    await controller.toggleRecording();
    await controller.toggleRecording();
    await controller.playVoice();
    await controller.replacePrimary();
    expect(playback.playedFiles, ['/tmp/voice.m4a']);
    expect(files.deleted, ['/tmp/voice.m4a']);
    expect(container.read(captureControllerProvider).hasPrimary, isFalse);
  });

  test('rapid save taps persist one frozen entry', () async {
    final persistence = BlockingPersistence();
    final container = captureContainer(save: persistence.call);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    controller.selectFormat(MemoryFormat.text);
    controller.updateText('Only once');

    final first = controller.save();
    final second = controller.save();
    persistence.complete();
    await Future.wait([first, second]);

    expect(persistence.calls, 1);
    expect(container.read(captureControllerProvider).phase, CapturePhase.saved);
    final request = persistence.requests.single;
    expect(request.payload.text, 'Only once');
    expect(request.metadata.id, 'entry-1');
    expect(request.metadata.createdAt, DateTime.utc(2026, 9, 1));
    expect(request.identity, identity);
  });

  test('save after completed save cannot create a duplicate entry', () async {
    var calls = 0;
    final container = captureContainer(
      save: (request) async {
        calls++;
        return request.metadata.copyWith(
          blobRef: 'entries/blobs/entry-1.keeper',
        );
      },
    );
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    controller.selectFormat(MemoryFormat.text);
    controller.updateText('Only once ever');
    await controller.save();
    await controller.save();
    expect(calls, 1);
  });

  test('failed save preserves the draft and retry can succeed', () async {
    var calls = 0;
    Future<EntryMetadata> save(EntrySaveRequest request) async {
      if (++calls == 1) throw StateError('disk full');
      return request.metadata.copyWith(blobRef: 'entries/blobs/entry-1.keeper');
    }

    final container = captureContainer(save: save);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    controller.selectFormat(MemoryFormat.text);
    controller.updateText('Keep this');
    controller.updateCaption('Caption');
    await controller.save();
    expect(
      container.read(captureControllerProvider).phase,
      CapturePhase.failed,
    );
    expect(container.read(captureControllerProvider).text, 'Keep this');
    expect(container.read(captureControllerProvider).caption, 'Caption');

    await controller.save();
    expect(calls, 2);
    expect(container.read(captureControllerProvider).phase, CapturePhase.saved);
  });

  test('failed media save cleans only the save snapshot', () async {
    final files = FakeCaptureFileAccess();
    final container = captureContainer(
      files: files,
      save: (request) async => throw StateError('service unavailable'),
    );
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    controller.acceptPhoto('/tmp/photo.jpg');
    await controller.save();
    expect(files.deleted, ['/tmp/photo-save.jpg']);
    expect(
      container.read(captureControllerProvider).photoPath,
      '/tmp/photo.jpg',
    );
  });

  test('secure media save uses bytes and owned plaintext reference', () async {
    EntrySaveRequest? captured;
    final files = FakeCaptureFileAccess();
    final container = captureContainer(
      files: files,
      save: (request) async {
        captured = request;
        return request.metadata.copyWith(
          blobRef: 'entries/blobs/entry-1.keeper',
        );
      },
    );
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    controller.acceptPhoto('/tmp/photo.jpg');
    controller.updateCaption('At the lake');
    await controller.save();

    expect(captured!.payload.primaryBytes, Uint8List.fromList([1, 2, 3]));
    expect(captured!.payload.caption, 'At the lake');
    expect(
      captured!.plaintextRefs.single.relativePath,
      'keepers-capture/photo.jpg',
    );
  });

  test('discard cancels active resources, deletes media, and resets', () async {
    final recorder = FakeVoiceCaptureAdapter();
    final playback = FakePlaybackAdapter();
    final files = FakeCaptureFileAccess();
    final container = captureContainer(
      recorder: recorder,
      playback: playback,
      files: files,
    );
    final controller = container.read(captureControllerProvider.notifier);
    controller.acceptPhoto('/tmp/photo.jpg');
    await controller.discard();
    expect(playback.stops, 1);
    expect(files.deleted, ['/tmp/photo.jpg']);
    expect(container.read(captureControllerProvider).hasDraft, isFalse);
    container.dispose();
  });

  test('provider disposal releases an active recording', () async {
    final recorder = FakeVoiceCaptureAdapter();
    final playback = FakePlaybackAdapter();
    final container = captureContainer(recorder: recorder, playback: playback);
    final controller = container.read(captureControllerProvider.notifier);
    controller.selectFormat(MemoryFormat.voice);
    await controller.toggleRecording();
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(recorder.cancels, 1);
    expect(recorder.disposes, 1);
    expect(playback.stops, 1);
    expect(playback.disposes, 1);
  });

  test(
    'caption and privacy edits preserve recorder ownership until stop',
    () async {
      final recorder = FakeVoiceCaptureAdapter();
      final container = captureContainer(recorder: recorder);
      addTearDown(container.dispose);
      final controller = container.read(captureControllerProvider.notifier);
      controller.selectFormat(MemoryFormat.voice);
      await controller.toggleRecording();
      controller.updateCaption('While speaking');
      controller.setPrivacy(PrivacyTier.legacy);
      await controller.toggleRecording();
      expect(recorder.starts, 1);
      expect(recorder.stops, 1);
      expect(
        container.read(captureControllerProvider).caption,
        'While speaking',
      );
    },
  );

  test(
    'committed cleanup failure is non-persistable and retains metadata',
    () async {
      var calls = 0;
      EntryMetadata? committed;
      final container = captureContainer(
        save: (request) async {
          calls++;
          committed = request.metadata.copyWith(
            blobRef: 'entries/blobs/entry-1.keeper',
          );
          throw EntrySaveFailure(
            primary: EntrySaveCause(
              phase: EntrySavePhase.plaintextCleanup,
              error: StateError('cleanup'),
              stackTrace: StackTrace.current,
            ),
            compensations: const [],
            consistency: const EntrySaveConsistency(
              metadataCommitted: true,
              finalizedBlobState: EntryArtifactState.present,
              stagedBlobState: EntryArtifactState.absent,
              plaintextMayRemain: true,
            ),
            committedMetadata: committed,
          );
        },
      );
      addTearDown(container.dispose);
      final controller = container.read(captureControllerProvider.notifier);
      controller.selectFormat(MemoryFormat.text);
      controller.updateText('Committed once');
      await controller.save();
      controller.updateText('Must not reopen');
      await controller.save();
      final state = container.read(captureControllerProvider);
      expect(calls, 1);
      expect(state.phase, CapturePhase.committedCleanup);
      expect(state.savedEntry, committed);
      expect(state.text, 'Committed once');
    },
  );

  test(
    'original draft delete failure cannot re-persist committed entry',
    () async {
      final files = FakeCaptureFileAccess(deleteError: StateError('locked'));
      var calls = 0;
      final container = captureContainer(
        files: files,
        save: (request) async {
          calls++;
          return request.metadata.copyWith(
            blobRef: 'entries/blobs/entry-1.keeper',
          );
        },
      );
      addTearDown(container.dispose);
      final controller = container.read(captureControllerProvider.notifier);
      controller.acceptPhoto('/tmp/photo.jpg');
      await controller.save();
      await controller.save();
      expect(calls, 1);
      expect(
        container.read(captureControllerProvider).phase,
        CapturePhase.committedCleanup,
      );
    },
  );

  test(
    'stale picker completion after discard is deleted and ignored',
    () async {
      final photo = BlockingPhotoCaptureAdapter();
      final files = FakeCaptureFileAccess();
      final container = captureContainer(photo: photo, files: files);
      addTearDown(container.dispose);
      final controller = container.read(captureControllerProvider.notifier);
      final pick = controller.pickPhoto(PhotoSource.library);
      await Future<void>.delayed(Duration.zero);
      var discardCompleted = false;
      final discard = controller.discard().whenComplete(
        () => discardCompleted = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(discardCompleted, isFalse);
      photo.completeRecovery(null);
      photo.complete('/tmp/stale.jpg');
      await Future.wait([pick, discard]);
      expect(container.read(captureControllerProvider).photoPath, isNull);
      expect(files.deleted, contains('/tmp/stale.jpg'));
    },
  );

  test('rapid recording taps serialize a single start', () async {
    final recorder = BlockingVoiceCaptureAdapter();
    final container = captureContainer(recorder: recorder);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    controller.selectFormat(MemoryFormat.voice);
    final first = controller.toggleRecording();
    final second = controller.toggleRecording();
    recorder.completeStart();
    await Future.wait([first, second]);
    expect(recorder.starts, 1);
  });

  test('discard waits for blocked stop before cancelling recorder', () async {
    final root = await Directory.systemTemp.createTemp('blocked-stop-');
    final support = await Directory.systemTemp.createTemp(
      'blocked-stop-support-',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
      if (await support.exists()) await support.delete(recursive: true);
    });
    final client = BlockingStopRecorderClient();
    final recorder = RecordVoiceCaptureAdapter(
      recorder: client,
      temporaryDirectory: root,
      recordingId: () => 'voice-1',
    );
    final files = OwnedCaptureFileAccess(
      temporaryDirectory: () async => root,
      idFactory: () => 'snapshot',
      blobStore: () async => testEncryptedBlobStore(support, root),
    );
    final container = captureContainer(recorder: recorder, files: files);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    await controller.selectFormat(MemoryFormat.voice);
    await controller.toggleRecording();

    final stop = controller.toggleRecording();
    await client.stopEntered.future;
    var discardCompleted = false;
    final discard = controller.discard().whenComplete(
      () => discardCompleted = true,
    );
    await Future<void>.delayed(Duration.zero);

    expect(discardCompleted, isFalse);
    expect(client.cancelEntered, isFalse);
    client.releaseStop.complete();
    await Future.wait([stop, discard]);

    expect(client.maximumConcurrentCalls, 1);
    expect(File(client.path!).existsSync(), isFalse);
    expect(container.read(captureControllerProvider), const CaptureDraft());
  });

  test(
    'startup recovery is one-shot and cannot overwrite newer draft',
    () async {
      final photo = BlockingPhotoCaptureAdapter();
      final container = captureContainer(photo: photo);
      addTearDown(container.dispose);
      final controller = container.read(captureControllerProvider.notifier);
      controller.selectFormat(MemoryFormat.text);
      controller.updateText('Newer');
      photo.completeRecovery('/tmp/recovered.jpg');
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(captureControllerProvider).format,
        MemoryFormat.text,
      );
      expect(photo.recoveryCalls, 1);
    },
  );

  test('startup recovery handles no data, recovered data, and error', () async {
    final none = FakePhotoCaptureAdapter();
    final noneContainer = captureContainer(photo: none);
    addTearDown(noneContainer.dispose);
    noneContainer.read(captureControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(none.recoveryCalls, 1);
    expect(noneContainer.read(captureControllerProvider).hasDraft, isFalse);

    final recovered = FakePhotoCaptureAdapter(recovered: '/tmp/lost.jpg');
    final recoveredContainer = captureContainer(photo: recovered);
    addTearDown(recoveredContainer.dispose);
    recoveredContainer.read(captureControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(
      recoveredContainer.read(captureControllerProvider).photoPath,
      '/tmp/lost.jpg',
    );

    final failed = FakePhotoCaptureAdapter(recoveryError: StateError('lost'));
    final failedContainer = captureContainer(photo: failed);
    addTearDown(failedContainer.dispose);
    failedContainer.read(captureControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(
      failedContainer.read(captureControllerProvider).phase,
      CapturePhase.failed,
    );
  });

  test('manual no-data recovery restores the prior editing state', () async {
    final photo = FakePhotoCaptureAdapter();
    final container = captureContainer(photo: photo);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    await controller.recoverLostPhoto();

    expect(
      container.read(captureControllerProvider).phase,
      CapturePhase.editing,
    );
    expect(photo.recoveryCalls, 2);
  });

  test('disposed startup recovery deletes its stale result', () async {
    final photo = BlockingPhotoCaptureAdapter();
    final files = FakeCaptureFileAccess();
    final container = captureContainer(photo: photo, files: files);
    container.read(captureControllerProvider);
    container.dispose();
    photo.completeRecovery('/tmp/disposed.jpg');
    await Future<void>.delayed(Duration.zero);
    expect(files.deleted, contains('/tmp/disposed.jpg'));
  });

  test('teardown awaits late recovery before retrying real cleanup', () async {
    final root = await Directory.systemTemp.createTemp('recovery-dispose-');
    final support = await Directory.systemTemp.createTemp('recovery-support-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
      if (await support.exists()) await support.delete(recursive: true);
    });
    final capture = Directory(
      '${root.path}${Platform.pathSeparator}keepers-capture',
    )..createSync();
    final recovered = File('${capture.path}${Platform.pathSeparator}late.jpg')
      ..writeAsBytesSync([1]);
    final store = testEncryptedBlobStore(
      support,
      root,
      failPlaintextDeletes: 1,
    );
    final files = OwnedCaptureFileAccess(
      temporaryDirectory: () async => root,
      idFactory: () => 'snapshot',
      blobStore: () async => store,
    );
    final photo = BlockingPhotoCaptureAdapter();
    final container = captureContainer(photo: photo, files: files);
    container.read(captureControllerProvider);
    container.dispose();

    photo.completeRecovery(recovered.path);
    for (var attempt = 0; attempt < 100 && recovered.existsSync(); attempt++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(recovered.existsSync(), isFalse);
  });

  test(
    'teardown awaits direct photo replacement and retries its stale owner',
    () async {
      final root = await Directory.systemTemp.createTemp('accept-dispose-');
      final support = await Directory.systemTemp.createTemp(
        'accept-dispose-support-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        if (await support.exists()) await support.delete(recursive: true);
      });
      final capture = Directory(
        '${root.path}${Platform.pathSeparator}keepers-capture',
      )..createSync();
      final oldPhoto = File('${capture.path}${Platform.pathSeparator}old.jpg')
        ..writeAsBytesSync([1]);
      final newPhoto = File('${capture.path}${Platform.pathSeparator}new.jpg')
        ..writeAsBytesSync([2]);
      final secure = TestSecureBlobFileSystem(
        supportDirectory: support,
        captureTemporaryDirectory: root,
      );
      final store = EncryptedBlobStore(
        support,
        captureTemporaryDirectory: root,
        fileSystem: secure,
      );
      final owned = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'snapshot',
        blobStore: () async => store,
      );
      final files = BlockingFirstDeleteCaptureFileAccess(owned, secure);
      final recorder = FakeVoiceCaptureAdapter();
      final container = captureContainer(recorder: recorder, files: files);
      final controller = container.read(captureControllerProvider.notifier);
      await controller.acceptPhoto(oldPhoto.path);

      final replacing = controller.acceptPhoto(newPhoto.path);
      await files.firstDeleteEntered.future;
      container.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(recorder.disposes, 0);
      files.releaseFirstDelete.complete();
      await replacing;
      for (
        var attempt = 0;
        attempt < 100 && (newPhoto.existsSync() || recorder.disposes == 0);
        attempt++
      ) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(newPhoto.existsSync(), isFalse);
      expect(recorder.disposes, 1);
    },
  );

  test('cleanup remains failure-total when playback stop fails', () async {
    final files = FakeCaptureFileAccess();
    final playback = FakePlaybackAdapter(stopError: StateError('stuck'));
    final container = captureContainer(files: files, playback: playback);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    await controller.acceptPhoto('/tmp/photo.jpg');
    await controller.replacePrimary();
    expect(files.deleted, contains('/tmp/photo.jpg'));
    expect(
      container.read(captureControllerProvider).photoPath,
      '/tmp/photo.jpg',
    );
    expect(
      container.read(captureControllerProvider).phase,
      CapturePhase.failed,
    );
  });

  test('stale picker cleanup still deletes when playback stop fails', () async {
    final photo = BlockingPhotoCaptureAdapter();
    final files = FakeCaptureFileAccess();
    final playback = FakePlaybackAdapter(stopError: StateError('stuck'));
    final container = captureContainer(
      photo: photo,
      files: files,
      playback: playback,
    );
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    final pick = controller.pickPhoto(PhotoSource.library);
    await Future<void>.delayed(Duration.zero);
    final discard = controller.discard();
    photo.completeRecovery(null);
    photo.complete('/tmp/stale.jpg');
    await Future.wait([pick, discard]);
    expect(files.deleted, contains('/tmp/stale.jpg'));
  });

  test('failed recorder cancellation retains ownership for retry', () async {
    final recorder = FakeVoiceCaptureAdapter(
      cancelError: StateError('recorder still active'),
    );
    final container = captureContainer(recorder: recorder);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    await controller.selectFormat(MemoryFormat.voice);
    await controller.toggleRecording();
    await controller.discard();
    expect(container.read(captureControllerProvider).recordingActive, isTrue);
    expect(recorder.cancels, 1);

    recorder.cancelError = null;
    await controller.discard();
    expect(recorder.cancels, 2);
    expect(container.read(captureControllerProvider), const CaptureDraft());
  });

  test(
    'partial native start and failed cleanup remain owned until discard retry',
    () async {
      final root = await Directory.systemTemp.createTemp('partial-voice-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final client = PartialStartRecorderClient();
      final recorder = RecordVoiceCaptureAdapter(
        recorder: client,
        temporaryDirectory: root,
        recordingId: () => 'voice-1',
      );
      final container = captureContainer(recorder: recorder);
      addTearDown(container.dispose);
      final controller = container.read(captureControllerProvider.notifier);
      await controller.selectFormat(MemoryFormat.voice);

      await controller.toggleRecording();

      expect(container.read(captureControllerProvider).recordingActive, isTrue);
      final path = client.path!;
      await Directory(path).delete();
      await File(path).writeAsBytes([7, 8, 9]);
      client.cancelError = null;
      await controller.discard();
      expect(File(path).existsSync(), isFalse);
    },
  );

  test('double pick and save during pick are serialized', () async {
    final photo = BlockingPhotoCaptureAdapter();
    var saves = 0;
    final container = captureContainer(
      photo: photo,
      save: (request) async {
        saves++;
        return request.metadata;
      },
    );
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    final first = controller.pickPhoto(PhotoSource.library);
    final second = controller.pickPhoto(PhotoSource.camera);
    await controller.save();
    expect(photo.pickCalls, 1);
    expect(saves, 0);
    photo.complete(null);
    await Future.wait([first, second]);
  });

  test('discard cannot race a save whose commit outcome is pending', () async {
    final persistence = BlockingPersistence();
    final files = FakeCaptureFileAccess();
    final container = captureContainer(save: persistence.call, files: files);
    addTearDown(container.dispose);
    final controller = container.read(captureControllerProvider.notifier);
    await controller.acceptPhoto('/tmp/photo.jpg');
    final saving = controller.save();
    await Future<void>.delayed(Duration.zero);
    await controller.discard();
    expect(
      container.read(captureControllerProvider).phase,
      CapturePhase.saving,
    );
    expect(files.deleted, isEmpty);
    persistence.complete();
    await saving;
    expect(container.read(captureControllerProvider).phase, CapturePhase.saved);
  });

  test(
    'committed cleanup retry removes real plaintext without persisting again',
    () async {
      final root = await Directory.systemTemp.createTemp('capture-retry-');
      final support = await Directory.systemTemp.createTemp('capture-support-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        if (await support.exists()) await support.delete(recursive: true);
      });
      final capture = Directory(
        '${root.path}${Platform.pathSeparator}keepers-capture',
      )..createSync();
      final original = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([4, 5, 6]);
      final store = testEncryptedBlobStore(
        support,
        root,
        failPlaintextDeletes: 1,
      );
      final files = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'snapshot',
        blobStore: () async => store,
      );
      var persistenceCalls = 0;
      final container = captureContainer(
        files: files,
        save: (request) async {
          persistenceCalls++;
          return request.metadata.copyWith(
            blobRef: 'entries/blobs/entry-1.keeper',
          );
        },
      );
      addTearDown(container.dispose);
      final controller = container.read(captureControllerProvider.notifier);
      await controller.acceptPhoto(original.path);
      await controller.save();
      expect(
        container.read(captureControllerProvider).phase,
        CapturePhase.committedCleanup,
      );
      expect(original.existsSync(), isTrue);

      await controller.retryCleanup();

      expect(persistenceCalls, 1);
      expect(
        container.read(captureControllerProvider).phase,
        CapturePhase.saved,
      );
      expect(original.existsSync(), isFalse);
      expect(capture.listSync(recursive: true).whereType<File>(), isEmpty);
    },
  );

  test(
    'committed cleanup is retried by teardown without persisting again',
    () async {
      final root = await Directory.systemTemp.createTemp('capture-dispose-');
      final support = await Directory.systemTemp.createTemp('capture-support-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        if (await support.exists()) await support.delete(recursive: true);
      });
      final capture = Directory(
        '${root.path}${Platform.pathSeparator}keepers-capture',
      )..createSync();
      final original = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([4, 5, 6]);
      final store = testEncryptedBlobStore(
        support,
        root,
        failPlaintextDeletes: 1,
      );
      final files = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'snapshot',
        blobStore: () async => store,
      );
      var persistenceCalls = 0;
      final container = captureContainer(
        files: files,
        save: (request) async {
          persistenceCalls++;
          return request.metadata.copyWith(
            blobRef: 'entries/blobs/entry-1.keeper',
          );
        },
      );
      final controller = container.read(captureControllerProvider.notifier);
      await controller.acceptPhoto(original.path);
      await controller.save();
      expect(
        container.read(captureControllerProvider).phase,
        CapturePhase.committedCleanup,
      );

      container.dispose();
      for (var attempt = 0; attempt < 100 && original.existsSync(); attempt++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(persistenceCalls, 1);
      expect(original.existsSync(), isFalse);
      expect(capture.listSync(recursive: true).whereType<File>(), isEmpty);
    },
  );

  test(
    'registry cleanup followed by media release finishes committed cleanup',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'capture-registry-retry-',
      );
      final support = await Directory.systemTemp.createTemp(
        'capture-registry-retry-support-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        if (await support.exists()) await support.delete(recursive: true);
      });
      final capture = Directory(
        '${root.path}${Platform.pathSeparator}keepers-capture',
      )..createSync();
      final original = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([4, 5, 6]);
      final secure = TestSecureBlobFileSystem(
        supportDirectory: support,
        captureTemporaryDirectory: root,
        failCaptureSnapshotDeletes: 1,
      );
      final store = EncryptedBlobStore(
        support,
        captureTemporaryDirectory: root,
        fileSystem: secure,
      );
      final files = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'snapshot',
        blobStore: () async => store,
      );
      var persistenceCalls = 0;
      final container = captureContainer(
        files: files,
        save: (request) async {
          persistenceCalls++;
          return request.metadata.copyWith(
            blobRef: 'entries/blobs/entry-1.keeper',
          );
        },
      );
      addTearDown(container.dispose);
      final controller = container.read(captureControllerProvider.notifier);
      await controller.acceptPhoto(original.path);
      await controller.save();
      expect(
        container.read(captureControllerProvider).phase,
        CapturePhase.committedCleanup,
      );

      await controller.retryCleanup();

      expect(persistenceCalls, 1);
      expect(
        container.read(captureControllerProvider).phase,
        CapturePhase.saved,
      );
      await files.retryPendingCleanup();
      expect(capture.listSync(recursive: true).whereType<File>(), isEmpty);
    },
  );

  test(
    'teardown does not re-register a snapshot cleaned by the registry',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'capture-registry-dispose-',
      );
      final support = await Directory.systemTemp.createTemp(
        'capture-registry-dispose-support-',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        if (await support.exists()) await support.delete(recursive: true);
      });
      final capture = Directory(
        '${root.path}${Platform.pathSeparator}keepers-capture',
      )..createSync();
      final original = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([4, 5, 6]);
      final secure = TestSecureBlobFileSystem(
        supportDirectory: support,
        captureTemporaryDirectory: root,
        failCaptureSnapshotDeletes: 1,
      );
      final store = EncryptedBlobStore(
        support,
        captureTemporaryDirectory: root,
        fileSystem: secure,
      );
      final files = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'snapshot',
        blobStore: () async => store,
      );
      final recorder = FakeVoiceCaptureAdapter();
      var persistenceCalls = 0;
      final container = captureContainer(
        files: files,
        recorder: recorder,
        save: (request) async {
          persistenceCalls++;
          return request.metadata.copyWith(
            blobRef: 'entries/blobs/entry-1.keeper',
          );
        },
      );
      final controller = container.read(captureControllerProvider.notifier);
      await controller.acceptPhoto(original.path);
      await controller.save();
      expect(
        container.read(captureControllerProvider).phase,
        CapturePhase.committedCleanup,
      );

      container.dispose();
      for (
        var attempt = 0;
        attempt < 100 && recorder.disposes == 0;
        attempt++
      ) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(recorder.disposes, 1);
      expect(persistenceCalls, 1);
      await files.retryPendingCleanup();
      expect(capture.listSync(recursive: true).whereType<File>(), isEmpty);
    },
  );
}

ProviderContainer captureContainer({
  PhotoCaptureAdapter? photo,
  VoiceCaptureAdapter? recorder,
  AudioPlaybackAdapter? playback,
  CaptureFileAccess? files,
  EntrySave? save,
}) => ProviderContainer(
  overrides: [
    photoCaptureAdapterProvider.overrideWithValue(
      photo ?? FakePhotoCaptureAdapter(),
    ),
    voiceCaptureAdapterProvider.overrideWithValue(
      recorder ?? FakeVoiceCaptureAdapter(),
    ),
    audioPlaybackAdapterProvider.overrideWithValue(
      playback ?? FakePlaybackAdapter(),
    ),
    captureFileAccessProvider.overrideWithValue(
      files ?? FakeCaptureFileAccess(),
    ),
    entrySaveProvider.overrideWithValue(save ?? _successfulSave),
    localIdentityProvider.overrideWithValue(const AsyncValue.data(identity)),
    idFactoryProvider.overrideWithValue(() => 'entry-1'),
    utcNowProvider.overrideWithValue(() => DateTime.utc(2026, 9, 1)),
  ],
);

Future<EntryMetadata> _successfulSave(EntrySaveRequest request) async =>
    request.metadata.copyWith(blobRef: 'entries/blobs/entry-1.keeper');

final class FakePhotoCaptureAdapter implements PhotoCaptureAdapter {
  FakePhotoCaptureAdapter({
    this.picked,
    this.recovered,
    this.error,
    this.recoveryError,
  });
  final String? picked;
  final String? recovered;
  final Object? error;
  final Object? recoveryError;
  int recoveryCalls = 0;

  @override
  Future<String?> pick(PhotoSource source) async {
    if (error != null) throw error!;
    return picked;
  }

  @override
  Future<String?> recoverLostPhoto() async {
    recoveryCalls++;
    if (recoveryError != null) throw recoveryError!;
    return recovered;
  }
}

class FakeVoiceCaptureAdapter implements VoiceCaptureAdapter {
  FakeVoiceCaptureAdapter({
    this.permission = true,
    this.startError,
    this.stopError,
    this.cancelError,
  });
  final bool permission;
  final Object? startError;
  final Object? stopError;
  Object? cancelError;
  bool recording = false;
  int cancels = 0;
  int starts = 0;
  int stops = 0;
  int disposes = 0;

  @override
  Stream<double> get amplitudes => const Stream.empty();
  @override
  bool get ownsPlaintext => recording;

  @override
  Future<void> cancel() async {
    cancels++;
    if (cancelError != null) throw cancelError!;
    recording = false;
  }

  @override
  Future<void> dispose() async {
    disposes++;
    await cancel();
  }

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start() async {
    starts++;
    recording = true;
    if (startError != null) throw startError!;
  }

  @override
  Future<VoiceRecording?> stop() async {
    stops++;
    if (stopError != null) throw stopError!;
    recording = false;
    return const VoiceRecording(
      path: '/tmp/voice.m4a',
      duration: Duration(seconds: 2),
    );
  }
}

final class FakePlaybackAdapter implements AudioPlaybackAdapter {
  FakePlaybackAdapter({this.stopError});
  final Object? stopError;
  int stops = 0;
  int disposes = 0;
  final playedFiles = <String>[];
  @override
  Future<void> playBytes(Uint8List bytes) async {}
  @override
  Future<void> playFile(String path) async => playedFiles.add(path);
  @override
  Future<void> stop() async {
    stops++;
    if (stopError != null) throw stopError!;
  }

  @override
  Future<void> dispose() async {
    disposes++;
  }
}

final class FakeCaptureFileAccess implements CaptureFileAccess {
  FakeCaptureFileAccess({this.deleteError});
  final Object? deleteError;
  final List<String> deleted = [];
  @override
  Future<CaptureMedia> read(String path) async => CaptureMedia(
    bytes: Uint8List.fromList([1, 2, 3]),
    extension: path.split('.').last,
    plaintextRef: 'keepers-capture/${path.split('/').last}',
    release: () async => deleted.add(
      '/tmp/${path.split('/').last.split('.').first}-save.${path.split('.').last}',
    ),
  );
  @override
  Future<void> deleteAll(Iterable<String> paths) async {
    deleted.addAll(paths);
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<void> retryPendingCleanup() async {}
}

final class BlockingFirstDeleteCaptureFileAccess implements CaptureFileAccess {
  BlockingFirstDeleteCaptureFileAccess(this.delegate, this.secure);
  final CaptureFileAccess delegate;
  final TestSecureBlobFileSystem secure;
  final firstDeleteEntered = Completer<void>();
  final releaseFirstDelete = Completer<void>();
  var _deleteCalls = 0;

  @override
  Future<CaptureMedia> read(String path) => delegate.read(path);

  @override
  Future<void> deleteAll(Iterable<String> paths) async {
    _deleteCalls++;
    if (_deleteCalls == 1) {
      firstDeleteEntered.complete();
      await releaseFirstDelete.future;
      await delegate.deleteAll(paths);
      secure.failPlaintextDeletes = 1;
      return;
    }
    await delegate.deleteAll(paths);
  }

  @override
  Future<void> retryPendingCleanup() => delegate.retryPendingCleanup();
}

final class BlockingPhotoCaptureAdapter implements PhotoCaptureAdapter {
  final _pick = Completer<String?>();
  final _recovery = Completer<String?>();
  int recoveryCalls = 0;
  int pickCalls = 0;
  @override
  Future<String?> pick(PhotoSource source) {
    pickCalls++;
    return _pick.future;
  }

  @override
  Future<String?> recoverLostPhoto() {
    recoveryCalls++;
    return _recovery.future;
  }

  void complete(String? path) => _pick.complete(path);
  void completeRecovery(String? path) => _recovery.complete(path);
}

final class BlockingVoiceCaptureAdapter extends FakeVoiceCaptureAdapter {
  final _start = Completer<void>();
  @override
  Future<void> start() async {
    starts++;
    await _start.future;
    recording = true;
  }

  void completeStart() => _start.complete();
}

final class BlockingPersistence {
  final completer = Completer<void>();
  int calls = 0;
  final requests = <EntrySaveRequest>[];
  Future<EntryMetadata> call(EntrySaveRequest request) async {
    calls++;
    requests.add(request);
    await completer.future;
    return request.metadata.copyWith(blobRef: 'entries/blobs/entry-1.keeper');
  }

  void complete() => completer.complete();
}

final class PartialStartRecorderClient implements VoiceRecorderClient {
  String? path;
  Object? cancelError = StateError('plugin cancel failed');
  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      const Stream.empty();
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    this.path = path;
    await Directory(path).create();
    throw StateError('native start failed after allocation');
  }

  @override
  Future<String?> stop() async => null;
  @override
  Future<void> cancel() async {
    if (cancelError != null) throw cancelError!;
  }

  @override
  Future<void> dispose() async {}
}

final class BlockingStopRecorderClient implements VoiceRecorderClient {
  final stopEntered = Completer<void>();
  final releaseStop = Completer<void>();
  String? path;
  bool cancelEntered = false;
  int _concurrentCalls = 0;
  int maximumConcurrentCalls = 0;

  void _enter() {
    _concurrentCalls++;
    if (_concurrentCalls > maximumConcurrentCalls) {
      maximumConcurrentCalls = _concurrentCalls;
    }
  }

  void _leave() => _concurrentCalls--;

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      const Stream.empty();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    _enter();
    try {
      this.path = path;
      await File(path).writeAsBytes([1, 2, 3]);
    } finally {
      _leave();
    }
  }

  @override
  Future<String?> stop() async {
    _enter();
    try {
      stopEntered.complete();
      await releaseStop.future;
      return path;
    } finally {
      _leave();
    }
  }

  @override
  Future<void> cancel() async {
    _enter();
    try {
      cancelEntered = true;
    } finally {
      _leave();
    }
  }

  @override
  Future<void> dispose() async {}
}

final class StopResultRecorderClient implements VoiceRecorderClient {
  StopResultRecorderClient({this.cancelError});

  String? path;
  String? stopResult;
  Object? cancelError;
  int cancels = 0;
  int starts = 0;

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      const Stream.empty();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    starts++;
    this.path = path;
    await File(path).writeAsBytes([1, 2, 3]);
  }

  @override
  Future<String?> stop() async => stopResult;

  @override
  Future<void> cancel() async {
    cancels++;
    if (cancelError != null) throw cancelError!;
  }

  @override
  Future<void> dispose() async {}
}
