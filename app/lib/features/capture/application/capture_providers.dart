// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/capsule/data/capsule_repository.dart';
import 'package:keepers/features/capture/data/audio_playback_adapter.dart';
import 'package:keepers/features/capture/data/encrypted_blob_store.dart';
import 'package:keepers/features/capture/data/entry_cipher.dart';
import 'package:keepers/features/capture/data/entry_key_resolver.dart';
import 'package:keepers/features/capture/data/entry_payload_codec.dart';
import 'package:keepers/features/capture/data/entry_persistence_service.dart';
import 'package:keepers/features/capture/data/entry_repository.dart';
import 'package:keepers/features/capture/data/photo_capture_adapter.dart';
import 'package:keepers/features/capture/data/voice_capture_adapter.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

typedef EntrySave = Future<EntryMetadata> Function(EntrySaveRequest request);

final class CaptureMedia {
  CaptureMedia({
    required Uint8List bytes,
    required this.extension,
    required this.plaintextRef,
    Future<void> Function()? release,
  }) : bytes = Uint8List.fromList(bytes),
       _release = release ?? _noop;
  final Uint8List bytes;
  final String extension;
  final String plaintextRef;
  final Future<void> Function() _release;
  bool _released = false;
  Future<void> release() async {
    if (_released) return;
    await _release();
    _released = true;
  }

  static Future<void> _noop() async {}
}

final class CaptureFileAccessFailure implements Exception {
  CaptureFileAccessFailure(Iterable<Object> causes)
    : causes = List<Object>.unmodifiable(causes);
  final List<Object> causes;
}

abstract interface class CaptureFileAccess {
  Future<CaptureMedia> read(String path);
  Future<void> deleteAll(Iterable<String> paths);
  Future<void> retryPendingCleanup();
}

final class CaptureCleanupRegistry {
  CaptureCleanupRegistry({
    required Future<Directory> temporaryDirectory,
    required Future<EncryptedBlobStore> blobStore,
  }) : _temporaryDirectory = temporaryDirectory,
       _blobStore = blobStore;

  final Future<Directory> _temporaryDirectory;
  final Future<EncryptedBlobStore> _blobStore;
  final Set<String> _pending = <String>{};
  final Set<CaptureSnapshotOwner> _pendingSnapshots =
      Set<CaptureSnapshotOwner>.identity();
  final Set<CaptureSnapshotOwner> _completedSnapshots =
      Set<CaptureSnapshotOwner>.identity();
  Future<void> _operationTail = Future<void>.value();

  Future<void> registerRelative(String relativeRef) => _serialize(() async {
    final root = await _temporaryDirectory;
    _validateRelative(root, relativeRef);
    _pending.add(relativeRef);
  });

  Future<void> registerSnapshot(CaptureSnapshotOwner snapshot) =>
      _serialize(() async {
        if (_completedSnapshots.contains(snapshot)) return;
        _pendingSnapshots.add(snapshot);
      });

  Future<void> cleanupSnapshot(CaptureSnapshotOwner snapshot) =>
      _serialize(() async {
        if (_completedSnapshots.contains(snapshot)) return;
        _pendingSnapshots.add(snapshot);
        await _cleanupSnapshots(<CaptureSnapshotOwner>{snapshot});
      });

  Future<void> cleanupRelative(String relativeRef) => _serialize(() async {
    final root = await _temporaryDirectory;
    _validateRelative(root, relativeRef);
    _pending.add(relativeRef);
    await _cleanup(<String>{relativeRef});
  });

  Future<void> cleanupAbsolute(Iterable<String> paths) => _serialize(() async {
    final root = await _temporaryDirectory;
    final refs = paths.map((path) => _relativeOwned(root, path)).toSet();
    _pending.addAll(refs);
    await _cleanup(refs);
  });

  Future<void> retryPending() => _serialize(() async {
    final failures = <Object>[];
    try {
      await _cleanup(Set<String>.of(_pending));
    } on Object catch (error) {
      failures.add(error);
    }
    try {
      await _cleanupSnapshots(
        Set<CaptureSnapshotOwner>.identity()..addAll(_pendingSnapshots),
      );
    } on Object catch (error) {
      failures.add(error);
    }
    if (failures.isNotEmpty) throw CaptureFileAccessFailure(failures);
  });

  Future<void> _cleanupSnapshots(Set<CaptureSnapshotOwner> snapshots) async {
    final store = await _blobStore;
    final failures = <Object>[];
    for (final snapshot in snapshots) {
      try {
        await store.deleteCaptureSnapshot(snapshot);
        _pendingSnapshots.remove(snapshot);
        _completedSnapshots.add(snapshot);
      } on CaptureSnapshotStoreFailure catch (error) {
        if (error.residualSnapshot == null) {
          _pendingSnapshots.remove(snapshot);
          _completedSnapshots.add(snapshot);
        }
        failures.add(error);
      } on Object catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) throw CaptureFileAccessFailure(failures);
  }

  Future<void> _cleanup(Set<String> refs) async {
    final store = await _blobStore;
    final root = await _temporaryDirectory;
    final failures = <Object>[];
    for (final ref in refs) {
      try {
        final authority = await store.validatePlaintextRefs([
          CapturePlaintextRef(ref),
        ]);
        await store.deletePlaintext(authority);
        _pending.remove(ref);
        if (p.dirname(ref) != 'keepers-capture') {
          try {
            await Directory(p.join(root.path, p.dirname(ref))).delete();
          } on FileSystemException {
            // Empty snapshot directories are secondary to plaintext removal.
          }
        }
      } on Object catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) throw CaptureFileAccessFailure(failures);
  }

  String _relativeOwned(Directory root, String path) {
    final normalizedRoot = p.normalize(
      p.join(root.absolute.path, 'keepers-capture'),
    );
    final normalizedPath = p.normalize(File(path).absolute.path);
    if (!p.isWithin(normalizedRoot, normalizedPath)) {
      throw ArgumentError.value(
        path,
        'path',
        'Capture media is outside the owned directory',
      );
    }
    final relative = p.relative(normalizedPath, from: root.absolute.path);
    _validateRelative(root, relative);
    return relative;
  }

  void _validateRelative(Directory root, String relativeRef) {
    final parts = p.split(relativeRef);
    final absolute = p.normalize(p.join(root.absolute.path, relativeRef));
    final captureRoot = p.normalize(
      p.join(root.absolute.path, 'keepers-capture'),
    );
    if (p.isAbsolute(relativeRef) ||
        parts.length < 2 ||
        parts.first != 'keepers-capture' ||
        !p.isWithin(captureRoot, absolute)) {
      throw ArgumentError.value(relativeRef, 'relativeRef');
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

final class OwnedCaptureFileAccess implements CaptureFileAccess {
  OwnedCaptureFileAccess({
    required Future<Directory> Function() temporaryDirectory,
    required String Function() idFactory,
    required Future<EncryptedBlobStore> Function() blobStore,
  }) : _temporaryDirectory = temporaryDirectory(),
       _idFactory = idFactory,
       _blobStore = blobStore() {
    _cleanupRegistry = CaptureCleanupRegistry(
      temporaryDirectory: _temporaryDirectory,
      blobStore: _blobStore,
    );
  }

  final Future<Directory> _temporaryDirectory;
  final String Function() _idFactory;
  final Future<EncryptedBlobStore> _blobStore;
  late final CaptureCleanupRegistry _cleanupRegistry;

  @override
  Future<CaptureMedia> read(String path) async {
    final root = await _temporaryDirectory;
    final relativeSource = _relativeOwned(root, path);
    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (!RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension)) {
      throw ArgumentError.value(
        path,
        'path',
        'Capture media extension is invalid',
      );
    }
    final snapshotId = _idFactory();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(snapshotId)) {
      throw ArgumentError.value(
        snapshotId,
        'idFactory',
        'Capture snapshot identifiers must use the safe segment alphabet',
      );
    }
    final store = await _blobStore;
    try {
      final snapshot = await store.createCaptureSnapshot(
        relativeSource: relativeSource,
        snapshotId: snapshotId,
        extension: extension,
      );
      await _cleanupRegistry.registerSnapshot(snapshot);
      return CaptureMedia(
        bytes: snapshot.bytes,
        extension: extension,
        plaintextRef: snapshot.relativePath,
        release: () => _cleanupRegistry.cleanupSnapshot(snapshot),
      );
    } on CaptureSnapshotStoreFailure catch (error) {
      final failures = <Object>[error.primary, ...error.additionalFailures];
      final residual = error.residualSnapshot;
      if (residual != null) {
        await _cleanupRegistry.registerSnapshot(residual);
        try {
          await _cleanupRegistry.cleanupSnapshot(residual);
        } on Object catch (cleanupError) {
          failures.add(cleanupError);
        }
      }
      if (failures.length == 1) throw failures.single;
      throw CaptureFileAccessFailure(failures);
    }
  }

  @override
  Future<void> deleteAll(Iterable<String> paths) async {
    await _cleanupRegistry.cleanupAbsolute(paths);
  }

  @override
  Future<void> retryPendingCleanup() => _cleanupRegistry.retryPending();

  String _relativeOwned(Directory root, String path) {
    final captureRoot = Directory(
      p.join(root.absolute.path, 'keepers-capture'),
    );
    final normalizedRoot = p.normalize(captureRoot.path);
    final normalizedPath = p.normalize(File(path).absolute.path);
    if (!p.isWithin(normalizedRoot, normalizedPath)) {
      throw ArgumentError.value(
        path,
        'path',
        'Capture media is outside the owned directory',
      );
    }
    final relative = p.relative(normalizedPath, from: root.absolute.path);
    final segments = p.split(relative);
    if (segments.isEmpty || segments.first != 'keepers-capture') {
      throw ArgumentError.value(path, 'path', 'Capture path is not owned');
    }
    return relative;
  }
}

final temporaryDirectoryProvider = FutureProvider<Directory>(
  (ref) => getTemporaryDirectory(),
);

final applicationSupportDirectoryProvider = FutureProvider<Directory>(
  (ref) => getApplicationSupportDirectory(),
);

final photoCaptureAdapterProvider = Provider<PhotoCaptureAdapter>((ref) {
  final temporaryDirectory = ref.watch(temporaryDirectoryProvider.future);
  final idFactory = ref.watch(idFactoryProvider);
  return ImagePickerPhotoCaptureAdapter(
    temporaryDirectory: () => temporaryDirectory,
    idFactory: idFactory,
  );
});

final voiceCaptureAdapterProvider = Provider<VoiceCaptureAdapter>((ref) {
  final temporaryDirectory = ref.watch(temporaryDirectoryProvider.future);
  final recordingId = ref.watch(idFactoryProvider);
  final adapter = RecordVoiceCaptureAdapter(
    recorder: AudioRecorderClient(AudioRecorder()),
    temporaryDirectoryFactory: () => temporaryDirectory,
    recordingId: recordingId,
  );
  return adapter;
});

final audioPlaybackAdapterProvider = Provider<AudioPlaybackAdapter>((ref) {
  final temporaryDirectory = ref.watch(temporaryDirectoryProvider.future);
  final adapter = AudioplayersPlaybackAdapter(
    player: AudioplayersDeviceFileAudioPlayer(AudioPlayer()),
    temporaryDirectory: () => temporaryDirectory,
    idFactory: ref.watch(idFactoryProvider),
  );
  return adapter;
});

final captureFileAccessProvider = Provider<CaptureFileAccess>((ref) {
  final temporaryDirectory = ref.watch(temporaryDirectoryProvider.future);
  final blobStore = ref.watch(entryBlobStoreProvider.future);
  final idFactory = ref.watch(idFactoryProvider);
  return OwnedCaptureFileAccess(
    temporaryDirectory: () => temporaryDirectory,
    idFactory: idFactory,
    blobStore: () => blobStore,
  );
});

final entryBlobStoreProvider = FutureProvider<EncryptedBlobStore>((ref) async {
  final supportFuture = ref.watch(applicationSupportDirectoryProvider.future);
  final temporaryFuture = ref.watch(temporaryDirectoryProvider.future);
  final support = await supportFuture;
  final temporary = await temporaryFuture;
  return EncryptedBlobStore(support, captureTemporaryDirectory: temporary);
});

final capsuleRepositoryProvider = Provider<CapsuleRepository>(
  (ref) => const CapsuleRepository(),
);

final entryPersistenceServiceProvider = FutureProvider<EntryPersistenceService>(
  (ref) async {
    final identityKeys = ref.watch(identityKeyServiceProvider);
    final blobStore = ref.watch(entryBlobStoreProvider.future);
    final database = ref.watch(databaseProvider.future);
    return EntryPersistenceService(
      codec: const EntryPayloadCodec(),
      keyResolver: EntryKeyResolver(identityKeys),
      cipher: EntryCipher(),
      blobStore: await blobStore,
      repository: EntryRepository(),
      capsuleRepository: ref.watch(capsuleRepositoryProvider),
      database: () => database,
    );
  },
);

final entrySaveProvider = Provider<EntrySave>((ref) {
  final service = ref.watch(entryPersistenceServiceProvider.future);
  return (request) async => (await service).save(request);
});
