import 'dart:convert';

final class CloudConfig {
  const CloudConfig._({this.url, this.publishableKey});

  const CloudConfig.unconfigured() : this._();

  static const urlDefine = 'KEEPERS_SUPABASE_URL';
  static const publishableKeyDefine = 'KEEPERS_SUPABASE_PUBLISHABLE_KEY';

  final Uri? url;
  final String? publishableKey;

  bool get isConfigured => url != null && publishableKey != null;

  factory CloudConfig.parse({
    required String url,
    required String publishableKey,
  }) {
    final normalizedUrl = url.trim();
    final normalizedKey = publishableKey.trim();
    if (normalizedUrl.isEmpty && normalizedKey.isEmpty) {
      return const CloudConfig.unconfigured();
    }
    if (normalizedUrl.isEmpty || normalizedKey.isEmpty) {
      throw const FormatException(
        'Supabase URL and publishable key must be configured together',
      );
    }
    if (!_isSupportedPublishableCredential(normalizedKey)) {
      throw const FormatException('Supabase publishable key is invalid');
    }

    final parsed = Uri.tryParse(normalizedUrl);
    if (parsed == null ||
        parsed.scheme != 'https' ||
        !parsed.hasAuthority ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        (parsed.path.isNotEmpty && parsed.path != '/')) {
      throw const FormatException('Supabase URL must be a plain HTTPS origin');
    }

    final canonicalUrl = parsed.path == '/' ? parsed.replace(path: '') : parsed;
    return CloudConfig._(url: canonicalUrl, publishableKey: normalizedKey);
  }

  static CloudConfig fromEnvironment() => CloudConfig.parse(
    url: const String.fromEnvironment(urlDefine),
    publishableKey: const String.fromEnvironment(publishableKeyDefine),
  );

  @override
  String toString() =>
      isConfigured ? 'CloudConfig(configured)' : 'CloudConfig(unconfigured)';
}

bool _isSupportedPublishableCredential(String value) {
  if (RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(value)) {
    return true;
  }

  final segments = value.split('.');
  if (segments.length != 3 || segments.any((segment) => segment.isEmpty)) {
    return false;
  }
  final headerBytes = _decodeCanonicalBase64Url(segments[0]);
  final payloadBytes = _decodeCanonicalBase64Url(segments[1]);
  final signatureBytes = _decodeCanonicalBase64Url(segments[2]);
  if (headerBytes == null ||
      payloadBytes == null ||
      signatureBytes == null ||
      signatureBytes.length != 32) {
    return false;
  }
  try {
    final header = jsonDecode(utf8.decode(headerBytes));
    final payload = jsonDecode(utf8.decode(payloadBytes));
    return header is Map &&
        header['alg'] == 'HS256' &&
        header['typ'] == 'JWT' &&
        payload is Map &&
        payload['iss'] == 'supabase' &&
        payload['role'] == 'anon';
  } on FormatException {
    return false;
  }
}

List<int>? _decodeCanonicalBase64Url(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value) || value.length % 4 == 1) {
    return null;
  }
  try {
    final decoded = base64Url.decode(base64Url.normalize(value));
    return base64UrlEncode(decoded).replaceAll('=', '') == value
        ? decoded
        : null;
  } on FormatException {
    return null;
  }
}
