import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/data/approved_family_join_installer.dart';
import 'package:keepers/features/family/data/family_code_cache_repository.dart';
import 'package:keepers/features/family/data/family_code_codec.dart';
import 'package:keepers/features/family/data/family_join_envelope_codec.dart';
import 'package:keepers/features/family/data/joining_key_store.dart';
import 'package:keepers/features/family/data/pending_family_code_store.dart';
import 'package:keepers/features/family/data/pending_join_completion_repository.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/storage/database_providers.dart';

final familyCodeCodecProvider = Provider<FamilyCodeCodec>(
  (ref) => CryptographicFamilyCodeCodec(),
);

final familyCodeCacheRepositoryProvider = Provider<FamilyCodeCacheRepository>(
  (ref) => const FamilyCodeCacheRepository(),
);

final joiningKeyStoreProvider = Provider<JoiningKeyStore>(
  (ref) => SecureJoiningKeyStore(ref.watch(secureValueStoreProvider)),
);

final pendingFamilyCodeStoreProvider = Provider<PendingFamilyCodeStore>(
  (ref) => SecurePendingFamilyCodeStore(ref.watch(secureValueStoreProvider)),
);

final familyJoinEnvelopeCodecProvider = Provider<FamilyJoinEnvelopeCodec>(
  (ref) => CryptographicFamilyJoinEnvelopeCodec(),
);

final pendingJoinCompletionRepositoryProvider =
    Provider<PendingJoinCompletionRepository>(
      (ref) => const PendingJoinCompletionRepository(),
    );

final approvedFamilyJoinInstallerProvider =
    Provider<ApprovedFamilyJoinInstaller>(
      (ref) => LocalApprovedFamilyJoinInstaller(
        () => ref.read(databaseProvider.future),
        ref.watch(identityKeyServiceProvider),
        ref.watch(memberRepositoryProvider),
        ref.watch(familyRosterRepositoryProvider),
        pendingCompletions: ref.watch(pendingJoinCompletionRepositoryProvider),
      ),
    );
