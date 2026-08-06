import 'dart:convert';
import 'dart:typed_data';

import 'package:keepers/features/capture/domain/capture_models.dart';

class EntryPayloadCodec {
  const EntryPayloadCodec();

  static const int version = 1;

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

  EntryPayload decode(Uint8List bytes) {
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
      final payload = EntryPayload(
        format: MemoryFormat.values.byName(formatName),
        primaryBytes: primary == null
            ? null
            : _decodeCanonicalPrimary(primary as String),
        text: text as String?,
        caption: caption as String?,
        mediaExtension: extension as String?,
        mediaDurationMs: durationMs as int?,
      );
      _validatePrimary(payload);
      return payload;
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('Invalid entry payload', error);
    }
  }

  Uint8List _decodeCanonicalPrimary(String value) {
    final alphabet = RegExp(r'^[A-Za-z0-9_-]*={0,2}$');
    if (!alphabet.hasMatch(value) || value.length % 4 != 0) {
      throw const FormatException('Entry payload primary is not canonical');
    }
    final decoded = Uint8List.fromList(base64Url.decode(value));
    if (base64UrlEncode(decoded) != value) {
      throw const FormatException('Entry payload primary is not canonical');
    }
    return decoded;
  }

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
