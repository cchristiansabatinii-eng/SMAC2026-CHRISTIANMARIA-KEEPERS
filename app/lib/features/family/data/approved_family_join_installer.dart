import 'package:keepers/features/family/data/family_roster_repository.dart';
import 'package:keepers/features/family/data/pending_join_completion_repository.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/data/member_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

abstract interface class ApprovedFamilyJoinInstaller {
  Future<PendingJoinCompletion> install({
    required ApprovedFamilyJoin approval,
    required List<int> familyKey,
    required String accountId,
  });
}

typedef ApprovedFamilyJoinDatabaseProvider = Future<Database> Function();

final class LocalApprovedFamilyJoinInstaller
    implements ApprovedFamilyJoinInstaller {
  const LocalApprovedFamilyJoinInstaller(
    this._database,
    this._identityKeys,
    this._members,
    this._roster, {
    this._pendingCompletions = const PendingJoinCompletionRepository(),
    DateTime Function()? utcNow,
  }) : _utcNow = utcNow ?? _systemUtcNow;

  final ApprovedFamilyJoinDatabaseProvider _database;
  final IdentityKeyService _identityKeys;
  final MemberRepository _members;
  final FamilyRosterRepository _roster;
  final PendingJoinCompletionRepository _pendingCompletions;
  final DateTime Function() _utcNow;

  @override
  Future<PendingJoinCompletion> install({
    required ApprovedFamilyJoin approval,
    required List<int> familyKey,
    required String accountId,
  }) async {
    StoredIdentityKey? storedFamilyKey;
    StoredIdentityKey? storedMemberKey;
    try {
      if (!approval.roster.any(
        (member) =>
            member.id == approval.localMemberId &&
            member.familyId == approval.familyId,
      )) {
        throw StateError('Approved local member is missing from the roster');
      }

      storedFamilyKey = await _identityKeys.importFamilyKey(
        familyId: approval.familyId,
        familyKey: familyKey,
      );
      storedMemberKey = await _identityKeys.createMemberKey(
        memberId: approval.localMemberId,
      );
      final database = await _database();
      final pending = PendingJoinCompletion(
        requestId: approval.requestId,
        familyId: approval.familyId,
        memberId: approval.localMemberId,
        accountId: accountId,
        installedAt: _utcNow(),
      );

      await database.transaction((transaction) async {
        await transaction.rawInsert(
          r'''
INSERT INTO families(id, name, family_key_ref, quorum, created_at)
VALUES (?, ?, ?, 1, ?)
ON CONFLICT(id) DO UPDATE SET
  name = excluded.name,
  family_key_ref = excluded.family_key_ref
''',
          [
            approval.familyId,
            approval.familyName.trim(),
            storedFamilyKey!.reference,
            _earliestJoin(approval.roster).millisecondsSinceEpoch,
          ],
        );
        await _roster.upsertCloudRoster(
          transaction,
          familyId: approval.familyId,
          members: approval.roster,
        );
        final updated = await transaction.update(
          'members',
          {'member_key_ref': storedMemberKey!.reference},
          where: 'id = ? AND family_id = ?',
          whereArgs: [approval.localMemberId, approval.familyId],
        );
        if (updated != 1) {
          throw StateError('Approved local member is missing from the roster');
        }
        await _members.bindLocalIdentity(
          transaction,
          familyId: approval.familyId,
          memberId: approval.localMemberId,
          accountId: accountId,
        );
        await _pendingCompletions.recordExact(transaction, pending);
      });
      return pending;
    } on Object {
      if (storedMemberKey case final key? when key.wasCreated) {
        await _rollbackBestEffort(key);
      }
      if (storedFamilyKey case final key? when key.wasCreated) {
        await _rollbackBestEffort(key);
      }
      throw const FamilyJoinFailure(
        FamilyJoinFailureCode.localPersistenceFailed,
      );
    }
  }

  Future<void> _rollbackBestEffort(StoredIdentityKey key) async {
    try {
      await _identityKeys.rollbackKey(key);
    } on Object {
      // Cleanup is compensating; preserve the typed persistence failure.
    }
  }

  static DateTime _earliestJoin(List<FamilyMember> members) {
    var earliest = members.first.joinedAt.toUtc();
    for (final member in members.skip(1)) {
      final joinedAt = member.joinedAt.toUtc();
      if (joinedAt.isBefore(earliest)) earliest = joinedAt;
    }
    return earliest;
  }

  static DateTime _systemUtcNow() => DateTime.now().toUtc();
}
