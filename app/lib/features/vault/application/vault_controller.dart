import 'dart:typed_data';

import 'package:keepers/features/capture/data/entry_cipher.dart';
import 'package:keepers/features/capture/data/entry_key_resolver.dart';
import 'package:keepers/features/capture/data/entry_payload_codec.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';

typedef EncryptedBlobReader = Future<Uint8List> Function(String relativeRef);

final class VaultController {
  const VaultController({
    required this.identity,
    required this.keyResolver,
    required this.cipher,
    required this.codec,
    required this.readEncryptedBlob,
  });

  static const unavailableMessage = 'This memory cannot be opened safely.';

  final LocalIdentity identity;
  final EntryKeyResolver keyResolver;
  final EntryCipher cipher;
  final EntryPayloadCodec codec;
  final EncryptedBlobReader readEncryptedBlob;

  Future<MemoryOpenResult> open(VaultEntryMetadata metadata) async {
    Uint8List? plaintext;
    try {
      if (metadata.familyId != identity.familyId) {
        throw const FormatException('Entry is outside the local family');
      }
      final key = await keyResolver.resolve(metadata.privacy, identity);
      final envelope = await readEncryptedBlob(metadata.blobRef);
      plaintext = await cipher.decrypt(
        envelopeBytes: envelope,
        keyBytes: key.bytes,
        metadata: metadata.toEntryMetadata(),
      );
      final payload = codec.decode(plaintext);
      if (payload.format != metadata.format) {
        throw const FormatException('Payload format does not match metadata');
      }
      return OpenedMemory(metadata: metadata, payload: payload);
    } on Object {
      return const UnavailableMemory(unavailableMessage);
    } finally {
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }
}
