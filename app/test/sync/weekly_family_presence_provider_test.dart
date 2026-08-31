import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/sync/weekly_family_presence_provider.dart';

void main() {
  test('fresh observations expose normalized nearby family member IDs', () {
    final now = DateTime.utc(2026, 9, 8, 12);
    final snapshot = WeeklyFamilyPresenceSnapshot.observed(
      nearbyMemberIds: const [' noura ', 'noura', '', 'mariam'],
      observedAt: now.subtract(const Duration(seconds: 4)),
    );

    expect(snapshot.trustedNearbyMemberIds(at: now), {'noura', 'mariam'});
  });

  test('stale, future, and unavailable observations fail closed', () {
    final now = DateTime.utc(2026, 9, 8, 12);

    expect(
      WeeklyFamilyPresenceSnapshot.observed(
        nearbyMemberIds: const ['noura'],
        observedAt: now.subtract(
          weeklyFamilyPresenceFreshness + const Duration(milliseconds: 1),
        ),
      ).trustedNearbyMemberIds(at: now),
      isEmpty,
    );
    expect(
      WeeklyFamilyPresenceSnapshot.observed(
        nearbyMemberIds: const ['noura'],
        observedAt: now.add(const Duration(seconds: 1)),
      ).trustedNearbyMemberIds(at: now),
      isEmpty,
    );
    expect(
      const WeeklyFamilyPresenceSnapshot.unavailable().trustedNearbyMemberIds(
        at: now,
      ),
      isEmpty,
    );
  });

  test('per-member observations expire independently', () {
    final now = DateTime.utc(2026, 9, 8, 12);
    final snapshot = WeeklyFamilyPresenceSnapshot.observedMembers(
      memberLastSeenAt: {
        'noura': now.subtract(const Duration(seconds: 16)),
        'mariam': now.subtract(const Duration(seconds: 4)),
        'future': now.add(const Duration(seconds: 1)),
      },
    );

    expect(snapshot.trustedNearbyMemberIds(at: now), {'mariam'});
    expect(
      snapshot.nextExpiryAt(at: now),
      now.add(const Duration(seconds: 11, milliseconds: 1)),
    );
  });

  test('per-member observations normalize IDs and keep newest duplicate', () {
    final now = DateTime.utc(2026, 9, 8, 12);
    final snapshot = WeeklyFamilyPresenceSnapshot.observedMembers(
      memberLastSeenAt: {
        ' noura ': now.subtract(const Duration(seconds: 9)),
        'noura': now.subtract(const Duration(seconds: 2)),
        '': now,
      },
    );

    expect(snapshot.memberLastSeenAt, {
      'noura': now.subtract(const Duration(seconds: 2)),
    });
    expect(snapshot.nearbyMemberIds, {'noura'});
    expect(snapshot.observedAt, now.subtract(const Duration(seconds: 2)));
  });
}
