import 'dart:async';

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

  /// The opaque app-owned marker paired with the current PKCE verifier.
  static const String authAttemptKey = 'auth-attempt';

  factory SecureSupabasePkceStorage({
    required SecureValueStore secureStore,
    required String keyPrefix,
  }) => SecureSupabasePkceStorage._(secureStore, keyPrefix);

  SecureSupabasePkceStorage._(this._secureStore, this._keyPrefix);

  final SecureValueStore _secureStore;
  final String _keyPrefix;
  Future<void> _operationTail = Future<void>.value();
  String? _activeAttempt;
  String? _callbackAttempt;
  bool _attemptLoaded = false;
  bool _callbackDetected = false;
  bool _verifierCheckedOut = false;

  String _key(String key) => '$_keyPrefix.$key';

  /// Restores the active marker before Supabase inspects an incoming deep link.
  Future<void> initialize() => _serialized(_loadActiveAttempt);

  /// Reserves the verifier slot for one newly generated authentication flow.
  Future<void> beginAuthAttempt(String attemptId) {
    if (!_isValidAuthAttempt(attemptId)) {
      throw ArgumentError.value(attemptId, 'attemptId');
    }
    return _serialized(() async {
      if (_verifierCheckedOut) {
        throw StateError('A PKCE callback exchange is already in progress.');
      }
      await _secureStore.delete(_key(legacyVerifierKey));
      await _secureStore.write(_key(authAttemptKey), attemptId);
      _activeAttempt = attemptId;
      _attemptLoaded = true;
      _verifierCheckedOut = false;
      _resetCallback();
    });
  }

  /// Records a structurally valid callback only when it belongs to the active
  /// flow. A missing marker is accepted solely for a legacy unmarked flow.
  bool acceptCallbackAttempt(String? attemptId) {
    if (attemptId != null && !_isValidAuthAttempt(attemptId)) return false;
    if (_callbackDetected) return false;
    final activeAttempt = _activeAttempt;
    final matches = activeAttempt == null
        ? attemptId == null
        : attemptId == activeAttempt;
    if (!matches) return false;
    _callbackDetected = true;
    _callbackAttempt = attemptId;
    return true;
  }

  @override
  Future<String?> getItem({required String key}) => _serialized(() async {
    if (key != legacyVerifierKey) {
      return _secureStore.read(_key(key));
    }
    await _loadActiveAttempt();
    if (!_callbackMatchesActiveAttempt()) return null;
    final value = await _secureStore.read(_key(key));
    if (value != null) _verifierCheckedOut = true;
    return value;
  });

  @override
  Future<void> setItem({required String key, required String value}) =>
      _serialized(() async {
        await _secureStore.write(_key(key), value);
        if (key == legacyVerifierKey) {
          _verifierCheckedOut = false;
          _resetCallback();
        }
      });

  @override
  Future<void> removeItem({required String key}) => _serialized(() async {
    if (key != legacyVerifierKey) {
      await _secureStore.delete(_key(key));
      return;
    }
    await _loadActiveAttempt();
    if (_callbackDetected && !_callbackMatchesActiveAttempt()) {
      _resetCallback();
      return;
    }
    await _deleteVerifierAndAttempt(terminal: true);
  });

  /// Cancels a browser flow only while its verifier is still waiting to be
  /// consumed. Once GoTrue has read the verifier, that callback exchange owns
  /// the flow and must remain the sole in-flight authentication attempt.
  Future<bool> cancelPendingVerifier() => _serialized(() async {
    if (_verifierCheckedOut) return false;
    await _deleteVerifierAndAttempt();
    return true;
  });

  /// Releases a verifier after GoTrue has reported that its callback exchange
  /// terminated with an error. A rejected or unrelated callback returns false
  /// and leaves the active verifier intact.
  Future<bool> clearFailedVerifier() => _serialized(() async {
    await _loadActiveAttempt();
    if (!_callbackMatchesActiveAttempt()) {
      _resetCallback();
      return false;
    }
    await _deleteVerifierAndAttempt(terminal: true);
    return true;
  });

  Future<void> _loadActiveAttempt() async {
    if (_attemptLoaded) return;
    final persisted = await _secureStore.read(_key(authAttemptKey));
    if (persisted != null && !_isValidAuthAttempt(persisted)) {
      await _secureStore.delete(_key(legacyVerifierKey));
      await _secureStore.delete(_key(authAttemptKey));
      _activeAttempt = null;
    } else {
      _activeAttempt = persisted;
    }
    _attemptLoaded = true;
  }

  bool _callbackMatchesActiveAttempt() {
    if (!_callbackDetected) return false;
    final activeAttempt = _activeAttempt;
    return activeAttempt == null
        ? _callbackAttempt == null
        : _callbackAttempt == activeAttempt;
  }

  Future<void> _deleteVerifierAndAttempt({bool terminal = false}) async {
    try {
      await _secureStore.delete(_key(legacyVerifierKey));
      await _secureStore.delete(_key(authAttemptKey));
    } on Object {
      if (terminal) {
        // GoTrue calls terminal cleanup only after an exchange has succeeded,
        // or the auth stream has reported failure. Let a retry reclaim the
        // slot even when secure deletion was transiently unavailable.
        _verifierCheckedOut = false;
      }
      rethrow;
    }
    _activeAttempt = null;
    _attemptLoaded = true;
    _verifierCheckedOut = false;
    _resetCallback();
  }

  void _resetCallback() {
    _callbackDetected = false;
    _callbackAttempt = null;
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final previous = _operationTail;
    final released = Completer<void>();
    _operationTail = released.future;
    return (() async {
      await previous;
      try {
        return await operation();
      } finally {
        released.complete();
      }
    })();
  }
}

bool _isValidAuthAttempt(String value) =>
    value.isNotEmpty &&
    value.length <= 128 &&
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
