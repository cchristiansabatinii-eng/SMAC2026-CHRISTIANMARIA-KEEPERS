import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/onboarding/data/family_repository.dart';
import 'package:keepers/features/onboarding/data/member_repository.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('family and adult member round-trip as one local identity', () async {
    final db = await _openSchemaV2Database();
    addTearDown(db.close);
    final families = FamilyRepository();
    final members = MemberRepository();

    await db.transaction((txn) async {
      await families.insert(
        txn,
        id: 'family-1',
        name: 'Sabati',
        familyKeyRef: 'family-key',
        createdAt: DateTime.utc(2026, 9, 1),
      );
      await members.insert(
        txn,
        id: 'member-1',
        familyId: 'family-1',
        name: 'Chris',
        memberKeyRef: 'member-key',
        colorToken: 'ochre',
        createdAt: DateTime.utc(2026, 9, 1),
      );
    });

    expect(
      await members.findLocalIdentity(db),
      const LocalIdentity(
        familyId: 'family-1',
        familyName: 'Sabati',
        familyKeyRef: 'family-key',
        memberId: 'member-1',
        memberName: 'Chris',
        memberKeyRef: 'member-key',
        colorToken: 'ochre',
      ),
    );
  });

  test('returns no local identity when the database is empty', () async {
    final db = await _openSchemaV2Database();
    addTearDown(db.close);

    expect(await MemberRepository().findLocalIdentity(db), isNull);
  });

  test('returns no identity when the earliest adult has no key', () async {
    final db = await _openSchemaV2Database();
    addTearDown(db.close);
    await _insertFamily(db);
    await _insertAdult(
      db,
      id: 'member-without-key',
      memberKeyRef: null,
      createdAt: DateTime.utc(2026, 9, 1),
    );
    await _insertAdult(
      db,
      id: 'member-with-key',
      memberKeyRef: 'member-key',
      createdAt: DateTime.utc(2026, 9, 2),
    );

    expect(await MemberRepository().findLocalIdentity(db), isNull);
  });

  test('breaks equal creation-time ties by member id', () async {
    final db = await _openSchemaV2Database();
    addTearDown(db.close);
    await _insertFamily(db);
    final createdAt = DateTime.utc(2026, 9, 1);
    await _insertAdult(
      db,
      id: 'member-z',
      memberKeyRef: 'z-key',
      createdAt: createdAt,
    );
    await _insertAdult(
      db,
      id: 'member-a',
      memberKeyRef: 'a-key',
      createdAt: createdAt,
    );

    expect(
      await MemberRepository().findLocalIdentity(db),
      const LocalIdentity(
        familyId: 'family-1',
        familyName: 'Sabati',
        familyKeyRef: 'family-key',
        memberId: 'member-a',
        memberName: 'member-a',
        memberKeyRef: 'a-key',
        colorToken: 'ochre',
      ),
    );
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

Future<void> _insertFamily(Database database) async {
  await FamilyRepository().insert(
    database,
    id: 'family-1',
    name: 'Sabati',
    familyKeyRef: 'family-key',
    createdAt: DateTime.utc(2026, 9, 1),
  );
}

Future<void> _insertAdult(
  Database database, {
  required String id,
  required String? memberKeyRef,
  required DateTime createdAt,
}) async {
  await database.insert('members', {
    'id': id,
    'family_id': 'family-1',
    'name': id,
    'role': 'adult',
    'member_key_ref': memberKeyRef,
    'color_token': 'ochre',
    'created_at': createdAt.millisecondsSinceEpoch,
  });
}
