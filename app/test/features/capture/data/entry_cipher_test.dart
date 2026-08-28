import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/data/entry_cipher.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';

void main() {
  EntryCipher deterministicCipher() => EntryCipher(
    nonceFactory: () =>
        Uint8List.fromList(List<int>.generate(12, (index) => index)),
  );

  test('AES-256-GCM round-trips through the versioned envelope', () async {
    final cipher = deterministicCipher();
    final plaintext = Uint8List.fromList([10, 20, 30]);
    final metadata = _entryMetadata();

    final encrypted = await cipher.encrypt(
      plaintext: plaintext,
      keyBytes: List<int>.filled(32, 1),
      metadata: metadata,
      keyScope: EntryKeyScope.family,
    );

    expect(encrypted, isNot(plaintext));
    expect(
      await cipher.decrypt(
        envelopeBytes: encrypted,
        keyBytes: List<int>.filled(32, 1),
        metadata: metadata,
      ),
      plaintext,
    );
  });

  test('bounded decrypt admits the exact plaintext limit', () async {
    final cipher = deterministicCipher();
    for (var length = 0; length <= 3; length++) {
      final plaintext = Uint8List.fromList(
        List<int>.generate(length, (index) => index + 1),
      );
      final encrypted = await cipher.encrypt(
        plaintext: plaintext,
        keyBytes: List<int>.filled(32, 1),
        metadata: _entryMetadata(),
        keyScope: EntryKeyScope.family,
      );

      expect(
        encrypted.lengthInBytes,
        lessThanOrEqualTo(
          EntryCipher.maxEnvelopeBytesForPlaintext(plaintext.lengthInBytes),
        ),
      );
      expect(
        await cipher.decrypt(
          envelopeBytes: encrypted,
          keyBytes: List<int>.filled(32, 1),
          metadata: _entryMetadata(),
          maxPlaintextBytes: plaintext.lengthInBytes,
        ),
        plaintext,
      );
    }
  });

  test(
    'bounded decrypt rejects oversized ciphertext before base64 decode',
    () async {
      final cipher = deterministicCipher();
      final encrypted = await cipher.encrypt(
        plaintext: Uint8List.fromList([1]),
        keyBytes: List<int>.filled(32, 1),
        metadata: _entryMetadata(),
        keyScope: EntryKeyScope.family,
      );
      final envelope =
          jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
      envelope['ciphertext'] = 'AAAA';

      await expectLater(
        cipher.decrypt(
          envelopeBytes: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
          keyBytes: List<int>.filled(32, 1),
          metadata: _entryMetadata(),
          maxPlaintextBytes: 2,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('ciphertext exceeds bounded decrypt limit'),
          ),
        ),
      );
    },
  );

  test(
    'bounded decrypt rejects oversized nonce and tag before base64 decode',
    () async {
      final cipher = deterministicCipher();
      final encrypted = await cipher.encrypt(
        plaintext: Uint8List.fromList([1]),
        keyBytes: List<int>.filled(32, 1),
        metadata: _entryMetadata(),
        keyScope: EntryKeyScope.family,
      );
      final valid = jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;

      for (final candidate in <(String, int)>[('nonce', 13), ('tag', 17)]) {
        final envelope = <String, dynamic>{...valid};
        envelope[candidate.$1] = _unpaddedBase64Url(Uint8List(candidate.$2));

        await expectLater(
          cipher.decrypt(
            envelopeBytes: Uint8List.fromList(
              utf8.encode(jsonEncode(envelope)),
            ),
            keyBytes: List<int>.filled(32, 1),
            metadata: _entryMetadata(),
            maxPlaintextBytes: 64,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('${candidate.$1} exceeds bounded decrypt limit'),
            ),
          ),
        );
      }
    },
  );

  test(
    'envelope has exactly five fields and unpadded base64url values',
    () async {
      final encrypted = await deterministicCipher().encrypt(
        plaintext: Uint8List.fromList([10]),
        keyBytes: List<int>.filled(32, 1),
        metadata: _entryMetadata(),
        keyScope: EntryKeyScope.family,
      );
      final envelope =
          jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;

      expect(envelope.keys.toList(), [
        'v',
        'scope',
        'nonce',
        'ciphertext',
        'tag',
      ]);
      expect(envelope['v'], 1);
      expect(envelope['scope'], 'family');
      for (final field in ['nonce', 'ciphertext', 'tag']) {
        expect(envelope[field], isA<String>());
        expect(envelope[field] as String, isNot(contains('=')));
      }
    },
  );

  test('AES-GCM rejects a wrong key', () async {
    final cipher = deterministicCipher();
    final metadata = _entryMetadata();
    final encrypted = await cipher.encrypt(
      plaintext: Uint8List.fromList([10, 20, 30]),
      keyBytes: List<int>.filled(32, 1),
      metadata: metadata,
      keyScope: EntryKeyScope.member,
    );

    await expectLater(
      cipher.decrypt(
        envelopeBytes: encrypted,
        keyBytes: List<int>.filled(32, 2),
        metadata: metadata,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('every authenticated metadata field rejects mutation', () async {
    final cipher = deterministicCipher();
    final metadata = _entryMetadata();
    final encrypted = await cipher.encrypt(
      plaintext: Uint8List.fromList([10, 20, 30]),
      keyBytes: List<int>.filled(32, 1),
      metadata: metadata,
      keyScope: EntryKeyScope.member,
    );
    final mutations = <EntryMetadata>[
      metadata.copyWith(id: 'different-entry'),
      metadata.copyWith(familyId: 'different-family'),
      metadata.copyWith(authorId: 'different-author'),
      metadata.copyWith(createdAt: DateTime.utc(2026, 9, 2)),
      metadata.copyWith(format: MemoryFormat.voice),
      metadata.copyWith(privacy: PrivacyTier.reveal),
    ];

    for (final mutation in mutations) {
      await expectLater(
        cipher.decrypt(
          envelopeBytes: encrypted,
          keyBytes: List<int>.filled(32, 1),
          metadata: mutation,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    }
  });

  test('nonce, ciphertext, tag, and key scope mutations fail closed', () async {
    final cipher = deterministicCipher();
    final metadata = _entryMetadata();
    final encrypted = await cipher.encrypt(
      plaintext: Uint8List.fromList([10, 20, 30]),
      keyBytes: List<int>.filled(32, 1),
      metadata: metadata,
      keyScope: EntryKeyScope.member,
    );

    for (final field in ['nonce', 'ciphertext', 'tag']) {
      final envelope =
          jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
      final encoded = envelope[field] as String;
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      bytes[0] ^= 1;
      envelope[field] = _unpaddedBase64Url(bytes);
      await expectLater(
        cipher.decrypt(
          envelopeBytes: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
          keyBytes: List<int>.filled(32, 1),
          metadata: metadata,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    }

    final scopeEnvelope =
        jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
    scopeEnvelope['scope'] = 'family';
    await expectLater(
      cipher.decrypt(
        envelopeBytes: Uint8List.fromList(
          utf8.encode(jsonEncode(scopeEnvelope)),
        ),
        keyBytes: List<int>.filled(32, 1),
        metadata: metadata,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test(
    'unknown envelope version and key scope are rejected before decrypt',
    () {
      final cipher = deterministicCipher();
      final metadata = _entryMetadata();
      final common = {
        'nonce': _unpaddedBase64Url(List<int>.filled(12, 0)),
        'ciphertext': '',
        'tag': _unpaddedBase64Url(List<int>.filled(16, 0)),
      };

      for (final envelope in [
        {'v': 99, 'scope': 'family', ...common},
        {'v': 1, 'scope': 'device', ...common},
      ]) {
        expect(
          () => cipher.decrypt(
            envelopeBytes: Uint8List.fromList(
              utf8.encode(jsonEncode(envelope)),
            ),
            keyBytes: List<int>.filled(32, 1),
            metadata: metadata,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'envelope parser requires exact keys and exact JSON value types',
    () async {
      final cipher = deterministicCipher();
      final encrypted = await cipher.encrypt(
        plaintext: Uint8List.fromList([1]),
        keyBytes: List<int>.filled(32, 1),
        metadata: _entryMetadata(),
        keyScope: EntryKeyScope.family,
      );
      final valid = jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
      final invalid = <Map<String, dynamic>>[
        {...valid}..remove('tag'),
        {...valid, 'extra': null},
        {...valid, 'v': 1.0},
        {...valid, 'scope': 1},
        {...valid, 'nonce': 1},
      ];

      for (final envelope in invalid) {
        await expectLater(
          () => cipher.decrypt(
            envelopeBytes: Uint8List.fromList(
              utf8.encode(jsonEncode(envelope)),
            ),
            keyBytes: List<int>.filled(32, 1),
            metadata: _entryMetadata(),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'envelope accepts only canonical unpadded base64url binary values',
    () async {
      final cipher = deterministicCipher();
      final encrypted = await cipher.encrypt(
        plaintext: Uint8List.fromList([1]),
        keyBytes: List<int>.filled(32, 1),
        metadata: _entryMetadata(),
        keyScope: EntryKeyScope.family,
      );
      final valid = jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
      final canonicalCiphertext = valid['ciphertext'] as String;
      final padBitAlias = _changeLastBase64PadBit(canonicalCiphertext);
      final invalid = <Map<String, dynamic>>[
        {...valid, 'nonce': '${valid['nonce']}='},
        {...valid, 'nonce': '+${(valid['nonce'] as String).substring(1)}'},
        {...valid, 'nonce': '%41${(valid['nonce'] as String).substring(1)}'},
        {...valid, 'ciphertext': padBitAlias},
      ];

      for (final envelope in invalid) {
        await expectLater(
          () => cipher.decrypt(
            envelopeBytes: Uint8List.fromList(
              utf8.encode(jsonEncode(envelope)),
            ),
            keyBytes: List<int>.filled(32, 1),
            metadata: _entryMetadata(),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('every encryption receives a fresh 96-bit nonce', () async {
    var seed = 0;
    final cipher = EntryCipher(
      nonceFactory: () => Uint8List.fromList(List<int>.filled(12, seed++)),
    );

    final first = await cipher.encrypt(
      plaintext: Uint8List(0),
      keyBytes: List<int>.filled(32, 1),
      metadata: _entryMetadata(),
      keyScope: EntryKeyScope.family,
    );
    final second = await cipher.encrypt(
      plaintext: Uint8List(0),
      keyBytes: List<int>.filled(32, 1),
      metadata: _entryMetadata(),
      keyScope: EntryKeyScope.family,
    );

    expect(first, isNot(second));
    final firstEnvelope =
        jsonDecode(utf8.decode(first)) as Map<String, dynamic>;
    final secondEnvelope =
        jsonDecode(utf8.decode(second)) as Map<String, dynamic>;
    expect(base64Url.decode(firstEnvelope['nonce'] as String), hasLength(12));
    expect(firstEnvelope['nonce'], isNot(secondEnvelope['nonce']));
  });

  test('encryption rejects a nonce that is not 96 bits', () async {
    final cipher = EntryCipher(nonceFactory: () => Uint8List(11));

    await expectLater(
      cipher.encrypt(
        plaintext: Uint8List(0),
        keyBytes: List<int>.filled(32, 1),
        metadata: _entryMetadata(),
        keyScope: EntryKeyScope.family,
      ),
      throwsArgumentError,
    );
  });
}

EntryMetadata _entryMetadata() => EntryMetadata(
  id: 'entry-1',
  familyId: 'family-1',
  authorId: 'member-1',
  createdAt: DateTime.utc(2026, 9, 1, 12, 30),
  format: MemoryFormat.photo,
  privacy: PrivacyTier.journal,
);

String _unpaddedBase64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

String _changeLastBase64PadBit(String value) {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final last = alphabet.indexOf(value[value.length - 1]);
  return '${value.substring(0, value.length - 1)}${alphabet[last + 1]}';
}
