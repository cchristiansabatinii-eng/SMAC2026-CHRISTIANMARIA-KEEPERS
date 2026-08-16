import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/data/family_roster_repository.dart';
import 'package:keepers/features/family/data/joined_family_installer.dart';
import 'package:keepers/features/onboarding/data/family_repository.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/data/member_repository.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:uuid/uuid.dart';

export 'package:keepers/features/onboarding/application/setup_controller.dart';

final familyRepositoryProvider = Provider((ref) => FamilyRepository());

final memberRepositoryProvider = Provider((ref) => MemberRepository());

final familyRosterRepositoryProvider = Provider(
  (ref) => FamilyRosterRepository(),
);

final identityKeyServiceProvider = Provider(
  (ref) => IdentityKeyService(ref.watch(secureValueStoreProvider)),
);

final joinedFamilyInstallerProvider = Provider<JoinedFamilyInstaller>(
  (ref) => LocalJoinedFamilyInstaller(
    () => ref.read(databaseProvider.future),
    ref.watch(identityKeyServiceProvider),
    ref.watch(memberRepositoryProvider),
    ref.watch(familyRosterRepositoryProvider),
  ),
);

final idFactoryProvider = Provider<String Function()>((ref) => const Uuid().v4);

final utcNowProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

final localIdentityProvider = FutureProvider<LocalIdentity?>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ref.watch(memberRepositoryProvider).findLocalIdentity(db);
});
