import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/data/entry_payload_codec.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';

void main() {
  const codec = EntryPayloadCodec();

  test('payload v1 round-trips every primary format and optional caption', () {
    final payloads = [
      EntryPayload(
        format: MemoryFormat.photo,
        primaryBytes: Uint8List.fromList([1, 2, 3]),
        text: null,
        caption: 'First morning',
        mediaExtension: 'jpg',
        mediaDurationMs: null,
      ),
      EntryPayload(
        format: MemoryFormat.voice,
        primaryBytes: Uint8List.fromList([4, 5, 6]),
        text: null,
        caption: null,
        mediaExtension: 'm4a',
        mediaDurationMs: 3210,
      ),
      const EntryPayload(
        format: MemoryFormat.text,
        primaryBytes: null,
        text: 'Only inside the envelope',
        caption: 'A private note',
        mediaExtension: null,
        mediaDurationMs: null,
      ),
    ];

    for (final payload in payloads) {
      expect(codec.decode(codec.encode(payload)), payload);
    }
  });

  test('bounded decode admits a primary at the exact source limit', () {
    final primary = Uint8List.fromList([1, 2, 3]);
    final encoded = codec.encode(
      EntryPayload(
        format: MemoryFormat.photo,
        primaryBytes: primary,
        text: null,
        caption: 'Within the bounded metadata allowance',
        mediaExtension: 'jpg',
        mediaDurationMs: null,
      ),
    );

    expect(
      encoded.lengthInBytes,
      lessThanOrEqualTo(
        EntryPayloadCodec.maxEncodedPayloadBytesForPrimary(
          primary.lengthInBytes,
        ),
      ),
    );
    expect(
      codec
          .decode(encoded, maxPrimaryBytes: primary.lengthInBytes)
          .primaryBytes,
      primary,
    );
  });

  test('bounded payload allowance covers the capture caption contract', () {
    final primary = Uint8List.fromList([1]);
    final encoded = codec.encode(
      EntryPayload(
        format: MemoryFormat.photo,
        primaryBytes: primary,
        text: null,
        caption: List.filled(280, '\u0001').join(),
        mediaExtension: 'abcdefghij',
        mediaDurationMs: null,
      ),
    );

    expect(
      encoded.lengthInBytes,
      lessThanOrEqualTo(
        EntryPayloadCodec.maxEncodedPayloadBytesForPrimary(
          primary.lengthInBytes,
        ),
      ),
    );
  });

  test('bounded decode rejects oversized plaintext before JSON decode', () {
    final oversized =
        Uint8List(EntryPayloadCodec.maxEncodedPayloadBytesForPrimary(1) + 1)
          ..fillRange(
            0,
            EntryPayloadCodec.maxEncodedPayloadBytesForPrimary(1) + 1,
            0xff,
          );

    expect(
      () => codec.decode(oversized, maxPrimaryBytes: 1),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('payload exceeds bounded decode limit'),
        ),
      ),
    );
  });

  test(
    'payload v1 encoding has one canonical field order and representation',
    () {
      final encoded = codec.encode(
        EntryPayload(
          format: MemoryFormat.photo,
          primaryBytes: Uint8List.fromList([1, 2, 3]),
          text: null,
          caption: 'First morning',
          mediaExtension: 'jpg',
          mediaDurationMs: null,
        ),
      );

      expect(
        utf8.decode(encoded),
        '{"v":1,"format":"photo","primary":"AQID","text":null,'
        '"caption":"First morning","extension":"jpg","duration_ms":null}',
      );
    },
  );

  test('unknown payload versions are rejected', () {
    expect(
      () => codec.decode(Uint8List.fromList(utf8.encode('{"v":99}'))),
      throwsFormatException,
    );
  });

  test('decode requires the exact v1 key set and JSON value types', () {
    final valid = <String, Object?>{
      'v': 1,
      'format': 'text',
      'primary': null,
      'text': 'A memory',
      'caption': null,
      'extension': null,
      'duration_ms': null,
    };
    final invalid = <Map<String, Object?>>[
      {...valid}..remove('caption'),
      {...valid, 'extra': null},
      {...valid, 'v': 1.0},
      {...valid, 'caption': 7},
      {...valid, 'duration_ms': 1.0},
    ];

    for (final map in invalid) {
      expect(
        () => codec.decode(Uint8List.fromList(utf8.encode(jsonEncode(map)))),
        throwsFormatException,
      );
    }
  });

  test('decode accepts only canonical padded base64url primary bytes', () {
    final valid = <String, Object?>{
      'v': 1,
      'format': 'photo',
      'primary': 'AQ==',
      'text': null,
      'caption': null,
      'extension': 'jpg',
      'duration_ms': null,
    };
    final invalidPrimary = ['AQ', 'AQ=', 'AQ===', 'AR==', '+/8=', '%41Q=='];

    expect(
      codec
          .decode(Uint8List.fromList(utf8.encode(jsonEncode(valid))))
          .primaryBytes,
      [1],
    );
    for (final primary in invalidPrimary) {
      expect(
        () => codec.decode(
          Uint8List.fromList(
            utf8.encode(jsonEncode({...valid, 'primary': primary})),
          ),
        ),
        throwsFormatException,
      );
    }
  });

  test('bounded decode rejects an oversized encoded primary before base64', () {
    final oversizedPrimary = <String, Object?>{
      'v': 1,
      'format': 'photo',
      'primary': 'AAAA',
      'text': null,
      'caption': null,
      'extension': 'jpg',
      'duration_ms': null,
    };

    expect(
      () => codec.decode(
        Uint8List.fromList(utf8.encode(jsonEncode(oversizedPrimary))),
        maxPrimaryBytes: 2,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('primary exceeds bounded decode limit'),
        ),
      ),
    );
  });

  test('decode zeroes primary bytes when later validation fails', () {
    final invalid = <String, Object?>{
      'v': 1,
      'format': 'photo',
      'primary': 'AQID',
      'text': 'second primary',
      'caption': null,
      'extension': 'jpg',
      'duration_ms': null,
    };
    FormatException? failure;

    try {
      codec.decode(Uint8List.fromList(utf8.encode(jsonEncode(invalid))));
    } on FormatException catch (error) {
      failure = error;
    }

    expect(failure, isNotNull);
    final validation = failure!.source! as ArgumentError;
    final rejectedPayload = validation.invalidValue! as EntryPayload;
    expect(rejectedPayload.primaryBytes, everyElement(0));
  });

  test('codec rejects payloads containing two primary representations', () {
    final ambiguousPhoto = EntryPayload(
      format: MemoryFormat.photo,
      primaryBytes: Uint8List.fromList([1]),
      text: 'second primary',
      caption: null,
      mediaExtension: 'jpg',
      mediaDurationMs: null,
    );
    final ambiguousText = EntryPayload(
      format: MemoryFormat.text,
      primaryBytes: Uint8List.fromList([1]),
      text: 'first primary',
      caption: null,
      mediaExtension: null,
      mediaDurationMs: null,
    );

    expect(() => codec.encode(ambiguousPhoto), throwsArgumentError);
    expect(() => codec.encode(ambiguousText), throwsArgumentError);
  });

  test(
    'codec rejects a payload missing its selected primary representation',
    () {
      const missingPhoto = EntryPayload(
        format: MemoryFormat.photo,
        primaryBytes: null,
        text: null,
        caption: 'caption is not a primary',
        mediaExtension: 'jpg',
        mediaDurationMs: null,
      );
      const missingText = EntryPayload(
        format: MemoryFormat.text,
        primaryBytes: null,
        text: null,
        caption: null,
        mediaExtension: null,
        mediaDurationMs: null,
      );

      expect(() => codec.encode(missingPhoto), throwsArgumentError);
      expect(() => codec.encode(missingText), throwsArgumentError);
    },
  );

  test('encode enforces every photo voice and text content invariant', () {
    final invalid = <EntryPayload>[
      EntryPayload(
        format: MemoryFormat.photo,
        primaryBytes: Uint8List(0),
        text: null,
        caption: null,
        mediaExtension: 'jpg',
        mediaDurationMs: null,
      ),
      EntryPayload(
        format: MemoryFormat.photo,
        primaryBytes: Uint8List.fromList([1]),
        text: null,
        caption: null,
        mediaExtension: null,
        mediaDurationMs: null,
      ),
      EntryPayload(
        format: MemoryFormat.photo,
        primaryBytes: Uint8List.fromList([1]),
        text: null,
        caption: null,
        mediaExtension: '../jpg',
        mediaDurationMs: null,
      ),
      EntryPayload(
        format: MemoryFormat.photo,
        primaryBytes: Uint8List.fromList([1]),
        text: null,
        caption: null,
        mediaExtension: 'jpg',
        mediaDurationMs: 1,
      ),
      EntryPayload(
        format: MemoryFormat.voice,
        primaryBytes: Uint8List(0),
        text: null,
        caption: null,
        mediaExtension: 'm4a',
        mediaDurationMs: 1,
      ),
      EntryPayload(
        format: MemoryFormat.voice,
        primaryBytes: Uint8List.fromList([1]),
        text: null,
        caption: null,
        mediaExtension: null,
        mediaDurationMs: 1,
      ),
      EntryPayload(
        format: MemoryFormat.voice,
        primaryBytes: Uint8List.fromList([1]),
        text: null,
        caption: null,
        mediaExtension: 'm4a/backup',
        mediaDurationMs: 1,
      ),
      for (final duration in <int?>[null, 0, -1])
        EntryPayload(
          format: MemoryFormat.voice,
          primaryBytes: Uint8List.fromList([1]),
          text: null,
          caption: null,
          mediaExtension: 'm4a',
          mediaDurationMs: duration,
        ),
      const EntryPayload(
        format: MemoryFormat.text,
        primaryBytes: null,
        text: '',
        caption: null,
        mediaExtension: null,
        mediaDurationMs: null,
      ),
      const EntryPayload(
        format: MemoryFormat.text,
        primaryBytes: null,
        text: '   ',
        caption: null,
        mediaExtension: null,
        mediaDurationMs: null,
      ),
      const EntryPayload(
        format: MemoryFormat.text,
        primaryBytes: null,
        text: 'memory',
        caption: null,
        mediaExtension: 'txt',
        mediaDurationMs: null,
      ),
      const EntryPayload(
        format: MemoryFormat.text,
        primaryBytes: null,
        text: 'memory',
        caption: null,
        mediaExtension: null,
        mediaDurationMs: 1,
      ),
    ];

    for (final payload in invalid) {
      expect(() => codec.encode(payload), throwsArgumentError);
    }
  });

  test('decode rejects the full empty and cross-format payload matrix', () {
    Map<String, Object?> raw({
      required String format,
      Object? primary,
      Object? text,
      Object? extension,
      Object? duration,
    }) => {
      'v': 1,
      'format': format,
      'primary': primary,
      'text': text,
      'caption': null,
      'extension': extension,
      'duration_ms': duration,
    };

    final invalid = <Map<String, Object?>>[
      raw(format: 'photo', primary: '', extension: 'jpg'),
      raw(format: 'photo', primary: 'AQ=='),
      raw(format: 'photo', primary: 'AQ==', extension: '../jpg'),
      raw(format: 'photo', primary: 'AQ==', extension: 'jpg', duration: 1),
      raw(format: 'photo', primary: 'AQ==', text: 'cross', extension: 'jpg'),
      raw(format: 'voice', primary: '', extension: 'm4a', duration: 1),
      raw(format: 'voice', primary: 'AQ==', duration: 1),
      raw(
        format: 'voice',
        primary: 'AQ==',
        extension: 'm4a/backup',
        duration: 1,
      ),
      raw(format: 'voice', primary: 'AQ==', extension: 'm4a'),
      raw(format: 'voice', primary: 'AQ==', extension: 'm4a', duration: 0),
      raw(format: 'voice', primary: 'AQ==', extension: 'm4a', duration: -1),
      raw(
        format: 'voice',
        primary: 'AQ==',
        text: 'cross',
        extension: 'm4a',
        duration: 1,
      ),
      raw(format: 'text', text: ''),
      raw(format: 'text', text: '   '),
      raw(format: 'text', primary: 'AQ==', text: 'cross'),
      raw(format: 'text', text: 'memory', extension: 'txt'),
      raw(format: 'text', text: 'memory', duration: 1),
    ];

    for (final map in invalid) {
      expect(
        () => codec.decode(Uint8List.fromList(utf8.encode(jsonEncode(map)))),
        throwsFormatException,
      );
    }
  });
}
