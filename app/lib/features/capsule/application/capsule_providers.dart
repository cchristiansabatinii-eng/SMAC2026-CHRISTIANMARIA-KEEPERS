import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/capsule/application/capsule_service.dart';
import 'package:keepers/features/capsule/domain/capsule_models.dart';
import 'package:keepers/features/capture/application/capture_providers.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/vault/application/vault_providers.dart';
import 'package:keepers/storage/database_providers.dart';

final capsuleAssignmentsProvider = FutureProvider<List<CapsuleAssignment>>((
  ref,
) async {
  final identity = await ref.watch(localIdentityProvider.future);
  if (identity == null) return const <CapsuleAssignment>[];
  final database = await ref.watch(databaseProvider.future);
  return ref
      .watch(capsuleRepositoryProvider)
      .listForMember(
        database,
        familyId: identity.familyId,
        memberId: identity.memberId,
      );
});

final capsuleServiceProvider = FutureProvider<CapsuleService>((ref) async {
  final identity = await ref.watch(localIdentityProvider.future);
  if (identity == null) {
    throw StateError('A local identity is required to open a Capsule');
  }
  final database = await ref.watch(databaseProvider.future);
  final vaultController = await ref.watch(vaultControllerProvider.future);
  return CapsuleService(
    database: database,
    identity: identity,
    capsuleRepository: ref.watch(capsuleRepositoryProvider),
    vaultRepository: ref.watch(vaultRepositoryProvider),
    openMemory: vaultController.open,
    utcNow: ref.watch(utcNowProvider),
  );
});
