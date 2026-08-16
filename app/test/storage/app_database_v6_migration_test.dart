import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/storage/app_database.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('fresh database creates both family-code join tables', () async {
    final fixture = await _DatabaseFixture.create();
    addTearDown(fixture.dispose);

    final database = await fixture.appDatabase.database;
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = tables.map((row) => row['name']);

    expect(names, contains('family_code_cache'));
    expect(names, contains('pending_family_join_completion'));
    expect(names, contains('pending_family_invite_completion'));
  });

  test(
    'version 5 to 6 preserves legacy completion and adds join state',
    () async {
      final fixture = await _DatabaseFixture.create(versionFive: true);
      addTearDown(fixture.dispose);

      final database = await fixture.appDatabase.database;

      expect(await database.query('pending_family_invite_completion'), [
        {
          'singleton': 1,
          'invite_id': 'invite-1',
          'family_id': 'family-1',
          'account_id': 'account-1',
          'installed_at': 2,
        },
      ]);
      expect(
        await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('family_code_cache', "
          "'pending_family_join_completion') ORDER BY name",
        ),
        [
          {'name': 'family_code_cache'},
          {'name': 'pending_family_join_completion'},
        ],
      );

      final statements = KeepersSchema.statementsForUpgrade(5, 6).join('\n');
      expect(statements, isNot(contains('DROP TABLE')));
      expect(
        KeepersSchema.tableNames,
        contains('pending_family_invite_completion'),
      );
    },
  );
}

final class _DatabaseFixture {
  _DatabaseFixture(this.directory, this.appDatabase);

  final Directory directory;
  final AppDatabase appDatabase;

  static Future<_DatabaseFixture> create({bool versionFive = false}) async {
    final directory = await Directory.systemTemp.createTemp(
      'keepers-v6-migration-',
    );
    if (versionFive) {
      final path =
          '${directory.path}${Platform.pathSeparator}database'
          '${Platform.pathSeparator}${AppDatabase.fileName}';
      await Directory(File(path).parent.path).create(recursive: true);
      final database = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (database, _) async {
            for (final statement in KeepersSchema.statementsForUpgrade(0, 5)) {
              await database.execute(statement);
            }
          },
        ),
      );
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
      await database.close();
    }
    final appDatabase = AppDatabase(
      DatabaseKeyStore(
        _MemorySecureValueStore(),
        randomBytesFactory: (length) => List<int>.generate(length, (i) => i),
      ),
      databaseFactory: databaseFactoryFfi,
      applicationSupportDirectory: () async => directory,
    );
    return _DatabaseFixture(directory, appDatabase);
  }

  Future<void> dispose() async {
    await appDatabase.close();
    await directory.delete(recursive: true);
  }
}

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
