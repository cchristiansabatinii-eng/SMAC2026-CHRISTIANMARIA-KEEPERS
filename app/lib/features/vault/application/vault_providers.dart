import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/capture/application/capture_providers.dart';
import 'package:keepers/features/capture/data/entry_cipher.dart';
import 'package:keepers/features/capture/data/entry_key_resolver.dart';
import 'package:keepers/features/capture/data/entry_payload_codec.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/vault/application/vault_controller.dart';
import 'package:keepers/features/vault/data/vault_repository.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/storage/database_providers.dart';

final vaultRepositoryProvider = Provider<VaultRepository>(
  (ref) => VaultRepository(),
);

final vaultEntriesProvider = FutureProvider<List<VaultEntryMetadata>>((
  ref,
) async {
  final identity = await ref.watch(localIdentityProvider.future);
  if (identity == null) return const [];
  final database = await ref.watch(databaseProvider.future);
  return ref
      .watch(vaultRepositoryProvider)
      .listForFamily(database, identity.familyId);
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
  );
});
