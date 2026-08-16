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
}

final class _MemorySecureValueStore implements SecureValueStore {
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
