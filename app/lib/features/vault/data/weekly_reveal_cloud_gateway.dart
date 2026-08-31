import 'dart:typed_data';

import 'package:keepers/features/capture/domain/capture_models.dart';

/// Opaque, family-key-encrypted Weekly Reveal entry advertised by the cloud.
///
/// The cloud receives routing metadata and ciphertext only. Captions, text,
/// photos, and audio are decrypted exclusively on family devices.
final class RemoteWeeklyRevealEntry {
  const RemoteWeeklyRevealEntry({
    required this.metadata,
    required this.storagePath,
    required this.blobSha256,
    required this.blobBytes,
    required this.state,
  });

  final EntryMetadata metadata;
  final String storagePath;
  final String blobSha256;
  final int blobBytes;
  final String state;
}

/// Optional capability exposed by a configured family cloud gateway.
abstract interface class WeeklyRevealCloudGateway {
  Future<void> publish(EntryMetadata metadata, Uint8List encryptedBlob);

  Future<List<RemoteWeeklyRevealEntry>> list(String familyId);

  Future<Uint8List> download(RemoteWeeklyRevealEntry entry);

  Stream<void> watch(String familyId);
}
