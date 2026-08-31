import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/data/entry_key_resolver.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/database_key_store.dart';

void main() {
  test(
    'journal uses member key while reveal and Capsule use family key',
    () async {
      final store = _MemorySecureValueStore()
        ..values['family-key'] = base64UrlEncode(List<int>.filled(32, 7))
        ..values['member-key'] = base64UrlEncode(List<int>.filled(32, 9));
      final resolver = EntryKeyResolver(IdentityKeyService(store));

      final journal = await resolver.resolve(PrivacyTier.journal, _identity);
      final reveal = await resolver.resolve(PrivacyTier.reveal, _identity);
      final capsule = await resolver.resolve(PrivacyTier.capsule, _identity);

      expect(journal.scope, EntryKeyScope.member);
      expect(journal.bytes, List<int>.filled(32, 9));
      expect(reveal.scope, EntryKeyScope.family);
      expect(reveal.bytes, List<int>.filled(32, 7));
      expect(capsule.scope, EntryKeyScope.family);
      expect(capsule.bytes, List<int>.filled(32, 7));
      expect(store.readReferences, ['member-key', 'family-key', 'family-key']);
    },
  );

  test('missing routed key fails closed', () async {
    final resolver = EntryKeyResolver(
      IdentityKeyService(_MemorySecureValueStore()),
    );

    await expectLater(
      resolver.resolve(PrivacyTier.journal, _identity),
      throwsStateError,
    );
  });
}

const _identity = LocalIdentity(
  familyId: 'family-1',
  familyName: 'Keepers',
  familyKeyRef: 'family-key',
  memberId: 'member-1',
  memberName: 'Chris',
  memberKeyRef: 'member-key',
  colorToken: 'ochre',
  avatar: AvatarConfig.defaults(seed: 'member-1'),
);

final class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = {};
  final List<String> readReferences = [];

  @override
  Future<String?> read(String key) async {
    readReferences.add(key);
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
