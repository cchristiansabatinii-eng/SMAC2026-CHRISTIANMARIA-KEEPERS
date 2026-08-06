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

    expect(names, KeepersSchema.tableNames.toSet());

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

  test('only supported forward upgrades are returned', () {
    expect(KeepersSchema.statementsForUpgrade(0, 2), [
      ...KeepersSchema.versionOneStatements,
      ...KeepersSchema.versionTwoStatements,
    ]);
    expect(
      KeepersSchema.statementsForUpgrade(1, 2),
      KeepersSchema.versionTwoStatements,
    );
    expect(() => KeepersSchema.statementsForUpgrade(1, 1), throwsArgumentError);
    expect(() => KeepersSchema.statementsForUpgrade(2, 1), throwsArgumentError);
    expect(() => KeepersSchema.statementsForUpgrade(0, 3), throwsArgumentError);
  });
}
