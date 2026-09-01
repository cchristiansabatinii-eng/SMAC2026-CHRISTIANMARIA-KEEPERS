// ignore_for_file: prefer_initializing_formals

import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:keepers/features/capture/data/entry_persistence_failure.dart';
import 'package:keepers/features/capture/data/secure_file_protocol.dart';
import 'package:path/path.dart' as p;

export 'package:keepers/features/capture/data/secure_file_protocol.dart';

abstract interface class SecureStagedBlob {
  String get attemptId;
}

abstract interface class SecurePlaintextCleanup {
  List<List<String>> get relativePaths;
}

abstract interface class SecurePublishedBlob {
  String get destinationName;
  String get publishedRef;
  SecureFileIdentity get identity;
}

abstract interface class SecureCaptureSnapshot {
  String get relativePath;
  Uint8List get bytes;
}

final class SecureCaptureSnapshotFailure implements Exception {
  SecureCaptureSnapshotFailure({
    required this.primary,
    required Iterable<Object> additionalFailures,
    required this.residualSnapshot,
  }) : additionalFailures = List<Object>.unmodifiable(additionalFailures);

  final Object primary;
  final List<Object> additionalFailures;
  final SecureCaptureSnapshot? residualSnapshot;
}

abstract interface class SecureCaptureFileSystem {
  Future<SecureCaptureSnapshot> createCaptureSnapshot({
    required List<String> sourceSegments,
    required String snapshotId,
    required String extension,
  });

  Future<void> deleteCaptureSnapshot(SecureCaptureSnapshot snapshot);
}

final class SecureBlobFileSystemFailure implements Exception {
  SecureBlobFileSystemFailure({
    required this.primary,
    required Iterable<EntrySaveCause> additionalFailures,
    required this.publishedBlob,
    required this.stagingMayRemain,
    this.finalBlobMayRemain = false,
  }) : additionalFailures = List<EntrySaveCause>.unmodifiable(
         additionalFailures,
       );

  final EntrySaveCause primary;
  final List<EntrySaveCause> additionalFailures;
  final SecurePublishedBlob? publishedBlob;
  final bool stagingMayRemain;
  final bool finalBlobMayRemain;

  String? get publishedBlobRef => publishedBlob?.publishedRef;
}

abstract interface class SecureBlobFileSystem {
  Future<SecureStagedBlob> stage(Uint8List encryptedBytes);

  Future<SecurePublishedBlob> finalize(
    SecureStagedBlob staged, {
    required String destinationName,
    required String publishedRef,
  });

  Future<Uint8List> readBlob(String destinationName);

  Future<bool> blobExists(String destinationName);

  Future<void> rollbackBlob(SecurePublishedBlob published);

  Future<SecurePlaintextCleanup> validatePlaintextRefs(
    List<List<String>> relativePaths,
  );

  Future<void> deletePlaintext(SecurePlaintextCleanup cleanup);
}

enum PosixFileBoundary {
  beforeStageLeafOpen,
  afterStageLeafOpenBeforeWrite,
  beforeFinalLink,
  afterFinalLinkBeforeIdentityCheck,
  beforeBlobLeafOpenForRead,
  afterBlobLeafOpenBeforeRead,
  beforeBlobUnlink,
  afterQuarantineIdentityCheckBeforeUnlink,
  beforePrivateMutationRelease,
  beforePlaintextLeafOpen,
  beforePlaintextUnlink,
  beforeAttemptCleanup,
  beforeCaptureSourceOpen,
  afterCaptureSourceOpen,
  afterCaptureAttemptCreateBeforeOpen,
  afterCaptureAttemptOpenBeforeIdentity,
  beforeCaptureSnapshotCreate,
  afterCaptureSnapshotCreate,
  beforeCaptureSnapshotCleanup,
  beforeCaptureSnapshotDescriptorRelease,
}

final class PosixFileBoundaryContext {
  const PosixFileBoundaryContext({
    required this.supportRootPath,
    required this.captureRootPath,
    this.attemptName,
    this.destinationName,
    this.plaintextSegments,
  });

  final String supportRootPath;
  final String captureRootPath;
  final String? attemptName;
  final String? destinationName;
  final List<String>? plaintextSegments;
}

typedef PosixFileBoundaryHook = void Function(
  PosixFileBoundary boundary,
  PosixFileBoundaryContext context,
);

/// Production filesystem for the maintained Android x64/arm64, iOS arm64,
/// Linux x64, and macOS x64/arm64 native gates.
///
/// Every child traversal and mutation is relative to an already-open directory
/// descriptor. Windows is deliberately unsupported until equivalent reparse
/// point and file-ID protections are implemented.
///
/// Threat model: mobile OS sandboxing and app-private roots exclude other
/// principals. In-process and same-euid writers with access to those roots must
/// cooperate through this component. Hostile or non-cooperating same-euid
/// mutation is out of scope because POSIX discretionary permissions cannot
/// provide mandatory exclusion from the owning identity. Each removal uses a
/// newly created 0700 directory handle that is never adopted from disk,
/// preventing in-scope operations from sharing candidate names.
final class PosixSecureBlobFileSystem
    implements SecureBlobFileSystem, SecureCaptureFileSystem {
  PosixSecureBlobFileSystem({
    required Directory supportDirectory,
    required Directory captureTemporaryDirectory,
    this.boundaryHook,
    this.syscallFaultInjector,
  }) : supportDirectory = supportDirectory.absolute,
       captureTemporaryDirectory = captureTemporaryDirectory.absolute;

  final Directory supportDirectory;
  final Directory captureTemporaryDirectory;
  final PosixFileBoundaryHook? boundaryHook;
  final PosixSyscallFaultInjector? syscallFaultInjector;
  final Object _token = Object();
  final Set<SecurePublishedBlob> _consumedPublications = Set.identity();

  _PosixBindings get _syscalls {
    _ensureSupported();
    return _PosixBindings.instance;
  }

  void _ensureSupported() {
    currentPosixNativeAbi();
  }

  @override
  Future<SecureStagedBlob> stage(Uint8List encryptedBytes) async {
    _ensureSupported();
    _PosixLayout? layout;
    _PosixStagedBlob? staged;
    try {
      layout = _openLayout(create: true);
      final attemptName = _createAttempt(layout.stagingFd);
      staged = _PosixStagedBlob(
        token: _token,
        attemptId: attemptName,
        layout: layout,
        attemptFd: -1,
      );
      staged.attemptFd = _openDirectoryAt(layout.stagingFd, attemptName);
      staged.attemptIdentity = _fileIdentity(
        staged.attemptFd,
        expectedKind: _FileKind.directory,
      );
      _hook(PosixFileBoundary.beforeStageLeafOpen, attemptName: attemptName);
      staged.sourceFd = _openFileAt(
        staged.attemptFd,
        _stagingLeaf,
        write: true,
        createExclusive: true,
      );
      staged.sourceIdentity = _fileIdentity(
        staged.sourceFd,
        expectedKind: _FileKind.regular,
      );
      _hook(
        PosixFileBoundary.afterStageLeafOpenBeforeWrite,
        attemptName: attemptName,
      );
      _writeAll(staged.sourceFd, encryptedBytes);
      _fsync(staged.sourceFd, 'encrypted staging payload');
      if (_fileIdentity(staged.sourceFd, expectedKind: _FileKind.regular) !=
          staged.sourceIdentity) {
        throw const FileSystemException(
          'Encrypted staging descriptor identity changed',
        );
      }
      _validateLayoutIdentities(staged.layout);
      return staged;
    } on Object catch (error, stackTrace) {
      final cleanupFailures = <EntrySaveCause>[];
      var stagingMayRemain = false;
      if (staged != null) {
        final cleanup = _cleanupAttempt(staged);
        cleanupFailures.addAll(cleanup.failures);
        stagingMayRemain = cleanup.mayRemain;
      } else if (layout != null) {
        cleanupFailures.addAll(_cleanupLayout(layout));
      }
      throw SecureBlobFileSystemFailure(
        primary: EntrySaveCause(
          phase: EntrySavePhase.stageBlob,
          error: error,
          stackTrace: stackTrace,
        ),
        additionalFailures: cleanupFailures,
        publishedBlob: null,
        stagingMayRemain: stagingMayRemain,
      );
    }
  }

  @override
  Future<SecurePublishedBlob> finalize(
    SecureStagedBlob staged, {
    required String destinationName,
    required String publishedRef,
  }) async {
    _ensureSupported();
    _validateDestinationName(destinationName);
    if (staged is! _PosixStagedBlob ||
        !identical(staged.token, _token) ||
        staged.consumed) {
      throw ArgumentError.value(
        staged,
        'staged',
        'Staged blob capability is invalid or belongs to another store',
      );
    }
    staged.consumed = true;
    EntrySaveCause? primary;
    final additional = <EntrySaveCause>[];
    _PosixPublishedBlob? publication;
    var finalBlobMayRemain = false;
    try {
      _validateLayoutIdentities(staged.layout);
      final sourceIdentity = _fileIdentity(
        staged.sourceFd,
        expectedKind: _FileKind.regular,
      );
      if (sourceIdentity != staged.sourceIdentity) {
        throw const FileSystemException(
          'Encrypted staging descriptor identity changed before publication',
        );
      }
      _hook(
        PosixFileBoundary.beforeFinalLink,
        attemptName: staged.attemptId,
        destinationName: destinationName,
      );
      _linkAt(
        staged.attemptFd,
        _stagingLeaf,
        staged.layout.blobsFd,
        destinationName,
      );
      _hook(
        PosixFileBoundary.afterFinalLinkBeforeIdentityCheck,
        attemptName: staged.attemptId,
        destinationName: destinationName,
      );
      int destinationFd = -1;
      try {
        destinationFd = _openFileAt(staged.layout.blobsFd, destinationName);
        final destinationIdentity = _fileIdentity(
          destinationFd,
          expectedKind: _FileKind.regular,
        );
        if (destinationIdentity != staged.sourceIdentity) {
          throw const FileSystemException(
            'Published blob does not match the retained staging descriptor',
          );
        }
        publication = _PosixPublishedBlob(
          token: _token,
          destinationName: destinationName,
          publishedRef: publishedRef,
          identity: destinationIdentity,
        );
      } on Object {
        final removal = const AnchoredQuarantineRemovalProtocol()
            .removeExpected(
              operations: _quarantineOperations(
                sourceParentFd: staged.layout.blobsFd,
                quarantineFd: staged.layout.quarantineFd,
                quarantineIdentity: staged.layout.quarantineIdentity!,
                destinationName: destinationName,
              ),
              originalName: destinationName,
              expectedIdentity: staged.sourceIdentity!,
              kind: SecureFileKind.regular,
            );
        publication = null;
        int? retainedLinks;
        Object? linkProofError;
        StackTrace? linkProofStackTrace;
        try {
          retainedLinks =
              removal.postRemovalLinkCount ?? _linkCount(staged.sourceFd);
          finalBlobMayRemain = retainedLinks > 1;
        } on Object catch (cleanupError, cleanupStackTrace) {
          finalBlobMayRemain = true;
          linkProofError = cleanupError;
          linkProofStackTrace = cleanupStackTrace;
        }
        if (!removal.removedOrMissing) {
          if (removal.state != QuarantineRemovalState.mismatchRestored &&
              removal.state != QuarantineRemovalState.mismatchQuarantined) {
            finalBlobMayRemain = true;
          }
          additional.add(
            EntrySaveCause(
              phase: EntrySavePhase.finalBlobRollback,
              error:
                  removal.error ??
                  FileSystemException(
                    'Published destination could not be safely removed: '
                    '${removal.state.name}',
                    removal.quarantineName,
                  ),
              stackTrace: removal.stackTrace ?? StackTrace.current,
            ),
          );
        } else if (retainedLinks != null && retainedLinks > 1) {
          additional.add(
            EntrySaveCause(
              phase: EntrySavePhase.finalBlobRollback,
              error: FileSystemException(
                'Published destination removal left an unexpected retained '
                'link (links: $retainedLinks)',
                removal.quarantineName,
              ),
              stackTrace: StackTrace.current,
            ),
          );
        }
        if (linkProofError != null) {
          additional.add(
            EntrySaveCause(
              phase: EntrySavePhase.finalBlobRollback,
              error: linkProofError,
              stackTrace: linkProofStackTrace!,
            ),
          );
        }
        if (removal.releaseError != null) {
          finalBlobMayRemain = true;
          additional.add(
            EntrySaveCause(
              phase: EntrySavePhase.finalBlobRollback,
              error: removal.releaseError!,
              stackTrace: removal.releaseStackTrace ?? StackTrace.current,
            ),
          );
        }
        rethrow;
      } finally {
        _closeIfOpen(destinationFd);
      }
      _fsync(staged.layout.blobsFd, 'encrypted blob directory');
    } on Object catch (error, stackTrace) {
      primary = EntrySaveCause(
        phase: EntrySavePhase.finalizeBlob,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final cleanup = _cleanupAttempt(staged);
    for (final failure in cleanup.failures) {
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
        stagingMayRemain: cleanup.mayRemain,
        finalBlobMayRemain: finalBlobMayRemain,
      );
    }
    return publication!;
  }

  @override
  Future<Uint8List> readBlob(String destinationName) async {
    _ensureSupported();
    _validateDestinationName(destinationName);
    _PosixLayout? layout;
    var fileFd = -1;
    try {
      layout = _openLayout(create: false, needsQuarantine: false);
      _hook(
        PosixFileBoundary.beforeBlobLeafOpenForRead,
        destinationName: destinationName,
      );
      fileFd = _openFileAt(layout.blobsFd, destinationName);
      _fileIdentity(fileFd, expectedKind: _FileKind.regular);
      _hook(
        PosixFileBoundary.afterBlobLeafOpenBeforeRead,
        destinationName: destinationName,
      );
      return _readAll(fileFd);
    } finally {
      _closeIfOpen(fileFd);
      if (layout != null) {
        _closeLayout(layout);
      }
    }
  }

  @override
  Future<bool> blobExists(String destinationName) async {
    _ensureSupported();
    _validateDestinationName(destinationName);
    _PosixLayout? layout;
    var fileFd = -1;
    try {
      layout = _openLayout(create: false, needsQuarantine: false);
      fileFd = _openFileAt(layout.blobsFd, destinationName);
      _fileIdentity(fileFd, expectedKind: _FileKind.regular);
      return true;
    } on _PosixException catch (error) {
      if (error.errno == _enoent) {
        return false;
      }
      rethrow;
    } finally {
      _closeIfOpen(fileFd);
      if (layout != null) {
        _closeLayout(layout);
      }
    }
  }

  @override
  Future<void> rollbackBlob(SecurePublishedBlob published) async {
    _ensureSupported();
    if (published is! _PosixPublishedBlob ||
        !identical(published.token, _token) ||
        !_consumedPublications.add(published)) {
      throw ArgumentError.value(
        published,
        'published',
        'Published blob capability is invalid, consumed, or belongs to '
            'another filesystem',
      );
    }
    final destinationName = published.destinationName;
    _validateDestinationName(destinationName);
    _PosixLayout? layout;
    try {
      try {
        layout = _openLayout(create: false, needsQuarantine: true);
      } on _PosixException catch (error) {
        if (error.errno == _enoent) {
          throw const FileSystemException(
            'Rollback cannot prove the finalized encrypted blob absent',
          );
        }
        rethrow;
      }
      _hook(
        PosixFileBoundary.beforeBlobUnlink,
        destinationName: destinationName,
      );
      final removal = const AnchoredQuarantineRemovalProtocol().removeExpected(
        operations: _quarantineOperations(
          sourceParentFd: layout.blobsFd,
          quarantineFd: layout.quarantineFd,
          quarantineIdentity: layout.quarantineIdentity!,
          destinationName: destinationName,
        ),
        originalName: destinationName,
        expectedIdentity: published.identity,
        kind: SecureFileKind.regular,
      );
      if (removal.state != QuarantineRemovalState.removed ||
          removal.postRemovalLinkCount != 0 ||
          removal.releaseError != null) {
        _throwRemovalFailure(
          removal,
          'Rollback could not prove the finalized encrypted blob absent '
          '(${removal.state.name}, links: '
          '${removal.postRemovalLinkCount ?? 'unknown'})',
        );
      }
      _fsync(layout.blobsFd, 'encrypted blob directory');
    } finally {
      if (layout != null) {
        _closeLayout(layout);
      }
    }
  }

  @override
  Future<SecureCaptureSnapshot> createCaptureSnapshot({
    required List<String> sourceSegments,
    required String snapshotId,
    required String extension,
  }) async {
    _ensureSupported();
    final segments = List<String>.unmodifiable(sourceSegments);
    _validateSegments(segments);
    _validateSegment(snapshotId);
    if (segments.length != 2 || segments.first != 'keepers-capture') {
      throw ArgumentError.value(
        segments,
        'sourceSegments',
        'Capture sources must be direct children of keepers-capture',
      );
    }
    if (!RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension)) {
      throw ArgumentError.value(extension, 'extension');
    }

    final support = _openTrustedRoot(supportDirectory, 'application support');
    _OpenedRoot? root;
    var captureFd = -1;
    var expectedSourceFd = -1;
    var sourceFd = -1;
    var attemptFd = -1;
    var snapshotFd = -1;
    var quarantineFd = -1;
    String? attemptName;
    _PosixCaptureSnapshot? owner;
    try {
      root = _openTrustedRoot(captureTemporaryDirectory, 'capture temporary');
      if (support.identity == root.identity ||
          _pathsOverlap(support.canonicalPath, root.canonicalPath)) {
        throw ArgumentError(
          'Capture temporary storage must be disjoint from application support',
        );
      }
      captureFd = _openDirectoryAt(root.fd, 'keepers-capture');
      final captureIdentity = _fileIdentity(
        captureFd,
        expectedKind: _FileKind.directory,
      );
      expectedSourceFd = _openFileAt(captureFd, segments.last);
      final sourceIdentity = _fileIdentity(
        expectedSourceFd,
        expectedKind: _FileKind.regular,
      );
      _hook(
        PosixFileBoundary.beforeCaptureSourceOpen,
        plaintextSegments: segments,
      );
      sourceFd = _openFileAt(captureFd, segments.last);
      if (_fileIdentity(sourceFd, expectedKind: _FileKind.regular) !=
          sourceIdentity) {
        throw const FileSystemException(
          'Capture source identity changed before operational open',
        );
      }
      _hook(
        PosixFileBoundary.afterCaptureSourceOpen,
        plaintextSegments: segments,
      );
      final sourceValidationFd = expectedSourceFd;
      expectedSourceFd = -1;
      _closeChecked(sourceValidationFd, 'capture source validation descriptor');

      quarantineFd = _openOrCreateDirectoryAt(
        root.fd,
        _captureQuarantineDirectory,
      );
      final quarantineIdentity = _fileIdentity(
        quarantineFd,
        expectedKind: _FileKind.directory,
      );
      _validateQuarantineAuthority(quarantineFd, quarantineIdentity);
      attemptName = _createPrivateDirectory(captureFd, 'snapshot');
      final leafName = 'payload.$extension';
      final relativeSegments = <String>[
        'keepers-capture',
        attemptName,
        leafName,
      ];
      final snapshotOwner = _PosixCaptureSnapshot(
        token: _token,
        relativePath: p.joinAll(relativeSegments),
        rootFd: root.fd,
        rootIdentity: root.identity,
        captureFd: captureFd,
        captureIdentity: captureIdentity,
        attemptFd: -1,
        attemptIdentity: null,
        snapshotFd: -1,
        snapshotIdentity: null,
        quarantineFd: quarantineFd,
        quarantineIdentity: quarantineIdentity,
        attemptName: attemptName,
        leafName: leafName,
      );
      owner = snapshotOwner;
      root = null;
      captureFd = -1;
      attemptFd = -1;
      snapshotFd = -1;
      quarantineFd = -1;

      _hook(
        PosixFileBoundary.afterCaptureAttemptCreateBeforeOpen,
        attemptName: attemptName,
        plaintextSegments: relativeSegments,
      );
      snapshotOwner._attemptFd = _openDirectoryAt(
        snapshotOwner._captureFd,
        attemptName,
      );
      _hook(
        PosixFileBoundary.afterCaptureAttemptOpenBeforeIdentity,
        attemptName: attemptName,
        plaintextSegments: relativeSegments,
      );
      snapshotOwner._attemptIdentity = _fileIdentity(
        snapshotOwner._attemptFd,
        expectedKind: _FileKind.directory,
      );
      _hook(
        PosixFileBoundary.beforeCaptureSnapshotCreate,
        attemptName: attemptName,
        plaintextSegments: relativeSegments,
      );
      snapshotOwner._snapshotFd = _openFileAt(
        snapshotOwner._attemptFd,
        leafName,
        write: true,
        createExclusive: true,
      );
      snapshotOwner._snapshotRemoved = false;
      snapshotOwner._snapshotIdentity = _fileIdentity(
        snapshotOwner._snapshotFd,
        expectedKind: _FileKind.regular,
      );
      _hook(
        PosixFileBoundary.afterCaptureSnapshotCreate,
        attemptName: attemptName,
        plaintextSegments: relativeSegments,
      );
      final bytes = _readAll(sourceFd);
      _writeAll(snapshotOwner._snapshotFd, bytes);
      _fsync(snapshotOwner._snapshotFd, 'capture snapshot payload');
      if (_fileIdentity(sourceFd, expectedKind: _FileKind.regular) !=
              sourceIdentity ||
          _fileIdentity(
                snapshotOwner._snapshotFd,
                expectedKind: _FileKind.regular,
              ) !=
              snapshotOwner._snapshotIdentity) {
        throw const FileSystemException(
          'Capture descriptor identity changed while snapshotting',
        );
      }
      var publicFd = -1;
      try {
        publicFd = _openFileAt(snapshotOwner._attemptFd, leafName);
        if (_fileIdentity(publicFd, expectedKind: _FileKind.regular) !=
            snapshotOwner._snapshotIdentity) {
          throw const FileSystemException(
            'Capture snapshot public identity changed during construction',
          );
        }
      } finally {
        _closeIfOpen(publicFd);
      }
      final completedSourceFd = sourceFd;
      sourceFd = -1;
      _closeChecked(completedSourceFd, 'capture source descriptor');
      snapshotOwner._bytesValue = Uint8List.fromList(bytes);
      return snapshotOwner;
    } on Object catch (error) {
      final additional = <Object>[];
      for (final descriptor in <({int fd, String label})>[
        (fd: sourceFd, label: 'capture source descriptor'),
        (fd: expectedSourceFd, label: 'capture source validation descriptor'),
      ]) {
        if (descriptor.fd >= 0) {
          try {
            _closeChecked(descriptor.fd, descriptor.label);
          } on Object catch (closeError) {
            additional.add(closeError);
          }
        }
      }
      if (owner == null) {
        for (final descriptor in <({int fd, String label})>[
          (fd: snapshotFd, label: 'unowned capture snapshot descriptor'),
          (fd: attemptFd, label: 'unowned capture attempt descriptor'),
          (fd: quarantineFd, label: 'capture quarantine descriptor'),
          (fd: captureFd, label: 'capture directory descriptor'),
        ]) {
          if (descriptor.fd >= 0) {
            try {
              _closeChecked(descriptor.fd, descriptor.label);
            } on Object catch (closeError) {
              additional.add(closeError);
            }
          }
        }
        if (root != null) {
          try {
            _closeChecked(root.fd, 'capture temporary root descriptor');
          } on Object catch (closeError) {
            additional.add(closeError);
          }
        }
      }
      throw SecureCaptureSnapshotFailure(
        primary: error,
        additionalFailures: additional,
        residualSnapshot: owner,
      );
    } finally {
      _closeIfOpen(support.fd);
    }
  }

  @override
  Future<void> deleteCaptureSnapshot(SecureCaptureSnapshot snapshot) async {
    _ensureSupported();
    if (snapshot is! _PosixCaptureSnapshot ||
        !identical(snapshot._token, _token) ||
        snapshot._cleaned) {
      throw ArgumentError.value(
        snapshot,
        'snapshot',
        'Capture snapshot owner is invalid, cleaned, or belongs to another store',
      );
    }
    final failures = <Object>[];
    if (!snapshot._snapshotRemoved || !snapshot._attemptRemoved) {
      try {
        _hook(
          PosixFileBoundary.beforeCaptureSnapshotCleanup,
          attemptName: snapshot._attemptName,
          plaintextSegments: p.split(snapshot.relativePath),
        );
        if (!snapshot._attemptRemoved && snapshot._attemptIdentity == null) {
          if (snapshot._attemptFd < 0) {
            try {
              snapshot._attemptFd = _openDirectoryAt(
                snapshot._captureFd,
                snapshot._attemptName,
              );
            } on _PosixException catch (error) {
              if (error.errno != _enoent || !snapshot._snapshotRemoved) {
                rethrow;
              }
              snapshot._attemptRemoved = true;
            }
          }
          if (!snapshot._attemptRemoved) {
            snapshot._attemptIdentity = _fileIdentity(
              snapshot._attemptFd,
              expectedKind: _FileKind.directory,
            );
          }
        }
        if (!snapshot._snapshotRemoved &&
            snapshot._snapshotIdentity == null &&
            snapshot._snapshotFd >= 0) {
          snapshot._snapshotIdentity = _fileIdentity(
            snapshot._snapshotFd,
            expectedKind: _FileKind.regular,
          );
        }
        if (_fileIdentity(
                  snapshot._rootFd,
                  expectedKind: _FileKind.directory,
                ) !=
                snapshot._rootIdentity ||
            _fileIdentity(
                  snapshot._captureFd,
                  expectedKind: _FileKind.directory,
                ) !=
                snapshot._captureIdentity ||
            (!snapshot._attemptRemoved &&
                (snapshot._attemptFd < 0 ||
                    snapshot._attemptIdentity == null ||
                    _fileIdentity(
                          snapshot._attemptFd,
                          expectedKind: _FileKind.directory,
                        ) !=
                        snapshot._attemptIdentity)) ||
            (!snapshot._snapshotRemoved &&
                (snapshot._snapshotFd < 0 ||
                    snapshot._snapshotIdentity == null ||
                    _fileIdentity(
                          snapshot._snapshotFd,
                          expectedKind: _FileKind.regular,
                        ) !=
                        snapshot._snapshotIdentity))) {
          throw const FileSystemException(
            'Capture snapshot retained descriptor identity changed',
          );
        }
        _validateQuarantineAuthority(
          snapshot._quarantineFd,
          snapshot._quarantineIdentity,
        );
        if (!snapshot._snapshotRemoved) {
          final snapshotIdentity = snapshot._snapshotIdentity;
          if (snapshotIdentity == null) {
            throw const FileSystemException(
              'Capture snapshot identity is unavailable',
            );
          }
          var publicFd = -1;
          try {
            try {
              publicFd = _openFileAt(snapshot._attemptFd, snapshot._leafName);
            } on _PosixException catch (error) {
              if (error.errno != _enoent) rethrow;
            }
            if (publicFd < 0) {
              if (_linkCount(snapshot._snapshotFd) != 0) {
                throw const FileSystemException(
                  'Original capture snapshot moved and remains linked',
                );
              }
              snapshot._snapshotRemoved = true;
            } else {
              final publicIdentity = _fileIdentity(
                publicFd,
                expectedKind: _FileKind.regular,
              );
              if (publicIdentity != snapshotIdentity) {
                throw const FileSystemException(
                  'Capture snapshot path contains a replacement identity',
                );
              }
              final removal = const AnchoredQuarantineRemovalProtocol()
                  .removeExpected(
                    operations: _quarantineOperations(
                      sourceParentFd: snapshot._attemptFd,
                      quarantineFd: snapshot._quarantineFd,
                      quarantineIdentity: snapshot._quarantineIdentity,
                      plaintextSegments: p.split(snapshot.relativePath),
                    ),
                    originalName: snapshot._leafName,
                    expectedIdentity: snapshotIdentity,
                    kind: SecureFileKind.regular,
                  );
              if (!removal.removedOrMissing ||
                  removal.postRemovalLinkCount != 0 ||
                  removal.releaseError != null) {
                _throwRemovalFailure(
                  removal,
                  'Capture snapshot identity could not be proven absent',
                );
              }
              snapshot._snapshotRemoved = true;
            }
          } finally {
            _closeIfOpen(publicFd);
          }
        }
        if (snapshot._snapshotRemoved && !snapshot._attemptRemoved) {
          try {
            _unlinkAt(
              snapshot._captureFd,
              snapshot._attemptName,
              directory: true,
            );
            _fsync(snapshot._captureFd, 'capture snapshot directory');
            snapshot._attemptRemoved = true;
          } on _PosixException catch (error) {
            if (error.errno == _enoent &&
                _linkCount(snapshot._attemptFd) == 0) {
              snapshot._attemptRemoved = true;
            } else {
              rethrow;
            }
          }
        }
      } on Object catch (error) {
        failures.add(error);
      }
    }
    if (snapshot._snapshotRemoved && snapshot._attemptRemoved) {
      try {
        _hook(
          PosixFileBoundary.beforeCaptureSnapshotDescriptorRelease,
          attemptName: snapshot._attemptName,
          plaintextSegments: p.split(snapshot.relativePath),
        );
      } on Object catch (error) {
        failures.add(error);
      }
      for (final close in <({int fd, String label, void Function() cleared})>[
        (
          fd: snapshot._snapshotFd,
          label: 'capture snapshot descriptor',
          cleared: () => snapshot._snapshotFd = -1,
        ),
        (
          fd: snapshot._attemptFd,
          label: 'capture snapshot attempt descriptor',
          cleared: () => snapshot._attemptFd = -1,
        ),
        (
          fd: snapshot._quarantineFd,
          label: 'capture quarantine descriptor',
          cleared: () => snapshot._quarantineFd = -1,
        ),
        (
          fd: snapshot._captureFd,
          label: 'capture directory descriptor',
          cleared: () => snapshot._captureFd = -1,
        ),
        (
          fd: snapshot._rootFd,
          label: 'capture temporary root descriptor',
          cleared: () => snapshot._rootFd = -1,
        ),
      ]) {
        if (close.fd < 0) continue;
        // A descriptor integer becomes unusable authority as soon as close is
        // attempted. Consume it first because both an error return and a
        // post-success fault leave retry safety ambiguous once the OS can
        // reuse the number for an unrelated resource.
        close.cleared();
        try {
          _closeChecked(close.fd, close.label);
        } on Object catch (error) {
          failures.add(error);
        }
      }
      snapshot._cleaned =
          snapshot._snapshotFd < 0 &&
          snapshot._attemptFd < 0 &&
          snapshot._quarantineFd < 0 &&
          snapshot._captureFd < 0 &&
          snapshot._rootFd < 0;
    }
    if (failures.isNotEmpty) {
      throw SecureCaptureSnapshotFailure(
        primary: failures.first,
        additionalFailures: failures.skip(1),
        residualSnapshot:
            !snapshot._snapshotRemoved ||
                !snapshot._attemptRemoved ||
                !snapshot._cleaned
            ? snapshot
            : null,
      );
    }
  }

  @override
  Future<SecurePlaintextCleanup> validatePlaintextRefs(
    List<List<String>> relativePaths,
  ) async {
    _ensureSupported();
    final support = _openTrustedRoot(supportDirectory, 'application support');
    _OpenedRoot? capture;
    var quarantineFd = -1;
    try {
      capture = _openTrustedRoot(
        captureTemporaryDirectory,
        'capture temporary',
      );
      if (support.identity == capture.identity ||
          _pathsOverlap(support.canonicalPath, capture.canonicalPath)) {
        throw ArgumentError(
          'Capture temporary storage must be disjoint from application support',
        );
      }
      quarantineFd = _openOrCreateDirectoryAt(
        capture.fd,
        _captureQuarantineDirectory,
      );
      final quarantineIdentity = _fileIdentity(
        quarantineFd,
        expectedKind: _FileKind.directory,
      );
      _validateQuarantineAuthority(quarantineFd, quarantineIdentity);
      final validated = <_ValidatedPlaintext>[];
      for (final rawSegments in relativePaths) {
        final segments = List<String>.unmodifiable(rawSegments);
        _validateSegments(segments);
        if (segments.first.toLowerCase() == _captureQuarantineDirectory) {
          throw ArgumentError.value(
            segments,
            'relativePaths',
            'Capture plaintext cannot use the reserved quarantine authority',
          );
        }
        var parentFd = capture.fd;
        final openedParents = <int>[];
        try {
          for (final segment in segments.take(segments.length - 1)) {
            parentFd = _openDirectoryAt(parentFd, segment);
            openedParents.add(parentFd);
          }
          var leafFd = -1;
          SecureFileIdentity? identity;
          try {
            leafFd = _openFileAt(parentFd, segments.last);
            identity = _fileIdentity(leafFd, expectedKind: _FileKind.regular);
          } on _PosixException catch (error) {
            if (error.errno != _enoent) {
              rethrow;
            }
          } finally {
            _closeIfOpen(leafFd);
          }
          validated.add(_ValidatedPlaintext(segments, identity));
        } finally {
          for (final fd in openedParents.reversed) {
            _closeIfOpen(fd);
          }
        }
      }
      final cleanup = _PosixPlaintextCleanup(
        token: _token,
        rootFd: capture.fd,
        rootIdentity: capture.identity,
        quarantineFd: quarantineFd,
        quarantineIdentity: quarantineIdentity,
        paths: validated,
      );
      quarantineFd = -1;
      capture = null;
      return cleanup;
    } finally {
      _closeIfOpen(support.fd);
      _closeIfOpen(quarantineFd);
      if (capture != null) {
        _closeIfOpen(capture.fd);
      }
    }
  }

  @override
  Future<void> deletePlaintext(SecurePlaintextCleanup cleanup) async {
    _ensureSupported();
    if (cleanup is! _PosixPlaintextCleanup ||
        !identical(cleanup.token, _token) ||
        cleanup.consumed) {
      throw ArgumentError.value(
        cleanup,
        'cleanup',
        'Plaintext cleanup capability is invalid or belongs to another store',
      );
    }
    cleanup.consumed = true;
    final failures = <EntrySaveCause>[];
    try {
      if (_fileIdentity(cleanup.rootFd, expectedKind: _FileKind.directory) !=
          cleanup.rootIdentity) {
        throw const FileSystemException(
          'Capture temporary root descriptor identity changed',
        );
      }
      _validateQuarantineAuthority(
        cleanup.quarantineFd,
        cleanup.quarantineIdentity,
      );
      for (final validated in cleanup.paths) {
        try {
          _deletePlaintextLeaf(cleanup, validated);
        } on SecureBlobFileSystemFailure catch (error) {
          failures.add(error.primary);
          failures.addAll(error.additionalFailures);
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
    } on Object catch (error, stackTrace) {
      failures.add(
        EntrySaveCause(
          phase: EntrySavePhase.plaintextCleanup,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    } finally {
      final rootFd = cleanup.rootFd;
      final quarantineFd = cleanup.quarantineFd;
      cleanup.rootFd = -1;
      cleanup.quarantineFd = -1;
      final closes = const FailureTotalCleanupRunner().run([
        PosixCleanupAction(
          PosixCleanupOperation.closeQuarantine,
          () => _closeChecked(
            quarantineFd,
            'capture quarantine authority descriptor',
          ),
        ),
        PosixCleanupAction(
          PosixCleanupOperation.closeRoot,
          () => _closeChecked(rootFd, 'capture temporary root descriptor'),
        ),
      ]);
      for (final failure in closes.failures) {
        failures.add(
          EntrySaveCause(
            phase: EntrySavePhase.plaintextCleanup,
            error: failure.error,
            stackTrace: failure.stackTrace,
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

  void _deletePlaintextLeaf(
    _PosixPlaintextCleanup cleanup,
    _ValidatedPlaintext validated,
  ) {
    var parentFd = cleanup.rootFd;
    final openedParents = <int>[];
    var leafFd = -1;
    EntrySaveCause? primary;
    final additional = <EntrySaveCause>[];
    try {
      var pathMissing = false;
      for (final segment in validated.segments.take(
        validated.segments.length - 1,
      )) {
        try {
          parentFd = _openDirectoryAt(parentFd, segment);
        } on _PosixException catch (error) {
          if (error.errno == _enoent) {
            pathMissing = true;
            break;
          }
          rethrow;
        }
        openedParents.add(parentFd);
      }
      if (!pathMissing) {
        _hook(
          PosixFileBoundary.beforePlaintextLeafOpen,
          plaintextSegments: validated.segments,
        );
        try {
          leafFd = _openFileAt(parentFd, validated.segments.last);
        } on _PosixException catch (error) {
          if (error.errno == _enoent) {
            pathMissing = true;
          } else {
            rethrow;
          }
        }
      }
      if (!pathMissing) {
        final currentIdentity = _fileIdentity(
          leafFd,
          expectedKind: _FileKind.regular,
        );
        if (validated.identity == null ||
            currentIdentity != validated.identity) {
          throw const FileSystemException(
            'Capture plaintext identity changed after capability validation',
          );
        }
        _hook(
          PosixFileBoundary.beforePlaintextUnlink,
          plaintextSegments: validated.segments,
        );
        final removal = const AnchoredQuarantineRemovalProtocol()
            .removeExpected(
              operations: _quarantineOperations(
                sourceParentFd: parentFd,
                quarantineFd: cleanup.quarantineFd,
                quarantineIdentity: cleanup.quarantineIdentity,
                plaintextSegments: validated.segments,
              ),
              originalName: validated.segments.last,
              expectedIdentity: currentIdentity,
              kind: SecureFileKind.regular,
            );
        if (!removal.removedOrMissing || removal.releaseError != null) {
          _throwRemovalFailure(
            removal,
            'Cleanup could not prove the validated plaintext absent '
            '(${removal.state.name}, links: '
            '${removal.postRemovalLinkCount ?? 'unknown'})',
          );
        }
        final retainedLinks =
            removal.postRemovalLinkCount ?? _linkCount(leafFd);
        if (retainedLinks != 0) {
          _throwRemovalFailure(
            removal,
            'Cleanup could not prove the validated plaintext absent '
            '(${removal.state.name}, links: $retainedLinks)',
          );
        }
        _fsync(parentFd, 'capture plaintext parent');
      }
    } on Object catch (error, stackTrace) {
      primary = EntrySaveCause(
        phase: EntrySavePhase.plaintextCleanup,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      final closeResult = const FailureTotalCleanupRunner().run([
        PosixCleanupAction(
          PosixCleanupOperation.closeSource,
          () => _closeChecked(leafFd, 'capture plaintext descriptor'),
        ),
        for (final fd in openedParents.reversed)
          PosixCleanupAction(
            PosixCleanupOperation.closeAttempt,
            () => _closeChecked(fd, 'capture plaintext parent descriptor'),
          ),
      ]);
      for (final failure in closeResult.failures) {
        final cause = EntrySaveCause(
          phase: EntrySavePhase.plaintextCleanup,
          error: failure.error,
          stackTrace: failure.stackTrace,
        );
        if (primary == null) {
          primary = cause;
        } else {
          additional.add(cause);
        }
      }
    }
    if (primary != null) {
      throw SecureBlobFileSystemFailure(
        primary: primary,
        additionalFailures: additional,
        publishedBlob: null,
        stagingMayRemain: false,
      );
    }
  }

  _PosixLayout _openLayout({
    required bool create,
    bool needsQuarantine = true,
  }) {
    final root = _openTrustedRoot(supportDirectory, 'application support');
    var entriesFd = -1;
    var stagingFd = -1;
    var blobsFd = -1;
    var quarantineFd = -1;
    try {
      entriesFd = create
          ? _openOrCreateDirectoryAt(root.fd, 'entries')
          : _openDirectoryAt(root.fd, 'entries');
      stagingFd = create
          ? _openOrCreateDirectoryAt(entriesFd, 'staging')
          : _openDirectoryAt(entriesFd, 'staging');
      blobsFd = create
          ? _openOrCreateDirectoryAt(entriesFd, 'blobs')
          : _openDirectoryAt(entriesFd, 'blobs');
      SecureFileIdentity? quarantineIdentity;
      if (needsQuarantine) {
        quarantineFd = _openOrCreateDirectoryAt(
          entriesFd,
          _quarantineDirectory,
        );
        quarantineIdentity = _fileIdentity(
          quarantineFd,
          expectedKind: _FileKind.directory,
        );
        _validateQuarantineAuthority(quarantineFd, quarantineIdentity);
      }
      return _PosixLayout(
        rootFd: root.fd,
        rootIdentity: root.identity,
        entriesFd: entriesFd,
        entriesIdentity: _fileIdentity(
          entriesFd,
          expectedKind: _FileKind.directory,
        ),
        stagingFd: stagingFd,
        stagingIdentity: _fileIdentity(
          stagingFd,
          expectedKind: _FileKind.directory,
        ),
        blobsFd: blobsFd,
        blobsIdentity: _fileIdentity(
          blobsFd,
          expectedKind: _FileKind.directory,
        ),
        quarantineFd: quarantineFd,
        quarantineIdentity: quarantineIdentity,
      );
    } catch (_) {
      _closeIfOpen(quarantineFd);
      _closeIfOpen(blobsFd);
      _closeIfOpen(stagingFd);
      _closeIfOpen(entriesFd);
      _closeIfOpen(root.fd);
      rethrow;
    }
  }

  _OpenedRoot _openTrustedRoot(Directory directory, String label) {
    final fd = _openDirectoryPath(directory.path);
    try {
      final identity = _fileIdentity(fd, expectedKind: _FileKind.directory);
      final canonical = p.normalize(directory.resolveSymbolicLinksSync());
      final canonicalFd = _openDirectoryPath(canonical);
      try {
        if (_fileIdentity(canonicalFd, expectedKind: _FileKind.directory) !=
            identity) {
          throw FileSystemException(
            '$label changed while its trusted handle was acquired',
            directory.path,
          );
        }
      } finally {
        _closeIfOpen(canonicalFd);
      }
      return _OpenedRoot(fd, identity, canonical);
    } catch (_) {
      _closeIfOpen(fd);
      rethrow;
    }
  }

  int _openOrCreateDirectoryAt(int parentFd, String name) {
    final pointer = name.toNativeUtf8();
    try {
      final result = _syscalls.mkdirAt(parentFd, pointer, _directoryMode);
      if (result != 0 && _syscalls.errno != _eexist) {
        throw _lastError('mkdirat', name);
      }
    } finally {
      calloc.free(pointer);
    }
    return _openDirectoryAt(parentFd, name);
  }

  int _openDirectoryPath(String path) {
    final pointer = path.toNativeUtf8();
    var fd = -1;
    try {
      fd = _syscalls.open(
        pointer,
        _flags.readOnly |
            _flags.directory |
            _flags.noFollow |
            _flags.closeOnExec,
        0,
      );
      if (fd < 0) {
        throw _lastError('open trusted directory', path);
      }
      try {
        _fileIdentity(fd, expectedKind: _FileKind.directory);
      } on Object {
        _closeIfOpen(fd);
        fd = -1;
        rethrow;
      }
      return fd;
    } finally {
      calloc.free(pointer);
    }
  }

  int _openDirectoryAt(int parentFd, String name) {
    _validateSegment(name);
    final pointer = name.toNativeUtf8();
    var fd = -1;
    try {
      fd = _syscalls.openAt(
        parentFd,
        pointer,
        _flags.readOnly |
            _flags.directory |
            _flags.noFollow |
            _flags.closeOnExec,
        0,
      );
      if (fd < 0) {
        throw _lastError('openat directory', name);
      }
      try {
        _fileIdentity(fd, expectedKind: _FileKind.directory);
      } on Object {
        _closeIfOpen(fd);
        fd = -1;
        rethrow;
      }
      return fd;
    } finally {
      calloc.free(pointer);
    }
  }

  int _openFileAt(
    int parentFd,
    String name, {
    bool write = false,
    bool createExclusive = false,
  }) {
    _validateSegment(name);
    final pointer = name.toNativeUtf8();
    try {
      var flags =
          (write ? _flags.readWrite : _flags.readOnly) |
          _flags.noFollow |
          _flags.closeOnExec;
      if (createExclusive) {
        flags |= _flags.create | _flags.exclusive;
      }
      final fd = _syscalls.openAt(parentFd, pointer, flags, _fileMode);
      if (fd < 0) {
        throw _lastError('openat file', name);
      }
      return fd;
    } finally {
      calloc.free(pointer);
    }
  }

  String _createAttempt(int stagingFd) =>
      _createPrivateDirectory(stagingFd, 'attempt');

  String _createPrivateDirectory(int parentFd, String prefix) {
    final random = Random.secure();
    for (var attempt = 0; attempt < 128; attempt += 1) {
      final name =
          '$prefix-${List<int>.generate(16, (_) => random.nextInt(256)).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
      final pointer = name.toNativeUtf8();
      try {
        if (_syscalls.mkdirAt(parentFd, pointer, _directoryMode) == 0) {
          return name;
        }
        if (_syscalls.errno != _eexist) {
          throw _lastError('mkdirat private directory', name);
        }
      } finally {
        calloc.free(pointer);
      }
    }
    throw const FileSystemException(
      'Unable to allocate an exclusive private directory',
    );
  }

  void _linkAt(
    int sourceParentFd,
    String sourceName,
    int destinationParentFd,
    String destinationName,
  ) {
    final source = sourceName.toNativeUtf8();
    final destination = destinationName.toNativeUtf8();
    try {
      if (_syscalls.linkAt(
            sourceParentFd,
            source,
            destinationParentFd,
            destination,
            0,
          ) !=
          0) {
        throw _lastError('linkat encrypted blob publication', destinationName);
      }
    } finally {
      calloc.free(source);
      calloc.free(destination);
    }
  }

  void _unlinkAt(int parentFd, String name, {bool directory = false}) {
    final pointer = name.toNativeUtf8();
    try {
      if (_syscalls.unlinkAt(
            parentFd,
            pointer,
            directory ? _flags.removeDirectory : 0,
          ) !=
          0) {
        throw _lastError('unlinkat', name);
      }
      syscallFaultInjector?.afterSuccess(PosixSyscallOperation.unlinkat);
    } finally {
      calloc.free(pointer);
    }
  }

  void _renameNoReplace(
    int sourceParentFd,
    String sourceName,
    int destinationParentFd,
    String destinationName,
  ) {
    _validateSegment(sourceName);
    _validateSegment(destinationName);
    final source = sourceName.toNativeUtf8();
    final destination = destinationName.toNativeUtf8();
    try {
      if (_syscalls.renameNoReplace(
            sourceParentFd,
            source,
            destinationParentFd,
            destination,
          ) !=
          0) {
        final errno = _syscalls.errno;
        if (errno == _eexist) {
          throw const AnchoredDestinationExists();
        }
        if (errno == _enoent) {
          throw const AnchoredEntryMissing();
        }
        throw _PosixException(
          'atomic no-replace rename',
          '$sourceName -> $destinationName',
          errno,
        );
      }
    } finally {
      calloc.free(source);
      calloc.free(destination);
    }
  }

  AnchoredQuarantineOperations _quarantineOperations({
    required int sourceParentFd,
    required int quarantineFd,
    required SecureFileIdentity quarantineIdentity,
    String? destinationName,
    List<String>? plaintextSegments,
  }) => _PosixQuarantineOperations(
    this,
    sourceParentFd: sourceParentFd,
    quarantineFd: quarantineFd,
    quarantineIdentity: quarantineIdentity,
    destinationName: destinationName,
    plaintextSegments: plaintextSegments,
  );

  Never _throwRemovalFailure(QuarantineRemovalResult removal, String message) {
    final operationError =
        removal.error ?? FileSystemException(message, removal.quarantineName);
    final operationStackTrace = removal.stackTrace ?? StackTrace.current;
    if (removal.releaseError == null) {
      Error.throwWithStackTrace(operationError, operationStackTrace);
    }
    throw _QuarantineRemovalAndReleaseFailure(
      operationError: operationError,
      operationStackTrace: operationStackTrace,
      releaseError: removal.releaseError!,
      releaseStackTrace: removal.releaseStackTrace ?? StackTrace.current,
    );
  }

  void _writeAll(int fd, Uint8List bytes) {
    final buffer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      var offset = 0;
      while (offset < bytes.length) {
        final written = _syscalls.write(
          fd,
          (buffer + offset).cast<Void>(),
          bytes.length - offset,
        );
        if (written <= 0) {
          throw _lastError('write encrypted staging payload', _stagingLeaf);
        }
        offset += written;
      }
    } finally {
      calloc.free(buffer);
    }
  }

  Uint8List _readAll(int fd) {
    const chunkSize = 64 * 1024;
    final buffer = calloc<Uint8>(chunkSize);
    final output = BytesBuilder(copy: false);
    try {
      while (true) {
        final count = _syscalls.read(fd, buffer.cast<Void>(), chunkSize);
        if (count < 0) {
          throw _lastError('read encrypted blob', 'encrypted blob');
        }
        if (count == 0) {
          return output.takeBytes();
        }
        output.add(Uint8List.fromList(buffer.asTypedList(count)));
      }
    } finally {
      calloc.free(buffer);
    }
  }

  SecureFileIdentity _fileIdentity(int fd, {required _FileKind expectedKind}) {
    final decoded = _fileStat(fd, expectedKind: expectedKind);
    return SecureFileIdentity(device: decoded.device, inode: decoded.inode);
  }

  PosixFileStat _fileStat(int fd, {required _FileKind expectedKind}) {
    final stat = calloc<Uint8>(_statBufferSize);
    try {
      if (_syscalls.fstat(fd, stat.cast<Void>()) != 0) {
        throw _lastError('fstat', 'descriptor $fd');
      }
      syscallFaultInjector?.afterSuccess(PosixSyscallOperation.fstat);
      final decoded = _statLayout.decode(stat.asTypedList(_statBufferSize));
      final mode = decoded.mode;
      final actualKind = mode & _fileTypeMask;
      final requiredKind = expectedKind == _FileKind.directory
          ? _directoryType
          : _regularFileType;
      if (actualKind != requiredKind) {
        throw const FileSystemException(
          'Descriptor does not identify the required real filesystem object',
        );
      }
      return decoded;
    } finally {
      calloc.free(stat);
    }
  }

  int _linkCount(int fd) {
    final stat = calloc<Uint8>(_statBufferSize);
    try {
      if (_syscalls.fstat(fd, stat.cast<Void>()) != 0) {
        throw _lastError('fstat link count', 'descriptor $fd');
      }
      syscallFaultInjector?.afterSuccess(PosixSyscallOperation.fstat);
      return _statLayout.decode(stat.asTypedList(_statBufferSize)).linkCount;
    } finally {
      calloc.free(stat);
    }
  }

  void _validateQuarantineAuthority(
    int fd,
    SecureFileIdentity expectedIdentity,
  ) {
    final stat = _fileStat(fd, expectedKind: _FileKind.directory);
    final actualIdentity = SecureFileIdentity(
      device: stat.device,
      inode: stat.inode,
    );
    if (actualIdentity != expectedIdentity ||
        stat.ownerId != _syscalls.effectiveUserId() ||
        stat.mode & _permissionMask != _directoryMode) {
      throw const FileSystemException(
        'Quarantine authority lost its retained identity, owner, or 0700 mode',
      );
    }
  }

  PosixStatLayout get _statLayout =>
      PosixStatLayout.forAbi(currentPosixNativeAbi());

  _CleanupResult _cleanupAttempt(_PosixStagedBlob staged) {
    var attemptRemoved = false;
    final cleanup = const FailureTotalCleanupRunner().run([
      PosixCleanupAction(
        PosixCleanupOperation.fstat,
        () => _validateLayoutIdentities(staged.layout),
      ),
      PosixCleanupAction(
        PosixCleanupOperation.boundaryHook,
        () => _hook(
          PosixFileBoundary.beforeAttemptCleanup,
          attemptName: staged.attemptId,
        ),
      ),
      PosixCleanupAction(PosixCleanupOperation.unlinkat, () {
        if (staged.attemptFd < 0 || staged.sourceIdentity == null) {
          throw const FileSystemException(
            'Staging payload lacks an owned descriptor identity',
          );
        }
        final removal = const AnchoredQuarantineRemovalProtocol()
            .removeExpected(
              operations: _quarantineOperations(
                sourceParentFd: staged.attemptFd,
                quarantineFd: staged.layout.quarantineFd,
                quarantineIdentity: staged.layout.quarantineIdentity!,
              ),
              originalName: _stagingLeaf,
              expectedIdentity: staged.sourceIdentity!,
              kind: SecureFileKind.regular,
            );
        if (removal.state != QuarantineRemovalState.removed ||
            removal.postRemovalLinkCount == null ||
            removal.releaseError != null) {
          _throwRemovalFailure(
            removal,
            'Staging payload could not be proven removed '
            '(${removal.state.name}, links: '
            '${removal.postRemovalLinkCount ?? 'unknown'})',
          );
        }
      }),
      PosixCleanupAction(PosixCleanupOperation.closeSource, () {
        final fd = staged.sourceFd;
        staged.sourceFd = -1;
        _closeChecked(fd, 'staging source descriptor');
      }),
      PosixCleanupAction(PosixCleanupOperation.closeAttempt, () {
        final fd = staged.attemptFd;
        staged.attemptFd = -1;
        _closeChecked(fd, 'staging attempt descriptor');
      }),
      PosixCleanupAction(PosixCleanupOperation.unlinkat, () {
        if (staged.attemptIdentity == null) {
          throw const FileSystemException(
            'Staging attempt lacks an owned directory identity',
          );
        }
        final removal = const AnchoredQuarantineRemovalProtocol()
            .removeExpected(
              operations: _quarantineOperations(
                sourceParentFd: staged.layout.stagingFd,
                quarantineFd: staged.layout.quarantineFd,
                quarantineIdentity: staged.layout.quarantineIdentity!,
              ),
              originalName: staged.attemptId,
              expectedIdentity: staged.attemptIdentity!,
              kind: SecureFileKind.directory,
            );
        attemptRemoved =
            removal.state == QuarantineRemovalState.removed &&
            removal.postRemovalLinkCount == 0 &&
            removal.releaseError == null;
        if (!attemptRemoved) {
          _throwRemovalFailure(
            removal,
            'Staging attempt could not be proven removed '
            '(${removal.state.name}, links: '
            '${removal.postRemovalLinkCount ?? 'unknown'})',
          );
        }
      }),
      PosixCleanupAction(
        PosixCleanupOperation.fsync,
        () => _fsync(staged.layout.stagingFd, 'encrypted staging directory'),
      ),
      PosixCleanupAction(PosixCleanupOperation.closeBlobs, () {
        _closeChecked(staged.layout.blobsFd, 'blob directory descriptor');
      }),
      PosixCleanupAction(PosixCleanupOperation.closeQuarantine, () {
        _closeChecked(
          staged.layout.quarantineFd,
          'quarantine authority descriptor',
        );
      }),
      PosixCleanupAction(PosixCleanupOperation.closeStaging, () {
        _closeChecked(staged.layout.stagingFd, 'staging directory descriptor');
      }),
      PosixCleanupAction(PosixCleanupOperation.closeEntries, () {
        _closeChecked(staged.layout.entriesFd, 'entries directory descriptor');
      }),
      PosixCleanupAction(PosixCleanupOperation.closeRoot, () {
        _closeChecked(staged.layout.rootFd, 'support root descriptor');
      }),
    ]);
    staged.layout.closed = true;
    return _CleanupResult([
      for (final failure in cleanup.failures)
        EntrySaveCause(
          phase: EntrySavePhase.stagingCleanup,
          error: failure.error,
          stackTrace: failure.stackTrace,
        ),
    ], !attemptRemoved);
  }

  void _closeLayout(_PosixLayout layout) {
    if (layout.closed) {
      return;
    }
    layout.closed = true;
    _closeIfOpen(layout.blobsFd);
    _closeIfOpen(layout.quarantineFd);
    _closeIfOpen(layout.stagingFd);
    _closeIfOpen(layout.entriesFd);
    _closeIfOpen(layout.rootFd);
  }

  List<EntrySaveCause> _cleanupLayout(_PosixLayout layout) {
    if (layout.closed) {
      return const [];
    }
    layout.closed = true;
    final cleanup = const FailureTotalCleanupRunner().run([
      PosixCleanupAction(
        PosixCleanupOperation.closeBlobs,
        () => _closeChecked(layout.blobsFd, 'blob directory descriptor'),
      ),
      PosixCleanupAction(
        PosixCleanupOperation.closeQuarantine,
        () => _closeChecked(
          layout.quarantineFd,
          'quarantine authority descriptor',
        ),
      ),
      PosixCleanupAction(
        PosixCleanupOperation.closeStaging,
        () => _closeChecked(layout.stagingFd, 'staging directory descriptor'),
      ),
      PosixCleanupAction(
        PosixCleanupOperation.closeEntries,
        () => _closeChecked(layout.entriesFd, 'entries directory descriptor'),
      ),
      PosixCleanupAction(
        PosixCleanupOperation.closeRoot,
        () => _closeChecked(layout.rootFd, 'support root descriptor'),
      ),
    ]);
    return [
      for (final failure in cleanup.failures)
        EntrySaveCause(
          phase: EntrySavePhase.stagingCleanup,
          error: failure.error,
          stackTrace: failure.stackTrace,
        ),
    ];
  }

  void _validateLayoutIdentities(_PosixLayout layout) {
    if (_fileIdentity(layout.rootFd, expectedKind: _FileKind.directory) !=
            layout.rootIdentity ||
        _fileIdentity(layout.entriesFd, expectedKind: _FileKind.directory) !=
            layout.entriesIdentity ||
        _fileIdentity(layout.stagingFd, expectedKind: _FileKind.directory) !=
            layout.stagingIdentity ||
        _fileIdentity(layout.blobsFd, expectedKind: _FileKind.directory) !=
            layout.blobsIdentity) {
      throw const FileSystemException(
        'Encrypted storage directory descriptor identity changed',
      );
    }
    if (layout.quarantineFd >= 0) {
      _validateQuarantineAuthority(
        layout.quarantineFd,
        layout.quarantineIdentity!,
      );
    }
  }

  void _closeIfOpen(int fd) {
    if (fd >= 0) {
      _syscalls.close(fd);
    }
  }

  void _closeChecked(int fd, String label) {
    if (fd >= 0 && _syscalls.close(fd) != 0) {
      throw _lastError('close', label);
    }
    if (fd >= 0) {
      syscallFaultInjector?.afterSuccess(PosixSyscallOperation.close);
    }
  }

  void _fsync(int fd, String label) {
    if (_syscalls.fsync(fd) != 0) {
      throw _lastError('fsync', label);
    }
    syscallFaultInjector?.afterSuccess(PosixSyscallOperation.fsync);
  }

  _PosixException _lastError(String operation, String path) =>
      _PosixException(operation, path, _syscalls.errno);

  _OpenFlags get _flags => _OpenFlags.forCurrentPlatform();

  void _hook(
    PosixFileBoundary boundary, {
    String? attemptName,
    String? destinationName,
    List<String>? plaintextSegments,
  }) {
    boundaryHook?.call(
      boundary,
      PosixFileBoundaryContext(
        supportRootPath: supportDirectory.path,
        captureRootPath: captureTemporaryDirectory.path,
        attemptName: attemptName,
        destinationName: destinationName,
        plaintextSegments: plaintextSegments,
      ),
    );
  }

  bool _pathsOverlap(String first, String second) =>
      p.equals(first, second) ||
      p.isWithin(first, second) ||
      p.isWithin(second, first);

  void _validateDestinationName(String name) {
    if (!name.endsWith('.keeper')) {
      throw ArgumentError.value(name, 'destinationName');
    }
    _validateSegment(name);
  }

  void _validateSegments(List<String> segments) {
    if (segments.isEmpty) {
      throw ArgumentError.value(segments, 'relativePaths');
    }
    for (final segment in segments) {
      _validateSegment(segment);
    }
  }

  void _validateSegment(String segment) {
    final stem = segment.split('.').first.toUpperCase();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(segment) ||
        segment.endsWith('.') ||
        segment.endsWith(' ') ||
        RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
      throw ArgumentError.value(segment, 'path segment');
    }
  }
}

const _stagingLeaf = 'payload.part';
const _quarantineDirectory = 'quarantine';
const _captureQuarantineDirectory = 'keepers-quarantine';
const _directoryMode = 0x1c0; // 0700
const _fileMode = 0x180; // 0600
const _permissionMask = 0x1ff; // 0777
const _enoent = 2;
const _eexist = 17;
const _statBufferSize = 512;
const _fileTypeMask = 0xf000;
const _regularFileType = 0x8000;
const _directoryType = 0x4000;

PosixNativeAbi currentPosixNativeAbi() => selectPosixNativeAbi(Abi.current());

enum _FileKind { regular, directory }

final class _OpenedRoot {
  const _OpenedRoot(this.fd, this.identity, this.canonicalPath);
  final int fd;
  final SecureFileIdentity identity;
  final String canonicalPath;
}

final class _PosixLayout {
  _PosixLayout({
    required this.rootFd,
    required this.rootIdentity,
    required this.entriesFd,
    required this.entriesIdentity,
    required this.stagingFd,
    required this.stagingIdentity,
    required this.blobsFd,
    required this.blobsIdentity,
    required this.quarantineFd,
    required this.quarantineIdentity,
  });

  final int rootFd;
  final SecureFileIdentity rootIdentity;
  final int entriesFd;
  final SecureFileIdentity entriesIdentity;
  final int stagingFd;
  final SecureFileIdentity stagingIdentity;
  final int blobsFd;
  final SecureFileIdentity blobsIdentity;
  final int quarantineFd;
  final SecureFileIdentity? quarantineIdentity;
  bool closed = false;
}

final class _PosixStagedBlob implements SecureStagedBlob {
  _PosixStagedBlob({
    required this.token,
    required this.attemptId,
    required this.layout,
    required this.attemptFd,
  });

  final Object token;
  @override
  final String attemptId;
  final _PosixLayout layout;
  int attemptFd;
  int sourceFd = -1;
  SecureFileIdentity? attemptIdentity;
  SecureFileIdentity? sourceIdentity;
  bool consumed = false;
}

final class _PosixPublishedBlob implements SecurePublishedBlob {
  const _PosixPublishedBlob({
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

final class _PosixCaptureSnapshot implements SecureCaptureSnapshot {
  _PosixCaptureSnapshot({
    required Object token,
    required this.relativePath,
    required int rootFd,
    required SecureFileIdentity rootIdentity,
    required int captureFd,
    required SecureFileIdentity captureIdentity,
    required int attemptFd,
    required SecureFileIdentity? attemptIdentity,
    required int snapshotFd,
    required SecureFileIdentity? snapshotIdentity,
    required int quarantineFd,
    required SecureFileIdentity quarantineIdentity,
    required String attemptName,
    required String leafName,
  }) : _token = token,
       _rootFd = rootFd,
       _rootIdentity = rootIdentity,
       _captureFd = captureFd,
       _captureIdentity = captureIdentity,
       _attemptFd = attemptFd,
       _attemptIdentity = attemptIdentity,
       _snapshotFd = snapshotFd,
       _snapshotIdentity = snapshotIdentity,
       _quarantineFd = quarantineFd,
       _quarantineIdentity = quarantineIdentity,
       _attemptName = attemptName,
       _leafName = leafName;

  final Object _token;
  @override
  final String relativePath;
  int _rootFd;
  final SecureFileIdentity _rootIdentity;
  int _captureFd;
  final SecureFileIdentity _captureIdentity;
  int _attemptFd;
  SecureFileIdentity? _attemptIdentity;
  int _snapshotFd;
  SecureFileIdentity? _snapshotIdentity;
  int _quarantineFd;
  final SecureFileIdentity _quarantineIdentity;
  final String _attemptName;
  final String _leafName;
  Uint8List _bytesValue = Uint8List(0);
  bool _snapshotRemoved = true;
  bool _attemptRemoved = false;
  bool _cleaned = false;

  @override
  Uint8List get bytes => Uint8List.fromList(_bytesValue);
}

final class _ValidatedPlaintext {
  const _ValidatedPlaintext(this.segments, this.identity);
  final List<String> segments;
  final SecureFileIdentity? identity;
}

final class _PosixPlaintextCleanup implements SecurePlaintextCleanup {
  _PosixPlaintextCleanup({
    required this.token,
    required this.rootFd,
    required this.rootIdentity,
    required this.quarantineFd,
    required this.quarantineIdentity,
    required this.paths,
  });

  final Object token;
  int rootFd;
  final SecureFileIdentity rootIdentity;
  int quarantineFd;
  final SecureFileIdentity quarantineIdentity;
  final List<_ValidatedPlaintext> paths;
  bool consumed = false;

  @override
  List<List<String>> get relativePaths =>
      List<List<String>>.unmodifiable(paths.map((path) => path.segments));
}

final class _CleanupResult {
  const _CleanupResult(this.failures, this.mayRemain);
  final List<EntrySaveCause> failures;
  final bool mayRemain;
}

final class _QuarantineRemovalAndReleaseFailure implements Exception {
  const _QuarantineRemovalAndReleaseFailure({
    required this.operationError,
    required this.operationStackTrace,
    required this.releaseError,
    required this.releaseStackTrace,
  });

  final Object operationError;
  final StackTrace operationStackTrace;
  final Object releaseError;
  final StackTrace releaseStackTrace;
}

final class _PosixQuarantineOperations implements AnchoredQuarantineOperations {
  _PosixQuarantineOperations(
    this.owner, {
    required this.sourceParentFd,
    required this.quarantineFd,
    required this.quarantineIdentity,
    this.destinationName,
    this.plaintextSegments,
  });

  final PosixSecureBlobFileSystem owner;
  final int sourceParentFd;
  final int quarantineFd;
  final SecureFileIdentity quarantineIdentity;
  final String? destinationName;
  final List<String>? plaintextSegments;
  final Random _random = Random.secure();
  String? _privateAuthorityName;
  int _privateAuthorityFd = -1;
  SecureFileIdentity? _privateAuthorityIdentity;

  @override
  void beginPrivateMutation() {
    owner._validateQuarantineAuthority(quarantineFd, quarantineIdentity);
    final authorityName = owner._createPrivateDirectory(
      quarantineFd,
      'operation',
    );
    _privateAuthorityName = authorityName;
    try {
      _privateAuthorityFd = owner._openDirectoryAt(quarantineFd, authorityName);
      _privateAuthorityIdentity = owner._fileIdentity(
        _privateAuthorityFd,
        expectedKind: _FileKind.directory,
      );
      _validatePrivateAuthority();
    } on Object catch (error, stackTrace) {
      final authorityFd = _privateAuthorityFd;
      _privateAuthorityFd = -1;
      _privateAuthorityName = null;
      _privateAuthorityIdentity = null;
      final causes = <PrivateMutationReleaseCause>[
        PrivateMutationReleaseCause(error: error, stack: stackTrace),
      ];
      if (authorityFd >= 0) {
        try {
          owner._closeChecked(
            authorityFd,
            'unverified private mutation authority descriptor',
          );
        } on Object catch (cleanupError, cleanupStackTrace) {
          causes.add(
            PrivateMutationReleaseCause(
              error: cleanupError,
              stack: cleanupStackTrace,
            ),
          );
        }
      }
      throw PrivateMutationReleaseFailure(causes);
    }
  }

  @override
  void releasePrivateMutation() {
    final authorityFd = _privateAuthorityFd;
    final authorityName = _privateAuthorityName;
    final authorityIdentity = _privateAuthorityIdentity;
    if (authorityFd < 0 || authorityName == null || authorityIdentity == null) {
      return;
    }
    _privateAuthorityFd = -1;
    _privateAuthorityName = null;
    _privateAuthorityIdentity = null;
    var authorityValid = false;
    var authorityUnlinked = false;
    final release = const FailureTotalCleanupRunner().run([
      PosixCleanupAction(PosixCleanupOperation.boundaryHook, () {
        owner._hook(
          PosixFileBoundary.beforePrivateMutationRelease,
          destinationName: destinationName,
          plaintextSegments: plaintextSegments,
        );
      }),
      PosixCleanupAction(PosixCleanupOperation.fstat, () {
        owner._validateQuarantineAuthority(quarantineFd, quarantineIdentity);
        owner._validateQuarantineAuthority(authorityFd, authorityIdentity);
        authorityValid = true;
      }),
      PosixCleanupAction(PosixCleanupOperation.unlinkat, () {
        if (!authorityValid) {
          throw const FileSystemException(
            'Private mutation authority identity could not be verified',
          );
        }
        owner._unlinkAt(quarantineFd, authorityName, directory: true);
        authorityUnlinked = true;
        if (owner._linkCount(authorityFd) != 0) {
          throw const FileSystemException(
            'Private mutation authority removal could not be verified',
          );
        }
      }),
      PosixCleanupAction(PosixCleanupOperation.fsync, () {
        if (!authorityUnlinked) {
          throw const FileSystemException(
            'Private mutation authority was retained',
          );
        }
        owner._fsync(quarantineFd, 'private mutation authority root');
      }),
      PosixCleanupAction(
        PosixCleanupOperation.closeQuarantine,
        () => owner._closeChecked(
          authorityFd,
          'private mutation authority descriptor',
        ),
      ),
    ]);
    if (release.failures.isNotEmpty) {
      throw PrivateMutationReleaseFailure([
        for (final failure in release.failures)
          PrivateMutationReleaseCause(
            error: failure.error,
            stack: failure.stackTrace,
          ),
      ]);
    }
  }

  @override
  String createQuarantineName() =>
      'candidate-${List<int>.generate(16, (_) => _random.nextInt(256)).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';

  @override
  void moveToQuarantineNoReplace(String sourceName, String quarantineName) {
    _validatePrivateAuthority();
    owner._renameNoReplace(
      sourceParentFd,
      sourceName,
      _privateAuthorityFd,
      quarantineName,
    );
  }

  @override
  void restoreFromQuarantineNoReplace(
    String quarantineName,
    String destinationName,
  ) {
    _validatePrivateAuthority();
    owner._renameNoReplace(
      _privateAuthorityFd,
      quarantineName,
      sourceParentFd,
      destinationName,
    );
  }

  @override
  SecureFileIdentity openIdentity(String name, SecureFileKind kind) {
    _validatePrivateAuthority();
    var fd = -1;
    try {
      fd = kind == SecureFileKind.directory
          ? owner._openDirectoryAt(_privateAuthorityFd, name)
          : owner._openFileAt(_privateAuthorityFd, name);
      return owner._fileIdentity(
        fd,
        expectedKind: kind == SecureFileKind.directory
            ? _FileKind.directory
            : _FileKind.regular,
      );
    } on _PosixException catch (error) {
      if (error.errno == _enoent) {
        throw const AnchoredEntryMissing();
      }
      rethrow;
    } finally {
      owner._closeIfOpen(fd);
    }
  }

  @override
  int unlinkPrivateCandidate(
    String name,
    SecureFileKind kind,
    SecureFileIdentity expectedIdentity,
  ) {
    _validatePrivateAuthority();
    var fd = -1;
    try {
      fd = kind == SecureFileKind.directory
          ? owner._openDirectoryAt(_privateAuthorityFd, name)
          : owner._openFileAt(_privateAuthorityFd, name);
      final actual = owner._fileIdentity(
        fd,
        expectedKind: kind == SecureFileKind.directory
            ? _FileKind.directory
            : _FileKind.regular,
      );
      if (actual != expectedIdentity) {
        throw const FileSystemException(
          'Quarantine identity changed immediately before removal',
        );
      }
      final linksBefore = owner._linkCount(fd);
      owner._hook(
        PosixFileBoundary.afterQuarantineIdentityCheckBeforeUnlink,
        destinationName: destinationName,
        plaintextSegments: plaintextSegments,
      );
      owner._unlinkAt(
        _privateAuthorityFd,
        name,
        directory: kind == SecureFileKind.directory,
      );
      final linksAfter = owner._linkCount(fd);
      final identityWasRemoved = kind == SecureFileKind.directory
          ? linksAfter == 0
          : linksAfter == linksBefore - 1;
      if (!identityWasRemoved) {
        throw const FileSystemException(
          'Quarantine removal did not unlink its verified identity',
        );
      }
      return linksAfter;
    } on _PosixException catch (error) {
      if (error.errno == _enoent) {
        throw const AnchoredEntryMissing();
      }
      rethrow;
    } finally {
      owner._closeIfOpen(fd);
    }
  }

  void _validatePrivateAuthority() {
    final identity = _privateAuthorityIdentity;
    if (_privateAuthorityFd < 0 || identity == null) {
      throw const FileSystemException(
        'Private mutation authority has not been created',
      );
    }
    owner._validateQuarantineAuthority(quarantineFd, quarantineIdentity);
    owner._validateQuarantineAuthority(_privateAuthorityFd, identity);
  }
}

final class _PosixException extends FileSystemException {
  const _PosixException(this.operation, String path, this.errno)
    : super('$operation failed with errno $errno', path);

  final String operation;
  final int errno;
}

final class _OpenFlags {
  const _OpenFlags({
    required this.readOnly,
    required this.readWrite,
    required this.create,
    required this.exclusive,
    required this.noFollow,
    required this.closeOnExec,
    required this.directory,
    required this.removeDirectory,
  });

  final int readOnly;
  final int readWrite;
  final int create;
  final int exclusive;
  final int noFollow;
  final int closeOnExec;
  final int directory;
  final int removeDirectory;

  factory _OpenFlags.forCurrentPlatform() {
    if (Platform.isMacOS || Platform.isIOS) {
      return const _OpenFlags(
        readOnly: 0,
        readWrite: 2,
        create: 0x200,
        exclusive: 0x800,
        noFollow: 0x100,
        closeOnExec: 0x1000000,
        directory: 0x100000,
        removeDirectory: 0x80,
      );
    }
    return const _OpenFlags(
      readOnly: 0,
      readWrite: 2,
      create: 0x40,
      exclusive: 0x80,
      noFollow: 0x20000,
      closeOnExec: 0x80000,
      directory: 0x10000,
      removeDirectory: 0x200,
    );
  }
}

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32, Uint32);
typedef _OpenDart = int Function(Pointer<Utf8>, int, int);
typedef _OpenAtNative = Int32 Function(Int32, Pointer<Utf8>, Int32, Uint32);
typedef _OpenAtDart = int Function(int, Pointer<Utf8>, int, int);
typedef _MkdirAtNative = Int32 Function(Int32, Pointer<Utf8>, Uint32);
typedef _MkdirAtDart = int Function(int, Pointer<Utf8>, int);
typedef _LinkAtNative = Int32 Function(
  Int32,
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Int32,
);
typedef _LinkAtDart = int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int);
typedef _UnlinkAtNative = Int32 Function(Int32, Pointer<Utf8>, Int32);
typedef _UnlinkAtDart = int Function(int, Pointer<Utf8>, int);
typedef _RenameNoReplaceNative = Int32 Function(
  Int32,
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Uint32,
);
typedef _RenameNoReplaceDart = int Function(
  int,
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  int,
);
typedef _RenameAt2SyscallNative = IntPtr Function(
  IntPtr,
  Int32,
  Pointer<Utf8>,
  Int32,
  Pointer<Utf8>,
  Uint32,
);
typedef _RenameAt2SyscallDart = int Function(
  int,
  int,
  Pointer<Utf8>,
  int,
  Pointer<Utf8>,
  int,
);
typedef _ReadWriteNative = IntPtr Function(Int32, Pointer<Void>, IntPtr);
typedef _ReadWriteDart = int Function(int, Pointer<Void>, int);
typedef _FstatNative = Int32 Function(Int32, Pointer<Void>);
typedef _FstatDart = int Function(int, Pointer<Void>);
typedef _FdNative = Int32 Function(Int32);
typedef _FdDart = int Function(int);
typedef _UidNative = Uint32 Function();
typedef _UidDart = int Function();
typedef _ErrnoNative = Pointer<Int32> Function();
typedef _ErrnoDart = Pointer<Int32> Function();

final class _PosixBindings {
  _PosixBindings._(DynamicLibrary library)
    : open = library.lookupFunction<_OpenNative, _OpenDart>('open'),
      openAt = library.lookupFunction<_OpenAtNative, _OpenAtDart>('openat'),
      mkdirAt = library.lookupFunction<_MkdirAtNative, _MkdirAtDart>('mkdirat'),
      linkAt = library.lookupFunction<_LinkAtNative, _LinkAtDart>('linkat'),
      unlinkAt = library.lookupFunction<_UnlinkAtNative, _UnlinkAtDart>(
        'unlinkat',
      ),
      _darwinRenameNoReplace = currentPosixNativeAbi().usesDarwinRename
          ? library
                .lookupFunction<_RenameNoReplaceNative, _RenameNoReplaceDart>(
                  'renameatx_np',
                )
          : null,
      _renameAt2Syscall = currentPosixNativeAbi().usesDarwinRename
          ? null
          : library
                .lookupFunction<_RenameAt2SyscallNative, _RenameAt2SyscallDart>(
                  'syscall',
                ),
      read = library.lookupFunction<_ReadWriteNative, _ReadWriteDart>('read'),
      write = library.lookupFunction<_ReadWriteNative, _ReadWriteDart>('write'),
      fstat = library.lookupFunction<_FstatNative, _FstatDart>(
        PosixStatLayout.forAbi(currentPosixNativeAbi()).fstatSymbol,
      ),
      fsync = library.lookupFunction<_FdNative, _FdDart>('fsync'),
      close = library.lookupFunction<_FdNative, _FdDart>('close'),
      effectiveUserId = library.lookupFunction<_UidNative, _UidDart>('geteuid'),
      _errnoLocation = library.lookupFunction<_ErrnoNative, _ErrnoDart>(
        currentPosixNativeAbi().errnoSymbol,
      );

  static final _PosixBindings instance = _PosixBindings._(
    DynamicLibrary.process(),
  );

  final _OpenDart open;
  final _OpenAtDart openAt;
  final _MkdirAtDart mkdirAt;
  final _LinkAtDart linkAt;
  final _UnlinkAtDart unlinkAt;
  final _RenameNoReplaceDart? _darwinRenameNoReplace;
  final _RenameAt2SyscallDart? _renameAt2Syscall;
  final _ReadWriteDart read;
  final _ReadWriteDart write;
  final _FstatDart fstat;
  final _FdDart fsync;
  final _FdDart close;
  final _UidDart effectiveUserId;
  final _ErrnoDart _errnoLocation;

  int renameNoReplace(
    int sourceParentFd,
    Pointer<Utf8> sourceName,
    int destinationParentFd,
    Pointer<Utf8> destinationName,
  ) {
    final abi = currentPosixNativeAbi();
    if (abi.usesDarwinRename) {
      return _darwinRenameNoReplace!(
        sourceParentFd,
        sourceName,
        destinationParentFd,
        destinationName,
        0x4,
      );
    }
    return _renameAt2Syscall!(
      abi.renameAt2SyscallNumber!,
      sourceParentFd,
      sourceName,
      destinationParentFd,
      destinationName,
      0x1,
    );
  }

  int get errno => _errnoLocation().value;
}
