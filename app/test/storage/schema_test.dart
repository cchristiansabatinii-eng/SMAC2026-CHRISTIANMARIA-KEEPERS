import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('v1 schema executes and creates every domain table', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);

    await database.execute('PRAGMA foreign_keys = ON');
    for (final statement in KeepersSchema.versionOneStatements) {
      await database.execute(statement);
    }

    final rows = await database.rawQuery(r'''
SELECT name FROM sqlite_master
WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
''');
    final names = rows.map((row) => row['name']).whereType<String>().toSet();

    expect(
      names,
      KeepersSchema.tableNames
          .where(
            (name) =>
                name != 'pending_family_invite_completion' &&
                name != 'family_code_cache' &&
                name != 'pending_family_join_completion',
          )
          .toSet(),
    );

    final foreignKeys = await database.rawQuery('PRAGMA foreign_keys');
    expect(foreignKeys.single['foreign_keys'], 1);
  });

  test('v1 models the privacy and lifecycle constraints', () {
    final schema = KeepersSchema.versionOneStatements.join('\n');

    expect(schema, contains("privacy_tier IN ('journal', 'reveal', 'legacy')"));
    expect(
      schema,
      contains("state IN ('pending', 'revealed', 'kept', 'expired')"),
    );
    expect(schema, contains('spectator_locked'));
    expect(schema, contains('closing_question_entry_id'));
    expect(schema, contains('memorial_state'));
  });

  test('v2 upgrades members with key reference and stable color', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);

    for (final statement in KeepersSchema.versionOneStatements) {
      await database.execute(statement);
    }
    for (final statement in KeepersSchema.statementsForUpgrade(1, 2)) {
      await database.execute(statement);
    }

    final columns = await database.rawQuery('PRAGMA table_info(members)');
    expect(
      columns.map((row) => row['name']),
      containsAll(['member_key_ref', 'color_token']),
    );
    final color = columns.singleWhere((row) => row['name'] == 'color_token');
    expect(color['notnull'], 1);
    expect(color['dflt_value'], "'ochre'");
  });

  test('v3 upgrades members with an opaque avatar recipe', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);

    for (final statement in KeepersSchema.statementsForUpgrade(0, 2)) {
      await database.execute(statement);
    }
    for (final statement in KeepersSchema.statementsForUpgrade(2, 3)) {
      await database.execute(statement);
    }

    final columns = await database.rawQuery('PRAGMA table_info(members)');
    final avatar = columns.singleWhere(
      (row) => row['name'] == 'avatar_config_json',
    );
    expect(avatar['type'], 'TEXT');
    expect(avatar['notnull'], 1);
    expect(avatar['dflt_value'], "'{}'");
  });

  test('v4 adds and backfills one explicit local identity binding', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await database.execute('PRAGMA foreign_keys = ON');
    for (final statement in KeepersSchema.statementsForUpgrade(0, 3)) {
      await database.execute(statement);
    }
    await database.insert('families', {
      'id': 'family-1',
      'name': 'Sabati',
      'family_key_ref': 'family-key',
      'quorum': 1,
      'created_at': 1,
    });
    await database.insert('members', {
      'id': 'member-child',
      'family_id': 'family-1',
      'name': 'Earlier child',
      'role': 'child',
      'created_at': 0,
      'member_key_ref': 'child-key',
      'color_token': 'teal',
      'avatar_config_json': '{}',
    });
    await database.insert('members', {
      'id': 'member-1',
      'family_id': 'family-1',
      'name': 'Chris',
      'role': 'adult',
      'created_at': 1,
      'member_key_ref': 'member-key',
      'color_token': 'ochre',
      'avatar_config_json': '{}',
    });

    for (final statement in KeepersSchema.statementsForUpgrade(3, 4)) {
      await database.execute(statement);
    }

    expect(await database.query('local_identity_binding'), [
      {
        'singleton': 1,
        'family_id': 'family-1',
        'member_id': 'member-1',
        'account_id': null,
      },
    ]);
  });

  test('v5 stores one pending invite completion and cascades it', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await database.execute('PRAGMA foreign_keys = ON');
    for (final statement in KeepersSchema.statementsForUpgrade(0, 5)) {
      await database.execute(statement);
    }
    await database.insert('families', {
      'id': 'family-1',
      'name': 'Sabati',
      'family_key_ref': 'family-key',
      'quorum': 1,
      'created_at': 1,
    });
    await database.insert('pending_family_invite_completion', {
      'singleton': 1,
      'invite_id': 'invite-1',
      'family_id': 'family-1',
      'account_id': 'account-1',
      'installed_at': 2,
    });
    expect(
      KeepersSchema.tableNames,
      contains('pending_family_invite_completion'),
    );

    expect(await database.query('pending_family_invite_completion'), [
      {
        'singleton': 1,
        'invite_id': 'invite-1',
        'family_id': 'family-1',
        'account_id': 'account-1',
        'installed_at': 2,
      },
    ]);

    await database.delete('families', where: 'id = ?', whereArgs: ['family-1']);
    expect(await database.query('pending_family_invite_completion'), isEmpty);
  });

  test('only supported forward upgrades are returned', () {
    expect(KeepersSchema.version, 6);
    expect(KeepersSchema.statementsForUpgrade(0, 6), [
      ...KeepersSchema.versionOneStatements,
      ...KeepersSchema.versionTwoStatements,
      ...KeepersSchema.versionThreeStatements,
      ...KeepersSchema.versionFourStatements,
      ...KeepersSchema.versionFiveStatements,
      ...KeepersSchema.versionSixStatements,
    ]);
    expect(KeepersSchema.statementsForUpgrade(1, 6), [
      ...KeepersSchema.versionTwoStatements,
      ...KeepersSchema.versionThreeStatements,
      ...KeepersSchema.versionFourStatements,
      ...KeepersSchema.versionFiveStatements,
      ...KeepersSchema.versionSixStatements,
    ]);
    expect(KeepersSchema.statementsForUpgrade(2, 6), [
      ...KeepersSchema.versionThreeStatements,
      ...KeepersSchema.versionFourStatements,
      ...KeepersSchema.versionFiveStatements,
      ...KeepersSchema.versionSixStatements,
    ]);
    expect(KeepersSchema.statementsForUpgrade(3, 6), [
      ...KeepersSchema.versionFourStatements,
      ...KeepersSchema.versionFiveStatements,
      ...KeepersSchema.versionSixStatements,
    ]);
    expect(KeepersSchema.statementsForUpgrade(4, 6), [
      ...KeepersSchema.versionFiveStatements,
      ...KeepersSchema.versionSixStatements,
    ]);
    expect(KeepersSchema.statementsForUpgrade(5, 6), [
      ...KeepersSchema.versionSixStatements,
    ]);
    expect(() => KeepersSchema.statementsForUpgrade(1, 1), throwsArgumentError);
    expect(() => KeepersSchema.statementsForUpgrade(2, 1), throwsArgumentError);
    expect(() => KeepersSchema.statementsForUpgrade(0, 7), throwsArgumentError);
  });
}
