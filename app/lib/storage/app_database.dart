import 'dart:io';

import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/schema.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final class AppDatabase {
  AppDatabase(this._keyStore);

  static const String fileName = 'keepers.db';

  final DatabaseKeyStore _keyStore;
  Future<Database>? _databaseFuture;

  Future<Database> get database => _databaseFuture ??= _open();

  Future<void> close() async {
    final databaseFuture = _databaseFuture;
    if (databaseFuture == null) {
      return;
    }

    final database = await databaseFuture;
    await database.close();
    _databaseFuture = null;
  }

  Future<Database> _open() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final databaseDirectory = Directory(
      p.join(supportDirectory.path, 'database'),
    );
    await databaseDirectory.create(recursive: true);

    final password = await _keyStore.getOrCreate();
    return openDatabase(
      p.join(databaseDirectory.path, fileName),
      password: password,
      version: KeepersSchema.version,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database database) async {
    await database.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database database, int version) {
    return _runStatements(
      database,
      KeepersSchema.statementsForUpgrade(0, version),
    );
  }

  Future<void> _onUpgrade(Database database, int oldVersion, int newVersion) {
    return _runStatements(
      database,
      KeepersSchema.statementsForUpgrade(oldVersion, newVersion),
    );
  }

  Future<void> _runStatements(
    Database database,
    List<String> statements,
  ) async {
    final batch = database.batch();
    for (final statement in statements) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }
}
