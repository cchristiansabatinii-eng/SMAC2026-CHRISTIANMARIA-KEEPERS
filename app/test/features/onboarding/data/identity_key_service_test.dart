import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/storage/database_key_store.dart';

void main() {
  test('creates independent 256-bit keys with stable references', () async {
    final store = _MemorySecureValueStore();
    var nextByte = 1;
    final service = IdentityKeyService(
      store,
      randomBytesFactory: (length) => List<int>.filled(length, nextByte++),
    );

    final keys = await service.createFor(
      familyId: 'family-1',
      memberId: 'member-1',
    );

    expect(keys.familyKeyRef, 'keepers.family.family-1.entry-key.v1');
    expect(keys.memberKeyRef, 'keepers.member.member-1.entry-key.v1');
    expect(await service.resolve(keys.familyKeyRef), hasLength(32));
    expect(await service.resolve(keys.memberKeyRef), hasLength(32));
    expect(
      await service.resolve(keys.familyKeyRef),
      isNot(await service.resolve(keys.memberKeyRef)),
    );
  });

  test('rolls back both references when setup cannot commit', () async {
    final store = _MemorySecureValueStore();
    final service = IdentityKeyService(
      store,
      randomBytesFactory: (length) => List<int>.filled(length, 7),
    );
    final keys = await service.createFor(familyId: 'f', memberId: 'm');

    await service.rollback(keys);

    expect(await store.read(keys.familyKeyRef), isNull);
    expect(await store.read(keys.memberKeyRef), isNull);
  });

  test('rolls back all new references when the second write fails', () async {
    final store = _MemorySecureValueStore(failWriteNumber: 2);
    final service = IdentityKeyService(
      store,
      randomBytesFactory: (length) => List<int>.filled(length, 7),
    );

    await expectLater(
      service.createFor(familyId: 'f', memberId: 'm'),
      throwsA(isA<StateError>()),
    );

    expect(store.values, isEmpty);
  });

  test('rejects a missing identity key reference', () async {
    final service = IdentityKeyService(_MemorySecureValueStore());

    await expectLater(service.resolve('missing-key'), throwsStateError);
  });

  test('rejects a stored identity key that is not 32 bytes', () async {
    final store = _MemorySecureValueStore()
      ..values['short-key'] = base64UrlEncode(List<int>.filled(31, 7));
    final service = IdentityKeyService(store);

    await expectLater(service.resolve('short-key'), throwsStateError);
  });

  test('returns resolved identity key bytes as an immutable list', () async {
    final store = _MemorySecureValueStore()
      ..values['identity-key'] = base64UrlEncode(List<int>.filled(32, 7));
    final service = IdentityKeyService(store);

    final resolved = await service.resolve('identity-key');

    expect(() => resolved[0] = 9, throwsUnsupportedError);
    expect(resolved[0], 7);
  });
}

final class _MemorySecureValueStore implements SecureValueStore {
  _MemorySecureValueStore({this.failWriteNumber});

  final int? failWriteNumber;
  final Map<String, String> values = {};
  int _writeCount = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    _writeCount += 1;
    if (_writeCount == failWriteNumber) {
      throw StateError('secure write failed');
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
