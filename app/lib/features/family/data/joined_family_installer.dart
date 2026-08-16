import 'package:keepers/features/family/data/family_roster_repository.dart';
import 'package:keepers/features/family/data/pending_invite_completion_repository.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/data/member_repository.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

abstract interface class JoinedFamilyInstaller {
  Future<void> install({
    required ClaimedFamily claim,
    required List<int> familyKey,
    required String accountId,
  });
}

typedef JoinedFamilyDatabaseProvider = Future<Database> Function();

final class LocalJoinedFamilyInstaller implements JoinedFamilyInstaller {
  const LocalJoinedFamilyInstaller(
    this._database,
    this._identityKeys,
    this._members,
    this._roster, {
    this._pendingCompletions = const PendingInviteCompletionRepository(),
    DateTime Function()? utcNow,
  }) : _utcNow = utcNow ?? _systemUtcNow;

  final JoinedFamilyDatabaseProvider _database;
  final IdentityKeyService _identityKeys;
  final MemberRepository _members;
  final FamilyRosterRepository _roster;
  final PendingInviteCompletionRepository _pendingCompletions;
  final DateTime Function() _utcNow;

  @override
  Future<void> install({
    required ClaimedFamily claim,
    required List<int> familyKey,
    required String accountId,
  }) async {
    StoredIdentityKey? storedFamilyKey;
    StoredIdentityKey? storedMemberKey;
    try {
      storedFamilyKey = await _identityKeys.importFamilyKey(
        familyId: claim.familyId,
        familyKey: familyKey,
      );
      storedMemberKey = await _identityKeys.createMemberKey(
        memberId: claim.localMemberId,
      );
      final database = await _database();
      final createdAt = _earliestJoin(claim.members);

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
            claim.familyId,
            claim.familyName.trim(),
            storedFamilyKey!.reference,
            createdAt.millisecondsSinceEpoch,
          ],
        );
        await _roster.upsertCloudRoster(
          transaction,
          familyId: claim.familyId,
          members: claim.members,
        );
        final updated = await transaction.update(
          'members',
          {'member_key_ref': storedMemberKey!.reference},
          where: 'id = ? AND family_id = ?',
          whereArgs: [claim.localMemberId, claim.familyId],
        );
        if (updated != 1) {
          throw StateError('Claimed local member is missing from the roster');
        }
        await _members.bindLocalIdentity(
          transaction,
          familyId: claim.familyId,
          memberId: claim.localMemberId,
          accountId: accountId,
        );
        await _pendingCompletions.recordExact(
          transaction,
          PendingInviteCompletion(
            inviteId: claim.envelope.inviteId,
            familyId: claim.familyId,
            accountId: accountId,
            installedAt: _utcNow(),
          ),
        );
      });
    } catch (_) {
      if (storedMemberKey != null) {
        await _rollbackBestEffort(storedMemberKey);
      }
      if (storedFamilyKey != null) {
        await _rollbackBestEffort(storedFamilyKey);
      }
      throw const InvitationFailure(
        InvitationFailureCode.localPersistenceFailed,
      );
    }
  }

  Future<void> _rollbackBestEffort(StoredIdentityKey key) async {
    try {
      await _identityKeys.rollbackKey(key);
    } on Object {
      // Preserve the typed persistence failure; cleanup is compensating only.
    }
  }

  DateTime _earliestJoin(List<FamilyMember> members) {
    if (members.isEmpty) {
      throw StateError('Claimed family roster is empty');
    }
    var earliest = members.first.joinedAt.toUtc();
    for (final member in members.skip(1)) {
      final joinedAt = member.joinedAt.toUtc();
      if (joinedAt.isBefore(earliest)) earliest = joinedAt;
    }
    return earliest;
  }

  static DateTime _systemUtcNow() => DateTime.now().toUtc();
}
