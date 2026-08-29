import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:keepers/features/family/data/cloud_config.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/secure_supabase_auth_storage.dart';
import 'package:keepers/features/family/data/supabase_cloud_family_gateway.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef SupabaseCloudClientInitializer = Future<SupabaseCloudClient> Function({
  required String url,
  required String publishableKey,
  required FlutterAuthClientOptions authOptions,
  required bool debug,
});

typedef LegacySessionStorageFactory = LocalStorage Function(
  String persistSessionKey,
);

typedef LegacyPkceStorageFactory = GotrueAsyncStorage Function();

/// Builds the optional cloud gateway without making cloud availability a
/// prerequisite for the local-first application.
///
/// The injectable boundary also keeps tests away from Supabase's process-wide
/// singleton while verifying the exact authentication storage passed to it.
Future<CloudFamilyGateway?> configuredCloudFamilyGateway({
  CloudConfig? config,
  SecureValueStore? secureValueStore,
  SupabaseCloudClientInitializer? initializeClient,
  LegacySessionStorageFactory? legacyStorageFactory,
  LegacyPkceStorageFactory? legacyPkceStorageFactory,
  String Function()? authAttemptIdFactory,
}) async {
  late final CloudConfig resolvedConfig;
  try {
    resolvedConfig = config ?? CloudConfig.fromEnvironment();
  } on FormatException {
    return null;
  }
  if (!resolvedConfig.isConfigured) return null;

  final url = resolvedConfig.url!;
  final legacyProjectReference = url.host.split('.').first;
  final originDigest = _originDigest(url);
  final legacySessionKey = 'sb-$legacyProjectReference-auth-token';
  final resolvedSecureValueStore =
      secureValueStore ?? FlutterSecureValueStore();
  final authStorage = SecureSupabaseAuthStorage(
    secureStore: resolvedSecureValueStore,
    secureSessionKey: 'keepers.supabase.auth-session.v1.$originDigest',
    legacyStorage: (legacyStorageFactory ?? _sharedPreferencesStorage)(
      legacySessionKey,
    ),
    legacyPkceStorage:
        (legacyPkceStorageFactory ?? _sharedPreferencesPkceStorage)(),
  );
  final pkceStorage = SecureSupabasePkceStorage(
    secureStore: resolvedSecureValueStore,
    keyPrefix: 'keepers.supabase.pkce.v1.$originDigest',
  );

  try {
    await pkceStorage.initialize();
    final client = await (initializeClient ?? _initializeSupabaseClient)(
      url: url.toString(),
      publishableKey: resolvedConfig.publishableKey!,
      authOptions: FlutterAuthClientOptions(
        localStorage: authStorage,
        pkceAsyncStorage: pkceStorage,
        detectSessionInUri: true,
        detectSessionInUriPredicate: (uri) =>
            _isKeepersAuthCallback(uri, pkceStorage),
        persistSession: true,
      ),
      debug: false,
    );
    return SupabaseCloudFamilyGateway(
      client,
      emailRedirectTo: _authBridgeRedirectUrl(url),
      authAttemptIdFactory: authAttemptIdFactory,
    );
  } on Object {
    return null;
  }
}

bool _isKeepersAuthCallback(Uri uri, SecureSupabasePkceStorage pkceStorage) {
  if (uri.scheme != 'keepers' ||
      uri.host != 'auth-callback' ||
      uri.authority != 'auth-callback' ||
      uri.path.isNotEmpty ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return false;
  }

  final parameters = uri.queryParametersAll;
  final attempts = parameters[supabaseAuthAttemptParameter];
  String? attemptId;
  if (attempts != null) {
    if (attempts.length != 1 || !_isValidAuthAttempt(attempts.single)) {
      return false;
    }
    attemptId = attempts.single;
  }
  final authParameters = Map<String, List<String>>.from(parameters)
    ..remove(supabaseAuthAttemptParameter);
  final codes = authParameters['code'];
  if (codes != null) {
    return authParameters.length == 1 &&
        _hasOneBoundedValue(codes) &&
        pkceStorage.acceptCallbackAttempt(attemptId);
  }

  const errorKeys = {'error', 'error_code', 'error_description'};
  if (authParameters.isEmpty ||
      authParameters.keys.any((key) => !errorKeys.contains(key)) ||
      !authParameters.values.every(_hasOneBoundedValue)) {
    return false;
  }
  return pkceStorage.acceptCallbackAttempt(attemptId);
}

bool _isValidAuthAttempt(String value) =>
    value.isNotEmpty &&
    value.length <= 128 &&
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

bool _hasOneBoundedValue(List<String> values) =>
    values.length == 1 &&
    values.single.isNotEmpty &&
    values.single.length <= 2048;

String _originDigest(Uri url) =>
    base64UrlEncode(const DartSha256().hashSync(utf8.encode(url.origin)).bytes)
        .replaceAll('=', '');

String _authBridgeRedirectUrl(Uri supabaseOrigin) => supabaseOrigin
    .replace(pathSegments: const ['functions', 'v1', 'keepers-auth-bridge'])
    .toString();

LocalStorage _sharedPreferencesStorage(String persistSessionKey) =>
    SharedPreferencesLocalStorage(persistSessionKey: persistSessionKey);

GotrueAsyncStorage _sharedPreferencesPkceStorage() =>
    SharedPreferencesGotrueAsyncStorage();

Future<SupabaseCloudClient> _initializeSupabaseClient({
  required String url,
  required String publishableKey,
  required FlutterAuthClientOptions authOptions,
  required bool debug,
}) async {
  final previous = _initializedSupabaseOrNull();
  if (previous != null) await previous.dispose();
  try {
    final supabase = await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      authOptions: authOptions,
      debug: debug,
    );
    final pkceStorage = authOptions.pkceAsyncStorage;
    if (pkceStorage is! SecureSupabasePkceStorage) {
      throw StateError('Keepers requires secure PKCE storage.');
    }
    return SupabaseCloudClientAdapter(supabase.client, pkceStorage);
  } on Object {
    final partial = _initializedSupabaseOrNull();
    if (partial != null) {
      try {
        await partial.dispose();
      } on Object {
        // A later retry attempts disposal again before reinitializing.
      }
    }
    rethrow;
  }
}

Supabase? _initializedSupabaseOrNull() {
  try {
    final supabase = Supabase.instance;
    return supabase.isInitialized ? supabase : null;
  } on AssertionError {
    return null;
  }
}
