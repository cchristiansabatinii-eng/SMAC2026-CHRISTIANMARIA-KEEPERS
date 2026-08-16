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
    final client = await (initializeClient ?? _initializeSupabaseClient)(
      url: url.toString(),
      publishableKey: resolvedConfig.publishableKey!,
      authOptions: FlutterAuthClientOptions(
        localStorage: authStorage,
        pkceAsyncStorage: pkceStorage,
        detectSessionInUri: false,
        persistSession: true,
      ),
      debug: false,
    );
    return SupabaseCloudFamilyGateway(client);
  } on Object {
    return null;
  }
}

String _originDigest(Uri url) =>
    base64UrlEncode(const DartSha256().hashSync(utf8.encode(url.origin)).bytes)
        .replaceAll('=', '');

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
  final supabase = await Supabase.initialize(
    url: url,
    publishableKey: publishableKey,
    authOptions: authOptions,
    debug: debug,
  );
  return SupabaseCloudClientAdapter(supabase.client);
}
