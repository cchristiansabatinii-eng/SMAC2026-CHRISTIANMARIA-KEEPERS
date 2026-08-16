import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:uuid/uuid.dart';

typedef RandomBytesFactory = List<int> Function(int length);

abstract interface class FamilyKeyEnvelopeCodec {
  Future<InvitationDraft> createDraft({
    required String familyId,
    required List<int> familyKey,
    required String inviteId,
    required DateTime expiresAt,
  });

  Future<List<int>> open({
    required FamilyInviteLink link,
    required InvitationEnvelope envelope,
  });
}

final class CryptographicFamilyKeyEnvelopeCodec
    implements FamilyKeyEnvelopeCodec {
  CryptographicFamilyKeyEnvelopeCodec({RandomBytesFactory? randomBytes})
    : _randomBytes = randomBytes ?? _secureRandomBytes,
      _aesGcm = AesGcm.with256bits(nonceLength: _nonceLength),
      _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: _keyLength);

  static const _keyLength = 32;
  static const _nonceLength = 12;
  static const _macLength = 16;
  static const _derivationInfo = 'keepers-family-invite-v1';

  final RandomBytesFactory _randomBytes;
  final AesGcm _aesGcm;
  final Hkdf _hkdf;

  @override
  Future<InvitationDraft> createDraft({
    required String familyId,
    required List<int> familyKey,
    required String inviteId,
    required DateTime expiresAt,
  }) async {
    _validateUuid(inviteId, 'inviteId');
    _validateUuid(familyId, 'familyId');
    _validateBytes(familyKey, expectedLength: _keyLength, field: 'familyKey');

    final tokenBytes = _nextRandomBytes(_keyLength);
    final wrappingSecretBytes = _nextRandomBytes(_keyLength);
    final nonce = _nextRandomBytes(_nonceLength);
    final token = _unpaddedBase64Url(tokenBytes);
    final wrappingSecret = _unpaddedBase64Url(wrappingSecretBytes);
    final link = FamilyInviteLink(
      inviteId: inviteId,
      token: token,
      wrappingSecret: wrappingSecret,
    );
    final tokenHash = await Sha256().hash(tokenBytes);
    final envelopeKey = await _deriveEnvelopeKey(
      wrappingSecret: wrappingSecretBytes,
      inviteId: inviteId,
    );
    final secretBox = await _aesGcm.encrypt(
      familyKey,
      secretKey: envelopeKey,
      nonce: nonce,
      aad: _authenticatedData(inviteId: inviteId, familyId: familyId),
    );
    final envelope = InvitationEnvelope(
      version: InvitationEnvelope.currentVersion,
      inviteId: inviteId,
      familyId: familyId,
      nonce: _unpaddedBase64Url(secretBox.nonce),
      ciphertext: _unpaddedBase64Url(secretBox.cipherText),
      mac: _unpaddedBase64Url(secretBox.mac.bytes),
    );
    return InvitationDraft(
      link: link,
      tokenHash: _unpaddedBase64Url(tokenHash.bytes),
      envelope: envelope,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<List<int>> open({
    required FamilyInviteLink link,
    required InvitationEnvelope envelope,
  }) async {
    try {
      final validatedLink = FamilyInviteLink.parse(link.toUri());
      final validatedEnvelope = InvitationEnvelope.fromJson(envelope.toJson());
      if (validatedLink.inviteId != validatedEnvelope.inviteId) {
        throw const InvitationFailure(InvitationFailureCode.envelopeRejected);
      }

      final wrappingSecret = _decodeBase64Url(
        validatedLink.wrappingSecret,
        expectedLength: _keyLength,
      );
      final envelopeKey = await _deriveEnvelopeKey(
        wrappingSecret: wrappingSecret,
        inviteId: validatedEnvelope.inviteId,
      );
      final secretBox = SecretBox(
        _decodeBase64Url(
          validatedEnvelope.ciphertext,
          expectedLength: _keyLength,
        ),
        nonce: _decodeBase64Url(
          validatedEnvelope.nonce,
          expectedLength: _nonceLength,
        ),
        mac: Mac(
          _decodeBase64Url(validatedEnvelope.mac, expectedLength: _macLength),
        ),
      );
      return await _aesGcm.decrypt(
        secretBox,
        secretKey: envelopeKey,
        aad: _authenticatedData(
          inviteId: validatedEnvelope.inviteId,
          familyId: validatedEnvelope.familyId,
        ),
      );
    } on InvitationFailure {
      rethrow;
    } on FormatException {
      throw const InvitationFailure(InvitationFailureCode.envelopeRejected);
    } on SecretBoxAuthenticationError {
      throw const InvitationFailure(InvitationFailureCode.envelopeRejected);
    }
  }

  Future<SecretKey> _deriveEnvelopeKey({
    required List<int> wrappingSecret,
    required String inviteId,
  }) => _hkdf.deriveKey(
    secretKey: SecretKey(wrappingSecret),
    nonce: Uuid.parse(inviteId),
    info: utf8.encode(_derivationInfo),
  );

  List<int> _nextRandomBytes(int length) {
    final bytes = _randomBytes(length);
    _validateBytes(bytes, expectedLength: length, field: 'randomBytes');
    return List<int>.unmodifiable(bytes);
  }

  static List<int> _authenticatedData({
    required String inviteId,
    required String familyId,
  }) =>
      utf8.encode('v${InvitationEnvelope.currentVersion}:$inviteId:$familyId');

  static List<int> _decodeBase64Url(
    String value, {
    required int expectedLength,
  }) {
    final decoded = base64Url.decode(base64Url.normalize(value));
    if (decoded.length != expectedLength ||
        _unpaddedBase64Url(decoded) != value) {
      throw const FormatException('Invalid invitation envelope bytes');
    }
    return decoded;
  }

  static void _validateUuid(String value, String field) {
    try {
      final bytes = Uuid.parse(value);
      if (Uuid.unparse(bytes) != value) {
        throw ArgumentError.value(value, field, 'Must be a canonical UUID');
      }
    } on FormatException {
      throw ArgumentError.value(value, field, 'Must be a canonical UUID');
    }
  }

  static void _validateBytes(
    List<int> bytes, {
    required int expectedLength,
    required String field,
  }) {
    if (bytes.length != expectedLength ||
        bytes.any((value) => value < 0 || value > 255)) {
      throw ArgumentError.value(
        bytes.length,
        field,
        'Must contain exactly $expectedLength bytes',
      );
    }
  }

  static String _unpaddedBase64Url(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static List<int> _secureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(
      length,
      (_) => random.nextInt(256),
      growable: false,
    );
  }
}
