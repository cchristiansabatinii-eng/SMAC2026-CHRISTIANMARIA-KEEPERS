import 'dart:convert';
import 'dart:math';

import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/database_key_store.dart';

final class StoredIdentityKey {
  const StoredIdentityKey({required this.reference, required this.wasCreated});

  final String reference;
  final bool wasCreated;
}

final class IdentityKeyService {
  IdentityKeyService(this._store, {RandomBytesFactory? randomBytesFactory})
    : _randomBytesFactory = randomBytesFactory ?? _secureBytes;

  final SecureValueStore _store;
  final RandomBytesFactory _randomBytesFactory;

  Future<StoredIdentityKey> importFamilyKey({
    required String familyId,
    required List<int> familyKey,
  }) async {
    if (familyKey.length != 32) {
      throw ArgumentError.value(familyKey.length, 'familyKey.length');
    }
    final reference = 'keepers.family.$familyId.entry-key.v1';
    final existing = await _store.read(reference);
    if (existing != null) {
      final existingBytes = await resolve(reference);
      if (!_sameBytes(existingBytes, familyKey)) {
        throw StateError('A different family key is already stored');
      }
      return StoredIdentityKey(reference: reference, wasCreated: false);
    }

    await _store.write(reference, base64UrlEncode(List<int>.from(familyKey)));
    return StoredIdentityKey(reference: reference, wasCreated: true);
  }

  Future<StoredIdentityKey> createMemberKey({required String memberId}) async {
    final reference = 'keepers.member.$memberId.entry-key.v1';
    final existing = await _store.read(reference);
    if (existing != null) {
      await resolve(reference);
      return StoredIdentityKey(reference: reference, wasCreated: false);
    }

    await _store.write(reference, base64UrlEncode(_randomBytesFactory(32)));
    return StoredIdentityKey(reference: reference, wasCreated: true);
  }

  Future<CreatedIdentityKeys> createFor({
    required String familyId,
    required String memberId,
  }) async {
    final familyRef = 'keepers.family.$familyId.entry-key.v1';
    final memberRef = 'keepers.member.$memberId.entry-key.v1';
    try {
      await _store.write(familyRef, base64UrlEncode(_randomBytesFactory(32)));
      await _store.write(memberRef, base64UrlEncode(_randomBytesFactory(32)));
      return CreatedIdentityKeys(
        familyKeyRef: familyRef,
        memberKeyRef: memberRef,
      );
    } catch (_) {
      await _store.delete(memberRef);
      await _store.delete(familyRef);
      rethrow;
    }
  }

  Future<List<int>> resolve(String reference) async {
    final encoded = await _store.read(reference);
    if (encoded == null) {
      throw StateError('Missing identity key: $reference');
    }
    final bytes = base64Url.decode(encoded);
    if (bytes.length != 32) {
      throw StateError('Invalid identity key: $reference');
    }
    return List<int>.unmodifiable(bytes);
  }

  Future<void> rollback(CreatedIdentityKeys keys) async {
    await _store.delete(keys.memberKeyRef);
    await _store.delete(keys.familyKeyRef);
  }

  Future<void> rollbackKey(StoredIdentityKey key) async {
    if (key.wasCreated) {
      await _store.delete(key.reference);
    }
  }

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  static List<int> _secureBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(
      length,
      (_) => random.nextInt(256),
      growable: false,
    );
  }
}
