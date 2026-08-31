import 'package:flutter/foundation.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';

enum MemoryFormat { photo, voice, text }

enum PrivacyTier {
  journal('journal'),
  reveal('reveal'),
  capsule('legacy');

  const PrivacyTier(this.storageValue);

  final String storageValue;

  static PrivacyTier fromStorage(String value) => switch (value) {
    'journal' => PrivacyTier.journal,
    'reveal' => PrivacyTier.reveal,
    'legacy' => PrivacyTier.capsule,
    _ => throw FormatException('Unsupported privacy tier: $value'),
  };
}

enum PhotoSource { camera, library }

enum CapturePhase {
  editing,
  recovering,
  picking,
  starting,
  recording,
  stopping,
  cleaning,
  saving,
  saved,
  committedCleanup,
  failed,
}

enum CapturePermissionSource { camera, library, microphone }

enum CaptureRetryIntent {
  save,
  discard,
  camera,
  library,
  recording,
  replacePrimary,
  recoverLostPhoto,
  selectPhoto,
  selectVoice,
  selectText,
  pendingCleanup,
  committedCleanup,
}

extension PhotoSourcePermission on PhotoSource {
  CapturePermissionSource get permissionSource => switch (this) {
    PhotoSource.camera => CapturePermissionSource.camera,
    PhotoSource.library => CapturePermissionSource.library,
  };
}

final class CapturePermissionException implements Exception {
  const CapturePermissionException(this.source, [this.cause]);

  final CapturePermissionSource source;
  final Object? cause;
}

enum EntryKeyScope { member, family }

final class EntryMetadata {
  const EntryMetadata({
    required this.id,
    required this.familyId,
    required this.authorId,
    required this.createdAt,
    required this.format,
    required this.privacy,
    this.blobRef,
  });

  final String id;
  final String familyId;
  final String authorId;
  final DateTime createdAt;
  final MemoryFormat format;
  final PrivacyTier privacy;
  final String? blobRef;

  Map<String, Object> authenticatedMap(EntryKeyScope scope) => {
    'author_id': authorId,
    'created_at': createdAt.millisecondsSinceEpoch,
    'entry_id': id,
    'entry_type': format.name,
    'family_id': familyId,
    'key_scope': scope.name,
    'privacy_tier': privacy.storageValue,
  };

  EntryMetadata copyWith({
    String? id,
    String? familyId,
    String? authorId,
    DateTime? createdAt,
    MemoryFormat? format,
    PrivacyTier? privacy,
    String? blobRef,
  }) => EntryMetadata(
    id: id ?? this.id,
    familyId: familyId ?? this.familyId,
    authorId: authorId ?? this.authorId,
    createdAt: createdAt ?? this.createdAt,
    format: format ?? this.format,
    privacy: privacy ?? this.privacy,
    blobRef: blobRef ?? this.blobRef,
  );

  @override
  bool operator ==(Object other) =>
      other is EntryMetadata &&
      other.id == id &&
      other.familyId == familyId &&
      other.authorId == authorId &&
      other.createdAt == createdAt &&
      other.format == format &&
      other.privacy == privacy &&
      other.blobRef == blobRef;

  @override
  int get hashCode =>
      Object.hash(id, familyId, authorId, createdAt, format, privacy, blobRef);
}

final class EntryPayload {
  const EntryPayload({
    required this.format,
    required this.primaryBytes,
    required this.text,
    required this.caption,
    required this.mediaExtension,
    required this.mediaDurationMs,
  });

  final MemoryFormat format;
  final Uint8List? primaryBytes;
  final String? text;
  final String? caption;
  final String? mediaExtension;
  final int? mediaDurationMs;

  @override
  bool operator ==(Object other) =>
      other is EntryPayload &&
      other.format == format &&
      listEquals(other.primaryBytes, primaryBytes) &&
      other.text == text &&
      other.caption == caption &&
      other.mediaExtension == mediaExtension &&
      other.mediaDurationMs == mediaDurationMs;

  @override
  int get hashCode => Object.hash(
    format,
    primaryBytes == null ? null : Object.hashAll(primaryBytes!),
    text,
    caption,
    mediaExtension,
    mediaDurationMs,
  );
}

final class EntrySaveRequest {
  EntrySaveRequest({
    required this.metadata,
    required this.payload,
    required this.identity,
    this.capsuleOptions,
    required Iterable<CapturePlaintextRef> plaintextRefs,
  }) : plaintextRefs = List<CapturePlaintextRef>.unmodifiable(plaintextRefs);

  final EntryMetadata metadata;
  final EntryPayload payload;
  final LocalIdentity identity;
  final CapsuleSaveOptions? capsuleOptions;
  final List<CapturePlaintextRef> plaintextRefs;
}

final class CapsuleSaveOptions {
  factory CapsuleSaveOptions({String? unlockTask}) {
    if (unlockTask == null) return const CapsuleSaveOptions._(null);
    final normalized = unlockTask.trim();
    if (normalized.isEmpty || normalized.length > maxTaskCharacters) {
      throw ArgumentError.value(
        unlockTask,
        'unlockTask',
        'A configured Capsule task must be 1–$maxTaskCharacters characters',
      );
    }
    return CapsuleSaveOptions._(normalized);
  }

  const CapsuleSaveOptions._(this.unlockTask);

  static const int maxTaskCharacters = 180;

  final String? unlockTask;

  @override
  bool operator ==(Object other) =>
      other is CapsuleSaveOptions && other.unlockTask == unlockTask;

  @override
  int get hashCode => unlockTask.hashCode;
}

final class CapturePlaintextRef {
  const CapturePlaintextRef(this.relativePath);

  final String relativePath;
}

final class CaptureDraft {
  const CaptureDraft({
    this.format = MemoryFormat.photo,
    this.privacy = PrivacyTier.reveal,
    this.caption = '',
    this.photoPath,
    this.voicePath,
    this.voiceDuration = Duration.zero,
    this.recordingActive = false,
    this.text = '',
    this.capsuleTaskEnabled = false,
    this.capsuleTask = '',
    this.phase = CapturePhase.editing,
    this.errorMessage,
    this.retryIntent,
    this.cleanupRequired = false,
    this.savedEntry,
  });

  final MemoryFormat format;
  final PrivacyTier privacy;
  final String caption;
  final String? photoPath;
  final String? voicePath;
  final Duration voiceDuration;
  final bool recordingActive;
  final String text;
  final bool capsuleTaskEnabled;
  final String capsuleTask;
  final CapturePhase phase;
  final String? errorMessage;
  final CaptureRetryIntent? retryIntent;
  final bool cleanupRequired;
  final EntryMetadata? savedEntry;

  bool get isRecording => recordingActive;
  bool get hasPrimary => switch (format) {
    MemoryFormat.photo => photoPath != null,
    MemoryFormat.voice => voicePath != null && voiceDuration > Duration.zero,
    MemoryFormat.text => text.trim().isNotEmpty,
  };
  bool get capsuleTaskValid {
    if (!capsuleTaskEnabled) return true;
    final normalized = capsuleTask.trim();
    return normalized.isNotEmpty &&
        normalized.length <= CapsuleSaveOptions.maxTaskCharacters;
  }

  bool get canSave =>
      hasPrimary &&
      !isRecording &&
      (privacy != PrivacyTier.capsule || capsuleTaskValid) &&
      (phase == CapturePhase.editing ||
          (phase == CapturePhase.failed &&
              retryIntent == CaptureRetryIntent.save));
  bool get retryRequiresCleanup => switch (retryIntent) {
    CaptureRetryIntent.discard ||
    CaptureRetryIntent.replacePrimary ||
    CaptureRetryIntent.selectPhoto ||
    CaptureRetryIntent.selectVoice ||
    CaptureRetryIntent.selectText ||
    CaptureRetryIntent.committedCleanup => true,
    _ => false,
  };
  bool get hasDraft =>
      hasPrimary ||
      caption.trim().isNotEmpty ||
      isRecording ||
      capsuleTaskEnabled ||
      capsuleTask.trim().isNotEmpty;

  CaptureDraft copyWith({
    MemoryFormat? format,
    PrivacyTier? privacy,
    String? caption,
    String? photoPath,
    bool clearPhotoPath = false,
    String? voicePath,
    bool clearVoicePath = false,
    Duration? voiceDuration,
    bool? recordingActive,
    String? text,
    bool? capsuleTaskEnabled,
    String? capsuleTask,
    CapturePhase? phase,
    String? errorMessage,
    bool clearErrorMessage = false,
    CaptureRetryIntent? retryIntent,
    bool clearRetryIntent = false,
    bool? cleanupRequired,
    EntryMetadata? savedEntry,
    bool clearSavedEntry = false,
  }) => CaptureDraft(
    format: format ?? this.format,
    privacy: privacy ?? this.privacy,
    caption: caption ?? this.caption,
    photoPath: clearPhotoPath ? null : photoPath ?? this.photoPath,
    voicePath: clearVoicePath ? null : voicePath ?? this.voicePath,
    voiceDuration: voiceDuration ?? this.voiceDuration,
    recordingActive: recordingActive ?? this.recordingActive,
    text: text ?? this.text,
    capsuleTaskEnabled: capsuleTaskEnabled ?? this.capsuleTaskEnabled,
    capsuleTask: capsuleTask ?? this.capsuleTask,
    phase: phase ?? this.phase,
    errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
    retryIntent: clearRetryIntent ? null : retryIntent ?? this.retryIntent,
    cleanupRequired: cleanupRequired ?? this.cleanupRequired,
    savedEntry: clearSavedEntry ? null : savedEntry ?? this.savedEntry,
  );
}
