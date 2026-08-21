import 'dart:async';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/storage/database_key_store.dart';

typedef JoiningSeedFactory = List<int> Function(int length);
typedef JoiningKeyOperation = Future<T> Function<T>(
  Future<T> Function(SimpleKeyPair keyPair) operation,
);

final class StoredJoiningKey {
  const StoredJoiningKey._({
    required this.reference,
    required this.publicKey,
    required this._use,
  });

  final String reference;
  final String publicKey;
  final JoiningKeyOperation _use;

  Future<T> use<T>(Future<T> Function(SimpleKeyPair keyPair) operation) =>
      _use(operation);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoredJoiningKey &&
          other.reference == reference &&
          other.publicKey == publicKey;

  @override
  int get hashCode => Object.hash(reference, publicKey);

  @override
  String toString() => 'StoredJoiningKey(<redacted>)';
}

abstract interface class JoiningKeyStore {
  Future<StoredJoiningKey> getOrCreate({
    required String accountId,
    required String memberId,
  });

  Future<StoredJoiningKey?> find({
    required String accountId,
    required String memberId,
  });

  Future<T> use<T>({
    required StoredJoiningKey key,
    required Future<T> Function(SimpleKeyPair keyPair) operation,
  });

  Future<void> deleteExact(StoredJoiningKey key);
}

final class SecureJoiningKeyStore implements JoiningKeyStore {
  SecureJoiningKeyStore(this._values, {JoiningSeedFactory? seedFactory})
    : _seedFactory = seedFactory ?? _secureRandomBytes;

  static const int seedLength = 32;

  final SecureValueStore _values;
  final JoiningSeedFactory _seedFactory;
  final X25519 _algorithm = X25519();
  static final Map<String, Future<void>> _referenceTails =
      <String, Future<void>>{};

  static String referenceFor({
    required String accountId,
    required String memberId,
  }) {
    _validateUuid(accountId, 'accountId');
    _validateUuid(memberId, 'memberId');
    return 'keepers.join.$accountId.$memberId.x25519-seed.v1';
  }

  @override
  Future<StoredJoiningKey> getOrCreate({
    required String accountId,
    required String memberId,
  }) async {
    final reference = referenceFor(accountId: accountId, memberId: memberId);
    return _exclusive(reference, () async {
      final existing = await _findExact(reference);
      if (existing != null) return existing;

      final seed = _seedFactory(seedLength);
      SimpleKeyPair? keyPair;
      try {
        _validateSeed(seed);
        keyPair = await _algorithm.newKeyPairFromSeed(seed);
        final publicKey = await keyPair.extractPublicKey();
        await _values.write(reference, unpaddedFamilyJoinBase64Url(seed));
        return _handle(
          reference: reference,
          publicKey: unpaddedFamilyJoinBase64Url(publicKey.bytes),
        );
      } finally {
        keyPair?.destroy();
        _zero(seed);
      }
    });
  }

  @override
  Future<StoredJoiningKey?> find({
    required String accountId,
    required String memberId,
  }) async {
    final reference = referenceFor(accountId: accountId, memberId: memberId);
    return _exclusive(reference, () => _findExact(reference));
  }

  Future<StoredJoiningKey?> _findExact(String reference) async {
    final encodedSeed = await _values.read(reference);
    if (encodedSeed == null) return null;
    final seed = _decodeSeed(encodedSeed);
    SimpleKeyPair? keyPair;
    try {
      keyPair = await _algorithm.newKeyPairFromSeed(seed);
      final publicKey = await keyPair.extractPublicKey();
      return _handle(
        reference: reference,
        publicKey: unpaddedFamilyJoinBase64Url(publicKey.bytes),
      );
    } finally {
      keyPair?.destroy();
      _zero(seed);
    }
  }

  @override
  Future<T> use<T>({
    required StoredJoiningKey key,
    required Future<T> Function(SimpleKeyPair keyPair) operation,
  }) async {
    _validateHandle(key);
    return _exclusive(key.reference, () async {
      final encodedSeed = await _values.read(key.reference);
      if (encodedSeed == null) {
        throw const FamilyJoinFailure(FamilyJoinFailureCode.invalidJoinKey);
      }
      final seed = _decodeSeed(encodedSeed);
      SimpleKeyPair? keyPair;
      try {
        keyPair = await _algorithm.newKeyPairFromSeed(seed);
        if (!await _keyMatches(keyPair, key.publicKey)) {
          throw const FamilyJoinFailure(FamilyJoinFailureCode.invalidJoinKey);
        }
        return await operation(keyPair);
      } finally {
        keyPair?.destroy();
        _zero(seed);
      }
    });
  }

  @override
  Future<void> deleteExact(StoredJoiningKey key) async {
    _validateHandle(key);
    return _exclusive(key.reference, () async {
      final encodedSeed = await _values.read(key.reference);
      if (encodedSeed == null) return;
      final seed = _decodeSeed(encodedSeed);
      SimpleKeyPair? keyPair;
      try {
        keyPair = await _algorithm.newKeyPairFromSeed(seed);
        if (await _keyMatches(keyPair, key.publicKey)) {
          await _values.delete(key.reference);
        }
      } finally {
        keyPair?.destroy();
        _zero(seed);
      }
    });
  }

  Future<bool> _keyMatches(SimpleKeyPair keyPair, String expected) async {
    final publicKey = await keyPair.extractPublicKey();
    return unpaddedFamilyJoinBase64Url(publicKey.bytes) == expected;
  }

  StoredJoiningKey _handle({
    required String reference,
    required String publicKey,
  }) {
    late final StoredJoiningKey key;
    key = StoredJoiningKey._(
      reference: reference,
      publicKey: publicKey,
      use: <T>(operation) => use(key: key, operation: operation),
    );
    return key;
  }

  static Future<T> _exclusive<T>(
    String reference,
    Future<T> Function() operation,
  ) async {
    final predecessor = _referenceTails[reference] ?? Future<void>.value();
    final complete = Completer<void>();
    _referenceTails[reference] = complete.future;
    try {
      await predecessor;
      return await operation();
    } finally {
      complete.complete();
      if (identical(_referenceTails[reference], complete.future)) {
        final _ = _referenceTails.remove(reference);
      }
    }
  }

  static List<int> _decodeSeed(String value) {
    try {
      return decodeCanonicalFamilyJoinBase64Url(
        value,
        expectedLength: seedLength,
        field: 'joining key seed',
      );
    } on FormatException {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.invalidJoinKey);
    }
  }

  static void _validateSeed(List<int> seed) {
    if (seed.length != seedLength ||
        seed.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError.value(seed.length, 'seed', 'Must contain 32 bytes');
    }
  }

  static void _validateHandle(StoredJoiningKey key) {
    if (!RegExp(
      r'^keepers\.join\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.x25519-seed\.v1$',
    ).hasMatch(key.reference)) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.invalidJoinKey);
    }
    try {
      decodeCanonicalFamilyJoinBase64Url(
        key.publicKey,
        expectedLength: seedLength,
        field: 'joining public key',
      );
    } on FormatException {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.invalidJoinKey);
    }
  }

  static void _validateUuid(String value, String field) {
    if (!isCanonicalFamilyJoinUuid(value)) {
      throw ArgumentError.value(value, field, 'Must be a canonical UUID');
    }
  }

  static void _zero(List<int> bytes) {
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = 0;
    }
  }

  static List<int> _secureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(
      length,
      (_) => random.nextInt(256),
      growable: false,
    );
  }
}
