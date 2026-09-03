import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/data/weekly_reveal_cloud_gateway.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';

typedef ListLocalWeeklyEntries = Future<List<VaultEntryMetadata>> Function(
  String familyId,
);
typedef ReadLocalWeeklyBlob = Future<Uint8List> Function(
  String blobRef, {
  required int maxBytes,
});
typedef ImportRemoteWeeklyEntry = Future<void> Function(
  RemoteWeeklyRevealEntry entry,
  Uint8List bytes,
);

/// Reconciles this device's opaque Weekly Reveal ciphertext with the family
/// relay. Every operation is idempotent by entry ID and transport failures
/// leave the device-local encrypted memory untouched for a later retry.
final class WeeklyRevealSyncService {
  const WeeklyRevealSyncService({
    required this.cloud,
    required this.listLocal,
    required this.readLocalBlob,
    required this.importRemote,
  });

  final WeeklyRevealCloudGateway cloud;
  final ListLocalWeeklyEntries listLocal;
  final ReadLocalWeeklyBlob readLocalBlob;
  final ImportRemoteWeeklyEntry importRemote;

  Future<void> synchronize(LocalIdentity identity) async {
    final local = await listLocal(identity.familyId);

    List<RemoteWeeklyRevealEntry> remote;
    try {
      remote = await cloud.list(identity.familyId);
    } on Object {
      return;
    }

    final remoteIds = {
      for (final entry in remote)
        if (_isImportable(entry, identity.familyId)) entry.metadata.id,
    };
    var published = false;

    for (final entry in local) {
      if (!_isPublishableBy(entry, identity) || remoteIds.contains(entry.id)) {
        continue;
      }
      try {
        final encrypted = await readLocalBlob(
          entry.blobRef,
          maxBytes: maximumWeeklyRevealBlobBytes,
        );
        await cloud.publish(entry.toEntryMetadata(), encrypted);
        remoteIds.add(entry.id);
        published = true;
      } on Object {
        // Local durability is authoritative. A later provider refresh retries
        // the exact idempotent upload without changing capture success.
      }
    }

    if (published) {
      try {
        remote = await cloud.list(identity.familyId);
      } on Object {
        // The initial manifest is still safe to reconcile. The newly uploaded
        // entry already exists locally and will appear on other devices once
        // their next manifest request succeeds.
      }
    }

    final localIds = local.map((entry) => entry.id).toSet();
    for (final entry in remote) {
      if (localIds.contains(entry.metadata.id) ||
          !_isImportable(entry, identity.familyId)) {
        continue;
      }
      try {
        final encrypted = await cloud.download(entry);
        if (encrypted.lengthInBytes != entry.blobBytes ||
            await _sha256(encrypted) != entry.blobSha256) {
          continue;
        }
        await importRemote(entry, encrypted);
        localIds.add(entry.metadata.id);
      } on Object {
        // One malformed, missing, or temporarily unavailable object must not
        // prevent the rest of the family manifest from converging.
      }
    }
  }

  bool _isPublishableBy(VaultEntryMetadata entry, LocalIdentity identity) =>
      entry.familyId == identity.familyId &&
      entry.authorId == identity.memberId &&
      entry.privacy == PrivacyTier.reveal &&
      entry.state == 'pending';

  bool _isImportable(RemoteWeeklyRevealEntry entry, String familyId) =>
      entry.metadata.familyId == familyId &&
      entry.metadata.privacy == PrivacyTier.reveal &&
      entry.state == 'pending' &&
      entry.blobBytes > 0 &&
      RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(entry.blobSha256);

  Future<String> _sha256(Uint8List bytes) async =>
      base64UrlEncode((await Sha256().hash(bytes)).bytes).replaceAll('=', '');
}
