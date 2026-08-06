import 'dart:convert';
import 'dart:math';

import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/database_key_store.dart';

final class IdentityKeyService {
  IdentityKeyService(this._store, {RandomBytesFactory? randomBytesFactory})
    : _randomBytesFactory = randomBytesFactory ?? _secureBytes;

  final SecureValueStore _store;
  final RandomBytesFactory _randomBytesFactory;

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

  static List<int> _secureBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(
      length,
      (_) => random.nextInt(256),
      growable: false,
    );
  }
}
