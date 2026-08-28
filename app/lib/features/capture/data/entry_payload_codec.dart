import 'dart:convert';
import 'dart:typed_data';

import 'package:keepers/features/capture/domain/capture_models.dart';

class EntryPayloadCodec {
  const EntryPayloadCodec();

  static const int version = 1;
  static const int _boundedPayloadMetadataAllowanceBytes = 4 * 1024;

  static int maxEncodedPayloadBytesForPrimary(int maxPrimaryBytes) {
    RangeError.checkNotNegative(maxPrimaryBytes, 'maxPrimaryBytes');
    return _maxPaddedBase64Length(maxPrimaryBytes) +
        _boundedPayloadMetadataAllowanceBytes;
  }

  Uint8List encode(EntryPayload payload) {
    _validatePrimary(payload);
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'v': version,
          'format': payload.format.name,
          'primary': payload.primaryBytes == null
              ? null
              : base64UrlEncode(payload.primaryBytes!),
          'text': payload.text,
          'caption': payload.caption,
          'extension': payload.mediaExtension,
          'duration_ms': payload.mediaDurationMs,
        }),
      ),
    );
  }

  EntryPayload decode(Uint8List bytes, {int? maxPrimaryBytes}) {
    if (maxPrimaryBytes != null) {
      RangeError.checkNotNegative(maxPrimaryBytes, 'maxPrimaryBytes');
      if (bytes.lengthInBytes >
          maxEncodedPayloadBytesForPrimary(maxPrimaryBytes)) {
        throw const FormatException(
          'Entry payload exceeds bounded decode limit',
        );
      }
    }
    Uint8List? decodedPrimary;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Entry payload must be a JSON object');
      }
      const fields = {
        'v',
        'format',
        'primary',
        'text',
        'caption',
        'extension',
        'duration_ms',
      };
      if (decoded.length != fields.length ||
          !fields.every(decoded.containsKey)) {
        throw const FormatException('Invalid entry payload fields');
      }
      if (decoded['v'] is! int || decoded['v'] != version) {
        throw const FormatException('Unsupported entry payload version');
      }
      final formatName = decoded['format'];
      if (formatName is! String) {
        throw const FormatException('Entry payload format is missing');
      }
      final primary = decoded['primary'];
      final text = decoded['text'];
      final caption = decoded['caption'];
      final extension = decoded['extension'];
      final durationMs = decoded['duration_ms'];
      if ((primary != null && primary is! String) ||
          (text != null && text is! String) ||
          (caption != null && caption is! String) ||
          (extension != null && extension is! String) ||
          (durationMs != null && durationMs is! int)) {
        throw const FormatException('Entry payload primary is invalid');
      }
      decodedPrimary = primary == null
          ? null
          : _decodeCanonicalPrimary(
              primary as String,
              maxDecodedBytes: maxPrimaryBytes,
            );
      final payload = EntryPayload(
        format: MemoryFormat.values.byName(formatName),
        primaryBytes: decodedPrimary,
        text: text as String?,
        caption: caption as String?,
        mediaExtension: extension as String?,
        mediaDurationMs: durationMs as int?,
      );
      _validatePrimary(payload);
      return payload;
    } on FormatException {
      decodedPrimary?.fillRange(0, decodedPrimary.length, 0);
      rethrow;
    } on Object catch (error) {
      decodedPrimary?.fillRange(0, decodedPrimary.length, 0);
      throw FormatException('Invalid entry payload', error);
    }
  }

  Uint8List _decodeCanonicalPrimary(String value, {int? maxDecodedBytes}) {
    final alphabet = RegExp(r'^[A-Za-z0-9_-]*={0,2}$');
    if (maxDecodedBytes != null &&
        value.length > _maxPaddedBase64Length(maxDecodedBytes)) {
      throw const FormatException(
        'Entry payload primary exceeds bounded decode limit',
      );
    }
    if (!alphabet.hasMatch(value) || value.length % 4 != 0) {
      throw const FormatException('Entry payload primary is not canonical');
    }
    final paddingBytes = value.endsWith('==')
        ? 2
        : value.endsWith('=')
        ? 1
        : 0;
    final predictedDecodedBytes = (value.length ~/ 4) * 3 - paddingBytes;
    if (maxDecodedBytes != null && predictedDecodedBytes > maxDecodedBytes) {
      throw const FormatException(
        'Entry payload primary exceeds bounded decode limit',
      );
    }
    Uint8List? decoded;
    try {
      decoded = base64Url.decode(value);
      if (maxDecodedBytes != null && decoded.lengthInBytes > maxDecodedBytes) {
        throw const FormatException(
          'Entry payload primary exceeds bounded decode limit',
        );
      }
      if (base64UrlEncode(decoded) != value) {
        throw const FormatException('Entry payload primary is not canonical');
      }
      return decoded;
    } on Object {
      decoded?.fillRange(0, decoded.length, 0);
      rethrow;
    }
  }

  static int _maxPaddedBase64Length(int decodedBytes) =>
      ((decodedBytes + 2) ~/ 3) * 4;

  void _validatePrimary(EntryPayload payload) {
    final safeExtension = RegExp(r'^[a-z0-9]{1,10}$');
    final valid = switch (payload.format) {
      MemoryFormat.photo =>
        payload.primaryBytes?.isNotEmpty == true &&
            payload.text == null &&
            payload.mediaExtension != null &&
            safeExtension.hasMatch(payload.mediaExtension!) &&
            payload.mediaDurationMs == null,
      MemoryFormat.voice =>
        payload.primaryBytes?.isNotEmpty == true &&
            payload.text == null &&
            payload.mediaExtension != null &&
            safeExtension.hasMatch(payload.mediaExtension!) &&
            payload.mediaDurationMs != null &&
            payload.mediaDurationMs! > 0,
      MemoryFormat.text =>
        payload.primaryBytes == null &&
            payload.text?.trim().isNotEmpty == true &&
            payload.mediaExtension == null &&
            payload.mediaDurationMs == null,
    };
    if (!valid) {
      throw ArgumentError.value(
        payload,
        'payload',
        'The selected format must have exactly one primary representation',
      );
    }
  }
}
