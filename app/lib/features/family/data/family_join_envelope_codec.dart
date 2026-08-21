import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:keepers/features/family/data/joining_key_store.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:uuid/uuid.dart';

typedef JoinEnvelopeRandomBytesFactory = List<int> Function(int length);

abstract interface class FamilyJoinEnvelopeCodec {
  Future<FamilyJoinApprovalEnvelope> seal({
    required JoinEnvelopeContext context,
    required String requesterPublicKey,
    required List<int> familyKey,
  });

  Future<List<int>> open({
    required FamilyJoinApprovalEnvelope envelope,
    required String expectedRequesterPublicKey,
    required StoredJoiningKey joiningKey,
  });
}

List<int> joinEnvelopeAad(JoinEnvelopeContext context) => utf8.encode(
  'v1:${context.familyId}:${context.requestId}:'
  '${context.requesterAccountId}:${context.codeVersion}',
);

final class CryptographicFamilyJoinEnvelopeCodec
    implements FamilyJoinEnvelopeCodec {
  CryptographicFamilyJoinEnvelopeCodec({
    JoinEnvelopeRandomBytesFactory? randomBytes,
  }) : _randomBytes = randomBytes ?? _secureRandomBytes,
       _aesGcm = AesGcm.with256bits(nonceLength: _nonceLength),
       _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: _keyLength);

  static const _keyLength = 32;
  static const _nonceLength = 12;
  static const _macLength = 16;

  final JoinEnvelopeRandomBytesFactory _randomBytes;
  final AesGcm _aesGcm;
  final Hkdf _hkdf;
  final X25519 _x25519 = X25519();

  @override
  Future<FamilyJoinApprovalEnvelope> seal({
    required JoinEnvelopeContext context,
    required String requesterPublicKey,
    required List<int> familyKey,
  }) async {
    _validateContext(context);
    final requesterBytes = _decodePublicKey(requesterPublicKey);
    _validateBytes(familyKey, expectedLength: _keyLength, field: 'familyKey');
    final ephemeralSeed = _nextRandomBytes(_keyLength);
    final nonce = _nextRandomBytes(_nonceLength);
    final familyKeyCopy = List<int>.from(familyKey);
    SimpleKeyPair? ephemeralKeyPair;
    try {
      ephemeralKeyPair = await _x25519.newKeyPairFromSeed(ephemeralSeed);
      final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();
      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: ephemeralKeyPair,
        remotePublicKey: SimplePublicKey(
          requesterBytes,
          type: KeyPairType.x25519,
        ),
      );
      final secretBox = await _withEnvelopeKey(
        sharedSecret: sharedSecret,
        context: context,
        operation: (key) => _aesGcm.encrypt(
          familyKeyCopy,
          secretKey: key,
          nonce: nonce,
          aad: joinEnvelopeAad(context),
        ),
      );
      return FamilyJoinApprovalEnvelope(
        version: FamilyJoinApprovalEnvelope.currentVersion,
        context: context,
        ephemeralPublicKey: unpaddedFamilyJoinBase64Url(
          ephemeralPublicKey.bytes,
        ),
        nonce: unpaddedFamilyJoinBase64Url(secretBox.nonce),
        ciphertext: unpaddedFamilyJoinBase64Url(secretBox.cipherText),
        mac: unpaddedFamilyJoinBase64Url(secretBox.mac.bytes),
      );
    } finally {
      ephemeralKeyPair?.destroy();
      _zero(ephemeralSeed);
      _zero(familyKeyCopy);
    }
  }

  @override
  Future<List<int>> open({
    required FamilyJoinApprovalEnvelope envelope,
    required String expectedRequesterPublicKey,
    required StoredJoiningKey joiningKey,
  }) async {
    try {
      final validatedEnvelope = FamilyJoinApprovalEnvelope.fromJson(
        envelope.toJson(),
      );
      _validateContext(validatedEnvelope.context);
      _decodePublicKey(expectedRequesterPublicKey);
      if (joiningKey.publicKey != expectedRequesterPublicKey) {
        throw const FamilyJoinFailure(FamilyJoinFailureCode.invalidJoinKey);
      }
      final ephemeralPublicKey = SimplePublicKey(
        decodeCanonicalFamilyJoinBase64Url(
          validatedEnvelope.ephemeralPublicKey,
          expectedLength: _keyLength,
          field: 'ephemeralPublicKey',
        ),
        type: KeyPairType.x25519,
      );
      return await joiningKey.use(
        (keyPair) => _openWithKeyPair(
          keyPair: keyPair,
          ephemeralPublicKey: ephemeralPublicKey,
          envelope: validatedEnvelope,
        ),
      );
    } on FamilyJoinFailure {
      rethrow;
    } on FormatException {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
    } on SecretBoxAuthenticationError {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
    } on ArgumentError {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
    }
  }

  Future<List<int>> _openWithKeyPair({
    required SimpleKeyPair keyPair,
    required SimplePublicKey ephemeralPublicKey,
    required FamilyJoinApprovalEnvelope envelope,
  }) async {
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: ephemeralPublicKey,
    );
    final secretBox = SecretBox(
      decodeCanonicalFamilyJoinBase64Url(
        envelope.ciphertext,
        expectedLength: _keyLength,
        field: 'ciphertext',
      ),
      nonce: decodeCanonicalFamilyJoinBase64Url(
        envelope.nonce,
        expectedLength: _nonceLength,
        field: 'nonce',
      ),
      mac: Mac(
        decodeCanonicalFamilyJoinBase64Url(
          envelope.mac,
          expectedLength: _macLength,
          field: 'mac',
        ),
      ),
    );
    return _withEnvelopeKey(
      sharedSecret: sharedSecret,
      context: envelope.context,
      operation: (key) => _aesGcm.decrypt(
        secretBox,
        secretKey: key,
        aad: joinEnvelopeAad(envelope.context),
      ),
    );
  }

  Future<T> _withEnvelopeKey<T>({
    required SecretKey sharedSecret,
    required JoinEnvelopeContext context,
    required Future<T> Function(SecretKey key) operation,
  }) async {
    List<int>? sharedSecretBytes;
    List<int>? derivedKeyBytes;
    SecretKey? sharedSecretInput;
    SecretKeyData? derived;
    SecretKeyData? envelopeKey;
    try {
      sharedSecretBytes = List<int>.from(await sharedSecret.extractBytes());
      sharedSecretInput = SecretKeyData(
        sharedSecretBytes,
        overwriteWhenDestroyed: true,
      );
      derived = await _hkdf.deriveKey(
        secretKey: sharedSecretInput,
        nonce: Uuid.parse(context.requestId),
        info: utf8.encode(
          'keepers-family-join-envelope-v1:${context.familyId}:'
          '${context.requesterAccountId}:${context.codeVersion}',
        ),
      );
      derivedKeyBytes = List<int>.from(derived.bytes);
      envelopeKey = SecretKeyData(
        derivedKeyBytes,
        overwriteWhenDestroyed: true,
      );
      return await operation(envelopeKey);
    } finally {
      envelopeKey?.destroy();
      derived?.destroy();
      sharedSecretInput?.destroy();
      sharedSecret.destroy();
      if (sharedSecretBytes != null) _zero(sharedSecretBytes);
      if (derivedKeyBytes != null) _zero(derivedKeyBytes);
    }
  }

  List<int> _nextRandomBytes(int length) {
    final bytes = List<int>.from(_randomBytes(length));
    _validateBytes(bytes, expectedLength: length, field: 'randomBytes');
    return bytes;
  }

  static List<int> _decodePublicKey(String value) =>
      decodeCanonicalFamilyJoinBase64Url(
        value,
        expectedLength: _keyLength,
        field: 'requesterPublicKey',
      );

  static void _validateContext(JoinEnvelopeContext context) {
    if (!isCanonicalFamilyJoinUuid(context.requestId) ||
        !isCanonicalFamilyJoinUuid(context.familyId) ||
        !isCanonicalFamilyJoinUuid(context.requesterAccountId) ||
        context.codeVersion <= 0) {
      throw ArgumentError('Invalid family join envelope context');
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

  static void _zero(List<int> bytes) {
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = 0;
    }
  }

  static List<int> _secureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(
      length,
      (_) => random.nextInt(256),
      growable: false,
    );
  }
}
