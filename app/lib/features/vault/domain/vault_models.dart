import 'package:keepers/features/capture/domain/capture_models.dart';

final class VaultEntryMetadata {
  const VaultEntryMetadata({
    required this.id,
    required this.familyId,
    required this.authorId,
    required this.createdAt,
    required this.format,
    required this.privacy,
    required this.blobRef,
    required this.state,
  });

  factory VaultEntryMetadata.fromRow(Map<String, Object?> row) =>
      VaultEntryMetadata(
        id: row['id']! as String,
        familyId: row['family_id']! as String,
        authorId: row['author_id']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at']! as int,
          isUtc: true,
        ),
        format: MemoryFormat.values.byName(row['entry_type']! as String),
        privacy: PrivacyTier.values.byName(row['privacy_tier']! as String),
        blobRef: row['blob_ref']! as String,
        state: row['state']! as String,
      );

  final String id;
  final String familyId;
  final String authorId;
  final DateTime createdAt;
  final MemoryFormat format;
  final PrivacyTier privacy;
  final String blobRef;
  final String state;

  /// Captions live only in the encrypted payload, never in vault metadata.
  String? get caption => null;

  EntryMetadata toEntryMetadata() => EntryMetadata(
    id: id,
    familyId: familyId,
    authorId: authorId,
    createdAt: createdAt,
    format: format,
    privacy: privacy,
    blobRef: blobRef,
  );

  VaultEntryMetadata copyWith({
    String? id,
    String? familyId,
    String? authorId,
    DateTime? createdAt,
    MemoryFormat? format,
    PrivacyTier? privacy,
    String? blobRef,
    String? state,
  }) => VaultEntryMetadata(
    id: id ?? this.id,
    familyId: familyId ?? this.familyId,
    authorId: authorId ?? this.authorId,
    createdAt: createdAt ?? this.createdAt,
    format: format ?? this.format,
    privacy: privacy ?? this.privacy,
    blobRef: blobRef ?? this.blobRef,
    state: state ?? this.state,
  );
}

sealed class MemoryOpenResult {
  const MemoryOpenResult();
}

final class OpenedMemory extends MemoryOpenResult {
  const OpenedMemory({required this.metadata, required this.payload});

  final VaultEntryMetadata metadata;
  final EntryPayload payload;
}

final class UnavailableMemory extends MemoryOpenResult {
  const UnavailableMemory(this.message);

  final String message;
}

extension MemoryFormatVaultCopy on MemoryFormat {
  String get vaultLabel => switch (this) {
    MemoryFormat.photo => 'Photo memory',
    MemoryFormat.voice => 'Voice memory',
    MemoryFormat.text => 'Text memory',
  };
}

extension PrivacyTierVaultCopy on PrivacyTier {
  String get vaultLabel => switch (this) {
    PrivacyTier.journal => 'Private Journal',
    PrivacyTier.reveal => 'Weekly Reveal',
    PrivacyTier.legacy => 'Legacy Milestone',
  };
}
