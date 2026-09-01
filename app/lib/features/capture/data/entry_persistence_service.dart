// ignore_for_file: prefer_initializing_formals

import 'package:keepers/features/capture/data/encrypted_blob_store.dart';
import 'package:keepers/features/capture/data/entry_cipher.dart';
import 'package:keepers/features/capture/data/entry_key_resolver.dart';
import 'package:keepers/features/capture/data/entry_payload_codec.dart';
import 'package:keepers/features/capture/data/entry_repository.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

export 'package:keepers/features/capture/data/entry_persistence_failure.dart';

typedef EntryDatabaseFactory = Future<Database> Function();

final class EntryPersistenceService {
  EntryPersistenceService({
    required EntryPayloadCodec codec,
    required EntryKeyResolver keyResolver,
    required EntryCipher cipher,
    required EntryBlobStore blobStore,
    required EntryMetadataRepository repository,
    required EntryDatabaseFactory database,
  }) : _codec = codec,
       _keyResolver = keyResolver,
       _cipher = cipher,
       _blobStore = blobStore,
       _repository = repository,
       _database = database;

  final EntryPayloadCodec _codec;
  final EntryKeyResolver _keyResolver;
  final EntryCipher _cipher;
  final EntryBlobStore _blobStore;
  final EntryMetadataRepository _repository;
  final EntryDatabaseFactory _database;

  Future<EntryMetadata> save(EntrySaveRequest request) async {
    EntrySavePhase phase = EntrySavePhase.plaintextValidation;
    EntrySaveCause? primary;
    final compensations = <EntrySaveCause>[];
    String? finalRef;
    FinalizedEncryptedBlob? finalized;
    CapturePlaintextCleanup? plaintextCleanup;
    var metadataCommitted = false;
    var finalizedBlobState = EntryArtifactState.absent;
    var stagedBlobState = EntryArtifactState.absent;
    var plaintextMayRemain = request.plaintextRefs.isNotEmpty;
    try {
      plaintextCleanup = await _blobStore.validatePlaintextRefs(
        request.plaintextRefs,
      );
      phase = EntrySavePhase.payloadEncoding;
      final canonicalPayload = _codec.encode(request.payload);
      phase = EntrySavePhase.requestValidation;
      _validateRequest(request);
      phase = EntrySavePhase.keyResolution;
      final resolvedKey = await _keyResolver.resolve(
        request.metadata.privacy,
        request.identity,
      );
      phase = EntrySavePhase.encryption;
      final encryptedPayload = await _cipher.encrypt(
        plaintext: canonicalPayload,
        keyBytes: resolvedKey.bytes,
        metadata: request.metadata,
        keyScope: resolvedKey.scope,
      );
      phase = EntrySavePhase.stageBlob;
      final staged = await _blobStore.stage(
        request.metadata.id,
        encryptedPayload,
      );
      stagedBlobState = EntryArtifactState.present;
      phase = EntrySavePhase.finalizeBlob;
      finalized = await _blobStore.finalize(staged);
      finalRef = finalized.relativeRef;
      stagedBlobState = EntryArtifactState.absent;
      finalizedBlobState = EntryArtifactState.present;
      phase = EntrySavePhase.databaseOpen;
      final database = await _database();
      phase = EntrySavePhase.metadataInsert;
      await database.transaction<void>(
        (transaction) =>
            _repository.insert(transaction, request.metadata, finalRef!),
      );
      metadataCommitted = true;
    } on Object catch (error, stackTrace) {
      if (error is EncryptedBlobStoreFailure) {
        primary = error.primary;
        compensations.addAll(error.additionalFailures);
        stagedBlobState = error.stagingMayRemain
            ? EntryArtifactState.unknown
            : EntryArtifactState.absent;
        if (error.finalBlobMayRemain) {
          finalizedBlobState = EntryArtifactState.unknown;
        }
        if (error.publishedBlob != null) {
          finalized = error.publishedBlob;
          finalRef = finalized!.relativeRef;
          finalizedBlobState = EntryArtifactState.present;
        }
      } else {
        primary = EntrySaveCause(
          phase: phase,
          error: error,
          stackTrace: stackTrace,
        );
        if (phase == EntrySavePhase.stageBlob) {
          stagedBlobState = EntryArtifactState.unknown;
        }
      }
      if (!metadataCommitted &&
          finalized != null &&
          finalizedBlobState != EntryArtifactState.absent) {
        try {
          await _blobStore.rollback(finalized);
          finalizedBlobState = EntryArtifactState.absent;
        } on Object catch (rollbackError, rollbackStackTrace) {
          finalizedBlobState = EntryArtifactState.unknown;
          compensations.add(
            EntrySaveCause(
              phase: EntrySavePhase.finalBlobRollback,
              error: rollbackError,
              stackTrace: rollbackStackTrace,
            ),
          );
        }
      }
    }

    if (plaintextCleanup != null) {
      try {
        await _blobStore.deletePlaintext(plaintextCleanup);
        plaintextMayRemain = false;
      } on Object catch (error, stackTrace) {
        final cleanupFailures = error is EncryptedBlobStoreFailure
            ? [error.primary, ...error.additionalFailures]
            : [
                EntrySaveCause(
                  phase: EntrySavePhase.plaintextCleanup,
                  error: error,
                  stackTrace: stackTrace,
                ),
              ];
        if (primary == null) {
          primary = cleanupFailures.first;
          compensations.addAll(cleanupFailures.skip(1));
        } else {
          compensations.addAll(cleanupFailures);
        }
      }
    }

    if (primary != null) {
      throw EntrySaveFailure(
        primary: primary,
        compensations: compensations,
        consistency: EntrySaveConsistency(
          metadataCommitted: metadataCommitted,
          finalizedBlobState: finalizedBlobState,
          stagedBlobState: stagedBlobState,
          plaintextMayRemain: plaintextMayRemain,
        ),
        committedMetadata: metadataCommitted
            ? request.metadata.copyWith(blobRef: finalRef)
            : null,
      );
    }
    return request.metadata.copyWith(blobRef: finalRef);
  }

  void _validateRequest(EntrySaveRequest request) {
    final metadata = request.metadata;
    final identity = request.identity;
    if (metadata.familyId != identity.familyId ||
        metadata.authorId != identity.memberId ||
        metadata.format != request.payload.format) {
      throw ArgumentError.value(
        request,
        'request',
        'Entry metadata must match its payload and author identity',
      );
    }
  }
}
