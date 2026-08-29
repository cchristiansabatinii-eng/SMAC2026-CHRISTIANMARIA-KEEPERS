import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/members/domain/avatar_catalog.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/data/family_repository.dart';
import 'package:keepers/features/onboarding/data/member_repository.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/app_database.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('family and adult member round-trip as one local identity', () async {
    final db = await _openSchemaV3Database();
    addTearDown(db.close);
    final families = FamilyRepository();
    final members = MemberRepository();
    const avatar = AvatarConfig.defaults(seed: 'member-1');

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
        avatar: avatar,
        createdAt: DateTime.utc(2026, 9, 1),
      );
      await _bindIdentity(
        txn,
        familyId: 'family-1',
        memberId: 'member-1',
        accountId: 'account-1',
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
        avatar: AvatarConfig.defaults(seed: 'member-1'),
        accountId: 'account-1',
      ),
    );
    expect(
      (await db.query('members')).single['avatar_config_json'],
      avatar.encode(),
    );
  });

  test('identity lookup follows binding rather than earliest adult', () async {
    final db = await _openSchemaV3Database();
    addTearDown(db.close);
    await _insertFamily(db);
    await _insertAdult(
      db,
      id: 'member-1',
      memberKeyRef: 'member-key-1',
      createdAt: DateTime.utc(2026, 9, 1),
    );
    await _insertAdult(
      db,
      id: 'member-2',
      memberKeyRef: 'member-key-2',
      createdAt: DateTime.utc(2026, 9, 2),
    );
    await _bindIdentity(db, familyId: 'family-1', memberId: 'member-2');

    expect(
      (await MemberRepository().findLocalIdentity(db))?.memberId,
      'member-2',
    );
  });

  test(
    'authentication binding is idempotent and cannot switch local members',
    () async {
      final db = await _openSchemaV3Database();
      addTearDown(db.close);
      await _insertFamily(db);
      await _insertAdult(
        db,
        id: 'member-1',
        memberKeyRef: 'member-key-1',
        createdAt: DateTime.utc(2026, 9, 1),
      );
      await _insertAdult(
        db,
        id: 'member-2',
        memberKeyRef: 'member-key-2',
        createdAt: DateTime.utc(2026, 9, 2),
      );
      final repository = MemberRepository();

      await repository.bindLocalIdentity(
        db,
        familyId: 'family-1',
        memberId: 'member-1',
      );
      await repository.bindLocalIdentity(
        db,
        familyId: 'family-1',
        memberId: 'member-1',
        accountId: 'account-1',
      );
      await repository.bindLocalIdentity(
        db,
        familyId: 'family-1',
        memberId: 'member-1',
        accountId: 'account-1',
      );
      await expectLater(
        repository.bindLocalIdentity(
          db,
          familyId: 'family-1',
          memberId: 'member-1',
          accountId: 'account-2',
        ),
        throwsStateError,
      );

      expect(await db.query('local_identity_binding'), [
        {
          'singleton': 1,
          'family_id': 'family-1',
          'member_id': 'member-1',
          'account_id': 'account-1',
        },
      ]);
      expect((await repository.findLocalIdentity(db))?.accountId, 'account-1');
    },
  );

  test(
    'clearing an exact account binding preserves the local family and member',
    () async {
      final db = await _openSchemaV3Database();
      addTearDown(db.close);
      await _insertFamily(db);
      await _insertAdult(
        db,
        id: 'member-1',
        memberKeyRef: 'member-key-1',
        createdAt: DateTime.utc(2026, 9, 1),
      );
      final repository = MemberRepository();
      await repository.bindLocalIdentity(
        db,
        familyId: 'family-1',
        memberId: 'member-1',
        accountId: 'account-1',
      );
      final familiesBefore = await db.query('families');
      final membersBefore = await db.query('members');

      final cleared = await repository.clearLocalIdentityAccountBinding(
        db,
        familyId: 'family-1',
        memberId: 'member-1',
        accountId: 'account-1',
      );

      expect(cleared, isTrue);
      expect((await repository.findLocalIdentity(db))?.accountId, isNull);
      expect(await db.query('families'), familiesBefore);
      expect(await db.query('members'), membersBefore);
    },
  );

  test('clearing an account binding refuses every identity mismatch', () async {
    final db = await _openSchemaV3Database();
    addTearDown(db.close);
    await _insertFamily(db);
    await _insertAdult(
      db,
      id: 'member-1',
      memberKeyRef: 'member-key-1',
      createdAt: DateTime.utc(2026, 9, 1),
    );
    final repository = MemberRepository();
    await repository.bindLocalIdentity(
      db,
      familyId: 'family-1',
      memberId: 'member-1',
      accountId: 'account-1',
    );

    for (final mismatch in const [
      (familyId: 'family-1', memberId: 'member-1', accountId: 'account-2'),
      (familyId: 'family-1', memberId: 'member-2', accountId: 'account-1'),
      (familyId: 'family-2', memberId: 'member-1', accountId: 'account-1'),
    ]) {
      expect(
        await repository.clearLocalIdentityAccountBinding(
          db,
          familyId: mismatch.familyId,
          memberId: mismatch.memberId,
          accountId: mismatch.accountId,
        ),
        isFalse,
      );
    }

    expect((await repository.findLocalIdentity(db))?.accountId, 'account-1');
  });

  test('local identity equality includes its nullable account binding', () {
    const unbound = LocalIdentity(
      familyId: 'family-1',
      familyName: 'Sabati',
      familyKeyRef: 'family-key',
      memberId: 'member-1',
      memberName: 'Chris',
      memberKeyRef: 'member-key',
      colorToken: 'ochre',
      avatar: AvatarConfig.defaults(seed: 'member-1'),
    );
    const bound = LocalIdentity(
      familyId: 'family-1',
      familyName: 'Sabati',
      familyKeyRef: 'family-key',
      memberId: 'member-1',
      memberName: 'Chris',
      memberKeyRef: 'member-key',
      colorToken: 'ochre',
      avatar: AvatarConfig.defaults(seed: 'member-1'),
      accountId: 'account-1',
    );

    expect(unbound, isNot(bound));
    expect(unbound.hashCode, isNot(bound.hashCode));
  });

  test('returns no local identity when the database is empty', () async {
    final db = await _openSchemaV3Database();
    addTearDown(db.close);

    expect(await MemberRepository().findLocalIdentity(db), isNull);
  });

  test('returns no identity when no local member is bound', () async {
    final db = await _openSchemaV3Database();
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

  test('bound identity ignores equal member creation times', () async {
    final db = await _openSchemaV3Database();
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
    await _bindIdentity(db, familyId: 'family-1', memberId: 'member-a');

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
        avatar: AvatarConfig.defaults(seed: 'member-a'),
      ),
    );
  });

  test('avatar update persists canonical recipe', () async {
    final db = await _openSchemaV3Database();
    addTearDown(db.close);
    final families = FamilyRepository();
    final members = MemberRepository();
    const original = AvatarConfig.defaults(seed: 'member-1');
    final changed = original.copyWith(
      selections: const {'head': 'hm1-p-000001'},
    );
    await families.insert(
      db,
      id: 'family-1',
      name: 'Sabati',
      familyKeyRef: 'family-key',
      createdAt: DateTime.utc(2026, 9, 4),
    );
    await members.insert(
      db,
      id: 'member-1',
      familyId: 'family-1',
      name: 'Chris',
      memberKeyRef: 'member-key-1',
      colorToken: 'ochre',
      avatar: original,
      createdAt: DateTime.utc(2026, 9, 4),
    );
    await _bindIdentity(db, familyId: 'family-1', memberId: 'member-1');
    await members.updateAvatar(db, memberId: 'member-1', avatar: changed);
    expect((await members.findLocalIdentity(db))?.avatar, changed);
    final row = (await db.query('members')).single;
    expect(row['avatar_config_json'], changed.encode());
  });

  test('avatar update rejects an unknown member id', () async {
    final db = await _openSchemaV3Database();
    addTearDown(db.close);

    expect(
      () => MemberRepository().updateAvatar(
        db,
        memberId: 'missing',
        avatar: const AvatarConfig.defaults(seed: 'missing'),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('avatar update changes only the selected member', () async {
    final db = await _openSchemaV3Database();
    addTearDown(db.close);
    final families = FamilyRepository();
    final members = MemberRepository();
    await families.insert(
      db,
      id: 'family-1',
      name: 'Sabati',
      familyKeyRef: 'family-key',
      createdAt: DateTime.utc(2026, 9, 4),
    );
    const first = AvatarConfig.defaults(seed: 'member-1');
    const second = AvatarConfig.defaults(seed: 'member-2');
    await members.insert(
      db,
      id: 'member-1',
      familyId: 'family-1',
      name: 'Chris',
      memberKeyRef: 'member-key-1',
      colorToken: 'ochre',
      avatar: first,
      createdAt: DateTime.utc(2026, 9, 4),
    );
    await members.insert(
      db,
      id: 'member-2',
      familyId: 'family-1',
      name: 'Taylor',
      memberKeyRef: 'member-key-2',
      colorToken: 'ochre',
      avatar: second,
      createdAt: DateTime.utc(2026, 9, 5),
    );
    final changed = first.copyWith(selections: const {'head': 'hm1-p-000001'});

    await members.updateAvatar(db, memberId: 'member-1', avatar: changed);

    final rows = await db.query('members', orderBy: 'id');
    expect(rows[0]['avatar_config_json'], changed.encode());
    expect(rows[1]['avatar_config_json'], second.encode());
  });

  test(
    'empty and malformed avatar recipes fall back to the member id',
    () async {
      final db = await _openSchemaV3Database();
      addTearDown(db.close);
      await _insertFamily(db);
      for (final recipe in const ['{}', 'not json']) {
        await _insertAdult(
          db,
          id: 'member-${recipe.length}',
          memberKeyRef: 'member-key-${recipe.length}',
          createdAt: DateTime.utc(2026, 9, recipe.length),
          avatarConfigJson: recipe,
        );
        await _bindIdentity(
          db,
          familyId: 'family-1',
          memberId: 'member-${recipe.length}',
        );
        final identity = await MemberRepository().findLocalIdentity(db);
        expect(
          identity?.avatar,
          AvatarConfig.defaults(seed: 'member-${recipe.length}'),
        );
        await db.delete('members');
      }
    },
  );

  test(
    'legacy schema row resets and saved Humation avatar survives reload',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'keepers-avatar-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'database', AppDatabase.fileName);
      var db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: KeepersSchema.version,
          onCreate: (database, version) async {
            for (final statement in KeepersSchema.statementsForUpgrade(
              0,
              version,
            )) {
              await database.execute(statement);
            }
          },
        ),
      );
      try {
        await _insertFamily(db);
        await _insertAdult(
          db,
          id: 'member-legacy',
          memberKeyRef: 'member-key',
          createdAt: DateTime.utc(2026, 9, 4),
          avatarConfigJson: '{"schemaVersion":1,"styleId":"previous-avatar","styleRevision":1,"seed":"old-member","hairVariant":"flat-crop"}',
        );
        await _bindIdentity(
          db,
          familyId: 'family-1',
          memberId: 'member-legacy',
        );
      } finally {
        await db.close();
      }

      final keyStore = DatabaseKeyStore(
        _MemorySecureValueStore(),
        randomBytesFactory: (length) => List<int>.filled(length, 7),
      );
      final appDatabase = AppDatabase(
        keyStore,
        databaseFactory: databaseFactoryFfi,
        applicationSupportDirectory: () async => directory,
      );
      try {
        db = await appDatabase.database;
        final members = MemberRepository();
        const fallback = AvatarConfig.defaults(seed: 'member-legacy');
        expect((await members.findLocalIdentity(db))?.avatar, fallback);
        final changed = avatarCatalog
            .optionsFor(AvatarCategory.head)
            .first
            .apply(fallback);
        await members.updateAvatar(
          db,
          memberId: 'member-legacy',
          avatar: changed,
        );
        await appDatabase.close();

        db = await appDatabase.database;
        expect((await members.findLocalIdentity(db))?.avatar, changed);
      } finally {
        await appDatabase.close();
      }
    },
  );
}

Future<Database> _openSchemaV3Database() async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await database.execute('PRAGMA foreign_keys = ON');
  for (final statement in KeepersSchema.statementsForUpgrade(
    0,
    KeepersSchema.version,
  )) {
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
  String? avatarConfigJson,
}) async {
  await database.insert('members', {
    'id': id,
    'family_id': 'family-1',
    'name': id,
    'role': 'adult',
    'member_key_ref': memberKeyRef,
    'color_token': 'ochre',
    'avatar_config_json': ?avatarConfigJson,
    'created_at': createdAt.millisecondsSinceEpoch,
  });
}

Future<void> _bindIdentity(
  DatabaseExecutor database, {
  required String familyId,
  required String memberId,
  String? accountId,
}) async {
  await database.insert('local_identity_binding', {
    'singleton': 1,
    'family_id': familyId,
    'member_id': memberId,
    'account_id': accountId,
  });
}

final class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
