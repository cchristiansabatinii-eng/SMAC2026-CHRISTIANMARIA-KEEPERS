import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/secure_supabase_auth_storage.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SecureSupabaseAuthStorage', () {
    test(
      'persists, restores, and removes the opaque session securely',
      () async {
        final secureStore = _MemorySecureValueStore();
        final storage = SecureSupabaseAuthStorage(
          secureStore: secureStore,
          secureSessionKey: 'keepers.test.auth-session',
        );

        await storage.initialize();
        expect(await storage.hasAccessToken(), isFalse);
        expect(await storage.accessToken(), isNull);

        await storage.persistSession('opaque-session-json');

        expect(await storage.hasAccessToken(), isTrue);
        expect(await storage.accessToken(), 'opaque-session-json');
        expect(secureStore.values, <String, String>{
          'keepers.test.auth-session': 'opaque-session-json',
        });

        await storage.removePersistedSession();

        expect(await storage.hasAccessToken(), isFalse);
        expect(await storage.accessToken(), isNull);
        expect(secureStore.values, isEmpty);
      },
    );

    test(
      'clears the legacy preference without migrating its session',
      () async {
        final secureStore = _MemorySecureValueStore();
        final legacyStorage = _MemoryLocalStorage('legacy-session-json');
        final legacyPkceStorage = _MemoryPkceStorage(<String, String>{
          SecureSupabasePkceStorage.legacyVerifierKey: 'legacy-verifier',
        });
        final storage = SecureSupabaseAuthStorage(
          secureStore: secureStore,
          secureSessionKey: 'keepers.test.auth-session',
          legacyStorage: legacyStorage,
          legacyPkceStorage: legacyPkceStorage,
        );

        await storage.initialize();

        expect(legacyStorage.initializeCalls, 1);
        expect(legacyStorage.session, isNull);
        expect(legacyPkceStorage.values, isEmpty);
        expect(await storage.accessToken(), isNull);
        expect(secureStore.values, isEmpty);
      },
    );

    test('fails closed when the legacy preference cannot be removed', () async {
      final secureStore = _MemorySecureValueStore()
        ..values['keepers.test.auth-session'] = 'secure-session-json';
      final storage = SecureSupabaseAuthStorage(
        secureStore: secureStore,
        secureSessionKey: 'keepers.test.auth-session',
        legacyStorage: _MemoryLocalStorage(
          'legacy-session-json',
          failRemoval: true,
        ),
      );

      await expectLater(storage.initialize(), throwsStateError);

      expect(
        secureStore.values['keepers.test.auth-session'],
        'secure-session-json',
      );
    });

    test(
      'fails closed when the legacy PKCE verifier cannot be removed',
      () async {
        final secureStore = _MemorySecureValueStore()
          ..values['keepers.test.auth-session'] = 'secure-session-json';
        final storage = SecureSupabaseAuthStorage(
          secureStore: secureStore,
          secureSessionKey: 'keepers.test.auth-session',
          legacyStorage: _MemoryLocalStorage(null),
          legacyPkceStorage: _MemoryPkceStorage(<String, String>{
            SecureSupabasePkceStorage.legacyVerifierKey: 'legacy-verifier',
          }, failRemoval: true),
        );

        await expectLater(storage.initialize(), throwsStateError);

        expect(
          secureStore.values['keepers.test.auth-session'],
          'secure-session-json',
        );
      },
    );
  });

  test('PKCE verifier values use the same secure value abstraction', () async {
    final secureStore = _MemorySecureValueStore();
    final storage = SecureSupabasePkceStorage(
      secureStore: secureStore,
      keyPrefix: 'keepers.test.pkce',
    );

    await storage.setItem(key: 'code-verifier', value: 'opaque-verifier');

    expect(await storage.getItem(key: 'code-verifier'), 'opaque-verifier');
    expect(secureStore.values, <String, String>{
      'keepers.test.pkce.code-verifier': 'opaque-verifier',
    });

    await storage.removeItem(key: 'code-verifier');

    expect(await storage.getItem(key: 'code-verifier'), isNull);
    expect(secureStore.values, isEmpty);
  });

  test('pending PKCE cancellation is atomic with verifier checkout', () async {
    final secureStore = _MemorySecureValueStore();
    final storage = SecureSupabasePkceStorage(
      secureStore: secureStore,
      keyPrefix: 'keepers.test.pkce',
    );

    await storage.beginAuthAttempt('attempt-a');
    await storage.setItem(
      key: SecureSupabasePkceStorage.legacyVerifierKey,
      value: 'opaque-verifier',
    );
    expect(
      await storage.cancelPendingVerifier(),
      isTrue,
      reason: 'a verifier that has not been checked out can be cancelled',
    );
    expect(secureStore.values, isEmpty);

    await storage.beginAuthAttempt('attempt-b');
    await storage.setItem(
      key: SecureSupabasePkceStorage.legacyVerifierKey,
      value: 'replacement-verifier',
    );
    expect(storage.acceptCallbackAttempt('attempt-b'), isTrue);
    expect(
      await storage.getItem(key: SecureSupabasePkceStorage.legacyVerifierKey),
      'replacement-verifier',
    );
    expect(
      await storage.cancelPendingVerifier(),
      isFalse,
      reason: 'an exchange that already read the verifier must finish alone',
    );
    expect(secureStore.values, isNotEmpty);

    expect(await storage.clearFailedVerifier(), isTrue);

    expect(secureStore.values, isEmpty);
    expect(
      await storage.cancelPendingVerifier(),
      isTrue,
      reason: 'a terminal callback failure releases the verifier slot',
    );
  });

  test(
    'an already-issued unmarked callback can consume a legacy verifier',
    () async {
      final secureStore = _MemorySecureValueStore();
      final storage = SecureSupabasePkceStorage(
        secureStore: secureStore,
        keyPrefix: 'keepers.test.pkce',
      );
      await storage.initialize();
      await storage.setItem(
        key: SecureSupabasePkceStorage.legacyVerifierKey,
        value: 'legacy-unmarked-verifier',
      );

      expect(storage.acceptCallbackAttempt(null), isTrue);
      expect(
        await storage.getItem(key: SecureSupabasePkceStorage.legacyVerifierKey),
        'legacy-unmarked-verifier',
      );
      await storage.removeItem(
        key: SecureSupabasePkceStorage.legacyVerifierKey,
      );

      expect(secureStore.values, isEmpty);
    },
  );

  test(
    'a stale callback cannot consume or clear a newer PKCE attempt',
    () async {
      final secureStore = _MemorySecureValueStore();
      final storage = SecureSupabasePkceStorage(
        secureStore: secureStore,
        keyPrefix: 'keepers.test.pkce',
      );

      await storage.beginAuthAttempt('attempt-a');
      await storage.setItem(
        key: SecureSupabasePkceStorage.legacyVerifierKey,
        value: 'verifier-a',
      );
      expect(storage.acceptCallbackAttempt('attempt-a'), isTrue);
      expect(await storage.cancelPendingVerifier(), isTrue);

      await storage.beginAuthAttempt('attempt-b');
      await storage.setItem(
        key: SecureSupabasePkceStorage.legacyVerifierKey,
        value: 'verifier-b',
      );

      final afterRestart = SecureSupabasePkceStorage(
        secureStore: secureStore,
        keyPrefix: 'keepers.test.pkce',
      );
      await afterRestart.initialize();

      expect(afterRestart.acceptCallbackAttempt('attempt-a'), isFalse);
      expect(
        await afterRestart.getItem(
          key: SecureSupabasePkceStorage.legacyVerifierKey,
        ),
        isNull,
      );
      expect(await afterRestart.clearFailedVerifier(), isFalse);
      expect(
        secureStore.values,
        containsPair(
          'keepers.test.pkce.${SecureSupabasePkceStorage.legacyVerifierKey}',
          'verifier-b',
        ),
      );

      expect(afterRestart.acceptCallbackAttempt('attempt-b'), isTrue);
      expect(
        await afterRestart.getItem(
          key: SecureSupabasePkceStorage.legacyVerifierKey,
        ),
        'verifier-b',
      );
      await afterRestart.removeItem(
        key: SecureSupabasePkceStorage.legacyVerifierKey,
      );
      expect(secureStore.values, isEmpty);
    },
  );

  test(
    'callback accepted before cancellation cannot remove its replacement',
    () async {
      final secureStore = _MemorySecureValueStore();
      final storage = SecureSupabasePkceStorage(
        secureStore: secureStore,
        keyPrefix: 'keepers.test.pkce',
      );

      await storage.beginAuthAttempt('attempt-a');
      await storage.setItem(
        key: SecureSupabasePkceStorage.legacyVerifierKey,
        value: 'verifier-a',
      );
      expect(storage.acceptCallbackAttempt('attempt-a'), isTrue);
      expect(await storage.cancelPendingVerifier(), isTrue);
      await storage.beginAuthAttempt('attempt-b');
      await storage.setItem(
        key: SecureSupabasePkceStorage.legacyVerifierKey,
        value: 'verifier-b',
      );

      expect(
        await storage.getItem(key: SecureSupabasePkceStorage.legacyVerifierKey),
        isNull,
      );
      expect(await storage.clearFailedVerifier(), isFalse);
      expect(storage.acceptCallbackAttempt('attempt-b'), isTrue);
      expect(
        storage.acceptCallbackAttempt('attempt-b'),
        isFalse,
        reason: 'one attempt may admit only one callback exchange',
      );
      expect(
        await storage.getItem(key: SecureSupabasePkceStorage.legacyVerifierKey),
        'verifier-b',
      );
    },
  );

  test('terminal delete failure leaves PKCE cleanup retryable', () async {
    final secureStore = _MemorySecureValueStore();
    final storage = SecureSupabasePkceStorage(
      secureStore: secureStore,
      keyPrefix: 'keepers.test.pkce',
    );
    await storage.beginAuthAttempt('attempt-a');
    await storage.setItem(
      key: SecureSupabasePkceStorage.legacyVerifierKey,
      value: 'verifier-a',
    );
    expect(storage.acceptCallbackAttempt('attempt-a'), isTrue);
    expect(
      await storage.getItem(key: SecureSupabasePkceStorage.legacyVerifierKey),
      'verifier-a',
    );
    secureStore.failNextDeleteKey =
        'keepers.test.pkce.${SecureSupabasePkceStorage.legacyVerifierKey}';

    await expectLater(
      storage.removeItem(key: SecureSupabasePkceStorage.legacyVerifierKey),
      throwsStateError,
    );

    expect(
      await storage.clearFailedVerifier(),
      isTrue,
      reason: 'a terminal cleanup failure must not leave checkout locked',
    );
    await storage.beginAuthAttempt('attempt-b');
    expect(
      secureStore.values,
      containsPair('keepers.test.pkce.auth-attempt', 'attempt-b'),
    );
  });
}

final class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = <String, String>{};
  String? failNextDeleteKey;

  @override
  Future<void> delete(String key) async {
    if (failNextDeleteKey == key) {
      failNextDeleteKey = null;
      throw StateError('secure delete unavailable');
    }
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

final class _MemoryLocalStorage extends LocalStorage {
  _MemoryLocalStorage(this.session, {this.failRemoval = false});

  String? session;
  final bool failRemoval;
  int initializeCalls = 0;

  @override
  Future<String?> accessToken() async => session;

  @override
  Future<bool> hasAccessToken() async => session != null;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    session = persistSessionString;
  }

  @override
  Future<void> removePersistedSession() async {
    if (failRemoval) {
      throw StateError('legacy storage unavailable');
    }
    session = null;
  }
}

final class _MemoryPkceStorage extends GotrueAsyncStorage {
  _MemoryPkceStorage(this.values, {this.failRemoval = false});

  final Map<String, String> values;
  final bool failRemoval;

  @override
  Future<String?> getItem({required String key}) async => values[key];

  @override
  Future<void> removeItem({required String key}) async {
    if (failRemoval) {
      throw StateError('legacy PKCE storage unavailable');
    }
    values.remove(key);
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }
}
