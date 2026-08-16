import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/cloud_config.dart';
import 'package:keepers/features/family/data/secure_supabase_auth_storage.dart';
import 'package:keepers/features/family/data/supabase_cloud_family_gateway.dart';
import 'package:keepers/features/family/data/supabase_cloud_gateway_bootstrap.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'configured bootstrap initializes Supabase with secure auth storage',
    () async {
      final secureStore = _MemorySecureValueStore();
      final legacyStorage = _MemoryLocalStorage('legacy-session-json');
      final legacyPkceStorage = _MemoryPkceStorage(<String, String>{
        SecureSupabasePkceStorage.legacyVerifierKey: 'legacy-verifier',
      });
      FlutterAuthClientOptions? capturedAuthOptions;
      String? capturedUrl;
      String? capturedKey;
      bool? capturedDebug;
      String? capturedLegacyKey;

      final gateway = await configuredCloudFamilyGateway(
        config: CloudConfig.parse(
          url: 'https://family-project.supabase.co',
          publishableKey: 'sb_publishable_example',
        ),
        secureValueStore: secureStore,
        legacyStorageFactory: (persistSessionKey) {
          capturedLegacyKey = persistSessionKey;
          return legacyStorage;
        },
        legacyPkceStorageFactory: () => legacyPkceStorage,
        initializeClient:
            ({
              required String url,
              required String publishableKey,
              required FlutterAuthClientOptions authOptions,
              required bool debug,
            }) async {
              capturedUrl = url;
              capturedKey = publishableKey;
              capturedDebug = debug;
              capturedAuthOptions = authOptions;
              await authOptions.localStorage!.initialize();
              return _FakeSupabaseCloudClient();
            },
      );

      expect(gateway, isA<SupabaseCloudFamilyGateway>());
      expect(capturedUrl, 'https://family-project.supabase.co');
      expect(capturedKey, 'sb_publishable_example');
      expect(capturedDebug, isFalse);
      expect(capturedLegacyKey, 'sb-family-project-auth-token');
      expect(
        capturedAuthOptions?.localStorage,
        isA<SecureSupabaseAuthStorage>(),
      );
      expect(capturedAuthOptions?.persistSession, isTrue);
      expect(capturedAuthOptions?.detectSessionInUri, isFalse);
      expect(
        capturedAuthOptions?.pkceAsyncStorage,
        isA<SecureSupabasePkceStorage>(),
      );
      expect(legacyStorage.session, isNull);
      expect(legacyPkceStorage.values, isEmpty);

      await capturedAuthOptions!.localStorage!.persistSession(
        'new-secure-session-json',
      );
      await capturedAuthOptions!.pkceAsyncStorage!.setItem(
        key: 'supabase.auth.token-code-verifier',
        value: 'new-secure-verifier',
      );
      expect(secureStore.values, <String, String>{
        'keepers.supabase.auth-session.v1.'
                'R0q2KB67O8wczyhj8vJlL545KxiO4CAhAiRs3SRdXYQ':
            'new-secure-session-json',
        'keepers.supabase.pkce.v1.'
                'R0q2KB67O8wczyhj8vJlL545KxiO4CAhAiRs3SRdXYQ.'
                'supabase.auth.token-code-verifier':
            'new-secure-verifier',
      });
    },
  );

  test(
    'unconfigured bootstrap does not initialize storage or Supabase',
    () async {
      var initializerCalled = false;
      var legacyFactoryCalled = false;

      final gateway = await configuredCloudFamilyGateway(
        config: const CloudConfig.unconfigured(),
        secureValueStore: _MemorySecureValueStore(),
        legacyStorageFactory: (_) {
          legacyFactoryCalled = true;
          return _MemoryLocalStorage(null);
        },
        initializeClient:
            ({
              required String url,
              required String publishableKey,
              required FlutterAuthClientOptions authOptions,
              required bool debug,
            }) async {
              initializerCalled = true;
              return _FakeSupabaseCloudClient();
            },
      );

      expect(gateway, isNull);
      expect(initializerCalled, isFalse);
      expect(legacyFactoryCalled, isFalse);
    },
  );

  test('secure auth namespaces digest the complete canonical origin', () async {
    final secureStore = _MemorySecureValueStore();
    final legacySessionKeys = <String>[];
    final capturedAuthOptions = <FlutterAuthClientOptions>[];

    Future<void> initialize(String origin) async {
      final gateway = await configuredCloudFamilyGateway(
        config: CloudConfig.parse(
          url: origin,
          publishableKey: 'sb_publishable_example',
        ),
        secureValueStore: secureStore,
        legacyStorageFactory: (persistSessionKey) {
          legacySessionKeys.add(persistSessionKey);
          return _MemoryLocalStorage(null);
        },
        legacyPkceStorageFactory: () => _MemoryPkceStorage(<String, String>{}),
        initializeClient:
            ({
              required String url,
              required String publishableKey,
              required FlutterAuthClientOptions authOptions,
              required bool debug,
            }) async {
              await authOptions.localStorage!.initialize();
              capturedAuthOptions.add(authOptions);
              return _FakeSupabaseCloudClient();
            },
      );
      expect(gateway, isA<SupabaseCloudFamilyGateway>());
    }

    await initialize('https://api.prod.example/');
    await initialize('https://api.stage.example');

    await capturedAuthOptions[0].localStorage!.persistSession('prod-session');
    await capturedAuthOptions[0].pkceAsyncStorage!.setItem(
      key: SecureSupabasePkceStorage.legacyVerifierKey,
      value: 'prod-verifier',
    );
    await capturedAuthOptions[1].localStorage!.persistSession('stage-session');
    await capturedAuthOptions[1].pkceAsyncStorage!.setItem(
      key: SecureSupabasePkceStorage.legacyVerifierKey,
      value: 'stage-verifier',
    );

    expect(legacySessionKeys, const ['sb-api-auth-token', 'sb-api-auth-token']);
    expect(secureStore.values, <String, String>{
      'keepers.supabase.auth-session.v1.'
              'cvXeIbVQP8AsBSQMMPpZ3XTVldBdVQb0r3LS9dP4lTQ':
          'prod-session',
      'keepers.supabase.pkce.v1.'
              'cvXeIbVQP8AsBSQMMPpZ3XTVldBdVQb0r3LS9dP4lTQ.'
              'supabase.auth.token-code-verifier':
          'prod-verifier',
      'keepers.supabase.auth-session.v1.'
              'LSwHEfXyYgqKUeSvVcCcHo9lFHuyVFkyhyh3JaQCne8':
          'stage-session',
      'keepers.supabase.pkce.v1.'
              'LSwHEfXyYgqKUeSvVcCcHo9lFHuyVFkyhyh3JaQCne8.'
              'supabase.auth.token-code-verifier':
          'stage-verifier',
    });
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
  _MemoryLocalStorage(this.session);

  String? session;

  @override
  Future<String?> accessToken() async => session;

  @override
  Future<bool> hasAccessToken() async => session != null;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> persistSession(String persistSessionString) async {
    session = persistSessionString;
  }

  @override
  Future<void> removePersistedSession() async {
    session = null;
  }
}

final class _MemoryPkceStorage extends GotrueAsyncStorage {
  _MemoryPkceStorage(this.values);

  final Map<String, String> values;

  @override
  Future<String?> getItem({required String key}) async => values[key];

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }
}

final class _FakeSupabaseCloudClient implements SupabaseCloudClient {
  @override
  String? get authenticatedAccountId => null;

  @override
  String? get authenticatedEmail => null;

  @override
  Future<void> requestEmailOtp(String email) async {}

  @override
  Future<Object?> rpc(
    String function, {
    required Map<String, Object?> params,
  }) async => null;

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {}
}
