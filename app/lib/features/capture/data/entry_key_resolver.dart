import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';

final class ResolvedEntryKey {
  ResolvedEntryKey(this.scope, List<int> bytes)
    : bytes = List<int>.unmodifiable(bytes);

  final EntryKeyScope scope;
  final List<int> bytes;
}

class EntryKeyResolver {
  EntryKeyResolver(this.identityKeys);

  final IdentityKeyService identityKeys;

  Future<ResolvedEntryKey> resolve(
    PrivacyTier privacy,
    LocalIdentity identity,
  ) async {
    final (scope, reference) = switch (privacy) {
      PrivacyTier.journal => (EntryKeyScope.member, identity.memberKeyRef),
      PrivacyTier.reveal ||
      PrivacyTier.capsule => (EntryKeyScope.family, identity.familyKeyRef),
    };
    return ResolvedEntryKey(scope, await identityKeys.resolve(reference));
  }
}
