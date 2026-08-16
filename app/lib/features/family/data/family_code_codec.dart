import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_join_failure.dart';

typedef FamilyCodeRandomSymbolIndex = int Function();
typedef FamilyCodeRandomBytesFactory = List<int> Function(int length);

abstract interface class FamilyCodeCodec {
  Future<FamilyCodeDraft> createDraft({
    required String familyId,
    required int codeVersion,
    required List<int> familyKey,
  });

  Future<FamilyCode> open({
    required EncryptedFamilyCodeMaterial material,
    required List<int> familyKey,
  });

  Future<String> lookupHash(FamilyCode code);
}

List<int> familyCodeAad(String familyId, int codeVersion) =>
    utf8.encode('keepers-family-code:v1:$familyId:$codeVersion');

final class CryptographicFamilyCodeCodec implements FamilyCodeCodec {
  CryptographicFamilyCodeCodec({
    FamilyCodeRandomSymbolIndex? randomSymbolIndex,
    FamilyCodeRandomBytesFactory? randomBytes,
  }) : _randomSymbolIndex = randomSymbolIndex ?? _secureRandomSymbolIndex,
       _randomBytes = randomBytes ?? _secureRandomBytes,
       _aesGcm = AesGcm.with256bits(nonceLength: _nonceLength);

  static const _familyKeyLength = 32;
  static const _nonceLength = 12;
  static const _macLength = 16;
  static const _ciphertextLength = 8;

  final FamilyCodeRandomSymbolIndex _randomSymbolIndex;
  final FamilyCodeRandomBytesFactory _randomBytes;
  final AesGcm _aesGcm;

  @override
  Future<FamilyCodeDraft> createDraft({
    required String familyId,
    required int codeVersion,
    required List<int> familyKey,
  }) async {
    _validateFamilyId(familyId);
    if (codeVersion <= 0) {
      throw ArgumentError.value(codeVersion, 'codeVersion', 'Must be positive');
    }
    _validateBytes(
      familyKey,
      expectedLength: _familyKeyLength,
      field: 'familyKey',
    );

    final code = FamilyCode.parse(
      List<String>.generate(
        _ciphertextLength,
        (_) => FamilyCode.alphabet[_nextSymbolIndex()],
        growable: false,
      ).join(),
    );
    final nonce = _nextRandomBytes(_nonceLength);
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(code.normalized),
      secretKey: SecretKey(familyKey),
      nonce: nonce,
      aad: familyCodeAad(familyId, codeVersion),
    );
    final material = EncryptedFamilyCodeMaterial(
      codecVersion: EncryptedFamilyCodeMaterial.currentCodecVersion,
      familyId: familyId,
      codeVersion: codeVersion,
      nonce: _unpaddedBase64Url(secretBox.nonce),
      ciphertext: _unpaddedBase64Url(secretBox.cipherText),
      mac: _unpaddedBase64Url(secretBox.mac.bytes),
    );
    return FamilyCodeDraft(
      code: code,
      lookupHash: await lookupHash(code),
      material: material,
    );
  }

  @override
  Future<FamilyCode> open({
    required EncryptedFamilyCodeMaterial material,
    required List<int> familyKey,
  }) async {
    try {
      _validateBytes(
        familyKey,
        expectedLength: _familyKeyLength,
        field: 'familyKey',
      );
      final validatedMaterial = EncryptedFamilyCodeMaterial.fromJson(
        material.toJson(),
      );
      final secretBox = SecretBox(
        _decodeCanonicalBase64Url(
          validatedMaterial.ciphertext,
          expectedLength: _ciphertextLength,
          field: 'ciphertext',
        ),
        nonce: _decodeCanonicalBase64Url(
          validatedMaterial.nonce,
          expectedLength: _nonceLength,
          field: 'nonce',
        ),
        mac: Mac(
          _decodeCanonicalBase64Url(
            validatedMaterial.mac,
            expectedLength: _macLength,
            field: 'mac',
          ),
        ),
      );
      final plaintext = await _aesGcm.decrypt(
        secretBox,
        secretKey: SecretKey(familyKey),
        aad: familyCodeAad(
          validatedMaterial.familyId,
          validatedMaterial.codeVersion,
        ),
      );
      return FamilyCode.parse(utf8.decode(plaintext));
    } on FamilyJoinFailure {
      rethrow;
    } on ArgumentError {
      rethrow;
    } on FormatException {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
    } on SecretBoxAuthenticationError {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
    }
  }

  @override
  Future<String> lookupHash(FamilyCode code) async => _unpaddedBase64Url(
    (await Sha256().hash(utf8.encode(code.normalized))).bytes,
  );

  int _nextSymbolIndex() {
    final index = _randomSymbolIndex();
    if (index < 0 || index >= FamilyCode.alphabet.length) {
      throw ArgumentError.value(
        index,
        'randomSymbolIndex',
        'Must be 0 through 31',
      );
    }
    return index;
  }

  List<int> _nextRandomBytes(int length) {
    final bytes = _randomBytes(length);
    _validateBytes(bytes, expectedLength: length, field: 'randomBytes');
    return List<int>.unmodifiable(bytes);
  }

  static void _validateFamilyId(String value) {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(value)) {
      throw ArgumentError.value(value, 'familyId', 'Must be a canonical UUID');
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

  static int _secureRandomSymbolIndex() =>
      Random.secure().nextInt(FamilyCode.alphabet.length);

  static List<int> _secureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(
      length,
      (_) => random.nextInt(256),
      growable: false,
    );
  }
}

List<int> _decodeCanonicalBase64Url(
  String value, {
  required int expectedLength,
  required String field,
}) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value) || value.length % 4 == 1) {
    throw FormatException('Invalid family code material $field');
  }
  try {
    final decoded = base64Url.decode(base64Url.normalize(value));
    if (decoded.length != expectedLength ||
        _unpaddedBase64Url(decoded) != value) {
      throw FormatException('Invalid family code material $field');
    }
    return decoded;
  } on FormatException {
    rethrow;
  } on Object catch (error) {
    throw FormatException('Invalid family code material $field', error);
  }
}

String _unpaddedBase64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');
