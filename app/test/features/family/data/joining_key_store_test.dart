import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/joining_key_store.dart';
import 'package:keepers/features/family/domain/family_join_failure.dart';
import 'package:keepers/storage/database_key_store.dart';

void main() {
  const accountId = '11111111-1111-4111-8111-111111111111';
  const memberId = '22222222-2222-4222-8222-222222222222';

  test('returns the same public key after a store restart', () async {
    final values = _MemorySecureValueStore();
    final store = SecureJoiningKeyStore(values, seedFactory: fixedSeed);
    final first = await store.getOrCreate(
      accountId: accountId,
      memberId: memberId,
    );
    final restarted = SecureJoiningKeyStore(values, seedFactory: fixedSeed);
    final second = await restarted.getOrCreate(
      accountId: accountId,
      memberId: memberId,
    );

    expect(second.publicKey, first.publicKey);
    expect(second.reference, first.reference);
  });

  test('never exposes the private seed in its handle or diagnostics', () async {
    final store = SecureJoiningKeyStore(
      _MemorySecureValueStore(),
      seedFactory: fixedSeed,
    );

    final key = await store.getOrCreate(
      accountId: accountId,
      memberId: memberId,
    );

    expect(key.toString(), 'StoredJoiningKey(<redacted>)');
    expect(key.toString(), isNot(contains(base64UrlEncode(fixedSeed(32)))));
  });

  test(
    'persists only canonical seed material and isolates identities',
    () async {
      const otherAccountId = '33333333-3333-4333-8333-333333333333';
      final values = _MemorySecureValueStore();
      final store = SecureJoiningKeyStore(values, seedFactory: fixedSeed);
      final first = await store.getOrCreate(
        accountId: accountId,
        memberId: memberId,
      );
      final second = await store.getOrCreate(
        accountId: otherAccountId,
        memberId: memberId,
      );

      expect(
        await values.read(first.reference),
        'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      );
      expect(first.reference, isNot(second.reference));
      expect(
        values.values.keys,
        containsAll(<String>[first.reference, second.reference]),
      );
    },
  );

  test('deletes exact material and rejects malformed stored seeds', () async {
    final values = _MemorySecureValueStore();
    final store = SecureJoiningKeyStore(values, seedFactory: fixedSeed);
    final key = await store.getOrCreate(
      accountId: accountId,
      memberId: memberId,
    );

    await store.deleteExact(key);
    expect(await values.read(key.reference), isNull);

    await values.write(key.reference, 'not-canonical=');
    await expectLater(
      store.find(accountId: accountId, memberId: memberId),
      throwsA(const FamilyJoinFailure(FamilyJoinFailureCode.invalidJoinKey)),
    );
  });

  test('serializes concurrent getOrCreate calls for one identity', () async {
    var generation = 0;
    final store = SecureJoiningKeyStore(
      _MemorySecureValueStore(),
      seedFactory: (length) => List<int>.filled(length, ++generation),
    );

    final keys = await Future.wait(<Future<StoredJoiningKey>>[
      store.getOrCreate(accountId: accountId, memberId: memberId),
      store.getOrCreate(accountId: accountId, memberId: memberId),
    ]);

    expect(generation, 1);
    expect(keys[0], keys[1]);
  });

  test('stale handles cannot delete replacement material', () async {
    final values = _MemorySecureValueStore();
    final store = SecureJoiningKeyStore(values, seedFactory: fixedSeed);
    final key = await store.getOrCreate(
      accountId: accountId,
      memberId: memberId,
    );
    await values.write(
      key.reference,
      base64UrlEncode(List<int>.filled(32, 9)).replaceAll('=', ''),
    );

    await store.deleteExact(key);

    expect(await values.read(key.reference), isNotNull);
  });

  test(
    'zeroes the mutable seed-factory buffer after deriving the key',
    () async {
      final source = List<int>.generate(32, (index) => index + 1);
      final store = SecureJoiningKeyStore(
        _MemorySecureValueStore(),
        seedFactory: (_) => source,
      );

      await store.getOrCreate(accountId: accountId, memberId: memberId);

      expect(source, everyElement(0));
    },
  );

  test('destroys the callback key pair when use completes', () async {
    final store = SecureJoiningKeyStore(
      _MemorySecureValueStore(),
      seedFactory: fixedSeed,
    );
    final key = await store.getOrCreate(
      accountId: accountId,
      memberId: memberId,
    );
    SimpleKeyPair? retained;

    await store.use<void>(
      key: key,
      operation: (keyPair) async {
        retained = keyPair;
      },
    );

    expect(retained, isNotNull);
    expect(retained!.hasBeenDestroyed, isTrue);
  });

  test(
    'serializes overlapping deletion and recreation for one identity',
    () async {
      final values = _DeleteGateSecureValueStore();
      var generation = 0;
      final store = SecureJoiningKeyStore(
        values,
        seedFactory: (length) => List<int>.filled(length, ++generation),
      );
      final first = await store.getOrCreate(
        accountId: accountId,
        memberId: memberId,
      );

      final deleting = store.deleteExact(first);
      await values.deleteStarted.future;
      final recreating = store.getOrCreate(
        accountId: accountId,
        memberId: memberId,
      );
      await Future<void>.delayed(Duration.zero);
      values.allowDelete.complete();
      final second = await recreating;
      await deleting;

      expect(second.publicKey, isNot(first.publicKey));
      expect(await values.read(second.reference), isNotNull);
    },
  );
}

List<int> fixedSeed(int length) => List<int>.generate(length, (index) => index);

class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

final class _DeleteGateSecureValueStore extends _MemorySecureValueStore {
  final deleteStarted = Completer<void>();
  final allowDelete = Completer<void>();

  @override
  Future<void> delete(String key) async {
    deleteStarted.complete();
    await allowDelete.future;
    await super.delete(key);
  }
}
