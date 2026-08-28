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
  static const int _maxEnvelopeMetadataBytes = 128;

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

  static int maxEnvelopeBytesForPlaintext(int maxPlaintextBytes) {
    RangeError.checkNotNegative(maxPlaintextBytes, 'maxPlaintextBytes');
    return _maxUnpaddedBase64Length(maxPlaintextBytes) +
        _maxEnvelopeMetadataBytes;
  }

  Future<Uint8List> decrypt({
    required Uint8List envelopeBytes,
    required List<int> keyBytes,
    required EntryMetadata metadata,
    int? maxPlaintextBytes,
  }) async {
    _validateKey(keyBytes);
    if (maxPlaintextBytes != null) {
      RangeError.checkNotNegative(maxPlaintextBytes, 'maxPlaintextBytes');
      if (envelopeBytes.lengthInBytes >
          maxEnvelopeBytesForPlaintext(maxPlaintextBytes)) {
        throw const FormatException(
          'Entry envelope exceeds bounded decrypt limit',
        );
      }
    }

    Uint8List? nonce;
    Uint8List? cipherText;
    Uint8List? tag;
    try {
      final envelope = _decodeEnvelope(envelopeBytes);
      final scope = _decodeScope(envelope['scope']);
      nonce = _decodeBinary(envelope, 'nonce', maxDecodedBytes: _nonceLength);
      cipherText = _decodeBinary(
        envelope,
        'ciphertext',
        maxDecodedBytes: maxPlaintextBytes,
      );
      tag = _decodeBinary(envelope, 'tag', maxDecodedBytes: _tagLength);
      if (nonce.length != _nonceLength) {
        throw const FormatException('Invalid AES-GCM nonce length');
      }
      if (tag.length != _tagLength) {
        throw const FormatException('Invalid AES-GCM tag length');
      }
      final box = SecretBox(cipherText, nonce: nonce, mac: Mac(tag));
      final decrypted = await _algorithm.decrypt(
        box,
        secretKey: SecretKey(keyBytes),
        aad: _authenticatedData(metadata, scope),
      );
      if (maxPlaintextBytes != null && decrypted.length > maxPlaintextBytes) {
        decrypted.fillRange(0, decrypted.length, 0);
        throw const FormatException(
          'Entry plaintext exceeds bounded decrypt limit',
        );
      }
      if (decrypted is Uint8List) return decrypted;
      try {
        return Uint8List.fromList(decrypted);
      } finally {
        decrypted.fillRange(0, decrypted.length, 0);
      }
    } finally {
      nonce?.fillRange(0, nonce.length, 0);
      cipherText?.fillRange(0, cipherText.length, 0);
      tag?.fillRange(0, tag.length, 0);
    }
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

  Uint8List _decodeBinary(
    Map<String, dynamic> envelope,
    String field, {
    int? maxDecodedBytes,
  }) {
    final value = envelope[field];
    final alphabet = RegExp(r'^[A-Za-z0-9_-]*$');
    if (value is! String) {
      throw FormatException('Invalid entry envelope $field');
    }
    if (maxDecodedBytes != null &&
        value.length > _maxUnpaddedBase64Length(maxDecodedBytes)) {
      throw FormatException(
        'Entry envelope $field exceeds bounded decrypt limit',
      );
    }
    if (!alphabet.hasMatch(value) || value.length % 4 == 1) {
      throw FormatException('Invalid entry envelope $field');
    }
    Uint8List? decoded;
    try {
      decoded = base64Url.decode(base64Url.normalize(value));
      if (maxDecodedBytes != null && decoded.lengthInBytes > maxDecodedBytes) {
        throw FormatException(
          'Entry envelope $field exceeds bounded decrypt limit',
        );
      }
      if (_unpaddedBase64Url(decoded) != value) {
        throw FormatException('Invalid entry envelope $field');
      }
      return decoded;
    } on FormatException {
      decoded?.fillRange(0, decoded.length, 0);
      rethrow;
    } on Object catch (error) {
      decoded?.fillRange(0, decoded.length, 0);
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

  static int _maxUnpaddedBase64Length(int decodedBytes) =>
      (decodedBytes * 4 + 2) ~/ 3;

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
