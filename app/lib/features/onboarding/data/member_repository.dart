import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final class MemberRepository {
  Future<void> insert(
    DatabaseExecutor db, {
    required String id,
    required String familyId,
    required String name,
    required String memberKeyRef,
    required String colorToken,
    required AvatarConfig avatar,
    required DateTime createdAt,
  }) async {
    await db.insert('members', {
      'id': id,
      'family_id': familyId,
      'name': name.trim(),
      'role': 'adult',
      'member_key_ref': memberKeyRef,
      'color_token': colorToken,
      'avatar_config_json': avatar.encode(),
      'created_at': createdAt.millisecondsSinceEpoch,
    });
  }

  Future<void> updateAvatar(
    DatabaseExecutor db, {
    required String memberId,
    required AvatarConfig avatar,
  }) async {
    final count = await db.update(
      'members',
      {'avatar_config_json': avatar.encode()},
      where: 'id = ?',
      whereArgs: [memberId],
    );
    if (count != 1) {
      throw StateError('Expected one member avatar update, updated $count');
    }
  }

  Future<void> bindLocalIdentity(
    DatabaseExecutor db, {
    required String familyId,
    required String memberId,
    String? accountId,
  }) async {
    final members = await db.query(
      'members',
      columns: const ['id'],
      where: 'id = ? AND family_id = ?',
      whereArgs: [memberId, familyId],
      limit: 1,
    );
    if (members.isEmpty) {
      throw StateError('Cannot bind an unknown family member');
    }

    final bindings = await db.query(
      'local_identity_binding',
      where: 'singleton = 1',
      limit: 1,
    );
    if (bindings.isEmpty) {
      await db.insert('local_identity_binding', {
        'singleton': 1,
        'family_id': familyId,
        'member_id': memberId,
        'account_id': accountId,
      });
      return;
    }

    final binding = bindings.single;
    if (binding['family_id'] != familyId || binding['member_id'] != memberId) {
      throw StateError('A different local family member is already bound');
    }
    final existingAccountId = binding['account_id'] as String?;
    if (existingAccountId != null &&
        accountId != null &&
        existingAccountId != accountId) {
      throw StateError('A different account is already bound');
    }
    if (existingAccountId == null && accountId != null) {
      await db.update('local_identity_binding', {
        'account_id': accountId,
      }, where: 'singleton = 1');
    }
  }

  Future<LocalIdentity?> findLocalIdentity(DatabaseExecutor db) async {
    final rows = await db.rawQuery(r'''
SELECT
  f.id AS family_id,
  f.name AS family_name,
  f.family_key_ref AS family_key_ref,
  m.id AS member_id,
  m.name AS member_name,
  m.member_key_ref AS member_key_ref,
  m.color_token AS color_token,
  m.avatar_config_json AS avatar_config_json,
  b.account_id AS account_id
FROM local_identity_binding AS b
JOIN members AS m ON m.id = b.member_id AND m.family_id = b.family_id
JOIN families AS f ON f.id = b.family_id
WHERE b.singleton = 1
''');
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.single;
    final memberKeyRef = row['member_key_ref'] as String?;
    if (memberKeyRef == null) {
      return null;
    }

    final memberId = row['member_id']! as String;
    return LocalIdentity(
      familyId: row['family_id']! as String,
      familyName: row['family_name']! as String,
      familyKeyRef: row['family_key_ref']! as String,
      memberId: memberId,
      memberName: row['member_name']! as String,
      memberKeyRef: memberKeyRef,
      colorToken: row['color_token']! as String,
      avatar: AvatarConfig.decode(
        row['avatar_config_json'] as String? ?? '{}',
        fallbackSeed: memberId,
      ),
      accountId: row['account_id'] as String?,
    );
  }
}
