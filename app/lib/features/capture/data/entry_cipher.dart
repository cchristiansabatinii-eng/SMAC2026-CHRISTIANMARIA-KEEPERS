import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';

typedef EntryNonceFactory = Uint8List Function();

class EntryCipher {
  EntryCipher({EntryNonceFactory? nonceFactory})
    : _nonceFactory = nonceFactory ?? _secureNonce,
      _algorithm = AesGcm.with256bits(nonceLength: 12);

  static const int envelopeVersion = 1;
  static const int _keyLength = 32;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;

  final EntryNonceFactory _nonceFactory;
  final AesGcm _algorithm;

  Future<Uint8List> encrypt({
    required Uint8List plaintext,
    required List<int> keyBytes,
    required EntryMetadata metadata,
    required EntryKeyScope keyScope,
  }) async {
    _validateKey(keyBytes);
    final nonce = Uint8List.fromList(_nonceFactory());
    if (nonce.length != _nonceLength) {
      throw ArgumentError.value(
        nonce.length,
        'nonceFactory',
        'AES-GCM nonces must be 96 bits',
      );
    }
    final secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
      aad: _authenticatedData(metadata, keyScope),
    );
    final envelope = <String, Object>{
      'v': envelopeVersion,
      'scope': keyScope.name,
      'nonce': _unpaddedBase64Url(secretBox.nonce),
      'ciphertext': _unpaddedBase64Url(secretBox.cipherText),
      'tag': _unpaddedBase64Url(secretBox.mac.bytes),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  Future<Uint8List> decrypt({
    required Uint8List envelopeBytes,
    required List<int> keyBytes,
    required EntryMetadata metadata,
  }) {
    _validateKey(keyBytes);
    final envelope = _decodeEnvelope(envelopeBytes);
    final scope = _decodeScope(envelope['scope']);
    final nonce = _decodeBinary(envelope, 'nonce');
    final cipherText = _decodeBinary(envelope, 'ciphertext');
    final tag = _decodeBinary(envelope, 'tag');
    if (nonce.length != _nonceLength) {
      throw const FormatException('Invalid AES-GCM nonce length');
    }
    if (tag.length != _tagLength) {
      throw const FormatException('Invalid AES-GCM tag length');
    }
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(tag));
    return _algorithm
        .decrypt(
          box,
          secretKey: SecretKey(keyBytes),
          aad: _authenticatedData(metadata, scope),
        )
        .then(Uint8List.fromList);
  }

  Map<String, dynamic> _decodeEnvelope(Uint8List envelopeBytes) {
    try {
      final decoded = jsonDecode(utf8.decode(envelopeBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Entry envelope must be a JSON object');
      }
      const fields = {'v', 'scope', 'nonce', 'ciphertext', 'tag'};
      if (decoded.length != fields.length ||
          !fields.every(decoded.containsKey)) {
        throw const FormatException('Invalid entry envelope fields');
      }
      if (decoded['v'] is! int || decoded['v'] != envelopeVersion) {
        throw const FormatException('Unsupported entry envelope version');
      }
      return decoded;
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('Invalid entry envelope', error);
    }
  }

  EntryKeyScope _decodeScope(Object? value) {
    if (value is! String) {
      throw const FormatException('Entry envelope scope is missing');
    }
    try {
      return EntryKeyScope.values.byName(value);
    } on ArgumentError {
      throw const FormatException('Unsupported entry key scope');
    }
  }

  Uint8List _decodeBinary(Map<String, dynamic> envelope, String field) {
    final value = envelope[field];
    final alphabet = RegExp(r'^[A-Za-z0-9_-]*$');
    if (value is! String ||
        !alphabet.hasMatch(value) ||
        value.length % 4 == 1) {
      throw FormatException('Invalid entry envelope $field');
    }
    try {
      final decoded = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(value)),
      );
      if (_unpaddedBase64Url(decoded) != value) {
        throw FormatException('Invalid entry envelope $field');
      }
      return decoded;
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('Invalid entry envelope $field', error);
    }
  }

  List<int> _authenticatedData(EntryMetadata metadata, EntryKeyScope scope) =>
      utf8.encode(
        jsonEncode(
          SplayTreeMap<String, Object>.of(metadata.authenticatedMap(scope)),
        ),
      );

  void _validateKey(List<int> keyBytes) {
    if (keyBytes.length != _keyLength) {
      throw ArgumentError.value(
        keyBytes.length,
        'keyBytes',
        'AES-256-GCM keys must be 256 bits',
      );
    }
  }

  static String _unpaddedBase64Url(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static Uint8List _secureNonce() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(
        _nonceLength,
        (_) => random.nextInt(256),
        growable: false,
      ),
    );
  }
}
