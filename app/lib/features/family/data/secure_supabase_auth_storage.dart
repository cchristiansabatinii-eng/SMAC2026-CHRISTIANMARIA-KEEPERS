import 'package:keepers/storage/database_key_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists Supabase's opaque session payload in the app's platform-backed
/// secure value store.
///
/// A previous build used Supabase's default SharedPreferences storage. When
/// supplied, [legacyStorage] is cleared before Supabase restores any session.
/// The legacy value is deliberately not read or migrated, forcing one safe
/// reauthentication instead of moving an untrusted preference into protected
/// storage.
final class SecureSupabaseAuthStorage extends LocalStorage {
  factory SecureSupabaseAuthStorage({
    required SecureValueStore secureStore,
    required String secureSessionKey,
    LocalStorage? legacyStorage,
    GotrueAsyncStorage? legacyPkceStorage,
  }) => SecureSupabaseAuthStorage._(
    secureStore,
    secureSessionKey,
    legacyStorage,
    legacyPkceStorage,
  );

  SecureSupabaseAuthStorage._(
    this._secureStore,
    this._secureSessionKey,
    this._legacyStorage,
    this._legacyPkceStorage,
  );

  final SecureValueStore _secureStore;
  final String _secureSessionKey;
  final LocalStorage? _legacyStorage;
  final GotrueAsyncStorage? _legacyPkceStorage;

  @override
  Future<void> initialize() async {
    final legacyStorage = _legacyStorage;
    if (legacyStorage != null) {
      await legacyStorage.initialize();
      await legacyStorage.removePersistedSession();
    }
    await _legacyPkceStorage?.removeItem(
      key: SecureSupabasePkceStorage.legacyVerifierKey,
    );
  }

  @override
  Future<bool> hasAccessToken() async =>
      await _secureStore.read(_secureSessionKey) != null;

  @override
  Future<String?> accessToken() => _secureStore.read(_secureSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _secureStore.write(_secureSessionKey, persistSessionString);

  @override
  Future<void> removePersistedSession() =>
      _secureStore.delete(_secureSessionKey);
}

/// Keeps GoTrue's short-lived PKCE verifier out of SharedPreferences too.
final class SecureSupabasePkceStorage extends GotrueAsyncStorage {
  /// The exact verifier key used by the pinned GoTrue 2.27.2 client.
  static const String legacyVerifierKey = 'supabase.auth.token-code-verifier';

  factory SecureSupabasePkceStorage({
    required SecureValueStore secureStore,
    required String keyPrefix,
  }) => SecureSupabasePkceStorage._(secureStore, keyPrefix);

  const SecureSupabasePkceStorage._(this._secureStore, this._keyPrefix);

  final SecureValueStore _secureStore;
  final String _keyPrefix;

  String _key(String key) => '$_keyPrefix.$key';

  @override
  Future<String?> getItem({required String key}) =>
      _secureStore.read(_key(key));

  @override
  Future<void> setItem({required String key, required String value}) =>
      _secureStore.write(_key(key), value);

  @override
  Future<void> removeItem({required String key}) =>
      _secureStore.delete(_key(key));
}
