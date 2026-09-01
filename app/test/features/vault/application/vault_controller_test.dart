import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/data/entry_cipher.dart';
import 'package:keepers/features/capture/data/entry_key_resolver.dart';
import 'package:keepers/features/capture/data/entry_payload_codec.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
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
}

final class _VaultHarness {
  _VaultHarness({
    required this.controller,
    required this.metadata,
    required this.resolvedReferences,
  });

  final VaultController controller;
  final VaultEntryMetadata metadata;
  final List<String> resolvedReferences;

  static Future<_VaultHarness> create({
    bool corruptTag = false,
    bool missingKey = false,
    bool payloadFormatMismatch = false,
  }) async {
    const identity = LocalIdentity(
      familyId: 'family-1',
      familyName: 'Sabati',
      familyKeyRef: 'family-key',
      memberId: 'member-1',
      memberName: 'Chris',
      memberKeyRef: 'member-key',
      colorToken: 'ochre',
    );
    final metadata = VaultEntryMetadata(
      id: 'entry-1',
      familyId: 'family-1',
      authorId: 'member-1',
      createdAt: DateTime.utc(2026, 9, 1),
      format: MemoryFormat.text,
      privacy: PrivacyTier.reveal,
      blobRef: 'entries/blobs/entry-1.keeper',
      state: 'pending',
    );
    final key = List<int>.filled(32, 7);
    final secureValues = _MemorySecureValueStore({
      if (!missingKey) 'family-key': base64UrlEncode(key),
      'member-key': base64UrlEncode(List<int>.filled(32, 8)),
    });
    final cipher = EntryCipher(
      nonceFactory: () => Uint8List.fromList(List<int>.generate(12, (i) => i)),
    );
    final codec = const EntryPayloadCodec();
    final payload = EntryPayload(
      format: payloadFormatMismatch ? MemoryFormat.photo : MemoryFormat.text,
      primaryBytes: payloadFormatMismatch
          ? Uint8List.fromList([1, 2, 3])
          : null,
      text: payloadFormatMismatch ? null : 'Only in memory',
      caption: null,
      mediaExtension: payloadFormatMismatch ? 'jpg' : null,
      mediaDurationMs: null,
    );
    final encrypted = await cipher.encrypt(
      plaintext: codec.encode(payload),
      keyBytes: key,
      metadata: metadata.toEntryMetadata(),
      keyScope: EntryKeyScope.family,
    );
    final storedBytes = corruptTag ? _corruptTag(encrypted) : encrypted;
    final resolvedReferences = <String>[];
    final controller = VaultController(
      identity: identity,
      keyResolver: EntryKeyResolver(IdentityKeyService(secureValues)),
      cipher: cipher,
      codec: codec,
      readEncryptedBlob: (relativeRef) async {
        resolvedReferences.add(relativeRef);
        if (relativeRef != 'entries/blobs/entry-1.keeper') {
          throw ArgumentError.value(relativeRef, 'relativeRef');
        }
        return Uint8List.fromList(storedBytes);
      },
    );
    return _VaultHarness(
      controller: controller,
      metadata: metadata,
      resolvedReferences: resolvedReferences,
    );
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
