import 'package:keepers/features/family/domain/family_code.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final class FamilyCodeCacheRecord {
  FamilyCodeCacheRecord({
    required this.material,
    required this.creatorAccountId,
    required DateTime updatedAt,
    required DateTime cachedAt,
  }) : updatedAt = _sqliteTimestamp(updatedAt),
       cachedAt = _sqliteTimestamp(cachedAt);

  final EncryptedFamilyCodeMaterial material;
  final String creatorAccountId;
  final DateTime updatedAt;
  final DateTime cachedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyCodeCacheRecord &&
          other.material == material &&
          other.creatorAccountId == creatorAccountId &&
          other.updatedAt == updatedAt &&
          other.cachedAt == cachedAt;

  @override
  int get hashCode =>
      Object.hash(material, creatorAccountId, updatedAt, cachedAt);

  @override
  String toString() => 'FamilyCodeCacheRecord(<encrypted material>)';
}

DateTime _sqliteTimestamp(DateTime value) =>
    DateTime.fromMillisecondsSinceEpoch(
      value.toUtc().millisecondsSinceEpoch,
      isUtc: true,
    );

final class FamilyCodeCacheRepository {
  const FamilyCodeCacheRepository();

  Future<FamilyCodeCacheRecord?> find(
    DatabaseExecutor db, {
    required String familyId,
  }) async {
    final rows = await db.query(
      'family_code_cache',
      where: 'family_id = ?',
      whereArgs: [familyId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return FamilyCodeCacheRecord(
      material: EncryptedFamilyCodeMaterial(
        codecVersion: row['codec_version']! as int,
        familyId: row['family_id']! as String,
        codeVersion: row['code_version']! as int,
        nonce: row['nonce']! as String,
        ciphertext: row['ciphertext']! as String,
        mac: row['mac']! as String,
      ),
      creatorAccountId: row['creator_account_id']! as String,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at']! as int,
        isUtc: true,
      ),
      cachedAt: DateTime.fromMillisecondsSinceEpoch(
        row['cached_at']! as int,
        isUtc: true,
      ),
    );
  }

  Future<void> upsert(DatabaseExecutor db, FamilyCodeCacheRecord record) async {
    await db.rawInsert(
      r'''
INSERT INTO family_code_cache(
  family_id,
  code_version,
  codec_version,
  nonce,
  ciphertext,
  mac,
  creator_account_id,
  updated_at,
  cached_at
)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(family_id) DO UPDATE SET
  code_version = excluded.code_version,
  codec_version = excluded.codec_version,
  nonce = excluded.nonce,
  ciphertext = excluded.ciphertext,
  mac = excluded.mac,
  creator_account_id = excluded.creator_account_id,
  updated_at = excluded.updated_at,
  cached_at = excluded.cached_at
WHERE excluded.code_version > family_code_cache.code_version
''',
      [
        record.material.familyId,
        record.material.codeVersion,
        record.material.codecVersion,
        record.material.nonce,
        record.material.ciphertext,
        record.material.mac,
        record.creatorAccountId,
        record.updatedAt.millisecondsSinceEpoch,
        record.cachedAt.millisecondsSinceEpoch,
      ],
    );

    final stored = await find(db, familyId: record.material.familyId);
    if (stored == record) return;
    if (stored != null &&
        stored.material == record.material &&
        stored.creatorAccountId == record.creatorAccountId &&
        stored.updatedAt == record.updatedAt) {
      return;
    }
    if (stored != null &&
        record.material.codeVersion < stored.material.codeVersion) {
      throw StateError('Refusing to roll back cached family code material');
    }
    throw StateError('Cached family code version has conflicting data');
  }
}
