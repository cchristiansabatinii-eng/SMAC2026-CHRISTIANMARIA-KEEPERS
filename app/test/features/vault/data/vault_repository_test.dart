import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/onboarding/data/family_repository.dart';
import 'package:keepers/features/onboarding/data/member_repository.dart';
import 'package:keepers/features/vault/data/vault_repository.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('vault returns newest family entries first without plaintext', () async {
    final db = await _openSchemaV2Database();
    addTearDown(db.close);
    await _insertIdentity(db, familyId: 'family-1', memberId: 'member-1');
    await _insertIdentity(db, familyId: 'family-2', memberId: 'member-2');
    await _insertEntry(
      db,
      id: 'older',
      familyId: 'family-1',
      authorId: 'member-1',
      createdAt: DateTime.utc(2026, 8, 31),
      transcript: 'must not leave the query boundary',
    );
    await _insertEntry(
      db,
      id: 'newer',
      familyId: 'family-1',
      authorId: 'member-1',
      createdAt: DateTime.utc(2026, 9, 1),
    );
    await _insertEntry(
      db,
      id: 'other-family',
      familyId: 'family-2',
      authorId: 'member-2',
      createdAt: DateTime.utc(2026, 9, 2),
    );

    final rows = await VaultRepository().listForFamily(db, 'family-1');

    expect(rows.map((entry) => entry.id), ['newer', 'older']);
    expect(rows.every((entry) => entry.caption == null), isTrue);
    expect(rows.every((entry) => entry.familyId == 'family-1'), isTrue);
  });

  test('equal timestamps are ordered by descending entry id', () async {
    final db = await _openSchemaV2Database();
    addTearDown(db.close);
    await _insertIdentity(db, familyId: 'family-1', memberId: 'member-1');
    final createdAt = DateTime.utc(2026, 9, 1);
    await _insertEntry(
      db,
      id: 'entry-a',
      familyId: 'family-1',
      authorId: 'member-1',
      createdAt: createdAt,
    );
    await _insertEntry(
      db,
      id: 'entry-z',
      familyId: 'family-1',
      authorId: 'member-1',
      createdAt: createdAt,
    );

    final rows = await VaultRepository().listForFamily(db, 'family-1');

    expect(rows.map((entry) => entry.id), ['entry-z', 'entry-a']);
  });
}

Future<Database> _openSchemaV2Database() async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await database.execute('PRAGMA foreign_keys = ON');
  for (final statement in KeepersSchema.statementsForUpgrade(0, 2)) {
    await database.execute(statement);
  }
  return database;
}

Future<void> _insertIdentity(
  Database database, {
  required String familyId,
  required String memberId,
}) async {
  await FamilyRepository().insert(
    database,
    id: familyId,
    name: familyId,
    familyKeyRef: '$familyId-key',
    createdAt: DateTime.utc(2026, 8, 1),
  );
  await MemberRepository().insert(
    database,
    id: memberId,
    familyId: familyId,
    name: memberId,
    memberKeyRef: '$memberId-key',
    colorToken: 'ochre',
    createdAt: DateTime.utc(2026, 8, 1),
  );
}

Future<void> _insertEntry(
  Database database, {
  required String id,
  required String familyId,
  required String authorId,
  required DateTime createdAt,
  String? transcript,
}) => database.insert('entries', {
  'id': id,
  'family_id': familyId,
  'author_id': authorId,
  'created_at': createdAt.millisecondsSinceEpoch,
  'entry_type': 'text',
  'privacy_tier': 'reveal',
  'blob_ref': 'entries/blobs/$id.keeper',
  'transcript': transcript,
  'state': 'pending',
});
