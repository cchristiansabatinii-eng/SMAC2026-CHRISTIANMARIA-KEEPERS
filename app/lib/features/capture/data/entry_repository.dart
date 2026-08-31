import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

abstract interface class EntryMetadataRepository {
  Future<void> insert(
    DatabaseExecutor db,
    EntryMetadata metadata,
    String blobRef,
  );
}

class EntryRepository implements EntryMetadataRepository {
  @override
  Future<void> insert(
    DatabaseExecutor db,
    EntryMetadata metadata,
    String blobRef,
  ) async {
    _validateBlobRef(blobRef);
    await db.insert('entries', {
      'id': metadata.id,
      'family_id': metadata.familyId,
      'author_id': metadata.authorId,
      'created_at': metadata.createdAt.millisecondsSinceEpoch,
      'entry_type': metadata.format.name,
      'privacy_tier': metadata.privacy.storageValue,
      'blob_ref': blobRef,
      'transcript': null,
      'embedding': null,
      'state': 'pending',
      'expires_at': null,
      'revealed_at': null,
      'kept_at': null,
    });
  }

  void _validateBlobRef(String blobRef) {
    final parts = p.split(blobRef);
    final valid =
        !p.isAbsolute(blobRef) &&
        parts.length == 3 &&
        parts[0] == 'entries' &&
        parts[1] == 'blobs' &&
        parts[2].endsWith('.keeper') &&
        parts[2].length > '.keeper'.length &&
        !parts.contains('..') &&
        !parts.contains('.');
    if (!valid) {
      throw ArgumentError.value(
        blobRef,
        'blobRef',
        'Only relative encrypted blob references may be stored',
      );
    }
  }
}
