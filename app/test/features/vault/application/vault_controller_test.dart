import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/data/entry_cipher.dart';
import 'package:keepers/features/capture/data/entry_key_resolver.dart';
import 'package:keepers/features/capture/data/entry_payload_codec.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/application/vault_controller.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/storage/database_key_store.dart';

void main() {
  test('open resolves the tier key and decrypts only in memory', () async {
    final scratch = await Directory.systemTemp.createTemp('keepers-vault-');
    addTearDown(() => scratch.delete(recursive: true));
    final harness = await _VaultHarness.create();

    final memory = await harness.controller.open(harness.metadata);

    expect(memory, isA<OpenedMemory>());
    expect((memory as OpenedMemory).payload.text, 'Only in memory');
    expect(harness.resolvedReferences, [harness.metadata.blobRef]);
    expect(await scratch.list().toList(), isEmpty);
  });

  test('a read-only decrypted buffer cannot cancel an opened memory', () async {
    final harness = await _VaultHarness.create(readOnlyPlaintext: true);

    final memory = await harness.controller.open(harness.metadata);

    expect(memory, isA<OpenedMemory>());
    expect((memory as OpenedMemory).payload.text, 'Only in memory');
  });

  test('corrupt payload becomes unavailable without partial content', () async {
    final harness = await _VaultHarness.create(corruptTag: true);

    final memory = await harness.controller.open(harness.metadata);

    expect(memory, isA<UnavailableMemory>());
    expect(
      (memory as UnavailableMemory).message,
      'This memory cannot be opened safely.',
    );
  });

  test('missing key and invalid blob refs fail closed', () async {
    final missingKey = await _VaultHarness.create(missingKey: true);
    final invalidRef = await _VaultHarness.create();

    expect(
      await missingKey.controller.open(missingKey.metadata),
      isA<UnavailableMemory>(),
    );
    expect(
      await invalidRef.controller.open(
        invalidRef.metadata.copyWith(blobRef: '../plaintext.txt'),
      ),
      isA<UnavailableMemory>(),
    );
    expect(invalidRef.resolvedReferences, ['../plaintext.txt']);
  });

  test('authenticated payload format mismatch exposes no content', () async {
    final harness = await _VaultHarness.create(payloadFormatMismatch: true);

    final memory = await harness.controller.open(harness.metadata);

    expect(memory, isA<UnavailableMemory>());
  });

  test(
    'photo preview uses the derived bounded read and clears its envelope',
    () async {
      final source = Uint8List.fromList([1, 2, 3]);
      final harness = await _VaultHarness.create(
        format: MemoryFormat.photo,
        primaryBytes: source,
      );

      final memory = await harness.controller.openPhotoPreview(
        harness.metadata,
        maxSourceBytes: source.lengthInBytes,
      );

      expect(memory, isA<OpenedMemory>());
      expect((memory as OpenedMemory).payload.primaryBytes, source);
      expect(harness.boundedReadLimits, [
        EntryCipher.maxEnvelopeBytesForPlaintext(
          EntryPayloadCodec.maxEncodedPayloadBytesForPrimary(
            source.lengthInBytes,
          ),
        ),
      ]);
      expect(harness.boundedEnvelopeBuffers.single, everyElement(0));
      expect(harness.cipher.lastPlaintext, everyElement(0));
    },
  );

  test(
    'photo preview rejects an oversized source while generic open remains',
    () async {
      final source = Uint8List.fromList([1, 2, 3]);
      final harness = await _VaultHarness.create(
        format: MemoryFormat.photo,
        primaryBytes: source,
      );

      expect(
        await harness.controller.openPhotoPreview(
          harness.metadata,
          maxSourceBytes: source.lengthInBytes - 1,
        ),
        isA<UnavailableMemory>(),
      );

      final generic = await harness.controller.open(harness.metadata);
      expect(generic, isA<OpenedMemory>());
      expect((generic as OpenedMemory).payload.primaryBytes, source);
      expect(harness.boundedReadLimits, hasLength(1));
    },
  );

  test('photo preview clears decoded primary on format mismatch', () async {
    final harness = await _VaultHarness.create(
      format: MemoryFormat.photo,
      payloadFormatOverride: MemoryFormat.voice,
    );

    expect(
      await harness.controller.openPhotoPreview(
        harness.metadata,
        maxSourceBytes: 3,
      ),
      isA<UnavailableMemory>(),
    );
    expect(harness.codec.lastDecodedPayload!.primaryBytes, everyElement(0));
    expect(harness.boundedEnvelopeBuffers.single, everyElement(0));
  });

  test('photo preview clears its envelope when decryption fails', () async {
    final harness = await _VaultHarness.create(
      format: MemoryFormat.photo,
      primaryBytes: Uint8List.fromList([1]),
      corruptTag: true,
    );

    expect(
      await harness.controller.openPhotoPreview(
        harness.metadata,
        maxSourceBytes: 1,
      ),
      isA<UnavailableMemory>(),
    );
    expect(harness.boundedEnvelopeBuffers.single, everyElement(0));
  });

  test(
    'photo preview rejects and clears an over-limit returned envelope',
    () async {
      final harness = await _VaultHarness.create(
        format: MemoryFormat.photo,
        primaryBytes: Uint8List.fromList([1]),
        returnOversizedBoundedEnvelope: true,
      );

      expect(
        await harness.controller.openPhotoPreview(
          harness.metadata,
          maxSourceBytes: 1,
        ),
        isA<UnavailableMemory>(),
      );
      expect(harness.boundedEnvelopeBuffers.single, everyElement(0));
    },
  );

  test('photo preview fails closed before reads for non-kept media', () async {
    final harness = await _VaultHarness.create(
      format: MemoryFormat.photo,
      primaryBytes: Uint8List.fromList([1]),
    );

    for (final metadata in [
      harness.metadata.copyWith(state: 'pending'),
      harness.metadata.copyWith(format: MemoryFormat.voice),
    ]) {
      expect(
        await harness.controller.openPhotoPreview(metadata, maxSourceBytes: 1),
        isA<UnavailableMemory>(),
      );
    }
    expect(harness.resolvedReferences, isEmpty);
    expect(harness.boundedReadLimits, isEmpty);
  });

  test('expired released memory fails closed before blob access', () async {
    final harness = await _VaultHarness.create(now: DateTime.utc(2026, 10, 8));

    final memory = await harness.controller.open(
      harness.metadata.copyWith(
        state: 'revealed',
        expiresAt: DateTime.utc(2026, 10, 7),
      ),
    );

    expect(memory, isA<UnavailableMemory>());
    expect(harness.resolvedReferences, isEmpty);
  });
}

final class _VaultHarness {
  _VaultHarness({
    required this.controller,
    required this.metadata,
    required this.resolvedReferences,
    required this.boundedReadLimits,
    required this.boundedEnvelopeBuffers,
    required this.cipher,
    required this.codec,
  });

  final VaultController controller;
  final VaultEntryMetadata metadata;
  final List<String> resolvedReferences;
  final List<int> boundedReadLimits;
  final List<Uint8List> boundedEnvelopeBuffers;
  final _RecordingEntryCipher cipher;
  final _RecordingEntryPayloadCodec codec;

  static Future<_VaultHarness> create({
    bool corruptTag = false,
    bool missingKey = false,
    bool payloadFormatMismatch = false,
    MemoryFormat format = MemoryFormat.text,
    MemoryFormat? payloadFormatOverride,
    Uint8List? primaryBytes,
    bool returnOversizedBoundedEnvelope = false,
    bool readOnlyPlaintext = false,
    DateTime? now,
  }) async {
    const identity = LocalIdentity(
      familyId: 'family-1',
      familyName: 'Sabati',
      familyKeyRef: 'family-key',
      memberId: 'member-1',
      memberName: 'Chris',
      memberKeyRef: 'member-key',
      colorToken: 'ochre',
      avatar: AvatarConfig.defaults(seed: 'member-1'),
    );
    final metadata = VaultEntryMetadata(
      id: 'entry-1',
      familyId: 'family-1',
      authorId: 'member-1',
      createdAt: DateTime.utc(2026, 9, 1),
      format: format,
      privacy: PrivacyTier.reveal,
      blobRef: 'entries/blobs/entry-1.keeper',
      state: format == MemoryFormat.photo ? 'kept' : 'pending',
    );
    final key = List<int>.filled(32, 7);
    final secureValues = _MemorySecureValueStore({
      if (!missingKey) 'family-key': base64UrlEncode(key),
      'member-key': base64UrlEncode(List<int>.filled(32, 8)),
    });
    final cipher = _RecordingEntryCipher(readOnlyPlaintext: readOnlyPlaintext);
    final codec = _RecordingEntryPayloadCodec();
    final payloadFormat =
        payloadFormatOverride ??
        (payloadFormatMismatch ? MemoryFormat.photo : format);
    final mediaPrimary =
        primaryBytes ??
        (payloadFormat == MemoryFormat.text
            ? null
            : Uint8List.fromList([1, 2, 3]));
    final payload = EntryPayload(
      format: payloadFormat,
      primaryBytes: mediaPrimary,
      text: payloadFormat == MemoryFormat.text ? 'Only in memory' : null,
      caption: null,
      mediaExtension: switch (payloadFormat) {
        MemoryFormat.photo => 'jpg',
        MemoryFormat.voice => 'm4a',
        MemoryFormat.text => null,
      },
      mediaDurationMs: payloadFormat == MemoryFormat.voice ? 1000 : null,
    );
    final encrypted = await cipher.encrypt(
      plaintext: codec.encode(payload),
      keyBytes: key,
      metadata: metadata.toEntryMetadata(),
      keyScope: EntryKeyScope.family,
    );
    final storedBytes = corruptTag ? _corruptTag(encrypted) : encrypted;
    final resolvedReferences = <String>[];
    final boundedReadLimits = <int>[];
    final boundedEnvelopeBuffers = <Uint8List>[];
    final controller = VaultController(
      identity: identity,
      keyResolver: EntryKeyResolver(IdentityKeyService(secureValues)),
      cipher: cipher,
      codec: codec,
      utcNow: () => now ?? DateTime.utc(2026, 9, 1),
      readEncryptedBlob: (relativeRef) async {
        resolvedReferences.add(relativeRef);
        if (relativeRef != 'entries/blobs/entry-1.keeper') {
          throw ArgumentError.value(relativeRef, 'relativeRef');
        }
        return Uint8List.fromList(storedBytes);
      },
      readEncryptedBlobBounded: (relativeRef, {required maxBytes}) async {
        resolvedReferences.add(relativeRef);
        boundedReadLimits.add(maxBytes);
        if (relativeRef != 'entries/blobs/entry-1.keeper') {
          throw ArgumentError.value(relativeRef, 'relativeRef');
        }
        final bytes = returnOversizedBoundedEnvelope
            ? Uint8List(maxBytes + 1)
            : Uint8List.fromList(storedBytes);
        boundedEnvelopeBuffers.add(bytes);
        return bytes;
      },
    );
    return _VaultHarness(
      controller: controller,
      metadata: metadata,
      resolvedReferences: resolvedReferences,
      boundedReadLimits: boundedReadLimits,
      boundedEnvelopeBuffers: boundedEnvelopeBuffers,
      cipher: cipher,
      codec: codec,
    );
  }
}

final class _RecordingEntryCipher extends EntryCipher {
  _RecordingEntryCipher({this.readOnlyPlaintext = false})
    : super(
        nonceFactory: () =>
            Uint8List.fromList(List<int>.generate(12, (index) => index)),
      );

  final bool readOnlyPlaintext;
  Uint8List? lastPlaintext;

  @override
  Future<Uint8List> decrypt({
    required Uint8List envelopeBytes,
    required List<int> keyBytes,
    required EntryMetadata metadata,
    int? maxPlaintextBytes,
  }) async {
    final plaintext = await super.decrypt(
      envelopeBytes: envelopeBytes,
      keyBytes: keyBytes,
      metadata: metadata,
      maxPlaintextBytes: maxPlaintextBytes,
    );
    final returned = readOnlyPlaintext
        ? plaintext.asUnmodifiableView()
        : plaintext;
    lastPlaintext = returned;
    return returned;
  }
}

final class _RecordingEntryPayloadCodec extends EntryPayloadCodec {
  EntryPayload? lastDecodedPayload;

  @override
  EntryPayload decode(Uint8List bytes, {int? maxPrimaryBytes}) {
    final payload = super.decode(bytes, maxPrimaryBytes: maxPrimaryBytes);
    lastDecodedPayload = payload;
    return payload;
  }
}

Uint8List _corruptTag(Uint8List encrypted) {
  final envelope = jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
  final tag = base64Url.decode(base64Url.normalize(envelope['tag'] as String));
  tag[0] ^= 1;
  envelope['tag'] = base64UrlEncode(tag).replaceAll('=', '');
  return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
}

final class _MemorySecureValueStore implements SecureValueStore {
  _MemorySecureValueStore(this.values);

  final Map<String, String> values;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
