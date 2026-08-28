import 'dart:io';
import 'dart:typed_data';

import 'package:keepers/features/capture/data/entry_persistence_failure.dart';
import 'package:keepers/features/capture/data/secure_blob_file_system.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:path/path.dart' as p;

export 'package:keepers/features/capture/data/entry_persistence_failure.dart';
export 'package:keepers/features/capture/data/secure_blob_file_system.dart';

abstract interface class EntryBlobStore {
  Future<StagedEncryptedBlob> stage(String entryId, Uint8List encryptedBytes);
  Future<FinalizedEncryptedBlob> finalize(StagedEncryptedBlob staged);
  Future<void> rollback(FinalizedEncryptedBlob finalized);
  Future<CapturePlaintextCleanup> validatePlaintextRefs(
    Iterable<CapturePlaintextRef> refs,
  );
  Future<void> deletePlaintext(CapturePlaintextCleanup cleanup);
}

/// Validates logical references and delegates every security-sensitive file
/// operation to a capability-based filesystem implementation.
class EncryptedBlobStore implements EntryBlobStore {
  EncryptedBlobStore(
    Directory supportDirectory, {
    required Directory captureTemporaryDirectory,
    SecureBlobFileSystem? fileSystem,
  }) : supportDirectory = supportDirectory.absolute,
       captureTemporaryDirectory = captureTemporaryDirectory.absolute,
       _fileSystem =
           fileSystem ??
           PosixSecureBlobFileSystem(
             supportDirectory: supportDirectory,
             captureTemporaryDirectory: captureTemporaryDirectory,
           );

  final Directory supportDirectory;
  final Directory captureTemporaryDirectory;
  final SecureBlobFileSystem _fileSystem;
  final Object _storeToken = Object();
  final Set<FinalizedEncryptedBlob> _consumedFinalized = Set.identity();
  final Set<_StoreBoundCaptureSnapshotOwner> _cleanedSnapshots = Set.identity();

  @override
  Future<StagedEncryptedBlob> stage(
    String entryId,
    Uint8List encryptedBytes,
  ) async {
    _validateEntryId(entryId);
    try {
      final secure = await _fileSystem.stage(encryptedBytes);
      return StagedEncryptedBlob._(
        storeToken: _storeToken,
        entryId: entryId,
        secure: secure,
      );
    } on SecureBlobFileSystemFailure catch (error) {
      throw _translateFailure(error);
    }
  }

  @override
  Future<FinalizedEncryptedBlob> finalize(StagedEncryptedBlob staged) async {
    _validateStagedHandle(staged);
    final relativeRef = _relativeRef(staged.entryId);
    try {
      final secure = await _fileSystem.finalize(
        staged.secure,
        destinationName: '${staged.entryId}.keeper',
        publishedRef: relativeRef,
      );
      return _finalized(relativeRef, secure);
    } on SecureBlobFileSystemFailure catch (error) {
      throw _translateFailure(error);
    }
  }

  Future<Uint8List> read(String relativeRef, {int? maxBytes}) {
    final entryId = _entryIdFromRelativeRef(relativeRef);
    return _fileSystem.readBlob('$entryId.keeper', maxBytes: maxBytes);
  }

  Future<bool> exists(String relativeRef) {
    final entryId = _entryIdFromRelativeRef(relativeRef);
    return _fileSystem.blobExists('$entryId.keeper');
  }

  @override
  Future<void> rollback(FinalizedEncryptedBlob finalized) async {
    if (finalized is! _StoreBoundFinalizedEncryptedBlob ||
        !identical(finalized.storeToken, _storeToken) ||
        !_consumedFinalized.add(finalized)) {
      throw ArgumentError.value(
        finalized,
        'finalized',
        'Finalized blob capability is invalid, consumed, or belongs to '
            'another encrypted blob store',
      );
    }
    _entryIdFromRelativeRef(finalized.relativeRef);
    await _fileSystem.rollbackBlob(finalized.secure);
  }

  @override
  Future<CapturePlaintextCleanup> validatePlaintextRefs(
    Iterable<CapturePlaintextRef> refs,
  ) async {
    final snapshot = List<CapturePlaintextRef>.unmodifiable(refs);
    final relativePaths = <List<String>>[];
    for (final ref in snapshot) {
      _validateCaptureRef(ref.relativePath);
      relativePaths.add(List<String>.unmodifiable(p.split(ref.relativePath)));
    }
    final secure = await _fileSystem.validatePlaintextRefs(relativePaths);
    return CapturePlaintextCleanup._(storeToken: _storeToken, secure: secure);
  }

  @override
  Future<void> deletePlaintext(CapturePlaintextCleanup cleanup) {
    if (!identical(cleanup.storeToken, _storeToken)) {
      throw ArgumentError.value(
        cleanup,
        'cleanup',
        'Plaintext cleanup capability belongs to another encrypted blob store',
      );
    }
    return _deletePlaintext(cleanup.secure);
  }

  Future<void> _deletePlaintext(SecurePlaintextCleanup cleanup) async {
    try {
      await _fileSystem.deletePlaintext(cleanup);
    } on SecureBlobFileSystemFailure catch (error) {
      throw _translateFailure(error);
    }
  }

  Future<CaptureSnapshotOwner> createCaptureSnapshot({
    required String relativeSource,
    required String snapshotId,
    required String extension,
  }) async {
    _validateCaptureRef(relativeSource);
    final fileSystem = _fileSystem;
    if (fileSystem is! SecureCaptureFileSystem) {
      throw UnsupportedError(
        'The configured secure filesystem cannot create capture snapshots',
      );
    }
    final captureFileSystem = fileSystem as SecureCaptureFileSystem;
    try {
      final secure = await captureFileSystem.createCaptureSnapshot(
        sourceSegments: List<String>.unmodifiable(p.split(relativeSource)),
        snapshotId: snapshotId,
        extension: extension,
      );
      return _StoreBoundCaptureSnapshotOwner(_storeToken, secure);
    } on SecureCaptureSnapshotFailure catch (error) {
      throw CaptureSnapshotStoreFailure(
        primary: error.primary,
        additionalFailures: error.additionalFailures,
        residualSnapshot: error.residualSnapshot == null
            ? null
            : _StoreBoundCaptureSnapshotOwner(
                _storeToken,
                error.residualSnapshot!,
              ),
      );
    }
  }

  Future<void> deleteCaptureSnapshot(CaptureSnapshotOwner snapshot) async {
    if (snapshot is! _StoreBoundCaptureSnapshotOwner ||
        !identical(snapshot._storeToken, _storeToken)) {
      throw ArgumentError.value(
        snapshot,
        'snapshot',
        'Capture snapshot owner is invalid or belongs to another store',
      );
    }
    if (_cleanedSnapshots.contains(snapshot)) return;
    final fileSystem = _fileSystem;
    if (fileSystem is! SecureCaptureFileSystem) {
      throw UnsupportedError(
        'The configured secure filesystem cannot clean capture snapshots',
      );
    }
    final captureFileSystem = fileSystem as SecureCaptureFileSystem;
    try {
      await captureFileSystem.deleteCaptureSnapshot(snapshot._secure);
      _cleanedSnapshots.add(snapshot);
    } on SecureCaptureSnapshotFailure catch (error) {
      final residual = error.residualSnapshot == null ? null : snapshot;
      if (residual == null) _cleanedSnapshots.add(snapshot);
      throw CaptureSnapshotStoreFailure(
        primary: error.primary,
        additionalFailures: error.additionalFailures,
        residualSnapshot: residual,
      );
    }
  }

  _StoreBoundFinalizedEncryptedBlob _finalized(
    String relativeRef,
    SecurePublishedBlob secure,
  ) => _StoreBoundFinalizedEncryptedBlob(
    storeToken: _storeToken,
    relativeRef: relativeRef,
    secure: secure,
  );

  EncryptedBlobStoreFailure _translateFailure(
    SecureBlobFileSystemFailure failure,
  ) => EncryptedBlobStoreFailure(
    primary: failure.primary,
    additionalFailures: failure.additionalFailures,
    publishedBlob: failure.publishedBlob == null
        ? null
        : _finalized(
            failure.publishedBlob!.publishedRef,
            failure.publishedBlob!,
          ),
    stagingMayRemain: failure.stagingMayRemain,
    finalBlobMayRemain: failure.finalBlobMayRemain,
  );

  String _relativeRef(String entryId) =>
      p.join('entries', 'blobs', '$entryId.keeper');

  String _entryIdFromRelativeRef(String relativeRef) {
    final parts = p.split(relativeRef);
    final filename = parts.isEmpty ? '' : parts.last;
    final entryId = filename.endsWith('.keeper')
        ? filename.substring(0, filename.length - '.keeper'.length)
        : '';
    final valid =
        !p.isAbsolute(relativeRef) &&
        parts.length == 3 &&
        parts[0] == 'entries' &&
        parts[1] == 'blobs' &&
        entryId.isNotEmpty;
    if (!valid) {
      throw ArgumentError.value(
        relativeRef,
        'relativeRef',
        'Encrypted blob reference must be a relative entry blob path',
      );
    }
    _validateEntryId(entryId);
    return entryId;
  }

  void _validateStagedHandle(StagedEncryptedBlob staged) {
    if (!identical(staged.storeToken, _storeToken)) {
      throw ArgumentError.value(
        staged,
        'staged',
        'Staged blob handle belongs to another encrypted blob store',
      );
    }
    _validateEntryId(staged.entryId);
  }

  void _validateEntryId(String entryId) {
    final stem = entryId.split('.').first.toUpperCase();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(entryId) ||
        RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
      throw ArgumentError.value(
        entryId,
        'entryId',
        'Entry ID must use the generated safe alphabet',
      );
    }
  }

  void _validateCaptureRef(String relativeRef) {
    final parts = p.split(relativeRef);
    final valid =
        relativeRef.isNotEmpty &&
        !p.isAbsolute(relativeRef) &&
        parts.isNotEmpty &&
        parts.first.toLowerCase() != 'keepers-quarantine' &&
        parts.every(_isSafePathSegment);
    if (!valid) {
      throw ArgumentError.value(
        relativeRef,
        'plaintextRefs',
        'Capture plaintext references must contain only safe relative segments',
      );
    }
  }

  bool _isSafePathSegment(String segment) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(segment) ||
        segment.endsWith('.') ||
        segment.endsWith(' ')) {
      return false;
    }
    final stem = segment.split('.').first.toUpperCase();
    return !RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem);
  }
}

final class StagedEncryptedBlob {
  const StagedEncryptedBlob._({
    required this.storeToken,
    required this.entryId,
    required this.secure,
  });

  final Object storeToken;
  final String entryId;
  final SecureStagedBlob secure;

  String get attemptId => secure.attemptId;
}

abstract interface class FinalizedEncryptedBlob {
  String get relativeRef;
  SecureFileIdentity get publicationIdentity;
}

final class _StoreBoundFinalizedEncryptedBlob
    implements FinalizedEncryptedBlob {
  const _StoreBoundFinalizedEncryptedBlob({
    required this.storeToken,
    required this.relativeRef,
    required this.secure,
  });

  final Object storeToken;
  @override
  final String relativeRef;
  final SecurePublishedBlob secure;

  @override
  SecureFileIdentity get publicationIdentity => secure.identity;
}

final class EncryptedBlobStoreFailure implements Exception {
  EncryptedBlobStoreFailure({
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
  final FinalizedEncryptedBlob? publishedBlob;
  final bool stagingMayRemain;
  final bool finalBlobMayRemain;

  String? get publishedBlobRef => publishedBlob?.relativeRef;

  @override
  String toString() =>
      'EncryptedBlobStoreFailure(primary: ${primary.phase.name}, '
      'additional: '
      '${additionalFailures.map((cause) => cause.phase.name).join(',')}, '
      'published: ${publishedBlob != null}, '
      'stagingMayRemain: $stagingMayRemain, '
      'finalBlobMayRemain: $finalBlobMayRemain)';
}

final class CapturePlaintextCleanup {
  const CapturePlaintextCleanup._({
    required this.storeToken,
    required this.secure,
  });

  final Object storeToken;
  final SecurePlaintextCleanup secure;

  List<List<String>> get relativePaths => secure.relativePaths;
}

sealed class CaptureSnapshotOwner {
  const CaptureSnapshotOwner._();

  String get relativePath;
  Uint8List get bytes;
}

final class _StoreBoundCaptureSnapshotOwner extends CaptureSnapshotOwner {
  const _StoreBoundCaptureSnapshotOwner(this._storeToken, this._secure)
    : super._();

  final Object _storeToken;
  final SecureCaptureSnapshot _secure;

  @override
  String get relativePath => _secure.relativePath;

  @override
  Uint8List get bytes => _secure.bytes;
}

final class CaptureSnapshotStoreFailure implements Exception {
  CaptureSnapshotStoreFailure({
    required this.primary,
    required Iterable<Object> additionalFailures,
    required this.residualSnapshot,
  }) : additionalFailures = List<Object>.unmodifiable(additionalFailures);

  final Object primary;
  final List<Object> additionalFailures;
  final CaptureSnapshotOwner? residualSnapshot;
}
