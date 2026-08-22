import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/storage/app_database.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'a transient open failure can be retried on the same instance',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'keepers-database-retry-',
      );
      addTearDown(() => support.delete(recursive: true));
      final factory = _FailOnceDatabaseFactory(databaseFactoryFfi);
      final database = AppDatabase(
        DatabaseKeyStore(
          _MemorySecureValueStore(),
          randomBytesFactory: (length) => List<int>.generate(length, (i) => i),
        ),
        databaseFactory: factory,
        applicationSupportDirectory: () async => support,
      );
      addTearDown(database.close);

      await expectLater(database.database, throwsStateError);
      final opened = await database.database;

      expect(factory.openCalls, 2);
      expect(opened.isOpen, isTrue);
    },
  );
}

final class _FailOnceDatabaseFactory implements DatabaseFactory {
  _FailOnceDatabaseFactory(this.delegate);

  final DatabaseFactory delegate;
  var openCalls = 0;

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async {
    openCalls += 1;
    if (openCalls == 1) throw StateError('temporary open failure');
    return delegate.openDatabase(path, options: options);
  }

  @override
  Future<void> deleteDatabase(String path) => delegate.deleteDatabase(path);

  @override
  Future<bool> databaseExists(String path) => delegate.databaseExists(path);

  @override
  Future<String> getDatabasesPath() => delegate.getDatabasesPath();

  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      delegate.readDatabaseBytes(path);

  @override
  Future<void> setDatabasesPath(String path) => delegate.setDatabasesPath(path);

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      delegate.writeDatabaseBytes(path, bytes);
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
