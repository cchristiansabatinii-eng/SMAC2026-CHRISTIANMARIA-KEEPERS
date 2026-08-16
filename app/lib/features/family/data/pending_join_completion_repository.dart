import 'package:sqflite_sqlcipher/sqflite.dart';

final class PendingJoinCompletion {
  PendingJoinCompletion({
    required this.requestId,
    required this.familyId,
    required this.memberId,
    required this.accountId,
    required DateTime installedAt,
  }) : installedAt = installedAt.toUtc();

  final String requestId;
  final String familyId;
  final String memberId;
  final String accountId;
  final DateTime installedAt;

  bool hasSameIdentity(PendingJoinCompletion other) =>
      requestId == other.requestId &&
      familyId == other.familyId &&
      memberId == other.memberId &&
      accountId == other.accountId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingJoinCompletion &&
          hasSameIdentity(other) &&
          installedAt == other.installedAt;

  @override
  int get hashCode =>
      Object.hash(requestId, familyId, memberId, accountId, installedAt);

  @override
  String toString() => 'PendingJoinCompletion(<redacted identifiers>)';
}

final class PendingJoinCompletionRepository {
  const PendingJoinCompletionRepository();

  Future<PendingJoinCompletion?> find(DatabaseExecutor db) async {
    final rows = await db.query(
      'pending_family_join_completion',
      where: 'singleton = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return PendingJoinCompletion(
      requestId: row['request_id']! as String,
      familyId: row['family_id']! as String,
      memberId: row['member_id']! as String,
      accountId: row['account_id']! as String,
      installedAt: DateTime.fromMillisecondsSinceEpoch(
        row['installed_at']! as int,
        isUtc: true,
      ),
    );
  }

  Future<void> recordExact(
    DatabaseExecutor db,
    PendingJoinCompletion pending,
  ) async {
    await db.insert('pending_family_join_completion', {
      'singleton': 1,
      'request_id': pending.requestId,
      'family_id': pending.familyId,
      'member_id': pending.memberId,
      'account_id': pending.accountId,
      'installed_at': pending.installedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final stored = await find(db);
    if (stored == null || !stored.hasSameIdentity(pending)) {
      throw StateError('A different family join completion is pending');
    }
  }

  Future<void> deleteExact(
    DatabaseExecutor db,
    PendingJoinCompletion pending,
  ) async {
    final stored = await find(db);
    if (stored == null) return;
    if (!stored.hasSameIdentity(pending)) {
      throw StateError('Refusing to delete another family join completion');
    }
    await db.delete(
      'pending_family_join_completion',
      where:
          'singleton = 1 AND request_id = ? AND family_id = ? '
          'AND member_id = ? AND account_id = ?',
      whereArgs: [
        pending.requestId,
        pending.familyId,
        pending.memberId,
        pending.accountId,
      ],
    );
  }
}
