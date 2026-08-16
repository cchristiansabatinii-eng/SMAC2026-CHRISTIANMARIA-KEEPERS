import 'package:sqflite_sqlcipher/sqflite.dart';

final class FamilyRepository {
  Future<void> insert(
    DatabaseExecutor db, {
    required String id,
    required String name,
    required String familyKeyRef,
    required DateTime createdAt,
  }) async {
    await db.insert('families', {
      'id': id,
      'name': name.trim(),
      'family_key_ref': familyKeyRef,
      'quorum': 1,
      'created_at': createdAt.millisecondsSinceEpoch,
    });
  }
}
