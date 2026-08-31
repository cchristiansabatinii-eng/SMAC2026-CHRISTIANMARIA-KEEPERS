import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/sync/flutter_weekly_presence_radio.dart';
import 'package:keepers/sync/weekly_presence_session.dart';
import 'package:keepers/sync/weekly_presence_token_codec.dart';

/// A nearby signal must refresh within this interval to affect Weekly quorum.
const weeklyFamilyPresenceFreshness = weeklyPresenceFreshness;

/// The local-only handoff between device proximity and Weekly presentation.
///
/// The default is deliberately unavailable. A BLE or authenticated local
/// session adapter can override [weeklyFamilyPresenceProvider] with recent
/// observations; stale, future-dated, and missing observations expose nobody.
@immutable
final class WeeklyFamilyPresenceSnapshot {
  const WeeklyFamilyPresenceSnapshot.unavailable()
    : memberLastSeenAt = const {},
      observedAt = null;

  factory WeeklyFamilyPresenceSnapshot.observed({
    required Iterable<String> nearbyMemberIds,
    required DateTime observedAt,
  }) => WeeklyFamilyPresenceSnapshot.observedMembers(
    memberLastSeenAt: {for (final id in nearbyMemberIds) id: observedAt},
  );

  factory WeeklyFamilyPresenceSnapshot.observedMembers({
    required Map<String, DateTime> memberLastSeenAt,
  }) {
    final normalized = <String, DateTime>{};
    for (final entry in memberLastSeenAt.entries) {
      final memberId = entry.key.trim();
      if (memberId.isEmpty) continue;
      final lastSeenAt = entry.value.toUtc();
      final existing = normalized[memberId];
      if (existing == null || lastSeenAt.isAfter(existing)) {
        normalized[memberId] = lastSeenAt;
      }
    }
    DateTime? latest;
    for (final lastSeenAt in normalized.values) {
      if (latest == null || lastSeenAt.isAfter(latest)) latest = lastSeenAt;
    }
    return WeeklyFamilyPresenceSnapshot._(
      memberLastSeenAt: Map.unmodifiable(normalized),
      observedAt: latest,
    );
  }

  const WeeklyFamilyPresenceSnapshot._({
    required this.memberLastSeenAt,
    required this.observedAt,
  });

  final Map<String, DateTime> memberLastSeenAt;
  final DateTime? observedAt;

  Set<String> get nearbyMemberIds => Set.unmodifiable(memberLastSeenAt.keys);

  Set<String> trustedNearbyMemberIds({
    required DateTime at,
    Duration freshness = weeklyFamilyPresenceFreshness,
  }) {
    if (freshness.isNegative) return const {};
    final trusted = <String>{};
    final normalizedAt = at.toUtc();
    for (final entry in memberLastSeenAt.entries) {
      final age = normalizedAt.difference(entry.value);
      if (!age.isNegative && age <= freshness) trusted.add(entry.key);
    }
    return Set.unmodifiable(trusted);
  }

  DateTime? nextExpiryAt({
    required DateTime at,
    Duration freshness = weeklyFamilyPresenceFreshness,
  }) {
    if (freshness.isNegative) return null;
    final normalizedAt = at.toUtc();
    DateTime? next;
    for (final lastSeenAt in memberLastSeenAt.values) {
      final age = normalizedAt.difference(lastSeenAt);
      if (age.isNegative || age > freshness) continue;
      final expiresAt = lastSeenAt
          .add(freshness)
          .add(const Duration(milliseconds: 1));
      if (next == null || expiresAt.isBefore(next)) next = expiresAt;
    }
    return next;
  }
}

abstract interface class WeeklyFamilyPresenceSessionActions {
  Future<void> start({
    required LocalIdentity identity,
    required Iterable<String> rosterMemberIds,
  });

  Future<void> updateRoster(Iterable<String> rosterMemberIds);

  Future<void> stop();
}

final weeklyPresenceRadioProvider = Provider<WeeklyPresenceRadio>(
  (ref) => FlutterWeeklyPresenceRadio(),
);

final weeklyPresenceFamilyKeyResolverProvider =
    Provider<WeeklyPresenceFamilyKeyResolver>(
      (ref) => ref.watch(identityKeyServiceProvider).resolve,
    );

final _weeklyFamilyPresenceControllerProvider = NotifierProvider.autoDispose
    .family<
      WeeklyFamilyPresenceController,
      WeeklyFamilyPresenceSnapshot,
      String
    >(WeeklyFamilyPresenceController.new);

final weeklyFamilyPresenceProvider = Provider.autoDispose
    .family<WeeklyFamilyPresenceSnapshot, String>(
      (ref, familyId) =>
          ref.watch(_weeklyFamilyPresenceControllerProvider(familyId)),
    );

/// Explicit foreground-session commands, kept separate from the snapshot so
/// reading attendance on the Wheel can never start Bluetooth implicitly.
final weeklyFamilyPresenceSessionActionsProvider = Provider.autoDispose
    .family<WeeklyFamilyPresenceSessionActions, String>(
      (ref, familyId) =>
          ref.watch(_weeklyFamilyPresenceControllerProvider(familyId).notifier),
    );

final class WeeklyFamilyPresenceController
    extends Notifier<WeeklyFamilyPresenceSnapshot>
    implements WeeklyFamilyPresenceSessionActions {
  WeeklyFamilyPresenceController(this._familyId);

  final String _familyId;
  WeeklyPresenceSession? _session;

  @override
  WeeklyFamilyPresenceSnapshot build() {
    final session = WeeklyPresenceSession(
      radio: ref.watch(weeklyPresenceRadioProvider),
      tokenEncoder: WeeklyPresenceTokenCodec(),
      resolveFamilyKey: ref.watch(weeklyPresenceFamilyKeyResolverProvider),
      now: ref.watch(utcNowProvider),
    );
    _session = session;
    final subscription = session.readings.listen((reading) {
      if (!ref.mounted || !identical(_session, session)) return;
      state = reading.isAvailable
          ? WeeklyFamilyPresenceSnapshot.observedMembers(
              memberLastSeenAt: reading.memberLastSeenAt,
            )
          : const WeeklyFamilyPresenceSnapshot.unavailable();
    });
    ref.onDispose(() {
      if (identical(_session, session)) _session = null;
      unawaited(subscription.cancel());
      unawaited(session.dispose());
    });
    return const WeeklyFamilyPresenceSnapshot.unavailable();
  }

  @override
  Future<void> start({
    required LocalIdentity identity,
    required Iterable<String> rosterMemberIds,
  }) {
    final session = _session;
    if (session == null || identity.familyId != _familyId) {
      return stop();
    }
    return session.start(
      WeeklyPresenceSessionRequest(
        familyId: identity.familyId,
        memberId: identity.memberId,
        familyKeyRef: identity.familyKeyRef,
        rosterMemberIds: Set.unmodifiable(rosterMemberIds),
      ),
    );
  }

  @override
  Future<void> updateRoster(Iterable<String> rosterMemberIds) =>
      _session?.updateRoster(Set.unmodifiable(rosterMemberIds)) ??
      Future<void>.value();

  @override
  Future<void> stop() => _session?.stop() ?? Future<void>.value();
}
