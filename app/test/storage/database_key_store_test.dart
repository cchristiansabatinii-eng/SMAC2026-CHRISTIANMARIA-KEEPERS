import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/storage/database_key_store.dart';

void main() {
  test('creates and reuses a 256-bit database key', () async {
    final secureStore = _MemorySecureValueStore();
    var generations = 0;
    final keyStore = DatabaseKeyStore(
      secureStore,
      randomBytesFactory: (length) {
        generations += 1;
        return List<int>.generate(length, (index) => index);
      },
    );

    final first = await keyStore.getOrCreate();
    final second = await keyStore.getOrCreate();

    expect(base64Url.decode(first), hasLength(32));
    expect(second, first);
    expect(generations, 1);
  });

  test('replaces a malformed stored key', () async {
    final secureStore = _MemorySecureValueStore()
      ..values[DatabaseKeyStore.keyName] = 'not-base64';
    final keyStore = DatabaseKeyStore(
      secureStore,
      randomBytesFactory: (length) => List<int>.filled(length, 7),
    );

    final key = await keyStore.getOrCreate();

    expect(base64Url.decode(key), hasLength(32));
    expect(secureStore.values[DatabaseKeyStore.keyName], key);
  });

  test('secure values can be deleted for rollback', () async {
    final store = _MemorySecureValueStore()..values['temporary'] = 'secret';

    await store.delete('temporary');

    expect(await store.read('temporary'), isNull);
  });
}

final class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
