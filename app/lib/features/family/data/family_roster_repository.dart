import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final class FamilyRosterRepository {
  Future<List<FamilyMember>> listLocal(
    DatabaseExecutor db, {
    required String familyId,
  }) async {
    final rows = await db.query(
      'members',
      where: 'family_id = ?',
      whereArgs: [familyId],
      orderBy: 'created_at ASC, id ASC',
    );
    return List<FamilyMember>.unmodifiable(rows.map(_decodeMember));
  }

  Future<void> upsertCloudRoster(
    DatabaseExecutor db, {
    required String familyId,
    required List<FamilyMember> members,
  }) async {
    if (members.any((member) => member.familyId != familyId)) {
      throw ArgumentError.value(members, 'members', 'Family ID mismatch');
    }

    final bindings = await db.query(
      'local_identity_binding',
      columns: const ['family_id', 'member_id'],
      where: 'singleton = 1',
      limit: 1,
    );
    final boundMemberId = bindings.isEmpty
        ? null
        : bindings.single['member_id'];
    final boundFamilyId = bindings.isEmpty
        ? null
        : bindings.single['family_id'];

    for (final member in members) {
      final existing = await db.query(
        'members',
        columns: const ['family_id'],
        where: 'id = ?',
        whereArgs: [member.id],
        limit: 1,
      );
      if (existing.isNotEmpty && existing.single['family_id'] != familyId) {
        throw StateError('A member ID belongs to another family');
      }

      if (existing.isEmpty) {
        await db.insert('members', {
          'id': member.id,
          'family_id': familyId,
          'name': member.name.trim(),
          'role': member.role,
          'created_at': member.joinedAt.toUtc().millisecondsSinceEpoch,
          'member_key_ref': null,
          'color_token': member.colorToken,
          'avatar_config_json': member.avatar.encode(),
        });
        continue;
      }

      final isBound = boundFamilyId == familyId && boundMemberId == member.id;
      await db.update(
        'members',
        {
          'name': member.name.trim(),
          'role': member.role,
          if (!isBound) 'color_token': member.colorToken,
          if (!isBound) 'avatar_config_json': member.avatar.encode(),
          'created_at': member.joinedAt.toUtc().millisecondsSinceEpoch,
        },
        where: 'id = ? AND family_id = ?',
        whereArgs: [member.id, familyId],
      );
    }
  }

  FamilyMember _decodeMember(Map<String, Object?> row) {
    final memberId = row['id']! as String;
    return FamilyMember(
      id: memberId,
      familyId: row['family_id']! as String,
      name: row['name']! as String,
      role: row['role']! as String,
      colorToken: row['color_token']! as String,
      avatar: AvatarConfig.decode(
        row['avatar_config_json'] as String? ?? '{}',
        fallbackSeed: memberId,
      ),
      joinedAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at']! as int,
        isUtc: true,
      ),
    );
  }
}
