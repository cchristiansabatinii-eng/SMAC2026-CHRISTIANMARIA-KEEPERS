import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/cloud_config.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/secure_supabase_auth_storage.dart';
import 'package:keepers/features/family/data/supabase_cloud_family_gateway.dart';
import 'package:keepers/features/family/data/supabase_cloud_gateway_bootstrap.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      final cloudClient = _FakeSupabaseCloudClient();

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
        authAttemptIdFactory: () => 'bootstrap-attempt',
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
              cloudClient.pkceStorage =
                  authOptions.pkceAsyncStorage! as SecureSupabasePkceStorage;
              await authOptions.localStorage!.initialize();
              return cloudClient;
            },
      );

      expect(gateway, isA<SupabaseCloudFamilyGateway>());
      await gateway!.requestEmailOtp('person@example.com');
      expect(cloudClient.requestedRedirects, const [
        'https://family-project.supabase.co/functions/v1/'
            'keepers-auth-bridge?attempt=bootstrap-attempt',
      ]);
      expect(cloudClient.startedAuthAttempts, const ['bootstrap-attempt']);
      expect(capturedUrl, 'https://family-project.supabase.co');
      expect(capturedKey, 'sb_publishable_example');
      expect(capturedDebug, isFalse);
      expect(capturedLegacyKey, 'sb-family-project-auth-token');
      expect(
        capturedAuthOptions?.localStorage,
        isA<SecureSupabaseAuthStorage>(),
      );
      expect(capturedAuthOptions?.persistSession, isTrue);
      expect(capturedAuthOptions?.detectSessionInUri, isTrue);
      final callbackPredicate =
          capturedAuthOptions?.detectSessionInUriPredicate;
      expect(callbackPredicate, isNotNull);
      expect(
        callbackPredicate!(
          Uri.parse(
            'keepers://auth-callback?code=authorization-code'
            '&attempt=bootstrap-attempt',
          ),
        ),
        isTrue,
      );
      expect(
        callbackPredicate(
          Uri.parse(
            'keepers://auth-callback?code=replayed-code'
            '&attempt=bootstrap-attempt',
          ),
        ),
        isFalse,
        reason: 'one auth attempt must admit only one callback exchange',
      );
      final pkceStorage =
          capturedAuthOptions!.pkceAsyncStorage! as SecureSupabasePkceStorage;
      expect(await pkceStorage.cancelPendingVerifier(), isTrue);
      await pkceStorage.beginAuthAttempt('bootstrap-attempt');
      expect(
        callbackPredicate(
          Uri.parse(
            'keepers://auth-callback?error=access_denied'
            '&error_code=oauth_access_denied'
            '&error_description=The+user+cancelled'
            '&attempt=bootstrap-attempt',
          ),
        ),
        isTrue,
      );
      expect(
        callbackPredicate(
          Uri.parse(
            'keepers://auth-callback?code=stale-code&attempt=stale-attempt',
          ),
        ),
        isFalse,
      );
      expect(
        callbackPredicate(
          Uri.parse('keepers://auth-callback?code=unmarked-code'),
        ),
        isFalse,
      );
      expect(
        callbackPredicate(
          Uri.parse('keepers://join?code=invitation-capability'),
        ),
        isFalse,
      );
      expect(
        callbackPredicate(
          Uri.parse('keepers://auth-callback/other?code=authorization-code'),
        ),
        isFalse,
      );
      for (final rejectedCallback in <String>[
        'keepers://auth-callback'
            '#access_token=attacker-session&refresh_token=attacker-refresh',
        'keepers://auth-callback?access_token=attacker-session',
        'keepers://auth-callback?code=authorization-code'
            '&access_token=attacker-session',
        'keepers://auth-callback?code=authorization-code'
            '&error=access_denied',
        'keepers://auth-callback?code=authorization-code'
            '&attempt=first&attempt=second',
        'keepers://auth-callback?code=authorization-code&attempt=',
        'keepers://auth-callback?code=authorization-code&attempt=bad%20value',
        'keepers://auth-callback?error=access_denied&unexpected=value',
        'keepers://auth-callback?error=first&error=second',
        'keepers://auth-callback?error=',
        'keepers://auth-callback?code=first-code&code=second-code',
        'keepers://auth-callback?code=',
        'keepers://auth-callback?code=authorization-code#unexpected',
        'keepers://auth-callback?code=authorization-code#',
        'keepers://user@auth-callback?code=authorization-code',
        'keepers://auth-callback:443?code=authorization-code',
      ]) {
        expect(
          callbackPredicate(Uri.parse(rejectedCallback)),
          isFalse,
          reason: 'Rejected unsafe auth callback: $rejectedCallback',
        );
      }
      expect(
        callbackPredicate(
          Uri(
            scheme: 'keepers',
            host: 'auth-callback',
            queryParameters: {'code': List<String>.filled(2049, 'a').join()},
          ),
        ),
        isFalse,
        reason: 'Authorization codes larger than the callback limit are unsafe',
      );
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
        'keepers.supabase.pkce.v1.'
                'R0q2KB67O8wczyhj8vJlL545KxiO4CAhAiRs3SRdXYQ.'
                'auth-attempt':
            'bootstrap-attempt',
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

  test(
    'a partial production initialization is disposed before retry',
    () async {
      if (_isSupabaseInitialized()) {
        await Supabase.instance.dispose();
      }
      addTearDown(() async {
        if (_isSupabaseInitialized()) {
          await Supabase.instance.dispose();
        }
      });
      final config = CloudConfig.parse(
        url: 'https://retry-project.supabase.co',
        publishableKey: _testAnonKey,
      );

      final failed = await configuredCloudFamilyGateway(
        config: config,
        secureValueStore: _MemorySecureValueStore(),
        legacyStorageFactory: (_) =>
            _MemoryLocalStorage(null, failRemoval: true),
        legacyPkceStorageFactory: () => _MemoryPkceStorage(<String, String>{}),
      );

      expect(failed, isNull);
      expect(
        _isSupabaseInitialized(),
        isFalse,
        reason: 'Retry must not inherit a client bound to stale auth storage',
      );

      final retried = await configuredCloudFamilyGateway(
        config: config,
        secureValueStore: _MemorySecureValueStore(),
        legacyStorageFactory: (_) => _MemoryLocalStorage(null),
        legacyPkceStorageFactory: () => _MemoryPkceStorage(<String, String>{}),
        authAttemptIdFactory: () => 'retry-attempt',
      );

      expect(retried, isA<SupabaseCloudFamilyGateway>());
      expect(_isSupabaseInitialized(), isTrue);
      expect(
        await (retried! as CloudFamilySocialAuth).cancelPendingProviderSignIn(),
        isTrue,
      );
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

bool _isSupabaseInitialized() {
  try {
    return Supabase.instance.isInitialized;
  } on AssertionError {
    return false;
  }
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
    if (failRemoval) throw StateError('legacy session removal failed');
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

final class _FakeSupabaseCloudClient
    implements SupabaseCloudClient, SupabaseCloudAuthAttemptClient {
  final requestedRedirects = <String>[];
  final startedAuthAttempts = <String>[];
  SecureSupabasePkceStorage? pkceStorage;

  @override
  Future<void> beginAuthAttempt(String attemptId) async {
    startedAuthAttempts.add(attemptId);
    await pkceStorage?.beginAuthAttempt(attemptId);
  }

  @override
  Future<bool> retirePendingAuthAttempt() async =>
      await pkceStorage?.cancelPendingVerifier() ?? true;

  @override
  String? get authenticatedAccountId => null;

  @override
  String? get authenticatedEmail => null;

  @override
  Future<void> requestEmailOtp(
    String email, {
    required String emailRedirectTo,
  }) async {
    requestedRedirects.add(emailRedirectTo);
  }

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

const _testAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
    'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53emxkenlsb2pyemdqemloZHJrIiwicm9sZSI6ImFub24iLCJpYXQiOjE2ODQxMzI2ODAsImV4cCI6MTk5OTcwODY4MH0.'
    'MU-LVeAPic93VLcRsHktxzYtBKBUMWAQb8E-0AQETPs';
