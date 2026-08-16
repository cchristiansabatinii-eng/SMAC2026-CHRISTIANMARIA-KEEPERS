import 'dart:convert';

final class FamilyCode {
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  const FamilyCode._(this.normalized);

  final String normalized;

  static FamilyCode parse(String input) {
    final normalized = input.toUpperCase().replaceAll(RegExp(r'[ -]'), '');
    if (normalized.length != 8 ||
        normalized.codeUnits.any(
          (unit) => !alphabet.codeUnits.contains(unit),
        )) {
      throw const FormatException('Invalid family code');
    }
    return FamilyCode._(normalized);
  }

  String get display =>
      '${normalized.substring(0, 4)}-${normalized.substring(4)}';

  Uri get joinUri => Uri.https('join.keepers.app', '/f/$display');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyCode && other.normalized == normalized;

  @override
  int get hashCode => normalized.hashCode;

  @override
  String toString() => 'FamilyCode(<redacted>)';
}

final class FamilyJoinLink {
  const FamilyJoinLink._(this.code);

  final FamilyCode code;

  static FamilyJoinLink parse(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host != 'join.keepers.app' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first != 'f') {
      throw const FormatException('Invalid family join link');
    }
    return FamilyJoinLink._(FamilyCode.parse(uri.pathSegments.last));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FamilyJoinLink && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'FamilyJoinLink(<redacted>)';
}

final class EncryptedFamilyCodeMaterial {
  static const currentCodecVersion = 1;

  const EncryptedFamilyCodeMaterial({
    required this.codecVersion,
    required this.familyId,
    required this.codeVersion,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  final int codecVersion;
  final String familyId;
  final int codeVersion;
  final String nonce;
  final String ciphertext;
  final String mac;

  factory EncryptedFamilyCodeMaterial.fromJson(Map<String, Object?> json) {
    const fields = {
      'codecVersion',
      'familyId',
      'codeVersion',
      'nonce',
      'ciphertext',
      'mac',
    };
    if (json.length != fields.length || !fields.every(json.containsKey)) {
      throw const FormatException('Invalid family code material fields');
    }
    final codecVersion = json['codecVersion'];
    final familyId = json['familyId'];
    final codeVersion = json['codeVersion'];
    final nonce = json['nonce'];
    final ciphertext = json['ciphertext'];
    final mac = json['mac'];
    if (codecVersion is! int ||
        familyId is! String ||
        codeVersion is! int ||
        nonce is! String ||
        ciphertext is! String ||
        mac is! String ||
        codecVersion != currentCodecVersion ||
        codeVersion <= 0 ||
        !_isCanonicalUuid(familyId)) {
      throw const FormatException('Invalid family code material values');
    }
    _decodeCanonicalBase64Url(nonce, expectedLength: 12, field: 'nonce');
    _decodeCanonicalBase64Url(
      ciphertext,
      expectedLength: 8,
      field: 'ciphertext',
    );
    _decodeCanonicalBase64Url(mac, expectedLength: 16, field: 'mac');
    return EncryptedFamilyCodeMaterial(
      codecVersion: codecVersion,
      familyId: familyId,
      codeVersion: codeVersion,
      nonce: nonce,
      ciphertext: ciphertext,
      mac: mac,
    );
  }

  Map<String, Object> toJson() => {
    'codecVersion': codecVersion,
    'familyId': familyId,
    'codeVersion': codeVersion,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'mac': mac,
  };

  EncryptedFamilyCodeMaterial copyWith({
    int? codecVersion,
    String? familyId,
    int? codeVersion,
    String? nonce,
    String? ciphertext,
    String? mac,
  }) => EncryptedFamilyCodeMaterial(
    codecVersion: codecVersion ?? this.codecVersion,
    familyId: familyId ?? this.familyId,
    codeVersion: codeVersion ?? this.codeVersion,
    nonce: nonce ?? this.nonce,
    ciphertext: ciphertext ?? this.ciphertext,
    mac: mac ?? this.mac,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EncryptedFamilyCodeMaterial &&
          other.codecVersion == codecVersion &&
          other.familyId == familyId &&
          other.codeVersion == codeVersion &&
          other.nonce == nonce &&
          other.ciphertext == ciphertext &&
          other.mac == mac;

  @override
  int get hashCode =>
      Object.hash(codecVersion, familyId, codeVersion, nonce, ciphertext, mac);

  @override
  String toString() => 'EncryptedFamilyCodeMaterial(<redacted>)';
}

final class EncryptedFamilyCodeRecord {
  const EncryptedFamilyCodeRecord({
    required this.material,
    required this.creatorAccountId,
    required this.createdAt,
    required this.updatedAt,
  });

  final EncryptedFamilyCodeMaterial material;
  final String creatorAccountId;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  String toString() => 'EncryptedFamilyCodeRecord(<redacted>)';
}

final class FamilyCodeDraft {
  const FamilyCodeDraft({
    required this.code,
    required this.lookupHash,
    required this.material,
  });

  final FamilyCode code;
  final String lookupHash;
  final EncryptedFamilyCodeMaterial material;

  @override
  String toString() => 'FamilyCodeDraft(<redacted>)';
}

bool _isCanonicalUuid(String value) =>
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(value);

List<int> _decodeCanonicalBase64Url(
  String value, {
  required int expectedLength,
  required String field,
}) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value) || value.length % 4 == 1) {
    throw FormatException('Invalid family code $field');
  }
  try {
    final decoded = base64Url.decode(base64Url.normalize(value));
    if (decoded.length != expectedLength ||
        _unpaddedBase64Url(decoded) != value) {
      throw FormatException('Invalid family code $field');
    }
    return decoded;
  } on FormatException {
    rethrow;
  } on Object catch (error) {
    throw FormatException('Invalid family code $field', error);
  }
}

String _unpaddedBase64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');
