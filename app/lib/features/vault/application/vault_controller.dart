import 'dart:typed_data';

import 'package:keepers/features/capture/data/entry_cipher.dart';
import 'package:keepers/features/capture/data/entry_key_resolver.dart';
import 'package:keepers/features/capture/data/entry_payload_codec.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';

typedef EncryptedBlobReader = Future<Uint8List> Function(String relativeRef);
typedef BoundedEncryptedBlobReader = Future<Uint8List> Function(
  String relativeRef, {
  required int maxBytes,
});

final class VaultController {
  const VaultController({
    required this.identity,
    required this.keyResolver,
    required this.cipher,
    required this.codec,
    required this.readEncryptedBlob,
    required this.readEncryptedBlobBounded,
    DateTime Function()? utcNow,
  }) : utcNow = utcNow ?? _systemUtcNow;

  static const unavailableMessage = 'This memory cannot be opened safely.';

  final LocalIdentity identity;
  final EntryKeyResolver keyResolver;
  final EntryCipher cipher;
  final EntryPayloadCodec codec;
  final EncryptedBlobReader readEncryptedBlob;
  final BoundedEncryptedBlobReader readEncryptedBlobBounded;
  final DateTime Function() utcNow;

  Future<MemoryOpenResult> open(VaultEntryMetadata metadata) => _open(metadata);

  Future<MemoryOpenResult> openPhotoPreview(
    VaultEntryMetadata metadata, {
    required int maxSourceBytes,
  }) => _open(metadata, maxSourceBytes: maxSourceBytes);

  Future<MemoryOpenResult> _open(
    VaultEntryMetadata metadata, {
    int? maxSourceBytes,
  }) async {
    Uint8List? envelope;
    Uint8List? plaintext;
    EntryPayload? payload;
    var payloadTransferred = false;
    try {
      if (maxSourceBytes != null) {
        RangeError.checkNotNegative(maxSourceBytes, 'maxSourceBytes');
        if (metadata.state != 'kept' || metadata.format != MemoryFormat.photo) {
          throw const FormatException(
            'Only kept photo memories can provide archive previews',
          );
        }
      }
      if (metadata.familyId != identity.familyId) {
        throw const FormatException('Entry is outside the local family');
      }
      final expiresAt = metadata.expiresAt;
      if (metadata.state == 'expired' ||
          (expiresAt != null && !expiresAt.toUtc().isAfter(utcNow().toUtc()))) {
        throw const FormatException('Entry has expired');
      }
      final key = await keyResolver.resolve(metadata.privacy, identity);
      int? maxPlaintextBytes;
      if (maxSourceBytes == null) {
        envelope = await readEncryptedBlob(metadata.blobRef);
      } else {
        maxPlaintextBytes = EntryPayloadCodec.maxEncodedPayloadBytesForPrimary(
          maxSourceBytes,
        );
        final maxEnvelopeBytes = EntryCipher.maxEnvelopeBytesForPlaintext(
          maxPlaintextBytes,
        );
        envelope = await readEncryptedBlobBounded(
          metadata.blobRef,
          maxBytes: maxEnvelopeBytes,
        );
        if (envelope.lengthInBytes > maxEnvelopeBytes) {
          throw const FormatException(
            'Entry envelope exceeds archive preview limit',
          );
        }
      }
      plaintext = await cipher.decrypt(
        envelopeBytes: envelope,
        keyBytes: key.bytes,
        metadata: metadata.toEntryMetadata(),
        maxPlaintextBytes: maxPlaintextBytes,
      );
      if (maxPlaintextBytes != null &&
          plaintext.lengthInBytes > maxPlaintextBytes) {
        throw const FormatException(
          'Entry plaintext exceeds archive preview limit',
        );
      }
      payload = codec.decode(plaintext, maxPrimaryBytes: maxSourceBytes);
      if (payload.format != metadata.format) {
        throw const FormatException('Payload format does not match metadata');
      }
      if (maxSourceBytes != null) {
        final primary = payload.primaryBytes;
        if (primary == null ||
            primary.isEmpty ||
            primary.lengthInBytes > maxSourceBytes) {
          throw const FormatException(
            'Entry primary exceeds archive preview limit',
          );
        }
      }
      payloadTransferred = true;
      return OpenedMemory(metadata: metadata, payload: payload);
    } on Object {
      return const UnavailableMemory(unavailableMessage);
    } finally {
      if (maxSourceBytes != null) {
        _clearBytesBestEffort(envelope);
      }
      _clearBytesBestEffort(plaintext);
      if (!payloadTransferred) {
        _clearBytesBestEffort(payload?.primaryBytes);
      }
    }
  }
}

void _clearBytesBestEffort(Uint8List? bytes) {
  if (bytes == null) return;
  try {
    bytes.fillRange(0, bytes.lengthInBytes, 0);
  } on UnsupportedError {
    // Some platform cryptography implementations return a read-only view.
    // Cleanup must never override the authenticated open result.
  }
}

DateTime _systemUtcNow() => DateTime.now().toUtc();
