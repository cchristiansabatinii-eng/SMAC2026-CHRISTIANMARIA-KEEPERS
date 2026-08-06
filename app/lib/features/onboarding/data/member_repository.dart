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
    required DateTime createdAt,
  }) async {
    await db.insert('members', {
      'id': id,
      'family_id': familyId,
      'name': name.trim(),
      'role': 'adult',
      'member_key_ref': memberKeyRef,
      'color_token': colorToken,
      'created_at': createdAt.millisecondsSinceEpoch,
    });
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
  m.color_token AS color_token
FROM members AS m
JOIN families AS f ON f.id = m.family_id
WHERE m.role = 'adult'
ORDER BY m.created_at ASC, m.id ASC
LIMIT 1
''');
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.single;
    final memberKeyRef = row['member_key_ref'] as String?;
    if (memberKeyRef == null) {
      return null;
    }

    return LocalIdentity(
      familyId: row['family_id']! as String,
      familyName: row['family_name']! as String,
      familyKeyRef: row['family_key_ref']! as String,
      memberId: row['member_id']! as String,
      memberName: row['member_name']! as String,
      memberKeyRef: memberKeyRef,
      colorToken: row['color_token']! as String,
    );
  }
}
