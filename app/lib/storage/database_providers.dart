import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/storage/app_database.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final secureValueStoreProvider = Provider<SecureValueStore>(
  (ref) => FlutterSecureValueStore(),
);

final databaseKeyStoreProvider = Provider<DatabaseKeyStore>(
  (ref) => DatabaseKeyStore(ref.watch(secureValueStoreProvider)),
);

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase(ref.watch(databaseKeyStoreProvider));
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final databaseProvider = FutureProvider<Database>(
  (ref) => ref.watch(appDatabaseProvider).database,
);
