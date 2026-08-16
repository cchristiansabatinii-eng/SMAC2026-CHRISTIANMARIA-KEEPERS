import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humation_flutter/humation_flutter.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/archive/presentation/archive_screen.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/ceremony/presentation/ceremony_screen.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/family/data/invite_share_service.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/family/presentation/family_invite_screen.dart';
import 'package:keepers/features/locks/presentation/locks_screen.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/member_page_screen.dart';
import 'package:keepers/features/members/presentation/your_memories_screen.dart';
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

void main() {
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

  testWidgets('home controls and shortcuts open every confirmed interface', (
    tester,
  ) async {
    await tester.pumpWidget(_observatory(entries: const []));
    await tester.pump();

    await tester.ensureVisible(find.text('CAPSULE'));
    await tester.pump();
    await tester.tap(find.text('CAPSULE'));
    await tester.pump();
    expect(find.byType(CeremonyScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Archive'));
    await tester.pump();
    expect(find.byType(ArchiveScreen), findsOneWidget);
    expect(find.text('Nothing kept yet'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Wheel'));
    await tester.pump();
    await tester.ensureVisible(find.text('LEGACY LOCK'));
    await tester.pump();
    await tester.tap(find.text('LEGACY LOCK'));
    await tester.pump();
    expect(find.byType(LocksScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Wheel'));
    await tester.pump();
    expect(find.byType(FamilyWheelScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Chris'), findsOneWidget);
    expect(find.text('Sabati'), findsOneWidget);
  });

  testWidgets('Invite route and gathering nudge remain separate operations', (
    tester,
  ) async {
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
    expect(find.byType(FamilyInviteScreen), findsOneWidget);
    expect(share.nudges, 0);

    Navigator.of(tester.element(find.byType(FamilyInviteScreen))).pop();
    await tester.pumpAndSettle();
    expect(rosterRefreshes, 1);
    const gatherLabel = 'Ask Noura, Mariam, Youssef & Layla to come';
    await tester.ensureVisible(find.text(gatherLabel));
    await tester.tap(find.text(gatherLabel));
    await tester.pump();
    expect(share.nudges, 1);
    expect(find.byType(FamilyInviteScreen), findsNothing);
  });

  testWidgets('resuming the app refreshes the synchronized roster', (
    tester,
  ) async {
    var rosterRefreshes = 0;
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        refreshRoster: () async => rosterRefreshes += 1,
      ),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(rosterRefreshes, 1);
  });

  testWidgets('large synchronized families remain available on both surfaces', (
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

    await tester.tap(find.bySemanticsLabel('Memory Key'));
    await tester.pump();
    for (final relative in relatives) {
      expect(find.bySemanticsLabel('${relative.name}, away'), findsOneWidget);
    }
    final lastMember = find.bySemanticsLabel('Relative 17, away');
    expect(lastMember.hitTestable(), findsNothing);
    await tester.ensureVisible(lastMember);
    await tester.pump();
    expect(lastMember.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
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

    await tester.ensureVisible(find.text('CAPSULE'));
    await tester.pump();
    await tester.tap(find.text('CAPSULE'));
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

  testWidgets('memory key receives real kept vault memories for random draw', (
    tester,
  ) async {
    await tester.pumpWidget(
      _observatory(
        entries: [_metadata(MemoryFormat.voice, 12).copyWith(state: 'kept')],
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('CAPSULE'));
    await tester.pump();
    await tester.tap(find.text('CAPSULE'));
    await tester.pump();

    expect(find.text('1 kept — one comes back at random'), findsOneWidget);
  });

  testWidgets(
    'single-device app can preview Weekly without unlocking the real recap',
    (tester) async {
      await tester.pumpWidget(_observatory(entries: const []));
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Memory Key'));
      await tester.pump();

      final weeklyCard = find.byKey(const ValueKey('weekly-recap-mode'));
      final weeklyOpen = tester.widget<OutlinedButton>(
        find.descendant(
          of: weeklyCard,
          matching: find.byKey(const ValueKey('weekly-recap-open')),
        ),
      );
      expect(weeklyOpen.onPressed, isNull);
      expect(find.text('1 of 2 devices'), findsOneWidget);

      final preview = find.byKey(const ValueKey('weekly-recap-preview'));
      expect(preview, findsOneWidget);
      expect(
        find.descendant(
          of: preview,
          matching: find.text('Preview weekly experience'),
        ),
        findsOneWidget,
      );

      await tester.tap(preview);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ceremony-reel')), findsOneWidget);
      expect(find.text('Photo memory'), findsOneWidget);
      expect(find.text('REHEARSAL MODE'), findsOneWidget);
    },
  );

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

    await tester.ensureVisible(find.text('CAPSULE'));
    await tester.pump();
    await tester.tap(find.text('CAPSULE'));
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
  FamilyRosterRefresh? refreshRoster,
}) => _observatoryWithOverride(
  vaultEntriesProvider.overrideWithValue(AsyncValue.data(entries)),
  mediaQuery: mediaQuery,
  rosterState: rosterState,
  refreshRoster: refreshRoster,
);

Widget _observatoryWithOverride(
  dynamic override, {
  MediaQueryData? mediaQuery,
  Future<EntryMetadata?> Function(BuildContext)? showCapture,
  InviteShareService? shareService,
  FamilyRosterState? rosterState,
  FamilyRosterRefresh? refreshRoster,
}) {
  final effectiveRoster =
      rosterState ??
      FamilyRosterState(members: _defaultRoster, hasLoadedLocal: true);
  return ProviderScope(
    overrides: [
      override,
      familyRosterProvider(_identity.familyId)
          .overrideWithBuild((ref, notifier) => effectiveRoster),
      familyRosterRefreshProvider(_identity.familyId)
          .overrideWithValue(refreshRoster ?? () async {}),
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

final class _NudgeShareService implements InviteShareService {
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
