import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final class VaultRepository {
  Future<List<VaultEntryMetadata>> listForFamily(
    DatabaseExecutor db,
    String familyId,
  ) async {
    final rows = await db.query(
      'entries',
      columns: const [
        'id',
        'family_id',
        'author_id',
        'created_at',
        'entry_type',
        'privacy_tier',
        'blob_ref',
        'state',
      ],
      where: 'family_id = ?',
      whereArgs: [familyId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(VaultEntryMetadata.fromRow).toList(growable: false);
  }
}
