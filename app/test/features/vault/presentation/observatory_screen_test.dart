import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humation_flutter/humation_flutter.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/archive/presentation/archive_screen.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/ceremony/presentation/ceremony_screen.dart';
import 'package:keepers/features/family/application/family_code_controller.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/family_join_requests_controller.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/family/application/pending_join_completion_controller.dart';
import 'package:keepers/features/family/data/invite_share_service.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/family/presentation/family_invite_sheet.dart';
import 'package:keepers/features/family/presentation/family_join_request_sheet.dart';
import 'package:keepers/features/locks/presentation/locks_screen.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/member_page_screen.dart';
import 'package:keepers/features/members/presentation/your_memories_screen.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/application/vault_providers.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/features/vault/presentation/observatory_screen.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/family_wheel_screen.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';

const _identity = LocalIdentity(
  familyId: 'family-1',
  familyName: 'Sabati',
  familyKeyRef: 'family-key',
  memberId: 'member-1',
  memberName: 'Chris',
  memberKeyRef: 'member-key',
  colorToken: 'ochre',
  avatar: AvatarConfig.defaults(seed: 'member-1'),
);

final _currentMember = FamilyMember(
  id: _identity.memberId,
  familyId: _identity.familyId,
  name: _identity.memberName,
  role: 'adult',
  colorToken: _identity.colorToken,
  avatar: _identity.avatar,
  joinedAt: DateTime.utc(2026, 9, 1),
);

final _defaultRoster = <FamilyMember>[
  _currentMember,
  _relative('noura', 'Noura', 'clay'),
  _relative('mariam', 'Mariam', 'sea'),
  _relative('youssef', 'Youssef', 'ochre'),
  _relative('layla', 'Layla', 'sage'),
];

final _observatoryRosterStateProvider =
    NotifierProvider<_ObservatoryRosterStateController, FamilyRosterState>(
      () => _ObservatoryRosterStateController(
        FamilyRosterState(members: _defaultRoster, hasLoadedLocal: true),
      ),
    );

final _pendingJoinRequest = PendingFamilyJoinRequest(
  requestId: '22222222-2222-4222-8222-222222222222',
  familyId: _identity.familyId,
  requesterAccountId: '33333333-3333-4333-8333-333333333333',
  memberId: '44444444-4444-4444-8444-444444444444',
  displayName: 'Amina',
  demographicRole: FamilyDemographicRole.adult,
  colorToken: 'clay',
  avatar: const AvatarConfig.defaults(
    seed: '44444444-4444-4444-8444-444444444444',
  ),
  joiningPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  codeVersion: 1,
  state: FamilyJoinRequestState.pending,
  createdAt: DateTime.utc(2026, 9, 7),
  expiresAt: DateTime.utc(2026, 9, 14),
);

FamilyMember _relative(String id, String name, String colorToken) =>
    FamilyMember(
      id: id,
      familyId: _identity.familyId,
      name: name,
      role: 'adult',
      colorToken: colorToken,
      avatar: AvatarConfig.defaults(seed: id),
      joinedAt: DateTime.utc(2026, 9, 2),
    );

FamilyMember _activatedPendingMember() => FamilyMember(
  id: _pendingJoinRequest.memberId,
  familyId: _identity.familyId,
  name: _pendingJoinRequest.displayName,
  role: _pendingJoinRequest.demographicRole.name,
  colorToken: _pendingJoinRequest.colorToken,
  avatar: _pendingJoinRequest.avatar,
  joinedAt: DateTime.utc(2026, 9, 7),
);

void main() {
  test('live Weekly loading is sequential and preserves entry order', () async {
    final entries = [
      _metadata(MemoryFormat.text, 1),
      _metadata(MemoryFormat.text, 2),
    ];
    final first = Completer<MemoryOpenResult>();
    final second = Completer<MemoryOpenResult>();
    final calls = <String>[];

    final loading = loadWeeklyMemoriesSequentially(entries, (entry) {
      calls.add(entry.id);
      return entry.id == entries.first.id ? first.future : second.future;
    });

    expect(calls, [entries.first.id]);
    first.complete(_openedText(entries.first, 'First memory'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, [entries.first.id, entries.last.id]);

    second.complete(_openedText(entries.last, 'Second memory'));
    final opened = await loading;
    expect(opened.map((memory) => memory.metadata.id), [
      entries.first.id,
      entries.last.id,
    ]);
  });

  test('an unavailable Weekly memory fails the whole load safely', () async {
    final entries = [
      _metadata(MemoryFormat.photo, 1),
      _metadata(MemoryFormat.photo, 2),
      _metadata(MemoryFormat.photo, 3),
    ];
    final decryptedBytes = Uint8List.fromList([11, 22, 33]);
    final calls = <String>[];

    final loading = loadWeeklyMemoriesSequentially(entries, (entry) async {
      calls.add(entry.id);
      if (entry.id == entries.first.id) {
        return _openedPhoto(entries.first, decryptedBytes);
      }
      return const UnavailableMemory('Unavailable');
    });

    await expectLater(loading, throwsA(isA<WeeklyMemoryLoadFailure>()));
    expect(calls, [entries.first.id, entries[1].id]);
    expect(decryptedBytes, everyElement(0));
  });

  test(
    'Weekly payload lease clears media when the experience closes',
    () async {
      final metadata = _metadata(MemoryFormat.photo, 1);
      final bytes = Uint8List.fromList([7, 8, 9]);
      final lease = WeeklyMemoryPayloadLease();

      await lease.own(Future.value([_openedPhoto(metadata, bytes)]));
      lease.release();

      expect(bytes, everyElement(0));
    },
  );

  test(
    'Weekly payload lease clears a load that finishes after closing',
    () async {
      final metadata = _metadata(MemoryFormat.photo, 1);
      final bytes = Uint8List.fromList([7, 8, 9]);
      final pending = Completer<List<OpenedMemory>>();
      final lease = WeeklyMemoryPayloadLease();
      final owned = lease.own(pending.future);

      lease.release();
      pending.complete([_openedPhoto(metadata, bytes)]);
      await owned;

      expect(bytes, everyElement(0));
    },
  );

  testWidgets('established identity renders the approved family members', (
    tester,
  ) async {
    await tester.pumpWidget(
      _observatory(
        entries: [
          _metadata(MemoryFormat.photo, 2),
          _metadata(MemoryFormat.text, 1),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(FamilyWheelScreen), findsOneWidget);
    expect(find.bySemanticsLabel('You, Chris, 40% sealed'), findsOneWidget);
    expect(find.bySemanticsLabel('Noura, away'), findsOneWidget);
    expect(find.bySemanticsLabel('Mariam, away'), findsOneWidget);
    expect(find.bySemanticsLabel('Youssef, away'), findsOneWidget);
    expect(find.bySemanticsLabel('Layla, away'), findsOneWidget);
    expect(find.text('NOURA'), findsOneWidget);
    expect(find.text('MARIAM'), findsOneWidget);
    expect(find.text('YOUSSEF'), findsOneWidget);
    expect(find.text('LAYLA'), findsOneWidget);
    expect(find.text('Add family to begin the circle'), findsNothing);
    expect(find.byType(KeepersBottomNav), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsNothing);
    expect(find.bySubtype<HumationAvatar>(), findsNWidgets(5));
  });

  testWidgets('local-only family never invents relatives', (tester) async {
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        rosterState: FamilyRosterState(
          members: [_currentMember],
          hasLoadedLocal: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('You, Chris, 0% sealed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('family-invite-node-action')),
      findsOneWidget,
    );
    for (final name in const ['NOURA', 'MARIAM', 'YOUSSEF', 'LAYLA']) {
      expect(find.text(name), findsNothing);
    }
    expect(find.bySubtype<HumationAvatar>(), findsOneWidget);
  });

  testWidgets('remote roster preserves stored identity and unknown activity', (
    tester,
  ) async {
    final storedAvatar = AvatarConfig(
      schemaVersion: AvatarConfig.currentSchemaVersion,
      styleId: AvatarConfig.currentStyleId,
      styleRevision: AvatarConfig.currentStyleRevision,
      seed: 'stored-remote',
      selections: const {},
      colors: const {'hair': '4a3728', 'skin': 'e0a17a'},
    );
    final remote = FamilyMember(
      id: 'stored-remote',
      familyId: _identity.familyId,
      name: 'Amina',
      role: 'adult',
      colorToken: 'sea',
      avatar: storedAvatar,
      joinedAt: DateTime.utc(2026, 9, 5),
    );
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        rosterState: FamilyRosterState(
          members: [_currentMember, remote],
          hasLoadedLocal: true,
        ),
      ),
    );
    await tester.pump();

    final wheel = tester.widget<FamilyWheelScreen>(
      find.byType(FamilyWheelScreen),
    );
    expect(wheel.members, hasLength(1));
    expect(wheel.members.single.avatar, storedAvatar);
    expect(wheel.members.single.color, KeepersColors.memberPalette[3]);
    expect(wheel.members.single.contribution, isNull);
    expect(wheel.members.single.presence, FamilyPresence.away);
    expect(find.bySemanticsLabel('Amina, away'), findsOneWidget);
    expect(find.bySemanticsLabel('You, Chris, 0% sealed'), findsOneWidget);
  });

  testWidgets('roster loading and local failure are explicit blocking states', (
    tester,
  ) async {
    await tester.pumpWidget(
      _observatory(entries: const [], rosterState: FamilyRosterState()),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Loading family'), findsOneWidget);
    expect(find.byType(FamilyWheelScreen), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        rosterState: FamilyRosterState(
          refreshFailure: const InvitationFailure(
            InvitationFailureCode.localPersistenceFailed,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('YOUR FAMILY COULD NOT BE OPENED'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(find.byType(FamilyWheelScreen), findsNothing);
  });

  testWidgets('cached roster remains visible when cloud refresh fails', (
    tester,
  ) async {
    var refreshes = 0;
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        rosterState: FamilyRosterState(
          members: _defaultRoster,
          hasLoadedLocal: true,
          refreshFailure: const InvitationFailure(
            InvitationFailureCode.networkUnavailable,
          ),
        ),
        refreshRoster: () async => refreshes += 1,
      ),
    );
    await tester.pump();

    expect(find.byType(FamilyWheelScreen), findsOneWidget);
    expect(find.text('FAMILY UPDATE UNAVAILABLE'), findsOneWidget);
    await tester.tap(find.text('RETRY'));
    await tester.pump();
    expect(refreshes, 1);
  });

  testWidgets('archive summary counts only kept memories', (tester) async {
    await tester.pumpWidget(
      _observatory(
        entries: [
          _metadata(MemoryFormat.photo, 1).copyWith(state: 'kept'),
          _metadata(MemoryFormat.voice, 2),
          _metadata(MemoryFormat.text, 3),
        ],
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('1 memory kept forever'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Archive'));
    await tester.pump();

    expect(find.byType(ArchiveScreen), findsOneWidget);
    expect(find.bySemanticsLabel('1 memory kept forever'), findsOneWidget);
    expect(find.bySemanticsLabel('3 memories kept forever'), findsNothing);
  });

  testWidgets('Family Wheel renders at 1.4x without clipping', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _observatory(
        entries: List.generate(
          6,
          (index) => _metadata(MemoryFormat.values[index % 3], 6 - index),
        ),
        mediaQuery: const MediaQueryData(
          textScaler: TextScaler.linear(1.4),
          disableAnimations: true,
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Hold to speak'), findsNothing);
  });

  testWidgets('tapping YOU opens every memory authored by the current member', (
    tester,
  ) async {
    final entries = [
      _metadata(
        MemoryFormat.photo,
        2,
      ).copyWith(privacy: PrivacyTier.journal, state: 'kept'),
      _metadata(MemoryFormat.voice, 3),
      _metadata(MemoryFormat.text, 4).copyWith(privacy: PrivacyTier.legacy),
      _metadata(MemoryFormat.text, 5).copyWith(authorId: 'member-2'),
    ];
    await tester.pumpWidget(_observatory(entries: entries));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('You, Chris, 60% sealed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(YourMemoriesScreen), findsOneWidget);
    expect(find.text('Your memories'), findsOneWidget);
    expect(find.byKey(const Key('your-memory-entry-photo-2')), findsOneWidget);
    expect(find.byKey(const Key('your-memory-entry-voice-3')), findsOneWidget);
    expect(find.byKey(const Key('your-memory-entry-text-4')), findsOneWidget);
    expect(find.byKey(const Key('your-memory-entry-text-5')), findsNothing);
    expect(find.text('Private Journal'), findsOneWidget);
    expect(find.text('Weekly Reveal'), findsOneWidget);
    expect(find.text('Legacy Milestone'), findsOneWidget);
  });

  testWidgets('capture success refreshes contribution before haptics', (
    tester,
  ) async {
    final saved = _entryMetadata(MemoryFormat.text, 3);
    final refreshed = _metadata(MemoryFormat.text, 3);
    final refresh = Completer<List<VaultEntryMetadata>>();
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    var loads = 0;
    await tester.pumpWidget(
      _observatoryWithOverride(
        vaultEntriesProvider.overrideWith((ref) async {
          loads += 1;
          return loads == 1 ? const [] : refresh.future;
        }),
        showCapture: (_) async => saved,
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Keep a memory'));
    await tester.pump();
    expect(haptics, isEmpty);
    refresh.complete([refreshed]);
    await tester.pump();

    expect(loads, 2);
    expect(find.bySemanticsLabel('You, Chris, 20% sealed'), findsOneWidget);
    expect(haptics, hasLength(1));
    await tester.pump(const Duration(milliseconds: 80));
    expect(haptics, hasLength(2));
  });

  testWidgets('capture cancellation neither refreshes nor vibrates', (
    tester,
  ) async {
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    var loads = 0;
    await tester.pumpWidget(
      _observatoryWithOverride(
        vaultEntriesProvider.overrideWith((ref) async {
          loads += 1;
          return const [];
        }),
        showCapture: (_) async => null,
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Keep a memory'));
    await tester.pump();

    expect(loads, 1);
    expect(haptics, isEmpty);
  });

  testWidgets('canonical entries open every confirmed interface', (
    tester,
  ) async {
    await tester.pumpWidget(_observatory(entries: const []));
    await tester.pump();

    expect(find.byKey(const ValueKey('weekly-recap-mode')), findsOneWidget);
    expect(find.text('LEGACY LOCK'), findsNothing);
    expect(find.text('CAPSULE'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Memory Key'));
    await tester.pump();
    expect(find.byType(CeremonyScreen), findsOneWidget);
    expect(find.text('LEGACY LOCK'), findsOneWidget);
    expect(find.text('CAPSULE'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('memory-key-legacy-entry')));
    await tester.pump();
    expect(find.byType(LocksScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Archive'));
    await tester.pump();
    expect(find.byType(ArchiveScreen), findsOneWidget);
    expect(find.text('Nothing kept yet'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Wheel'));
    await tester.pump();
    expect(find.byType(FamilyWheelScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Chris'), findsOneWidget);
    expect(find.text('Sabati'), findsOneWidget);
  });

  testWidgets(
    'wheel and header open the same offline non-creator invite sheet',
    (tester) async {
      final share = _NudgeShareService();
      var rosterRefreshes = 0;
      await tester.pumpWidget(
        _observatoryWithOverride(
          vaultEntriesProvider.overrideWithValue(
            const AsyncValue.data(<VaultEntryMetadata>[]),
          ),
          shareService: share,
          refreshRoster: () async => rosterRefreshes += 1,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('family-invite-node-action')));
      await tester.pumpAndSettle();
      expect(find.byType(FamilyInviteSheet), findsOneWidget);
      expect(find.byKey(const Key('family-code-display')), findsOneWidget);
      expect(find.text('Regenerate code'), findsNothing);
      expect(share.nudges, 0);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(rosterRefreshes, 1);

      await tester.tap(find.bySemanticsLabel('Family code K 7 M 4 P 2 Q 8'));
      await tester.pumpAndSettle();
      expect(find.byType(FamilyInviteSheet), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(rosterRefreshes, 2);

      const gatherLabel = 'Ask Noura, Mariam, Youssef & Layla to come';
      await tester.ensureVisible(find.text(gatherLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(gatherLabel));
      await tester.pump();
      expect(share.nudges, 1);
      expect(find.byType(FamilyInviteSheet), findsNothing);
    },
  );

  testWidgets('pending family request notice opens its resolution sheet', (
    tester,
  ) async {
    final requests = _ObservatoryJoinRequestsController(
      FamilyJoinRequestsState(requests: [_pendingJoinRequest]),
    );
    var rosterRefreshes = 0;
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        requestsController: requests,
        refreshRoster: () async => rosterRefreshes += 1,
      ),
    );
    await tester.pump();

    expect(find.text('Amina wants to join'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('family-join-request-notice')));
    await tester.pumpAndSettle();

    expect(find.byType(FamilyJoinRequestSheet), findsOneWidget);
    expect(find.text('Amina wants to join'), findsWidgets);
    await tester.tap(find.byKey(const Key('approve-join-request')));
    await tester.pumpAndSettle();
    expect(requests.approveCalls, 1);
    expect(find.byType(FamilyJoinRequestSheet), findsNothing);
    expect(rosterRefreshes, 1);
  });

  testWidgets(
    'decline cancel expiry and unknown disappearance never start polling',
    (tester) async {
      final requests = _ObservatoryJoinRequestsController(
        FamilyJoinRequestsState(requests: [_pendingJoinRequest]),
      );
      var rosterRefreshes = 0;
      await tester.pumpWidget(
        _observatory(
          entries: const [],
          requestsController: requests,
          refreshRoster: () async => rosterRefreshes += 1,
        ),
      );
      await tester.pump();

      requests.emit(const FamilyJoinRequestsState());
      await tester.pump();
      await tester.pump(const Duration(hours: 1));

      expect(rosterRefreshes, 0);
      expect(find.text('Amina wants to join'), findsNothing);
    },
  );

  testWidgets(
    'a recent approval polls until delayed membership activation appears',
    (tester) async {
      final requests = _ObservatoryJoinRequestsController(
        FamilyJoinRequestsState(requests: [_pendingJoinRequest]),
      );
      final roster = _ObservatoryRosterStateController(
        FamilyRosterState(members: _defaultRoster, hasLoadedLocal: true),
      );
      var activationIsVisible = false;
      var rosterRefreshes = 0;

      await tester.pumpWidget(
        _observatory(
          entries: const [],
          requestsController: requests,
          rosterController: roster,
          refreshRoster: () async {
            rosterRefreshes += 1;
            if (activationIsVisible) {
              roster.emit(
                FamilyRosterState(
                  members: [..._defaultRoster, _activatedPendingMember()],
                  hasLoadedLocal: true,
                ),
              );
            }
          },
        ),
      );
      await tester.pump();

      requests.emit(
        FamilyJoinRequestsState(
          activationCandidateMemberIds: {_pendingJoinRequest.memberId},
        ),
      );
      await tester.pump();
      expect(rosterRefreshes, 1);

      activationIsVisible = true;
      await tester.pump(const Duration(minutes: 5));
      await tester.pump();

      expect(rosterRefreshes, greaterThan(1));
      final wheel = tester.widget<FamilyWheelScreen>(
        find.byType(FamilyWheelScreen),
      );
      expect(
        wheel.members.map((member) => member.id),
        contains(_pendingJoinRequest.memberId),
      );

      final refreshesAfterActivation = rosterRefreshes;
      await tester.pump(const Duration(hours: 1));
      await tester.pump();
      expect(rosterRefreshes, refreshesAfterActivation);
    },
  );

  testWidgets(
    'activation beyond one minute reconciles without another request signal',
    (tester) async {
      final requests = _ObservatoryJoinRequestsController(
        FamilyJoinRequestsState(requests: [_pendingJoinRequest]),
      );
      final roster = _ObservatoryRosterStateController(
        FamilyRosterState(members: _defaultRoster, hasLoadedLocal: true),
      );
      var activationIsVisible = false;
      var rosterRefreshes = 0;

      await tester.pumpWidget(
        _observatory(
          entries: const [],
          requestsController: requests,
          rosterController: roster,
          refreshRoster: () async {
            rosterRefreshes += 1;
            if (activationIsVisible) {
              roster.emit(
                FamilyRosterState(
                  members: [..._defaultRoster, _activatedPendingMember()],
                  hasLoadedLocal: true,
                ),
              );
            }
          },
        ),
      );
      await tester.pump();

      requests.emit(
        FamilyJoinRequestsState(
          activationCandidateMemberIds: {_pendingJoinRequest.memberId},
        ),
      );
      await tester.pump();
      expect(rosterRefreshes, 1);

      for (var retry = 0; retry < 2; retry += 1) {
        await tester.pump(const Duration(minutes: 5));
        await tester.pump();
      }
      expect(rosterRefreshes, 3);

      activationIsVisible = true;
      await tester.pump(const Duration(minutes: 5));
      await tester.pump();

      final wheel = tester.widget<FamilyWheelScreen>(
        find.byType(FamilyWheelScreen),
      );
      expect(
        wheel.members.map((member) => member.id),
        contains(_pendingJoinRequest.memberId),
      );

      final refreshesAfterActivation = rosterRefreshes;
      await tester.pump(const Duration(hours: 1));
      await tester.pump();
      expect(rosterRefreshes, refreshesAfterActivation);
    },
  );

  testWidgets('activation polling stays within twelve reads per hour', (
    tester,
  ) async {
    final requests = _ObservatoryJoinRequestsController(
      FamilyJoinRequestsState(requests: [_pendingJoinRequest]),
    );
    var rosterRefreshes = 0;
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        requestsController: requests,
        refreshRoster: () async => rosterRefreshes += 1,
      ),
    );
    await tester.pump();

    requests.emit(
      FamilyJoinRequestsState(
        activationCandidateMemberIds: {_pendingJoinRequest.memberId},
      ),
    );
    await tester.pump();
    for (var retry = 0; retry < 11; retry += 1) {
      await tester.pump(const Duration(minutes: 5));
      await tester.pump();
    }

    expect(rosterRefreshes, 12);
    final refreshesBeforeDisposal = rosterRefreshes;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(hours: 1));
    expect(rosterRefreshes, refreshesBeforeDisposal);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated activation candidate signals are deduplicated', (
    tester,
  ) async {
    final requests = _ObservatoryJoinRequestsController(
      FamilyJoinRequestsState(requests: [_pendingJoinRequest]),
    );
    var rosterRefreshes = 0;
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        requestsController: requests,
        refreshRoster: () async => rosterRefreshes += 1,
      ),
    );
    await tester.pump();

    final candidateState = FamilyJoinRequestsState(
      activationCandidateMemberIds: {_pendingJoinRequest.memberId},
    );
    requests.emit(
      FamilyJoinRequestsState(
        activationCandidateMemberIds: {_pendingJoinRequest.memberId},
      ),
    );
    await tester.pump();
    expect(rosterRefreshes, 1);

    requests.emit(candidateState);
    await tester.pump();

    expect(rosterRefreshes, 1);
  });

  testWidgets('gathering nudge prevents duplicate shares and reports failure', (
    tester,
  ) async {
    final share = _ControlledNudgeShareService();
    await tester.pumpWidget(
      _observatoryWithOverride(
        vaultEntriesProvider.overrideWithValue(
          const AsyncValue.data(<VaultEntryMetadata>[]),
        ),
        shareService: share,
      ),
    );
    await tester.pump();

    const gatherLabel = 'Ask Noura, Mariam, Youssef & Layla to come';
    await tester.ensureVisible(find.text(gatherLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(gatherLabel));
    await tester.tap(find.text(gatherLabel), warnIfMissed: false);
    await tester.pump();
    expect(share.nudges, 1);

    share.pending.completeError(StateError('share unavailable'));
    await tester.pump();
    expect(
      find.text('Sharing could not be opened. Try again.'),
      findsOneWidget,
    );
  });

  testWidgets('resume refreshes family code, joins, roster, and vault', (
    tester,
  ) async {
    var rosterRefreshes = 0;
    var vaultLoads = 0;
    var completionRecoveries = 0;
    final code = _ObservatoryFamilyCodeController();
    final requests = _ObservatoryJoinRequestsController();
    await tester.pumpWidget(
      _observatoryWithOverride(
        vaultEntriesProvider.overrideWith((ref) async {
          vaultLoads += 1;
          return const [];
        }),
        refreshRoster: () async => rosterRefreshes += 1,
        codeController: code,
        requestsController: requests,
        recoverJoin: () async {
          completionRecoveries += 1;
          return const PendingJoinCompletionState();
        },
      ),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(rosterRefreshes, 1);
    expect(vaultLoads, 2);
    expect(code.loadCalls, 1);
    expect(requests.refreshCalls, 1);
    expect(completionRecoveries, 1);
  });

  testWidgets('large synchronized families remain available on the wheel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final relatives = List.generate(
      18,
      (index) => FamilyMember(
        id: 'relative-$index',
        familyId: _identity.familyId,
        name: 'Relative $index',
        role: 'adult',
        colorToken: index.isEven ? 'sea' : 'clay',
        avatar: AvatarConfig.defaults(seed: 'relative-$index'),
        joinedAt: DateTime.utc(2026, 9, 5).add(Duration(minutes: index)),
      ),
    );
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        mediaQuery: const MediaQueryData(
          textScaler: TextScaler.linear(1.4),
          disableAnimations: true,
        ),
        rosterState: FamilyRosterState(
          members: [_currentMember, ...relatives],
          hasLoadedLocal: true,
        ),
      ),
    );
    await tester.pump();

    final wheel = tester.widget<FamilyWheelScreen>(
      find.byType(FamilyWheelScreen),
    );
    expect(
      wheel.members.map((member) => member.id),
      relatives.map((member) => member.id),
    );
    expect(tester.takeException(), isNull);

    expect(find.byKey(const ValueKey('weekly-recap-mode')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Memory Key'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('memory-key-legacy-entry')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Relative 17, away'), findsNothing);
  });

  testWidgets('persisted remote profile omits device-local activity claims', (
    tester,
  ) async {
    final remote = _relative('amina', 'Amina', 'sea');
    await tester.pumpWidget(
      _observatory(
        entries: [
          _metadata(MemoryFormat.text, 3).copyWith(authorId: remote.id),
        ],
        rosterState: FamilyRosterState(
          members: [_currentMember, remote],
          hasLoadedLocal: true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Amina, away'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(MemberPageScreen), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Amina avatar')), findsOneWidget);
    expect(find.textContaining('% of this week sealed'), findsNothing);
    expect(find.textContaining('sealed this week'), findsNothing);
    expect(
      find.text('Current-week memories stay closed until ceremony.'),
      findsNothing,
    );
  });

  testWidgets('center plus opens capture from every main destination', (
    tester,
  ) async {
    var captures = 0;
    await tester.pumpWidget(
      _observatoryWithOverride(
        vaultEntriesProvider.overrideWithValue(
          const AsyncValue.data(<VaultEntryMetadata>[]),
        ),
        showCapture: (_) async {
          captures += 1;
          return null;
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Memory Key'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Keep a memory'));
    await tester.pump();

    for (final destination in const ['Archive', 'Settings']) {
      await tester.tap(find.bySemanticsLabel(destination));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Keep a memory'));
      await tester.pump();
    }

    expect(captures, 3);
  });

  testWidgets('archive receives real kept vault memories for random draw', (
    tester,
  ) async {
    await tester.pumpWidget(
      _observatory(
        entries: [_metadata(MemoryFormat.voice, 12).copyWith(state: 'kept')],
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Archive'));
    await tester.pump();

    expect(find.byType(ArchiveScreen), findsOneWidget);
    expect(find.text('Draw a memory'), findsOneWidget);
    expect(find.bySemanticsLabel('1 memory kept forever'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Memory Key'));
    await tester.pump();
    expect(find.text('Draw a memory'), findsNothing);
  });

  testWidgets('archive attributes kept memories to roster members', (
    tester,
  ) async {
    await tester.pumpWidget(
      _observatory(
        entries: [
          _metadata(
            MemoryFormat.voice,
            13,
          ).copyWith(authorId: 'noura', state: 'kept'),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Archive'));
    await tester.pump();

    expect(find.textContaining('Noura · Voices'), findsOneWidget);
    expect(find.textContaining('Family member · Voices'), findsNothing);
  });

  testWidgets('weekly progress counts same-week pending reveal photos only', (
    tester,
  ) async {
    final thisWeek = DateTime.now().toUtc();
    await tester.pumpWidget(
      _observatory(
        entries: [
          _metadata(MemoryFormat.photo, 1).copyWith(createdAt: thisWeek),
          _metadata(MemoryFormat.voice, 2).copyWith(createdAt: thisWeek),
          _metadata(MemoryFormat.text, 3).copyWith(createdAt: thisWeek),
        ],
      ),
    );
    await tester.pump();

    final wheel = tester.widget<FamilyWheelScreen>(
      find.byType(FamilyWheelScreen),
    );
    expect(wheel.weeklyPhotoCount, 1);
  });

  testWidgets('weekly photos reset at device-local Monday', (tester) async {
    final localMonday = DateTime(2026, 9, 7);
    await tester.pumpWidget(
      _observatory(
        entries: [
          _metadata(MemoryFormat.photo, 4).copyWith(
            createdAt: localMonday
                .subtract(const Duration(microseconds: 1))
                .toUtc(),
          ),
          _metadata(
            MemoryFormat.photo,
            5,
          ).copyWith(createdAt: localMonday.toUtc()),
        ],
        now: localMonday.add(const Duration(hours: 1)),
      ),
    );
    await tester.pump();

    final wheel = tester.widget<FamilyWheelScreen>(
      find.byType(FamilyWheelScreen),
    );
    expect(wheel.weeklyPhotoCount, 1);
  });

  testWidgets('weekly photos exclude timestamps after the supplied time', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 9, 12);
    await tester.pumpWidget(
      _observatory(
        entries: [
          _metadata(
            MemoryFormat.photo,
            6,
          ).copyWith(createdAt: now.subtract(const Duration(hours: 1)).toUtc()),
          _metadata(MemoryFormat.photo, 7).copyWith(
            createdAt: now.add(const Duration(microseconds: 1)).toUtc(),
          ),
        ],
        now: now,
      ),
    );
    await tester.pump();

    final wheel = tester.widget<FamilyWheelScreen>(
      find.byType(FamilyWheelScreen),
    );
    expect(wheel.weeklyPhotoCount, 1);
  });

  testWidgets(
    'single-device app can preview Weekly without unlocking the real recap',
    (tester) async {
      await tester.pumpWidget(_observatory(entries: const []));
      await tester.pump();

      final weeklyCard = find.byKey(const ValueKey('weekly-recap-mode'));
      final weeklyOpen = tester.widget<OutlinedButton>(
        find.descendant(
          of: weeklyCard,
          matching: find.byKey(const ValueKey('weekly-recap-open')),
        ),
      );
      expect(weeklyOpen.onPressed, isNull);
      final progress = find.bySemanticsLabel('Weekly photo progress');
      expect(progress, findsOneWidget);
      expect(
        tester.getSemantics(progress).getSemanticsData().value,
        '0 of 5 photos. 5 photos needed',
      );
      expect(
        find.textContaining('family member needs to be present'),
        findsNothing,
      );

      final preview = find.byKey(const ValueKey('weekly-recap-preview'));
      expect(preview, findsOneWidget);
      expect(
        find.descendant(
          of: preview,
          matching: find.text('Preview weekly experience'),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(preview);
      await tester.pump();
      await tester.tap(preview);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ceremony-reel')), findsOneWidget);
      expect(find.text('Photo memory'), findsOneWidget);
      expect(find.text('REHEARSAL MODE'), findsOneWidget);
    },
  );

  testWidgets(
    'debug app temporarily opens a full Weekly vault without proximity data',
    (tester) async {
      final now = DateTime(2026, 9, 9, 12);
      final entries = List.generate(
        5,
        (index) => _metadata(
          MemoryFormat.photo,
          index + 1,
        ).copyWith(createdAt: now.subtract(Duration(hours: index + 1)).toUtc()),
      );

      await tester.pumpWidget(_observatory(entries: entries, now: now));
      await tester.pump();

      final wheel = tester.widget<FamilyWheelScreen>(
        find.byType(FamilyWheelScreen),
      );
      expect(
        wheel.weeklyPresencePolicy,
        WeeklyPresencePolicy.temporaryAllowUntilProximityProxy,
      );

      final open = find.byKey(const ValueKey('weekly-recap-open'));
      await tester.ensureVisible(open);
      await tester.pump();
      expect(
        tester
            .getSemantics(open)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        find.text('Ask Noura, Mariam, Youssef & Layla to come'),
        findsOneWidget,
      );
    },
    semanticsEnabled: true,
  );

  testWidgets('real Weekly callback never opens the rehearsal fixture', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 9, 12);
    final entries = List.generate(
      5,
      (index) => _metadata(
        MemoryFormat.photo,
        index + 1,
      ).copyWith(createdAt: now.subtract(Duration(hours: index + 1)).toUtc()),
    );
    await tester.pumpWidget(_observatory(entries: entries, now: now));
    await tester.pump();

    tester
        .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
        .onOpenWeeklyExperience!
        .call();
    await tester.pump();

    final ceremony = tester.widget<CeremonyScreen>(find.byType(CeremonyScreen));
    expect(ceremony.weeklyPreview, isFalse);
    expect(ceremony.weeklyMemories, isNotNull);
    expect(ceremony.onWeeklyDecision, isNotNull);
    expect(
      find.byKey(const ValueKey('weekly-experience-loading')),
      findsOneWidget,
    );
    expect(find.text('REHEARSAL MODE'), findsNothing);
    expect(find.text('A small moment'), findsNothing);
  });

  testWidgets('destination shell stays stable at phone width and 1.4x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        mediaQuery: const MediaQueryData(
          textScaler: TextScaler.linear(1.4),
          disableAnimations: true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Memory Key'));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'Memory Key');

    for (final destination in const ['Archive', 'Settings', 'Wheel']) {
      await tester.tap(find.bySemanticsLabel(destination));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: destination);
    }
  });
}

Widget _observatory({
  required List<VaultEntryMetadata> entries,
  MediaQueryData? mediaQuery,
  FamilyRosterState? rosterState,
  _ObservatoryRosterStateController? rosterController,
  FamilyRosterRefresh? refreshRoster,
  _ObservatoryFamilyCodeController? codeController,
  _ObservatoryJoinRequestsController? requestsController,
  FamilyJoinCompletionRecovery? recoverJoin,
  DateTime? now,
}) => _observatoryWithOverride(
  vaultEntriesProvider.overrideWithValue(AsyncValue.data(entries)),
  mediaQuery: mediaQuery,
  rosterState: rosterState,
  rosterController: rosterController,
  refreshRoster: refreshRoster,
  codeController: codeController,
  requestsController: requestsController,
  recoverJoin: recoverJoin,
  now: now,
);

Widget _observatoryWithOverride(
  dynamic override, {
  MediaQueryData? mediaQuery,
  Future<EntryMetadata?> Function(BuildContext)? showCapture,
  InviteShareService? shareService,
  FamilyRosterState? rosterState,
  _ObservatoryRosterStateController? rosterController,
  FamilyRosterRefresh? refreshRoster,
  _ObservatoryFamilyCodeController? codeController,
  _ObservatoryJoinRequestsController? requestsController,
  FamilyJoinCompletionRecovery? recoverJoin,
  DateTime? now,
}) {
  final effectiveRoster =
      rosterState ??
      FamilyRosterState(members: _defaultRoster, hasLoadedLocal: true);
  final effectiveRosterController =
      rosterController ?? _ObservatoryRosterStateController(effectiveRoster);
  final effectiveCode = codeController ?? _ObservatoryFamilyCodeController();
  final effectiveRequests =
      requestsController ?? _ObservatoryJoinRequestsController();
  return ProviderScope(
    overrides: [
      override,
      _observatoryRosterStateProvider.overrideWith(
        () => effectiveRosterController,
      ),
      familyRosterProvider(_identity.familyId).overrideWithBuild(
        (ref, notifier) => ref.watch(_observatoryRosterStateProvider),
      ),
      familyRosterRefreshProvider(_identity.familyId)
          .overrideWithValue(refreshRoster ?? () async {}),
      familyCodeControllerProvider(_identity.familyId)
          .overrideWith(() => effectiveCode),
      familyJoinRequestsControllerProvider(_identity.familyId)
          .overrideWith(() => effectiveRequests),
      familyJoinCompletionRecoveryProvider.overrideWithValue(
        recoverJoin ?? () async => const PendingJoinCompletionState(),
      ),
      if (now != null) utcNowProvider.overrideWithValue(() => now.toUtc()),
      if (shareService != null)
        inviteShareServiceProvider.overrideWithValue(shareService),
    ],
    child: MaterialApp(
      theme: KeepersTheme.dark(),
      home: MediaQuery(
        data: mediaQuery ?? const MediaQueryData(disableAnimations: true),
        child: ObservatoryScreen(identity: _identity, showCapture: showCapture),
      ),
    ),
  );
}

final class _ObservatoryRosterStateController
    extends Notifier<FamilyRosterState> {
  _ObservatoryRosterStateController(this.initial);

  final FamilyRosterState initial;

  @override
  FamilyRosterState build() => initial;

  void emit(FamilyRosterState next) => state = next;
}

final class _ObservatoryFamilyCodeController extends FamilyCodeController {
  _ObservatoryFamilyCodeController() : super(_identity.familyId);

  var loadCalls = 0;

  @override
  FamilyCodeState build() => const FamilyCodeState(
    phase: FamilyCodePhase.ready,
    displayCode: 'K7M4-P2Q8',
    codeVersion: 1,
    isOffline: true,
  );

  @override
  Future<void> load() async => loadCalls += 1;
}

final class _ObservatoryJoinRequestsController
    extends FamilyJoinRequestsController {
  _ObservatoryJoinRequestsController([
    this.initial = const FamilyJoinRequestsState(),
  ]) : super(_identity.familyId);

  final FamilyJoinRequestsState initial;
  var refreshCalls = 0;
  var approveCalls = 0;

  @override
  FamilyJoinRequestsState build() => initial;

  void emit(FamilyJoinRequestsState next) => state = next;

  @override
  Future<void> approve(String requestId) async {
    approveCalls += 1;
    state = FamilyJoinRequestsState(
      activationCandidateMemberIds: {_pendingJoinRequest.memberId},
    );
  }

  @override
  Future<void> refresh() async => refreshCalls += 1;
}

final class _NudgeShareService extends InviteShareService {
  var nudges = 0;

  @override
  Future<void> shareGatheringNudge({Rect? sharePositionOrigin}) async {
    nudges += 1;
  }

  @override
  Future<void> shareInvitation(
    Uri invitationUri, {
    Rect? sharePositionOrigin,
  }) => throw UnimplementedError();
}

final class _ControlledNudgeShareService extends InviteShareService {
  var nudges = 0;
  final pending = Completer<void>();

  @override
  Future<void> shareGatheringNudge({Rect? sharePositionOrigin}) {
    nudges += 1;
    return pending.future;
  }

  @override
  Future<void> shareInvitation(
    Uri invitationUri, {
    Rect? sharePositionOrigin,
  }) => throw UnimplementedError();
}

VaultEntryMetadata _metadata(MemoryFormat format, int day) =>
    VaultEntryMetadata(
      id: 'entry-${format.name}-$day',
      familyId: 'family-1',
      authorId: 'member-1',
      createdAt: DateTime.utc(2026, 8, day),
      format: format,
      privacy: PrivacyTier.reveal,
      blobRef: 'entries/blobs/entry-${format.name}-$day.keeper',
      state: 'pending',
    );

EntryMetadata _entryMetadata(MemoryFormat format, int day) => EntryMetadata(
  id: 'entry-${format.name}-$day',
  familyId: 'family-1',
  authorId: 'member-1',
  createdAt: DateTime.utc(2026, 8, day),
  format: format,
  privacy: PrivacyTier.reveal,
  blobRef: 'entries/blobs/entry-${format.name}-$day.keeper',
);

OpenedMemory _openedText(VaultEntryMetadata metadata, String text) =>
    OpenedMemory(
      metadata: metadata,
      payload: EntryPayload(
        format: MemoryFormat.text,
        primaryBytes: null,
        text: text,
        caption: null,
        mediaExtension: null,
        mediaDurationMs: null,
      ),
    );

OpenedMemory _openedPhoto(VaultEntryMetadata metadata, Uint8List bytes) =>
    OpenedMemory(
      metadata: metadata,
      payload: EntryPayload(
        format: MemoryFormat.photo,
        primaryBytes: bytes,
        text: null,
        caption: null,
        mediaExtension: 'jpg',
        mediaDurationMs: null,
      ),
    );
