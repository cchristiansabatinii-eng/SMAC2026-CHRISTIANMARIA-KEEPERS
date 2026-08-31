import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final class VaultRepository {
  static const releaseRetention = Duration(days: 30);

  Future<VaultEntryMetadata?> findByIdForFamily(
    DatabaseExecutor db, {
    required String entryId,
    required String familyId,
  }) async {
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
        'expires_at',
      ],
      where: 'id = ? AND family_id = ?',
      whereArgs: [entryId, familyId],
      limit: 1,
    );
    return rows.isEmpty ? null : VaultEntryMetadata.fromRow(rows.single);
  }

  Future<List<VaultEntryMetadata>> listForFamily(
    DatabaseExecutor db,
    String familyId, {
    DateTime? now,
  }) async {
    final nowMs = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    await db.update(
      'entries',
      {'state': 'expired'},
      where:
          'family_id = ? AND state = ? AND expires_at IS NOT NULL '
          'AND expires_at <= ?',
      whereArgs: [familyId, 'revealed', nowMs],
    );
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
        'expires_at',
      ],
      where: 'family_id = ? AND state != ?',
      whereArgs: [familyId, 'expired'],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(VaultEntryMetadata.fromRow).toList(growable: false);
  }

  Future<bool> resolveWeeklyEntry(
    DatabaseExecutor db, {
    required VaultEntryMetadata entry,
    required WeeklyMemoryDisposition disposition,
    required DateTime decidedAt,
  }) async {
    if (entry.privacy != PrivacyTier.reveal || entry.state != 'pending') {
      throw StateError('Only pending Weekly Reveal entries can be resolved.');
    }
    final decidedAtUtc = decidedAt.toUtc();
    final decidedAtMs = decidedAtUtc.millisecondsSinceEpoch;
    final values = switch (disposition) {
      WeeklyMemoryDisposition.keep => <String, Object?>{
        'state': 'kept',
        'revealed_at': decidedAtMs,
        'kept_at': decidedAtMs,
        'expires_at': null,
      },
      WeeklyMemoryDisposition.release => <String, Object?>{
        'state': 'revealed',
        'revealed_at': decidedAtMs,
        'kept_at': null,
        'expires_at': decidedAtUtc.add(releaseRetention).millisecondsSinceEpoch,
      },
    };
    final updated = await db.update(
      'entries',
      values,
      where: 'id = ? AND family_id = ? AND privacy_tier = ? AND state = ?',
      whereArgs: [entry.id, entry.familyId, 'reveal', 'pending'],
    );
    return updated == 1;
  }
}
