import 'dart:convert';

enum InvitationFailureCode {
  notConfigured,
  signedOut,
  invalidEmail,
  invalidOtp,
  networkUnavailable,
  forbidden,
  notOwner,
  malformedLink,
  expired,
  revoked,
  alreadyClaimed,
  emailMismatch,
  differentFamily,
  envelopeRejected,
  localPersistenceFailed,
  unknown,
}

final class InvitationFailure implements Exception {
  const InvitationFailure(this.code);

  final InvitationFailureCode code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvitationFailure && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'InvitationFailure(${code.name})';
}

final class FamilyInviteLink {
  static const version = 1;

  const FamilyInviteLink({
    required this.inviteId,
    required this.token,
    required this.wrappingSecret,
  });

  final String inviteId;
  final String token;
  final String wrappingSecret;

  Uri toUri() => Uri(
    scheme: 'keepers',
    host: 'join',
    queryParameters: {
      'v': '$version',
      'i': inviteId,
      't': token,
      's': wrappingSecret,
    },
  );

  static FamilyInviteLink parse(Uri uri) {
    if (uri.scheme != 'keepers' ||
        uri.host != 'join' ||
        uri.path.isNotEmpty ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('Invalid family invitation location');
    }
    const expectedKeys = {'v', 'i', 't', 's'};
    final parameters = uri.queryParametersAll;
    if (parameters.length != expectedKeys.length ||
        !expectedKeys.every(parameters.containsKey) ||
        parameters.values.any((values) => values.length != 1)) {
      throw const FormatException('Invalid family invitation fields');
    }

    final parsedVersion = parameters['v']!.single;
    final inviteId = parameters['i']!.single;
    final token = parameters['t']!.single;
    final wrappingSecret = parameters['s']!.single;
    if (parsedVersion != '$version') {
      throw const FormatException('Unsupported family invitation version');
    }
    if (!_isCanonicalUuid(inviteId)) {
      throw const FormatException('Invalid family invitation identifier');
    }
    _decodeCanonicalBase64Url(token, expectedLength: 32, field: 'token');
    _decodeCanonicalBase64Url(
      wrappingSecret,
      expectedLength: 32,
      field: 'wrapping secret',
    );
    return FamilyInviteLink(
      inviteId: inviteId,
      token: token,
      wrappingSecret: wrappingSecret,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyInviteLink &&
          other.inviteId == inviteId &&
          other.token == token &&
          other.wrappingSecret == wrappingSecret;

  @override
  int get hashCode => Object.hash(inviteId, token, wrappingSecret);

  @override
  String toString() => 'FamilyInviteLink(<redacted>)';
}

final class InvitationEnvelope {
  static const currentVersion = 1;

  const InvitationEnvelope({
    required this.version,
    required this.inviteId,
    required this.familyId,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  final int version;
  final String inviteId;
  final String familyId;
  final String nonce;
  final String ciphertext;
  final String mac;

  factory InvitationEnvelope.fromJson(Map<String, Object?> json) {
    const fields = {
      'version',
      'inviteId',
      'familyId',
      'nonce',
      'ciphertext',
      'mac',
    };
    if (json.length != fields.length || !fields.every(json.containsKey)) {
      throw const FormatException('Invalid invitation envelope fields');
    }
    final version = json['version'];
    final inviteId = json['inviteId'];
    final familyId = json['familyId'];
    final nonce = json['nonce'];
    final ciphertext = json['ciphertext'];
    final mac = json['mac'];
    if (version is! int ||
        inviteId is! String ||
        familyId is! String ||
        nonce is! String ||
        ciphertext is! String ||
        mac is! String) {
      throw const FormatException('Invalid invitation envelope value types');
    }
    if (version != currentVersion) {
      throw const FormatException('Unsupported invitation envelope version');
    }
    if (!_isCanonicalUuid(inviteId) || !_isCanonicalUuid(familyId)) {
      throw const FormatException('Invalid invitation envelope identifier');
    }
    _decodeCanonicalBase64Url(nonce, expectedLength: 12, field: 'nonce');
    _decodeCanonicalBase64Url(
      ciphertext,
      expectedLength: 32,
      field: 'ciphertext',
    );
    _decodeCanonicalBase64Url(mac, expectedLength: 16, field: 'mac');
    return InvitationEnvelope(
      version: version,
      inviteId: inviteId,
      familyId: familyId,
      nonce: nonce,
      ciphertext: ciphertext,
      mac: mac,
    );
  }

  Map<String, Object> toJson() => {
    'version': version,
    'inviteId': inviteId,
    'familyId': familyId,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'mac': mac,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvitationEnvelope &&
          other.version == version &&
          other.inviteId == inviteId &&
          other.familyId == familyId &&
          other.nonce == nonce &&
          other.ciphertext == ciphertext &&
          other.mac == mac;

  @override
  int get hashCode =>
      Object.hash(version, inviteId, familyId, nonce, ciphertext, mac);
}

final class InvitationDraft {
  InvitationDraft({
    required this.link,
    required this.tokenHash,
    required this.envelope,
    required DateTime expiresAt,
  }) : expiresAt = expiresAt.toUtc();

  final FamilyInviteLink link;
  final String tokenHash;
  final InvitationEnvelope envelope;
  final DateTime expiresAt;
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
    throw FormatException('Invalid invitation $field');
  }
  try {
    final decoded = base64Url.decode(base64Url.normalize(value));
    if (decoded.length != expectedLength ||
        base64UrlEncode(decoded).replaceAll('=', '') != value) {
      throw FormatException('Invalid invitation $field');
    }
    return decoded;
  } on FormatException {
    rethrow;
  } on Object catch (error) {
    throw FormatException('Invalid invitation $field', error);
  }
}
