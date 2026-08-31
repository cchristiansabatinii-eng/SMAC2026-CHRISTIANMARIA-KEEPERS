import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecureValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

final class FlutterSecureValueStore implements SecureValueStore {
  FlutterSecureValueStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }
}

typedef RandomBytesFactory = List<int> Function(int length);

final class DatabaseKeyStore {
  DatabaseKeyStore(
    this._store, {
    RandomBytesFactory? randomBytesFactory,
  }) : _randomBytesFactory =
            randomBytesFactory ?? _generateSecureRandomBytes;

  static const String keyName = 'keepers.database.encryption-key.v1';
  static const int keyLengthInBytes = 32;

  final SecureValueStore _store;
  final RandomBytesFactory _randomBytesFactory;

  Future<String> getOrCreate() async {
    final existing = await _store.read(keyName);
    if (existing != null && _isValidKey(existing)) {
      return existing;
    }

    final key = base64UrlEncode(
      _randomBytesFactory(keyLengthInBytes),
    );
    await _store.write(keyName, key);
    return key;
  }

  static bool _isValidKey(String value) {
    try {
      return base64Url.decode(value).length == keyLengthInBytes;
    } on FormatException {
      return false;
    }
  }

  static List<int> _generateSecureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(
      length,
      (_) => random.nextInt(256),
      growable: false,
    );
  }
}
