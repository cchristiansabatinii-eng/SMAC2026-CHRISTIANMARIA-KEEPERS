import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/capture/application/capture_providers.dart';
import 'package:keepers/features/capture/data/encrypted_blob_store.dart';
import 'package:keepers/features/capture/data/entry_cipher.dart';
import 'package:keepers/features/capture/data/entry_key_resolver.dart';
import 'package:keepers/features/capture/data/entry_payload_codec.dart';
import 'package:keepers/features/capture/data/entry_repository.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/vault/application/vault_controller.dart';
import 'package:keepers/features/vault/data/vault_repository.dart';
import 'package:keepers/features/vault/data/weekly_reveal_cloud_gateway.dart';
import 'package:keepers/features/vault/data/weekly_reveal_sync_service.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

final vaultRepositoryProvider = Provider<VaultRepository>(
  (ref) => VaultRepository(),
);

final _weeklyRevealSyncGateProvider = Provider<_WeeklyRevealSyncGate>(
  (_) => _WeeklyRevealSyncGate(),
);

final vaultEntriesProvider = FutureProvider<List<VaultEntryMetadata>>((
  ref,
) async {
  final identity = await ref.watch(localIdentityProvider.future);
  if (identity == null) return const [];
  // A roster refresh can make a newly joined author's foreign-key row
  // available, so it is also a reason to retry a previously deferred import.
  ref.watch(familyRosterProvider(identity.familyId));
  final database = await ref.watch(databaseProvider.future);
  final repository = ref.watch(vaultRepositoryProvider);
  final cloudFamily = ref.watch(cloudFamilyGatewayProvider);
  if (cloudFamily case WeeklyRevealCloudGateway cloud) {
    final subscription = cloud.watch(identity.familyId).listen((_) {
      if (ref.mounted) ref.invalidateSelf();
    });
    ref.onDispose(subscription.cancel);
    final blobStore = await ref.watch(entryBlobStoreProvider.future);
    final service = WeeklyRevealSyncService(
      cloud: cloud,
      listLocal: (familyId) => repository.listForFamily(database, familyId),
      readLocalBlob: blobStore.read,
      importRemote: (entry, bytes) => _importRemoteWeeklyReveal(
        database: database,
        repository: repository,
        blobStore: blobStore,
        remote: entry,
        bytes: bytes,
      ),
    );
    await ref
        .watch(_weeklyRevealSyncGateProvider)
        .run(() => service.synchronize(identity));
  }
  return repository.listForFamily(database, identity.familyId);
});

final vaultControllerProvider = FutureProvider<VaultController>((ref) async {
  final identity = await ref.watch(localIdentityProvider.future);
  if (identity == null) {
    throw StateError('A local identity is required to open the vault');
  }
  final blobStore = await ref.watch(entryBlobStoreProvider.future);
  return VaultController(
    identity: identity,
    keyResolver: EntryKeyResolver(ref.watch(identityKeyServiceProvider)),
    cipher: EntryCipher(),
    codec: const EntryPayloadCodec(),
    readEncryptedBlob: blobStore.read,
    readEncryptedBlobBounded: (relativeRef, {required maxBytes}) =>
        blobStore.read(relativeRef, maxBytes: maxBytes),
  );
});

Future<void> _importRemoteWeeklyReveal({
  required Database database,
  required VaultRepository repository,
  required EncryptedBlobStore blobStore,
  required RemoteWeeklyRevealEntry remote,
  required Uint8List bytes,
}) async {
  final metadata = remote.metadata;
  final existing = await repository.findByIdForFamily(
    database,
    entryId: metadata.id,
    familyId: metadata.familyId,
  );
  if (existing != null) return;

  final relativeRef = p.join('entries', 'blobs', '${metadata.id}.keeper');
  if (await blobStore.exists(relativeRef)) {
    final existingBytes = await blobStore.read(
      relativeRef,
      maxBytes: remote.blobBytes,
    );
    if (!_sameBytes(existingBytes, bytes)) {
      throw StateError(
        'A different encrypted blob already uses this entry ID.',
      );
    }
    await EntryRepository().insert(database, metadata, relativeRef);
    return;
  }

  final staged = await blobStore.stage(metadata.id, bytes);
  final finalized = await blobStore.finalize(staged);
  try {
    await EntryRepository().insert(database, metadata, finalized.relativeRef);
  } on Object {
    await blobStore.rollback(finalized);
    rethrow;
  }
}

bool _sameBytes(Uint8List left, Uint8List right) {
  if (left.lengthInBytes != right.lengthInBytes) return false;
  var difference = 0;
  for (var index = 0; index < left.lengthInBytes; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

final class _WeeklyRevealSyncGate {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
