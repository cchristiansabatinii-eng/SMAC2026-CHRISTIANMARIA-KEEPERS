import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/sync/weekly_family_presence_provider.dart';
import 'package:keepers/sync/weekly_presence_session.dart';
import 'package:keepers/sync/weekly_presence_token_codec.dart';

void main() {
  test(
    'provider bridges a scoped radio session into trusted attendance',
    () async {
      final now = DateTime.utc(2026, 9, 8, 12);
      final familyKey = List<int>.generate(32, (index) => index);
      final radio = _FakeRadio();
      final container = ProviderContainer(
        overrides: [
          weeklyPresenceRadioProvider.overrideWithValue(radio),
          weeklyPresenceFamilyKeyResolverProvider.overrideWithValue((
            reference,
          ) async {
            expect(reference, 'family-key');
            return List<int>.from(familyKey);
          }),
          utcNowProvider.overrideWithValue(() => now),
        ],
      );
      final subscription = container.listen(
        weeklyFamilyPresenceProvider(_identity.familyId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
      });

      final actions = container.read(
        weeklyFamilyPresenceSessionActionsProvider(_identity.familyId),
      );
      await actions.start(
        identity: _identity,
        rosterMemberIds: const {'member-a', 'member-b'},
      );

      final codec = WeeklyPresenceTokenCodec();
      final memberBUuid = codec.serviceUuid(
        familyKey: familyKey,
        familyId: _identity.familyId,
        memberId: 'member-b',
        slot: codec.slotFor(now),
      );
      radio.handle.emit({memberBUuid});
      await Future<void>.delayed(Duration.zero);

      expect(
        container
            .read(weeklyFamilyPresenceProvider(_identity.familyId))
            .trustedNearbyMemberIds(at: now),
        {'member-b'},
      );

      await actions.stop();
      expect(
        container
            .read(weeklyFamilyPresenceProvider(_identity.familyId))
            .trustedNearbyMemberIds(at: now),
        isEmpty,
      );
      expect(radio.handle.stopCalls, 1);
    },
  );
}

const _identity = LocalIdentity(
  familyId: 'family-1',
  familyName: 'The Family',
  familyKeyRef: 'family-key',
  memberId: 'member-a',
  memberName: 'Alex',
  memberKeyRef: 'member-key',
  colorToken: 'amber',
  avatar: AvatarConfig.defaults(seed: 'member-a'),
);

final class _FakeRadio implements WeeklyPresenceRadio {
  final handle = _FakeHandle();

  @override
  Future<WeeklyPresenceRadioHandle> open({required String serviceUuid}) async {
    expect(serviceUuid, isNotEmpty);
    return handle;
  }
}

final class _FakeHandle implements WeeklyPresenceRadioHandle {
  final _advertisements =
      StreamController<WeeklyPresenceAdvertisement>.broadcast(sync: true);
  final _statuses = StreamController<WeeklyPresenceRadioStatus>.broadcast(
    sync: true,
  );
  var stopCalls = 0;

  @override
  Stream<WeeklyPresenceAdvertisement> get advertisements =>
      _advertisements.stream;

  @override
  WeeklyPresenceRadioStatus get initialStatus =>
      WeeklyPresenceRadioStatus.ready;

  @override
  Stream<WeeklyPresenceRadioStatus> get statuses => _statuses.stream;

  @override
  Future<void> stop() async => stopCalls += 1;

  @override
  Future<WeeklyPresenceRadioStatus> updateAdvertisement({
    required String serviceUuid,
  }) async => WeeklyPresenceRadioStatus.ready;

  void emit(Set<String> serviceUuids) => _advertisements.add(
    WeeklyPresenceAdvertisement(serviceUuids: serviceUuids),
  );
}
