import 'package:keepers/features/capture/domain/capture_models.dart';

enum EntrySavePhase {
  plaintextValidation,
  payloadEncoding,
  requestValidation,
  keyResolution,
  encryption,
  stageBlob,
  finalizeBlob,
  stagingCleanup,
  databaseOpen,
  metadataInsert,
  finalBlobRollback,
  plaintextCleanup,
}

final class EntrySaveCause {
  const EntrySaveCause({
    required this.phase,
    required this.error,
    required this.stackTrace,
  });

  final EntrySavePhase phase;
  final Object error;
  final StackTrace stackTrace;
}

enum EntryArtifactState { absent, present, unknown }

final class EntrySaveConsistency {
  const EntrySaveConsistency({
    required this.metadataCommitted,
    required this.finalizedBlobState,
    required this.stagedBlobState,
    required this.plaintextMayRemain,
  });

  final bool metadataCommitted;
  final EntryArtifactState finalizedBlobState;
  final EntryArtifactState stagedBlobState;
  final bool plaintextMayRemain;

  bool get finalizedBlobPresent =>
      finalizedBlobState == EntryArtifactState.present;
  bool get stagedBlobMayRemain => stagedBlobState != EntryArtifactState.absent;
}

final class EntrySaveFailure implements Exception {
  EntrySaveFailure({
    required this.primary,
    required Iterable<EntrySaveCause> compensations,
    required this.consistency,
    this.committedMetadata,
  }) : compensations = List<EntrySaveCause>.unmodifiable(compensations) {
    final hasAuthoritativeMetadata =
        committedMetadata != null && committedMetadata!.blobRef != null;
    if (consistency.metadataCommitted != hasAuthoritativeMetadata) {
      throw ArgumentError(
        'Committed consistency requires authoritative metadata with a blob reference',
      );
    }
  }

  final EntrySaveCause primary;
  final List<EntrySaveCause> compensations;
  final EntrySaveConsistency consistency;
  final EntryMetadata? committedMetadata;

  @override
  String toString() =>
      'EntrySaveFailure(primary: ${primary.phase.name}, '
      'compensations: ${compensations.map((cause) => cause.phase.name).join(',')})';
}
