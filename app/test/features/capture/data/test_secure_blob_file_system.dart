import 'dart:io';
import 'dart:typed_data';

import 'package:keepers/features/capture/data/encrypted_blob_store.dart';
import 'package:path/path.dart' as p;

/// A deliberately test-only Dart-IO model. Production tests for confinement
/// live in posix_secure_blob_file_system_test.dart and exercise the FFI backend.
final class TestSecureBlobFileSystem
    implements SecureBlobFileSystem, SecureCaptureFileSystem {
  TestSecureBlobFileSystem({
    required this.supportDirectory,
    required this.captureTemporaryDirectory,
    this.finalizeError,
    this.finalizeAdditionalFailures = const [],
    this.blockAttemptCleanup = false,
    this.finalBlobMayRemain = false,
    this.failPlaintextDeletes = 0,
    this.failCaptureSnapshotDeletes = 0,
    this.failCaptureSnapshotCloseAfterCleanup = 0,
    this.captureBoundaryHook,
    this.failCaptureSourceClose = false,
  });

  final Directory supportDirectory;
  final Directory captureTemporaryDirectory;
  final Object? finalizeError;
  final List<EntrySaveCause> finalizeAdditionalFailures;
  final bool blockAttemptCleanup;
  final bool finalBlobMayRemain;
  int failPlaintextDeletes;
  int failCaptureSnapshotDeletes;
  int failCaptureSnapshotCloseAfterCleanup;
  int captureSnapshotCleanupCalls = 0;
  final PosixFileBoundaryHook? captureBoundaryHook;
  final bool failCaptureSourceClose;
  final Object _token = Object();
  final Set<SecurePublishedBlob> _consumedPublications = Set.identity();
  final Set<SecurePlaintextCleanup> _consumedPlaintext = Set.identity();
  final Set<SecureCaptureSnapshot> _cleanedSnapshots = Set.identity();
  int _nextInode = 1;

  @override
  Future<SecureStagedBlob> stage(Uint8List encryptedBytes) async {
    Directory? attempt;
    try {
      final staging = Directory(
        p.join(supportDirectory.path, 'entries', 'staging'),
      );
      await staging.create(recursive: true);
      await Directory(p.join(supportDirectory.path, 'entries', 'blobs'))
          .create(recursive: true);
      attempt = await staging.createTemp('attempt-');
      final file = File(p.join(attempt.path, 'payload.part'));
      await file.writeAsBytes(encryptedBytes, flush: true);
      return TestStagedBlob(attempt, file);
    } on Object catch (error, stackTrace) {
      var mayRemain = false;
      final additional = <EntrySaveCause>[];
      if (attempt != null) {
        try {
          await attempt.delete(recursive: true);
        } on Object catch (cleanupError, cleanupStackTrace) {
          mayRemain = true;
          additional.add(
            EntrySaveCause(
              phase: EntrySavePhase.stagingCleanup,
              error: cleanupError,
              stackTrace: cleanupStackTrace,
            ),
          );
        }
      }
      throw SecureBlobFileSystemFailure(
        primary: EntrySaveCause(
          phase: EntrySavePhase.stageBlob,
          error: error,
          stackTrace: stackTrace,
        ),
        additionalFailures: additional,
        publishedBlob: null,
        stagingMayRemain: mayRemain,
      );
    }
  }

  @override
  Future<SecurePublishedBlob> finalize(
    SecureStagedBlob staged, {
    required String destinationName,
    required String publishedRef,
  }) async {
    final value = staged as TestStagedBlob;
    EntrySaveCause? primary;
    final additional = <EntrySaveCause>[];
    TestPublishedBlob? publication;
    try {
      if (finalizeError != null) {
        if (blockAttemptCleanup) {
          await value.attempt.delete(recursive: true);
          await File(value.attempt.path).writeAsString('cleanup blocker');
        }
        throw finalizeError!;
      }
      final finalFile = File(
        p.join(supportDirectory.path, 'entries', 'blobs', destinationName),
      );
      await finalFile.create(exclusive: true);
      await finalFile.writeAsBytes(await value.file.readAsBytes(), flush: true);
      publication = TestPublishedBlob(
        token: _token,
        destinationName: destinationName,
        publishedRef: publishedRef,
        identity: SecureFileIdentity(device: 0, inode: _nextInode++),
      );
    } on Object catch (error, stackTrace) {
      primary = EntrySaveCause(
        phase: EntrySavePhase.finalizeBlob,
        error: error,
        stackTrace: stackTrace,
      );
      additional.addAll(finalizeAdditionalFailures);
    }
    try {
      if (await FileSystemEntity.type(value.attempt.path, followLinks: false) ==
          FileSystemEntityType.directory) {
        await value.attempt.delete(recursive: true);
      } else if (await FileSystemEntity.type(
            value.attempt.path,
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException(
          'Attempt cleanup requires a directory',
          value.attempt.path,
        );
      }
    } on Object catch (error, stackTrace) {
      final failure = EntrySaveCause(
        phase: EntrySavePhase.stagingCleanup,
        error: error,
        stackTrace: stackTrace,
      );
      if (primary == null) {
        primary = failure;
      } else {
        additional.add(failure);
      }
    }
    if (primary != null) {
      throw SecureBlobFileSystemFailure(
        primary: primary,
        additionalFailures: additional,
        publishedBlob: publication,
        stagingMayRemain:
            await FileSystemEntity.type(
              value.attempt.path,
              followLinks: false,
            ) !=
            FileSystemEntityType.notFound,
        finalBlobMayRemain: finalBlobMayRemain,
      );
    }
    return publication!;
  }

  @override
  Future<Uint8List> readBlob(String destinationName) =>
      File(p.join(supportDirectory.path, 'entries', 'blobs', destinationName))
          .readAsBytes();

  @override
  Future<bool> blobExists(String destinationName) =>
      File(p.join(supportDirectory.path, 'entries', 'blobs', destinationName))
          .exists();

  @override
  Future<void> rollbackBlob(SecurePublishedBlob published) async {
    if (published is! TestPublishedBlob ||
        !identical(published.token, _token) ||
        !_consumedPublications.add(published)) {
      throw ArgumentError.value(published, 'published');
    }
    final file = File(
      p.join(
        supportDirectory.path,
        'entries',
        'blobs',
        published.destinationName,
      ),
    );
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<SecureCaptureSnapshot> createCaptureSnapshot({
    required List<String> sourceSegments,
    required String snapshotId,
    required String extension,
  }) async {
    if (sourceSegments.length != 2 ||
        sourceSegments.first != 'keepers-capture') {
      throw ArgumentError.value(sourceSegments, 'sourceSegments');
    }
    final source = File(
      p.joinAll([captureTemporaryDirectory.path, ...sourceSegments]),
    );
    final type = await FileSystemEntity.type(source.path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw FileSystemException(
        'Capture source must be a real file',
        source.path,
      );
    }
    captureBoundaryHook?.call(
      PosixFileBoundary.beforeCaptureSourceOpen,
      PosixFileBoundaryContext(
        supportRootPath: supportDirectory.path,
        captureRootPath: captureTemporaryDirectory.path,
        plaintextSegments: sourceSegments,
      ),
    );
    final input = await source.open(mode: FileMode.read);
    Directory? attempt;
    TestCaptureSnapshot? owner;
    try {
      captureBoundaryHook?.call(
        PosixFileBoundary.afterCaptureSourceOpen,
        PosixFileBoundaryContext(
          supportRootPath: supportDirectory.path,
          captureRootPath: captureTemporaryDirectory.path,
          plaintextSegments: sourceSegments,
        ),
      );
      final capture = Directory(
        p.join(captureTemporaryDirectory.path, 'keepers-capture'),
      );
      attempt = await capture.createTemp('snapshot-');
      final snapshot = File(p.join(attempt.path, 'payload.$extension'));
      final relativePath = p.relative(
        snapshot.path,
        from: captureTemporaryDirectory.path,
      );
      owner = TestCaptureSnapshot(
        token: _token,
        relativePath: relativePath,
        file: snapshot,
        attempt: attempt,
      );
      captureBoundaryHook?.call(
        PosixFileBoundary.afterCaptureAttemptCreateBeforeOpen,
        PosixFileBoundaryContext(
          supportRootPath: supportDirectory.path,
          captureRootPath: captureTemporaryDirectory.path,
          attemptName: p.basename(attempt.path),
          plaintextSegments: p.split(relativePath),
        ),
      );
      captureBoundaryHook?.call(
        PosixFileBoundary.afterCaptureAttemptOpenBeforeIdentity,
        PosixFileBoundaryContext(
          supportRootPath: supportDirectory.path,
          captureRootPath: captureTemporaryDirectory.path,
          attemptName: p.basename(attempt.path),
          plaintextSegments: p.split(relativePath),
        ),
      );
      captureBoundaryHook?.call(
        PosixFileBoundary.beforeCaptureSnapshotCreate,
        PosixFileBoundaryContext(
          supportRootPath: supportDirectory.path,
          captureRootPath: captureTemporaryDirectory.path,
          attemptName: p.basename(attempt.path),
          plaintextSegments: p.split(relativePath),
        ),
      );
      await snapshot.create(exclusive: true);
      owner.snapshotCreated = true;
      captureBoundaryHook?.call(
        PosixFileBoundary.afterCaptureSnapshotCreate,
        PosixFileBoundaryContext(
          supportRootPath: supportDirectory.path,
          captureRootPath: captureTemporaryDirectory.path,
          attemptName: p.basename(attempt.path),
          plaintextSegments: p.split(relativePath),
        ),
      );
      final bytes = await input.read(await input.length());
      await snapshot.writeAsBytes(bytes, flush: true);
      await input.close();
      if (failCaptureSourceClose) {
        throw StateError('injected source close failure');
      }
      owner.bytesValue = Uint8List.fromList(bytes);
      return owner;
    } on Object catch (error) {
      try {
        await input.close();
      } on Object {
        // The test backend models only the primary injected close boundary.
      }
      throw SecureCaptureSnapshotFailure(
        primary: error,
        additionalFailures: const [],
        residualSnapshot: owner,
      );
    }
  }

  @override
  Future<void> deleteCaptureSnapshot(SecureCaptureSnapshot snapshot) async {
    if (snapshot is! TestCaptureSnapshot ||
        !identical(snapshot.token, _token) ||
        _cleanedSnapshots.contains(snapshot)) {
      throw ArgumentError.value(snapshot, 'snapshot');
    }
    captureSnapshotCleanupCalls++;
    captureBoundaryHook?.call(
      PosixFileBoundary.beforeCaptureSnapshotCleanup,
      PosixFileBoundaryContext(
        supportRootPath: supportDirectory.path,
        captureRootPath: captureTemporaryDirectory.path,
        attemptName: p.basename(snapshot.attempt.path),
        plaintextSegments: p.split(snapshot.relativePath),
      ),
    );
    if (failCaptureSnapshotDeletes > 0) {
      failCaptureSnapshotDeletes--;
      throw SecureCaptureSnapshotFailure(
        primary: StateError('injected capture snapshot deletion failure'),
        additionalFailures: const [],
        residualSnapshot: snapshot,
      );
    }
    if (snapshot.snapshotCreated) {
      final type = await FileSystemEntity.type(
        snapshot.file.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.file) {
        await snapshot.file.delete();
        snapshot.snapshotCreated = false;
      } else if (type != FileSystemEntityType.notFound) {
        throw SecureCaptureSnapshotFailure(
          primary: FileSystemException(
            'Capture snapshot must be a real file',
            snapshot.file.path,
          ),
          additionalFailures: const [],
          residualSnapshot: snapshot,
        );
      } else {
        snapshot.snapshotCreated = false;
      }
    }
    try {
      await snapshot.attempt.delete();
    } on Object catch (error) {
      throw SecureCaptureSnapshotFailure(
        primary: error,
        additionalFailures: const [],
        residualSnapshot: snapshot,
      );
    }
    _cleanedSnapshots.add(snapshot);
    if (failCaptureSnapshotCloseAfterCleanup > 0) {
      failCaptureSnapshotCloseAfterCleanup--;
      throw SecureCaptureSnapshotFailure(
        primary: StateError('injected ambiguous capture descriptor close'),
        additionalFailures: const [],
        residualSnapshot: null,
      );
    }
  }

  @override
  Future<SecurePlaintextCleanup> validatePlaintextRefs(
    List<List<String>> relativePaths,
  ) async {
    final support = p.normalize(await supportDirectory.resolveSymbolicLinks());
    final capture = p.normalize(
      await captureTemporaryDirectory.resolveSymbolicLinks(),
    );
    if (p.equals(support, capture) ||
        p.isWithin(support, capture) ||
        p.isWithin(capture, support)) {
      throw ArgumentError('Capture and support roots must be disjoint');
    }
    final paths = <String>[];
    for (final segments in relativePaths) {
      final candidate = p.normalize(p.joinAll([capture, ...segments]));
      if (!p.isWithin(capture, candidate)) {
        throw ArgumentError.value(segments, 'relativePaths');
      }
      final type = await FileSystemEntity.type(candidate, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw FileSystemException('Plaintext must be a real file', candidate);
      }
      paths.add(candidate);
    }
    return TestPlaintextCleanup(relativePaths, paths);
  }

  @override
  Future<void> deletePlaintext(SecurePlaintextCleanup cleanup) async {
    if (!_consumedPlaintext.add(cleanup)) {
      throw ArgumentError.value(cleanup, 'cleanup', 'Capability was consumed');
    }
    if (failPlaintextDeletes > 0) {
      failPlaintextDeletes--;
      throw SecureBlobFileSystemFailure(
        primary: EntrySaveCause(
          phase: EntrySavePhase.plaintextCleanup,
          error: StateError('injected plaintext deletion failure'),
          stackTrace: StackTrace.current,
        ),
        additionalFailures: const [],
        publishedBlob: null,
        stagingMayRemain: false,
      );
    }
    final value = cleanup as TestPlaintextCleanup;
    final failures = <EntrySaveCause>[];
    for (final path in value.absolutePaths) {
      try {
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.notFound) {
          continue;
        }
        if (type != FileSystemEntityType.file) {
          throw FileSystemException('Plaintext must be a real file', path);
        }
        await File(path).delete();
      } on Object catch (error, stackTrace) {
        failures.add(
          EntrySaveCause(
            phase: EntrySavePhase.plaintextCleanup,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }
    if (failures.isNotEmpty) {
      throw SecureBlobFileSystemFailure(
        primary: failures.first,
        additionalFailures: failures.skip(1),
        publishedBlob: null,
        stagingMayRemain: false,
      );
    }
  }
}

final class TestStagedBlob implements SecureStagedBlob {
  const TestStagedBlob(this.attempt, this.file);
  final Directory attempt;
  final File file;

  @override
  String get attemptId => p.basename(attempt.path);
}

final class TestPublishedBlob implements SecurePublishedBlob {
  const TestPublishedBlob({
    required this.token,
    required this.destinationName,
    required this.publishedRef,
    required this.identity,
  });

  final Object token;
  @override
  final String destinationName;
  @override
  final String publishedRef;
  @override
  final SecureFileIdentity identity;
}

final class TestPlaintextCleanup implements SecurePlaintextCleanup {
  TestPlaintextCleanup(List<List<String>> relativePaths, this.absolutePaths)
    : relativePaths = List<List<String>>.unmodifiable(
        relativePaths.map(List<String>.unmodifiable),
      );

  @override
  final List<List<String>> relativePaths;
  final List<String> absolutePaths;
}

final class TestCaptureSnapshot implements SecureCaptureSnapshot {
  TestCaptureSnapshot({
    required this.token,
    required this.relativePath,
    required this.file,
    required this.attempt,
  });

  final Object token;
  @override
  final String relativePath;
  final File file;
  final Directory attempt;
  Uint8List bytesValue = Uint8List(0);
  bool snapshotCreated = false;

  @override
  Uint8List get bytes => Uint8List.fromList(bytesValue);
}

EncryptedBlobStore testEncryptedBlobStore(
  Directory support,
  Directory capture, {
  Object? finalizeError,
  List<EntrySaveCause> finalizeAdditionalFailures = const [],
  bool blockAttemptCleanup = false,
  bool finalBlobMayRemain = false,
  int failPlaintextDeletes = 0,
  int failCaptureSnapshotDeletes = 0,
  PosixFileBoundaryHook? captureBoundaryHook,
  bool failCaptureSourceClose = false,
}) => EncryptedBlobStore(
  support,
  captureTemporaryDirectory: capture,
  fileSystem: TestSecureBlobFileSystem(
    supportDirectory: support,
    captureTemporaryDirectory: capture,
    finalizeError: finalizeError,
    finalizeAdditionalFailures: finalizeAdditionalFailures,
    blockAttemptCleanup: blockAttemptCleanup,
    finalBlobMayRemain: finalBlobMayRemain,
    failPlaintextDeletes: failPlaintextDeletes,
    failCaptureSnapshotDeletes: failCaptureSnapshotDeletes,
    captureBoundaryHook: captureBoundaryHook,
    failCaptureSourceClose: failCaptureSourceClose,
  ),
);

extension TestStagedBlobAccess on StagedEncryptedBlob {
  TestStagedBlob get _testValue => secure as TestStagedBlob;
  Directory get attemptDirectory => _testValue.attempt;
  File get file => _testValue.file;
}

extension TestEncryptedBlobStoreAccess on EncryptedBlobStore {
  Future<File> resolve(String relativeRef) async {
    await read(relativeRef);
    return File(p.join(supportDirectory.path, relativeRef));
  }
}
