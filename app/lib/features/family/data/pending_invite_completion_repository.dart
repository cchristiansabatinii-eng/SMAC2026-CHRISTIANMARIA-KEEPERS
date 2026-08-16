import 'package:sqflite_sqlcipher/sqflite.dart';

final class PendingInviteCompletion {
  PendingInviteCompletion({
    required this.inviteId,
    required this.familyId,
    required this.accountId,
    required DateTime installedAt,
  }) : installedAt = installedAt.toUtc();

  final String inviteId;
  final String familyId;
  final String accountId;
  final DateTime installedAt;

  bool hasSameIdentity(PendingInviteCompletion other) =>
      inviteId == other.inviteId &&
      familyId == other.familyId &&
      accountId == other.accountId;

  @override
  bool operator ==(Object other) =>
      other is PendingInviteCompletion &&
      hasSameIdentity(other) &&
      installedAt == other.installedAt;

  @override
  int get hashCode => Object.hash(inviteId, familyId, accountId, installedAt);

  @override
  String toString() => 'PendingInviteCompletion(<redacted identifiers>)';
}

final class PendingInviteCompletionRepository {
  const PendingInviteCompletionRepository();

  Future<PendingInviteCompletion?> find(DatabaseExecutor db) async {
    final rows = await db.query(
      'pending_family_invite_completion',
      where: 'singleton = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return PendingInviteCompletion(
      inviteId: row['invite_id']! as String,
      familyId: row['family_id']! as String,
      accountId: row['account_id']! as String,
      installedAt: DateTime.fromMillisecondsSinceEpoch(
        row['installed_at']! as int,
        isUtc: true,
      ),
    );
  }

  Future<void> recordExact(
    DatabaseExecutor db,
    PendingInviteCompletion pending,
  ) async {
    await db.insert('pending_family_invite_completion', {
      'singleton': 1,
      'invite_id': pending.inviteId,
      'family_id': pending.familyId,
      'account_id': pending.accountId,
      'installed_at': pending.installedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final stored = await find(db);
    if (stored == null || !stored.hasSameIdentity(pending)) {
      throw StateError('A different invitation completion is pending');
    }
  }

  Future<void> deleteExact(
    DatabaseExecutor db,
    PendingInviteCompletion pending,
  ) async {
    final stored = await find(db);
    if (stored == null) return;
    if (!stored.hasSameIdentity(pending)) {
      throw StateError('Refusing to delete another invitation completion');
    }
    await db.delete(
      'pending_family_invite_completion',
      where:
          'singleton = 1 AND invite_id = ? AND family_id = ? '
          'AND account_id = ?',
      whereArgs: [pending.inviteId, pending.familyId, pending.accountId],
    );
  }
}
