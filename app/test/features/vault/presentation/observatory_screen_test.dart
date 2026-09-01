import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humation_flutter/humation_flutter.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/archive/presentation/archive_screen.dart';
import 'package:keepers/features/capsule/application/capsule_providers.dart';
import 'package:keepers/features/capsule/domain/capsule_models.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/ceremony/presentation/ceremony_screen.dart';
import 'package:keepers/features/ceremony/presentation/weekly_waiting_room_screen.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_code_controller.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/family_join_requests_controller.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/family/application/pending_join_completion_controller.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/invite_share_service.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/family/presentation/family_invite_sheet.dart';
import 'package:keepers/features/family/presentation/family_join_request_sheet.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/member_page_screen.dart';
import 'package:keepers/features/members/presentation/your_memories_screen.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/application/vault_providers.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/features/vault/presentation/observatory_screen.dart';
import 'package:keepers/sync/weekly_family_presence_provider.dart';
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

  test('an unavailable Weekly memory does not block valid memories', () async {
    final entries = [
      _metadata(MemoryFormat.photo, 1),
      _metadata(MemoryFormat.photo, 2),
      _metadata(MemoryFormat.photo, 3),
    ];
    final calls = <String>[];

    final opened = await loadWeeklyMemoriesSequentially(entries, (entry) async {
      calls.add(entry.id);
      if (entry.id == entries[1].id) {
        return const UnavailableMemory('Unreadable legacy memory');
      }
      return _openedPhoto(entry, Uint8List.fromList([11, 22, 33]));
    });

    expect(calls, entries.map((entry) => entry.id));
    expect(opened.map((memory) => memory.metadata.id), [
      entries.first.id,
      entries.last.id,
    ]);
  });

  test('Weekly loading fails safely when no memory can be opened', () async {
    final entries = [
      _metadata(MemoryFormat.photo, 1),
      _metadata(MemoryFormat.photo, 2),
    ];

    final loading = loadWeeklyMemoriesSequentially(
      entries,
      (_) async => const UnavailableMemory('Unreadable memory'),
    );

    await expectLater(
      loading,
      throwsA(
        isA<WeeklyMemoryLoadFailure>()
            .having((failure) => failure.attemptedCount, 'attemptedCount', 2)
            .having((failure) => failure.openedCount, 'openedCount', 0)
            .having(
              (failure) => failure.openedPhotoCount,
              'openedPhotoCount',
              0,
            ),
      ),
    );
  });

  test(
    'five authenticated photos still open when an extra entry is unreadable',
    () async {
      final entries = [
        _metadata(MemoryFormat.photo, 1),
        _metadata(MemoryFormat.photo, 2),
        _metadata(MemoryFormat.photo, 3),
        _metadata(MemoryFormat.photo, 4),
        _metadata(MemoryFormat.photo, 5),
        _metadata(MemoryFormat.text, 6),
      ];

      final opened = await loadWeeklyMemoriesSequentially(
        entries,
        (entry) async => entry.format == MemoryFormat.text
            ? const UnavailableMemory('Unreadable extra entry')
            : _openedPhoto(entry, Uint8List.fromList([1, 2, 3])),
        minimumOpenedPhotos: 5,
      );

      expect(
        opened.map((memory) => memory.metadata.id),
        entries.take(5).map((entry) => entry.id),
      );
    },
  );

  test(
    'fewer than five authenticated photos fail and clear opened media',
    () async {
      final entries = [
        _metadata(MemoryFormat.photo, 1),
        _metadata(MemoryFormat.photo, 2),
        _metadata(MemoryFormat.photo, 3),
        _metadata(MemoryFormat.photo, 4),
        _metadata(MemoryFormat.photo, 5),
      ];
      final decryptedBytes = <Uint8List>[];

      final loading = loadWeeklyMemoriesSequentially(entries, (entry) async {
        if (entry.id == entries.last.id) {
          return const UnavailableMemory('Unreadable photo');
        }
        final bytes = Uint8List.fromList([entry.createdAt.second]);
        decryptedBytes.add(bytes);
        return _openedPhoto(entry, bytes);
      }, minimumOpenedPhotos: 5);

      await expectLater(
        loading,
        throwsA(
          isA<WeeklyMemoryLoadFailure>()
              .having((failure) => failure.attemptedCount, 'attemptedCount', 5)
              .having((failure) => failure.openedCount, 'openedCount', 4)
              .having(
                (failure) => failure.openedPhotoCount,
                'openedPhotoCount',
                4,
              ),
        ),
      );
      for (final bytes in decryptedBytes) {
        expect(bytes, everyElement(0));
      }
    },
  );

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

  test('archive preview opens only an exact kept photo', () async {
    final keptPhoto = _metadata(MemoryFormat.photo, 1).copyWith(state: 'kept');
    final pendingPhoto = _metadata(MemoryFormat.photo, 2);
    final keptVoice = _metadata(MemoryFormat.voice, 3).copyWith(state: 'kept');
    final keptText = _metadata(MemoryFormat.text, 4).copyWith(state: 'kept');
    final previewBytes = Uint8List.fromList([1, 2, 3]);
    final openedIds = <String>[];
    final sourceLimits = <int>[];

    Future<MemoryOpenResult> open(
      VaultEntryMetadata entry, {
      required int maxSourceBytes,
    }) async {
      openedIds.add(entry.id);
      sourceLimits.add(maxSourceBytes);
      if (!identical(entry, keptPhoto)) {
        throw StateError('An ineligible archive entry was opened');
      }
      return _openedPhoto(entry, previewBytes);
    }

    final loaded = await loadArchivePhotoPreview(
      summary: _archiveMemory(keptPhoto),
      entries: [keptPhoto, pendingPhoto, keptVoice, keptText],
      open: open,
    );

    expect(loaded, same(previewBytes));
    expect(openedIds, [keptPhoto.id]);
    expect(sourceLimits, [archivePhotoPreviewMaxSourceBytes]);
    expect(
      await loadArchivePhotoPreview(
        summary: _archiveMemory(pendingPhoto),
        entries: [keptPhoto, pendingPhoto, keptVoice, keptText],
        open: open,
      ),
      isNull,
    );
    expect(
      await loadArchivePhotoPreview(
        summary: _archiveMemory(keptVoice),
        entries: [keptPhoto, pendingPhoto, keptVoice, keptText],
        open: open,
      ),
      isNull,
    );
    expect(
      await loadArchivePhotoPreview(
        summary: _archiveMemory(keptText),
        entries: [keptPhoto, pendingPhoto, keptVoice, keptText],
        open: open,
      ),
      isNull,
    );
    expect(openedIds, [keptPhoto.id]);
  });

  test(
    'archive preview rejects unavailable or malformed results safely',
    () async {
      final keptPhoto = _metadata(
        MemoryFormat.photo,
        1,
      ).copyWith(state: 'kept');
      final summary = _archiveMemory(keptPhoto);

      expect(
        await loadArchivePhotoPreview(
          summary: summary,
          entries: [keptPhoto],
          open: (_, {required int maxSourceBytes}) async =>
              const UnavailableMemory('Unavailable'),
        ),
        isNull,
      );
      expect(
        await loadArchivePhotoPreview(
          summary: summary,
          entries: [keptPhoto],
          open: (_, {required int maxSourceBytes}) async =>
              throw StateError('Vault unavailable'),
        ),
        isNull,
      );

      final wrongFormatBytes = Uint8List.fromList([4, 5, 6]);
      expect(
        await loadArchivePhotoPreview(
          summary: summary,
          entries: [keptPhoto],
          open: (entry, {required int maxSourceBytes}) async => OpenedMemory(
            metadata: entry,
            payload: EntryPayload(
              format: MemoryFormat.voice,
              primaryBytes: wrongFormatBytes,
              text: null,
              caption: null,
              mediaExtension: 'm4a',
              mediaDurationMs: 1000,
            ),
          ),
        ),
        isNull,
      );
      expect(wrongFormatBytes, everyElement(0));

      final mismatchedBytes = Uint8List.fromList([7, 8, 9]);
      expect(
        await loadArchivePhotoPreview(
          summary: summary,
          entries: [keptPhoto],
          open: (entry, {required int maxSourceBytes}) async => _openedPhoto(
            entry.copyWith(id: 'another-entry'),
            mismatchedBytes,
          ),
        ),
        isNull,
      );
      expect(mismatchedBytes, everyElement(0));
    },
  );

  test('archive preview fails closed for stale or missing summaries', () async {
    final keptPhoto = _metadata(MemoryFormat.photo, 1).copyWith(state: 'kept');
    var openCalls = 0;

    Future<MemoryOpenResult> open(
      VaultEntryMetadata entry, {
      required int maxSourceBytes,
    }) async {
      openCalls += 1;
      return _openedPhoto(entry, Uint8List.fromList([1]));
    }

    expect(
      await loadArchivePhotoPreview(
        summary: _archiveMemory(keptPhoto, id: 'stale-entry'),
        entries: [keptPhoto],
        open: open,
      ),
      isNull,
    );
    expect(
      await loadArchivePhotoPreview(
        summary: _archiveMemory(keptPhoto),
        entries: const [],
        open: open,
      ),
      isNull,
    );
    expect(openCalls, 0);
  });

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
    expect(find.bySemanticsLabel('You, Chris, 0% sealed'), findsOneWidget);
    expect(find.bySemanticsLabel('Noura, away, 0% sealed'), findsOneWidget);
    expect(find.bySemanticsLabel('Mariam, away, 0% sealed'), findsOneWidget);
    expect(find.bySemanticsLabel('Youssef, away, 0% sealed'), findsOneWidget);
    expect(find.bySemanticsLabel('Layla, away, 0% sealed'), findsOneWidget);
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

  testWidgets('remote roster preserves stored identity and zero contribution', (
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
    expect(wheel.members.single.contribution, 0);
    expect(wheel.members.single.presence, FamilyPresence.away);
    expect(find.bySemanticsLabel('Amina, away, 0% sealed'), findsOneWidget);
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

  testWidgets(
    'owner bootstrap retries a persistent forbidden roster only once across authoritative identity binding',
    (tester) async {
      const accountId = 'account-1';
      final boundIdentity = LocalIdentity(
        familyId: _identity.familyId,
        familyName: _identity.familyName,
        familyKeyRef: _identity.familyKeyRef,
        memberId: _identity.memberId,
        memberName: _identity.memberName,
        memberKeyRef: _identity.memberKeyRef,
        colorToken: _identity.colorToken,
        avatar: _identity.avatar,
        accountId: accountId,
      );
      final gateway = _ObservatoryCloudGateway(accountId);
      var rosterRefreshes = 0;
      final firstRefreshStarted = Completer<void>();
      final finishFirstRefresh = Completer<void>();
      final persistentForbiddenRoster = FamilyRosterState(
        members: [_currentMember],
        hasLoadedLocal: true,
        refreshFailure: const InvitationFailure(
          InvitationFailureCode.forbidden,
        ),
      );
      final roster = _ObservatoryRosterStateController(
        persistentForbiddenRoster,
      );
      final code = _ObservatoryFamilyCodeController(
        initial: const FamilyCodeState(),
      );
      Future<void> refreshRoster() async {
        rosterRefreshes += 1;
        if (rosterRefreshes != 1) return;
        firstRefreshStarted.complete();
        await finishFirstRefresh.future;
        roster.emit(
          FamilyRosterState(
            members: [_currentMember],
            hasLoadedLocal: true,
            refreshFailure: const InvitationFailure(
              InvitationFailureCode.forbidden,
            ),
          ),
        );
      }

      await tester.pumpWidget(
        _observatory(
          entries: const [],
          rosterController: roster,
          codeController: code,
          cloudGateway: gateway,
          refreshRoster: refreshRoster,
        ),
      );
      await tester.pump();
      expect(find.text('FAMILY UPDATE UNAVAILABLE'), findsOneWidget);

      code.emit(
        const FamilyCodeState(
          phase: FamilyCodePhase.ready,
          displayCode: 'K7M4-P2Q8',
          codeVersion: 1,
          isCreator: true,
        ),
      );
      await tester.pump();
      await firstRefreshStarted.future;

      // The code controller has authoritatively bound this local profile, but
      // the Observatory receives that identity update on the following frame.
      await tester.pumpWidget(
        _observatory(
          entries: const [],
          identity: boundIdentity,
          rosterController: roster,
          codeController: code,
          cloudGateway: gateway,
          refreshRoster: refreshRoster,
        ),
      );
      finishFirstRefresh.complete();
      await tester.pump();
      await tester.pump();

      expect(rosterRefreshes, 1);
      expect(find.text('FAMILY UPDATE UNAVAILABLE'), findsOneWidget);
    },
  );

  testWidgets(
    'account-family conflict replaces the family UI with safe recovery',
    (tester) async {
      var accountSwitches = 0;
      await tester.pumpWidget(
        _observatory(
          entries: const [],
          codeController: _ObservatoryFamilyCodeController(
            initial: const FamilyCodeState(
              phase: FamilyCodePhase.failed,
              failure: FamilyJoinFailure(
                FamilyJoinFailureCode.accountFamilyConflict,
              ),
            ),
          ),
          onUseAnotherAccount: () async => accountSwitches += 1,
        ),
      );
      await tester.pump();

      expect(find.byType(FamilyWheelScreen), findsNothing);
      expect(
        find.text('THIS ACCOUNT IS ALREADY CONNECTED TO ANOTHER FAMILY.'),
        findsOneWidget,
      );
      expect(find.text('Use another account'), findsOneWidget);
      await tester.tap(find.text('Use another account'));
      await tester.pump();
      expect(accountSwitches, 1);
    },
  );

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

  testWidgets('archive receives a photo preview loader', (tester) async {
    await tester.pumpWidget(_observatory(entries: const []));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Archive'));
    await tester.pump();

    final archive = tester.widget<ArchiveScreen>(find.byType(ArchiveScreen));
    expect(archive.loadPhotoPreview, isNotNull);
  });

  testWidgets('archive suspends previews while a memory viewer covers it', (
    tester,
  ) async {
    final entry = _metadata(MemoryFormat.photo, 1).copyWith(state: 'kept');
    await tester.pumpWidget(_observatory(entries: [entry]));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Archive'));
    await tester.pump();

    var archive = tester.widget<ArchiveScreen>(find.byType(ArchiveScreen));
    expect(archive.loadPhotoPreview, isNotNull);
    archive.onOpenMemory(_archiveMemory(entry));
    await tester.pump();

    final coveredArchive = find.byType(ArchiveScreen, skipOffstage: false);
    archive = tester.widget<ArchiveScreen>(coveredArchive);
    expect(archive.loadPhotoPreview, isNull);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    archive = tester.widget<ArchiveScreen>(find.byType(ArchiveScreen));
    expect(archive.loadPhotoPreview, isNotNull);
  });

  testWidgets('archive suspends previews while the app is backgrounded', (
    tester,
  ) async {
    await tester.pumpWidget(_observatory(entries: const []));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Archive'));
    await tester.pump();

    expect(
      tester.widget<ArchiveScreen>(find.byType(ArchiveScreen)).loadPhotoPreview,
      isNotNull,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(
      tester.widget<ArchiveScreen>(find.byType(ArchiveScreen)).loadPhotoPreview,
      isNull,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
      tester.widget<ArchiveScreen>(find.byType(ArchiveScreen)).loadPhotoPreview,
      isNotNull,
    );
  });

  testWidgets('archive ignores a stale open request', (tester) async {
    await tester.pumpWidget(_observatory(entries: const []));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Archive'));
    await tester.pump();

    final archive = tester.widget<ArchiveScreen>(find.byType(ArchiveScreen));
    final stale = _metadata(MemoryFormat.photo, 1).copyWith(state: 'kept');
    expect(() => archive.onOpenMemory(_archiveMemory(stale)), returnsNormally);
    expect(tester.takeException(), isNull);
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
      _metadata(MemoryFormat.text, 4).copyWith(privacy: PrivacyTier.capsule),
      _metadata(MemoryFormat.text, 5).copyWith(authorId: 'member-2'),
    ];
    await tester.pumpWidget(_observatory(entries: entries));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('You, Chris, 0% sealed'));
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
    expect(find.text('Capsule'), findsOneWidget);
    expect(find.text('Shared as Capsule'), findsOneWidget);
    expect(find.textContaining('milestone'), findsNothing);
    expect(
      find.text(
        'Everything you have kept lives here, including Weekly Reveal and Capsule memories.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('capture success refreshes contribution before haptics', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 9, 12);
    final saved = _entryMetadata(MemoryFormat.photo, 3);
    final refreshed = _metadata(
      MemoryFormat.photo,
      3,
    ).copyWith(createdAt: now.toUtc());
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
        now: now,
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

  testWidgets('canonical destinations expose one Capsule Memory Key', (
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
    expect(find.textContaining('Legacy'), findsNothing);
    expect(find.text('Capsule'), findsOneWidget);

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

  testWidgets('Memory Key receives persisted Capsule state and safe metadata', (
    tester,
  ) async {
    final entry = _metadata(
      MemoryFormat.photo,
      9,
    ).copyWith(privacy: PrivacyTier.capsule, authorId: 'noura');
    final assignment = _capsuleAssignment(
      id: 'capsule-1',
      contentEntryId: entry.id,
      authorId: 'noura',
      unlockTask: 'Share one family story.',
      state: CapsuleAssignmentState.locked,
    );
    await tester.pumpWidget(
      _observatory(
        entries: [entry],
        capsuleAssignments: AsyncValue.data([assignment]),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Memory Key'));
    await tester.pump();

    final ceremony = tester.widget<CeremonyScreen>(find.byType(CeremonyScreen));
    expect(ceremony.capsuleAssignments, [assignment]);
    expect(ceremony.capsuleEntries, {entry.id: entry});
    expect(ceremony.capsuleAuthorNames['noura'], 'Noura');
    expect(ceremony.capsuleLoading, isFalse);
    expect(ceremony.capsuleErrorMessage, isNull);
    expect(ceremony.onCompleteCapsuleTask, isNotNull);
    expect(ceremony.onOpenCapsule, isNotNull);
    expect(find.text('Share one family story.'), findsOneWidget);
    expect(find.text('From Noura'), findsOneWidget);
    expect(find.text('Photo memory · 09 Aug 2026'), findsOneWidget);
    expect(find.textContaining('Legacy'), findsNothing);
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

  testWidgets('pending family request can be reviewed outside the wheel', (
    tester,
  ) async {
    final requests = _ObservatoryJoinRequestsController(
      FamilyJoinRequestsState(requests: [_pendingJoinRequest]),
    );
    await tester.pumpWidget(
      _observatory(entries: const [], requestsController: requests),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Archive'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('global-family-join-request-notice')),
      findsOneWidget,
    );
    expect(find.text('AMINA WANTS TO JOIN YOUR FAMILY'), findsOneWidget);
    await tester.tap(find.text('REVIEW REQUEST'));
    await tester.pumpAndSettle();

    expect(find.byType(FamilyJoinRequestSheet), findsOneWidget);
    await tester.tap(find.byKey(const Key('approve-join-request')));
    await tester.pumpAndSettle();
    expect(requests.approveCalls, 1);
    expect(
      find.byKey(const ValueKey('global-family-join-request-notice')),
      findsNothing,
    );
  });

  testWidgets('owner bootstrap retries the pending request inbox', (
    tester,
  ) async {
    final code = _ObservatoryFamilyCodeController(
      initial: const FamilyCodeState(phase: FamilyCodePhase.loading),
    );
    final requests = _ObservatoryJoinRequestsController(
      const FamilyJoinRequestsState(
        failure: FamilyJoinFailure(FamilyJoinFailureCode.forbidden),
      ),
    );
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        codeController: code,
        requestsController: requests,
      ),
    );
    await tester.pump();

    code.emit(
      const FamilyCodeState(
        phase: FamilyCodePhase.ready,
        displayCode: 'K7M4-P2Q8',
        codeVersion: 1,
        isCreator: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(requests.refreshCalls, 1);
  });

  testWidgets('owner can retry when pending requests fail to load', (
    tester,
  ) async {
    final requests = _ObservatoryJoinRequestsController(
      const FamilyJoinRequestsState(
        failure: FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable),
      ),
    );
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        codeController: _ObservatoryFamilyCodeController(
          initial: const FamilyCodeState(
            phase: FamilyCodePhase.ready,
            displayCode: 'K7M4-P2Q8',
            codeVersion: 1,
            isCreator: true,
          ),
        ),
        requestsController: requests,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('family-join-requests-failure-notice')),
      findsOneWidget,
    );
    await tester.tap(find.text('RETRY'));
    await tester.pump();

    expect(requests.refreshCalls, 1);
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

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('weekly-recap-mode')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('weekly-recap-mode')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Memory Key'));
    await tester.pump();
    expect(find.byKey(const ValueKey('memory-key-legacy-entry')), findsNothing);
    expect(find.text('Capsule'), findsOneWidget);
    expect(find.bySemanticsLabel('Relative 17, away'), findsNothing);
  });

  testWidgets(
    'persisted remote profile shows derived contribution without sealed entries',
    (tester) async {
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

      await tester.tap(find.bySemanticsLabel('Amina, away, 0% sealed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(MemberPageScreen), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Amina avatar')), findsOneWidget);
      expect(find.text('0% of this week sealed'), findsOneWidget);
      expect(find.textContaining('sealed this week'), findsNothing);
      expect(
        find.text('Current-week memories stay closed until ceremony.'),
        findsNothing,
      );
    },
  );

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
    expect(find.text('Random Memory'), findsOneWidget);
    expect(find.bySemanticsLabel('1 memory kept forever'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Memory Key'));
    await tester.pump();
    expect(find.text('Random Memory'), findsNothing);
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

    final archive = tester.widget<ArchiveScreen>(find.byType(ArchiveScreen));
    expect(archive.memories.single.authorName, 'Noura');
    expect(archive.memories.single.theme, 'Voices');
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

  testWidgets(
    'contribution rings use each author current-week pending Reveal photos',
    (tester) async {
      final now = DateTime(2026, 9, 9, 12);
      final thisWeek = now.subtract(const Duration(hours: 1)).toUtc();
      final priorWeek = now.subtract(const Duration(days: 8)).toUtc();
      await tester.pumpWidget(
        _observatory(
          entries: [
            _metadata(MemoryFormat.photo, 1).copyWith(createdAt: thisWeek),
            _metadata(MemoryFormat.voice, 2).copyWith(createdAt: thisWeek),
            _metadata(MemoryFormat.photo, 3).copyWith(createdAt: priorWeek),
            _metadata(
              MemoryFormat.photo,
              4,
            ).copyWith(createdAt: thisWeek, state: 'kept'),
            _metadata(
              MemoryFormat.photo,
              5,
            ).copyWith(createdAt: thisWeek, privacy: PrivacyTier.journal),
            _metadata(
              MemoryFormat.photo,
              6,
            ).copyWith(authorId: 'noura', createdAt: thisWeek),
            _metadata(
              MemoryFormat.photo,
              7,
            ).copyWith(authorId: 'noura', createdAt: thisWeek),
            _metadata(
              MemoryFormat.photo,
              8,
            ).copyWith(authorId: 'noura', createdAt: priorWeek),
          ],
          now: now,
          rosterState: FamilyRosterState(
            members: [_currentMember, _relative('noura', 'Noura', 'clay')],
            hasLoadedLocal: true,
          ),
        ),
      );
      await tester.pump();

      final wheel = tester.widget<FamilyWheelScreen>(
        find.byType(FamilyWheelScreen),
      );
      expect(wheel.weeklyPhotoCount, 3);
      expect(wheel.yourContribution, 0.2);
      expect(wheel.members.single.contribution, 0.4);
      expect(find.bySemanticsLabel('You, Chris, 20% sealed'), findsOneWidget);
      expect(find.bySemanticsLabel('Noura, away, 40% sealed'), findsOneWidget);
    },
  );

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
    'incomplete Weekly stays locked without exposing a preview route',
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
      expect(find.byKey(const ValueKey('weekly-recap-preview')), findsNothing);
      expect(find.text('Preview weekly experience'), findsNothing);
      expect(find.byType(CeremonyScreen), findsNothing);
    },
  );

  testWidgets(
    'completed progress enters the waiting room without loading weekly media',
    (tester) async {
      final now = DateTime(2026, 9, 9, 12);
      final entries = List.generate(
        5,
        (index) => _metadata(
          MemoryFormat.photo,
          index + 1,
        ).copyWith(createdAt: now.subtract(Duration(hours: index + 1)).toUtc()),
      );
      var loadCalls = 0;

      await tester.pumpWidget(
        _observatory(
          entries: entries,
          now: now,
          weeklyMemoryLoader: (requested) async {
            loadCalls += 1;
            return requested
                .map(
                  (entry) => _openedPhoto(
                    entry,
                    Uint8List.fromList([entry.id.length]),
                  ),
                )
                .toList(growable: false);
          },
        ),
      );
      await tester.pump();

      tester
          .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
          .onEnterWeeklyWaitingRoom!
          .call();
      await tester.pump();

      expect(find.byKey(const ValueKey('weekly-waiting-room')), findsOneWidget);
      expect(find.byType(WeeklyWaitingRoomScreen), findsOneWidget);
      expect(find.text('1 of 5 family members are here'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('weekly-waiting-room-start')),
        findsNothing,
      );
      expect(loadCalls, 0);

      await tester.tap(find.byTooltip('Close waiting room'));
      await tester.pump();
      expect(find.byType(FamilyWheelScreen), findsOneWidget);
      expect(loadCalls, 0);
    },
  );

  testWidgets('quorum start loads the real Weekly payload exactly once', (
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
    var loadCalls = 0;

    await tester.pumpWidget(
      _observatory(
        entries: entries,
        now: now,
        rosterState: FamilyRosterState(
          members: [_currentMember],
          hasLoadedLocal: true,
        ),
        weeklyMemoryLoader: (requested) async {
          loadCalls += 1;
          return requested
              .map(
                (entry) =>
                    _openedPhoto(entry, Uint8List.fromList([entry.id.length])),
              )
              .toList(growable: false);
        },
      ),
    );
    await tester.pump();

    tester
        .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
        .onEnterWeeklyWaitingRoom!
        .call();
    await tester.pump();

    expect(find.byType(WeeklyWaitingRoomScreen), findsOneWidget);
    expect(loadCalls, 0);
    final start = find.byKey(const ValueKey('weekly-waiting-room-start'));
    expect(start, findsOneWidget);
    expect(find.text('Start weekly experience'), findsOneWidget);

    await tester.ensureVisible(start);
    await tester.pump();
    final room = tester.widget<WeeklyWaitingRoomScreen>(
      find.byType(WeeklyWaitingRoomScreen),
    );
    await tester.tap(start);
    room.onStart();
    await tester.pump();

    expect(loadCalls, 1);
    final ceremony = tester.widget<CeremonyScreen>(find.byType(CeremonyScreen));
    expect(ceremony.weeklyPreview, isFalse);
    expect(ceremony.weeklyMemories, isNotNull);
    expect(ceremony.onWeeklyDecision, isNotNull);
    expect(find.text('REHEARSAL MODE'), findsNothing);
  });

  testWidgets('fresh local presence starts a multi-member Weekly room', (
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
    var loadCalls = 0;
    await tester.pumpWidget(
      _observatory(
        entries: entries,
        now: now,
        rosterState: FamilyRosterState(
          members: [
            _currentMember,
            _relative('noura', 'Noura', 'clay'),
            _relative('mariam', 'Mariam', 'sea'),
            _relative('layla', 'Layla', 'sage'),
          ],
          hasLoadedLocal: true,
        ),
        presenceSnapshot: WeeklyFamilyPresenceSnapshot.observed(
          nearbyMemberIds: const {'noura', 'mariam'},
          observedAt: now.toUtc().subtract(const Duration(seconds: 2)),
        ),
        weeklyMemoryLoader: (_) async {
          loadCalls += 1;
          return const [];
        },
      ),
    );
    await tester.pump();

    tester
        .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
        .onEnterWeeklyWaitingRoom!
        .call();
    await tester.pump();

    expect(find.text('3 of 4 family members are here'), findsOneWidget);
    final start = find.byKey(const ValueKey('weekly-waiting-room-start'));
    expect(start, findsOneWidget);
    expect(loadCalls, 0);
    await tester.ensureVisible(start);
    await tester.pump();
    await tester.tap(start);
    await tester.pump();
    expect(loadCalls, 1);
  });

  testWidgets(
    'Weekly Start waits for roster refresh then recalculates a 4 to 5 member quorum',
    (tester) async {
      final now = DateTime(2026, 9, 9, 12);
      final entries = List.generate(
        5,
        (index) => _metadata(
          MemoryFormat.photo,
          index + 1,
        ).copyWith(createdAt: now.subtract(Duration(hours: index + 1)).toUtc()),
      );
      final cachedRoster = FamilyRosterState(
        members: [
          _currentMember,
          _relative('noura', 'Noura', 'clay'),
          _relative('mariam', 'Mariam', 'sea'),
          _relative('layla', 'Layla', 'sage'),
        ],
        hasLoadedLocal: true,
      );
      final refreshedRoster = FamilyRosterState(
        members: [
          ...cachedRoster.members,
          _relative('youssef', 'Youssef', 'ochre'),
        ],
        hasLoadedLocal: true,
      );
      final rosterController = _ObservatoryRosterStateController(cachedRoster);
      final presenceActions = _RecordingWeeklyPresenceActions();
      final releaseRefresh = Completer<void>();
      var refreshCalls = 0;
      var loadCalls = 0;

      await tester.pumpWidget(
        _observatory(
          entries: entries,
          now: now,
          rosterState: cachedRoster,
          rosterController: rosterController,
          presenceActions: presenceActions,
          refreshRoster: () async {
            refreshCalls += 1;
            rosterController.emit(
              FamilyRosterState(
                members: cachedRoster.members,
                hasLoadedLocal: true,
                isRefreshing: true,
              ),
            );
            await releaseRefresh.future;
            rosterController.emit(refreshedRoster);
          },
          presenceSnapshot: WeeklyFamilyPresenceSnapshot.observed(
            nearbyMemberIds: const {'noura', 'mariam'},
            observedAt: now.toUtc(),
          ),
          weeklyMemoryLoader: (_) async {
            loadCalls += 1;
            return const [];
          },
        ),
      );
      await tester.pump();

      tester
          .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
          .onEnterWeeklyWaitingRoom!
          .call();
      await tester.pump();

      expect(refreshCalls, 1);
      expect(presenceActions.starts, hasLength(1));
      expect(find.text('3 of 4 family members are here'), findsOneWidget);
      expect(find.text('Checking the latest family list…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('weekly-waiting-room-start')),
        findsNothing,
      );
      final pendingRoom = tester.widget<WeeklyWaitingRoomScreen>(
        find.byType(WeeklyWaitingRoomScreen),
      );
      expect(pendingRoom.onStart(), isFalse);
      expect(loadCalls, 0);

      releaseRefresh.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('3 of 5 family members are here'), findsOneWidget);
      expect(find.text('1 more family member needs to join'), findsOneWidget);
      expect(find.text('Checking the latest family list…'), findsNothing);
      expect(
        find.byKey(const ValueKey('weekly-waiting-room-start')),
        findsNothing,
      );
      expect(loadCalls, 0);
    },
  );

  testWidgets('Weekly presence session exists only while the room is open', (
    tester,
  ) async {
    final actions = _RecordingWeeklyPresenceActions();
    final roster = [
      _currentMember,
      _relative('noura', 'Noura', 'clay'),
      _relative('mariam', 'Mariam', 'sea'),
    ];
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        rosterState: FamilyRosterState(members: roster, hasLoadedLocal: true),
        presenceActions: actions,
      ),
    );
    await tester.pump();

    expect(actions.starts, isEmpty);
    tester
        .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
        .onEnterWeeklyWaitingRoom!
        .call();
    await tester.pump();

    expect(actions.starts, hasLength(1));
    expect(actions.starts.single.identity, _identity);
    expect(actions.starts.single.rosterMemberIds, {
      _currentMember.id,
      'noura',
      'mariam',
    });
    tester
        .widget<WeeklyWaitingRoomScreen>(find.byType(WeeklyWaitingRoomScreen))
        .onClose();
    await tester.pump();

    expect(actions.stopCalls, 1);
    expect(find.byType(FamilyWheelScreen), findsOneWidget);
  });

  testWidgets(
    'backgrounding stops presence and foreground waiting resumes it',
    (tester) async {
      final actions = _RecordingWeeklyPresenceActions();
      await tester.pumpWidget(
        _observatory(entries: const [], presenceActions: actions),
      );
      await tester.pump();
      tester
          .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
          .onEnterWeeklyWaitingRoom!
          .call();
      await tester.pump();
      expect(actions.starts, hasLength(1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(actions.stopCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(actions.starts, hasLength(2));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(actions.stopCalls, 2);
    },
  );

  testWidgets('active waiting room forwards roster changes to presence', (
    tester,
  ) async {
    final actions = _RecordingWeeklyPresenceActions();
    final initialRoster = FamilyRosterState(
      members: [_currentMember, _relative('noura', 'Noura', 'clay')],
      hasLoadedLocal: true,
    );
    final rosterController = _ObservatoryRosterStateController(initialRoster);
    await tester.pumpWidget(
      _observatory(
        entries: const [],
        rosterState: initialRoster,
        rosterController: rosterController,
        presenceActions: actions,
      ),
    );
    await tester.pump();
    tester
        .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
        .onEnterWeeklyWaitingRoom!
        .call();
    await tester.pump();

    rosterController.emit(
      FamilyRosterState(
        members: [_currentMember, _relative('mariam', 'Mariam', 'sea')],
        hasLoadedLocal: true,
      ),
    );
    await tester.pump();

    expect(actions.rosterUpdates.last, {_currentMember.id, 'mariam'});
  });

  testWidgets('accepted Weekly Start stops presence before loading memories', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 9, 12);
    final actions = _RecordingWeeklyPresenceActions();
    final callOrder = <String>[];
    final entries = List.generate(
      5,
      (index) => _metadata(
        MemoryFormat.photo,
        index + 1,
      ).copyWith(createdAt: now.subtract(Duration(hours: index + 1)).toUtc()),
    );
    actions.onStop = () => callOrder.add('stop');
    await tester.pumpWidget(
      _observatory(
        entries: entries,
        now: now,
        rosterState: FamilyRosterState(
          members: [_currentMember],
          hasLoadedLocal: true,
        ),
        presenceActions: actions,
        weeklyMemoryLoader: (_) async {
          callOrder.add('load');
          return const [];
        },
      ),
    );
    await tester.pump();
    tester
        .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
        .onEnterWeeklyWaitingRoom!
        .call();
    await tester.pump();

    final room = tester.widget<WeeklyWaitingRoomScreen>(
      find.byType(WeeklyWaitingRoomScreen),
    );
    expect(room.onStart(), isTrue);
    await tester.pump();

    expect(callOrder, ['stop', 'load']);
  });

  testWidgets('Weekly start rejects presence that expires during the reveal', (
    tester,
  ) async {
    var clock = DateTime(2026, 9, 9, 12);
    final entries = List.generate(
      5,
      (index) => _metadata(
        MemoryFormat.photo,
        index + 1,
      ).copyWith(createdAt: clock.subtract(Duration(hours: index + 1)).toUtc()),
    );
    var loadCalls = 0;
    await tester.pumpWidget(
      _observatory(
        entries: entries,
        nowProvider: () => clock.toUtc(),
        mediaQuery: const MediaQueryData(disableAnimations: false),
        rosterState: FamilyRosterState(
          members: [
            _currentMember,
            _relative('noura', 'Noura', 'clay'),
            _relative('mariam', 'Mariam', 'sea'),
            _relative('layla', 'Layla', 'sage'),
          ],
          hasLoadedLocal: true,
        ),
        presenceSnapshot: WeeklyFamilyPresenceSnapshot.observed(
          nearbyMemberIds: const {'noura', 'mariam'},
          observedAt: clock.toUtc(),
        ),
        weeklyMemoryLoader: (_) async {
          loadCalls += 1;
          return const [];
        },
      ),
    );
    await tester.pump();

    tester
        .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
        .onEnterWeeklyWaitingRoom!
        .call();
    await tester.pump();
    final start = find.byKey(const ValueKey('weekly-waiting-room-start'));
    await tester.ensureVisible(start);
    await tester.pump();
    await tester.tap(start);
    await tester.pump();

    clock = clock.add(
      weeklyFamilyPresenceFreshness + const Duration(milliseconds: 1),
    );
    await tester.pump(
      weeklyWaitingRoomRevealDuration + const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();

    expect(loadCalls, 0);
    expect(find.text('1 of 4 family members are here'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('weekly-waiting-room-start')),
      findsNothing,
    );
  });

  testWidgets('waiting room removes stale presence when its TTL expires', (
    tester,
  ) async {
    var clock = DateTime(2026, 9, 9, 12);
    final entries = List.generate(
      5,
      (index) => _metadata(
        MemoryFormat.photo,
        index + 1,
      ).copyWith(createdAt: clock.subtract(Duration(hours: index + 1)).toUtc()),
    );
    await tester.pumpWidget(
      _observatory(
        entries: entries,
        nowProvider: () => clock.toUtc(),
        rosterState: FamilyRosterState(
          members: [
            _currentMember,
            _relative('noura', 'Noura', 'clay'),
            _relative('mariam', 'Mariam', 'sea'),
            _relative('layla', 'Layla', 'sage'),
          ],
          hasLoadedLocal: true,
        ),
        presenceSnapshot: WeeklyFamilyPresenceSnapshot.observed(
          nearbyMemberIds: const {'noura', 'mariam'},
          observedAt: clock.toUtc(),
        ),
      ),
    );
    await tester.pump();

    tester
        .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
        .onEnterWeeklyWaitingRoom!
        .call();
    await tester.pump();
    expect(find.text('3 of 4 family members are here'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('weekly-waiting-room-start')),
      findsOneWidget,
    );

    final expiryDelay =
        weeklyFamilyPresenceFreshness + const Duration(milliseconds: 1);
    clock = clock.add(expiryDelay);
    await tester.pump(expiryDelay);
    await tester.pump();

    expect(find.text('1 of 4 family members are here'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('weekly-waiting-room-start')),
      findsNothing,
    );
  });

  testWidgets('Weekly start revalidates photos after Monday rollover', (
    tester,
  ) async {
    var clock = DateTime(2026, 9, 13, 23, 59);
    final entries = List.generate(
      5,
      (index) => _metadata(
        MemoryFormat.photo,
        index + 1,
      ).copyWith(createdAt: clock.subtract(Duration(hours: index + 1)).toUtc()),
    );
    var loadCalls = 0;

    await tester.pumpWidget(
      _observatory(
        entries: entries,
        nowProvider: () => clock.toUtc(),
        rosterState: FamilyRosterState(
          members: [_currentMember],
          hasLoadedLocal: true,
        ),
        weeklyMemoryLoader: (_) async {
          loadCalls += 1;
          return const [];
        },
      ),
    );
    await tester.pump();

    tester
        .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
        .onEnterWeeklyWaitingRoom!
        .call();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('weekly-waiting-room-start')),
      findsOneWidget,
    );

    clock = DateTime(2026, 9, 14, 0, 1);
    final start = find.byKey(const ValueKey('weekly-waiting-room-start'));
    await tester.ensureVisible(start);
    await tester.pump();
    await tester.tap(start);
    await tester.pump();

    expect(loadCalls, 0);
    expect(
      find.text(
        'Weekly progress changed. Return to the Wheel to finish five photos.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('weekly-waiting-room-start')),
      findsNothing,
    );
  });

  testWidgets(
    'loading and a 5-to-4 photo refresh recover without stale Start',
    (tester) async {
      final now = DateTime(2026, 9, 9, 12);
      final entries = List.generate(
        5,
        (index) => _metadata(
          MemoryFormat.photo,
          index + 1,
        ).copyWith(createdAt: now.subtract(Duration(hours: index + 1)).toUtc()),
      );
      final reload = Completer<List<VaultEntryMetadata>>();
      var providerCalls = 0;
      var loadCalls = 0;
      final rosterState = FamilyRosterState(
        members: [_currentMember],
        hasLoadedLocal: true,
      );
      await tester.pumpWidget(
        _observatoryWithOverride(
          vaultEntriesProvider.overrideWith((ref) async {
            providerCalls += 1;
            if (providerCalls == 1 || providerCalls >= 3) return entries;
            return reload.future;
          }),
          now: now,
          rosterState: rosterState,
          weeklyMemoryLoader: (_) async {
            loadCalls += 1;
            return const [];
          },
        ),
      );
      await tester.pumpAndSettle();

      tester
          .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
          .onEnterWeeklyWaitingRoom!
          .call();
      await tester.pump();
      final start = find.byKey(const ValueKey('weekly-waiting-room-start'));
      await tester.ensureVisible(start);
      await tester.pump();

      final roomBeforeRefresh = tester.widget<WeeklyWaitingRoomScreen>(
        find.byType(WeeklyWaitingRoomScreen),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ObservatoryScreen)),
      );
      container.invalidate(vaultEntriesProvider);
      expect(roomBeforeRefresh.onStart(), isFalse);
      await tester.pump();
      await tester.pump();
      expect(loadCalls, 0);
      expect(start, findsNothing);

      reload.complete(entries.take(4).toList(growable: false));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Weekly progress changed. Return to the Wheel to finish five photos.',
        ),
        findsOneWidget,
      );

      container.invalidate(vaultEntriesProvider);
      await tester.pumpAndSettle();
      final recoveredStart = find.byKey(
        const ValueKey('weekly-waiting-room-start'),
      );
      expect(recoveredStart, findsOneWidget);
      expect(tester.widget<FilledButton>(recoveredStart).onPressed, isNotNull);
      await tester.tap(recoveredStart);
      await tester.pump();
      expect(loadCalls, 1);
    },
  );

  testWidgets(
    'identity replacement releases pending and completed Weekly payloads',
    (tester) async {
      const replacementIdentity = LocalIdentity(
        familyId: 'family-2',
        familyName: 'Second family',
        familyKeyRef: 'family-key-2',
        memberId: 'member-2',
        memberName: 'Taylor',
        memberKeyRef: 'member-key-2',
        colorToken: 'sea',
        avatar: AvatarConfig.defaults(seed: 'member-2'),
        accountId: 'account-2',
      );
      final replacementMember = FamilyMember(
        id: replacementIdentity.memberId,
        familyId: replacementIdentity.familyId,
        name: replacementIdentity.memberName,
        role: 'adult',
        colorToken: replacementIdentity.colorToken,
        avatar: replacementIdentity.avatar,
        joinedAt: DateTime.utc(2026, 9, 8),
      );
      final now = DateTime(2026, 9, 9, 12);
      final entries = List.generate(
        5,
        (index) => _metadata(
          MemoryFormat.photo,
          index + 1,
        ).copyWith(createdAt: now.subtract(Duration(hours: index + 1)).toUtc()),
      );

      for (final completeBeforeSwitch in const [false, true]) {
        final bytes = Uint8List.fromList(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
            'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );
        final load = Completer<List<OpenedMemory>>();
        final container = ProviderContainer(
          overrides: [
            vaultEntriesProvider.overrideWithValue(AsyncValue.data(entries)),
            familyRosterProvider(_identity.familyId).overrideWithBuild(
              (ref, notifier) => FamilyRosterState(
                members: [_currentMember],
                hasLoadedLocal: true,
              ),
            ),
            familyRosterProvider(replacementIdentity.familyId)
                .overrideWithBuild(
                  (ref, notifier) => FamilyRosterState(
                    members: [replacementMember],
                    hasLoadedLocal: true,
                  ),
                ),
            familyRosterRefreshProvider(_identity.familyId)
                .overrideWithValue(() async {}),
            familyRosterRefreshProvider(replacementIdentity.familyId)
                .overrideWithValue(() async {}),
            familyCodeControllerProvider(_identity.familyId)
                .overrideWith(_ObservatoryFamilyCodeController.new),
            familyCodeControllerProvider(replacementIdentity.familyId)
                .overrideWith(_ObservatoryFamilyCodeController.new),
            familyJoinRequestsControllerProvider(_identity.familyId)
                .overrideWith(_ObservatoryJoinRequestsController.new),
            familyJoinRequestsControllerProvider(replacementIdentity.familyId)
                .overrideWith(_ObservatoryJoinRequestsController.new),
            utcNowProvider.overrideWithValue(() => now.toUtc()),
          ],
        );
        Widget host(
          LocalIdentity identity, {
          WeeklyMemoryLoader? weeklyMemoryLoader,
        }) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: KeepersTheme.dark(),
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: ObservatoryScreen(
                identity: identity,
                onUseAnotherAccount: () async {},
                weeklyMemoryLoader: weeklyMemoryLoader,
              ),
            ),
          ),
        );

        await tester.pumpWidget(
          host(_identity, weeklyMemoryLoader: (_) => load.future),
        );
        await tester.pump();

        tester
            .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
            .onEnterWeeklyWaitingRoom!
            .call();
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('weekly-waiting-room-start')),
        );
        await tester.pump();

        if (completeBeforeSwitch) {
          load.complete([_openedPhoto(entries.first, bytes)]);
          await tester.pump();
          expect(bytes, isNot(everyElement(0)));
        }

        await tester.pumpWidget(host(replacementIdentity));
        await tester.pump();

        expect(find.byType(FamilyWheelScreen), findsOneWidget);
        expect(find.byType(WeeklyWaitingRoomScreen), findsNothing);
        expect(find.byKey(const ValueKey('ceremony-reel')), findsNothing);

        if (!completeBeforeSwitch) {
          load.complete([_openedPhoto(entries.first, bytes)]);
          await tester.pump();
        }
        expect(bytes, everyElement(0));

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        container.dispose();
      }
    },
  );

  testWidgets('stale local presence cannot start a multi-member room', (
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
    var loadCalls = 0;
    await tester.pumpWidget(
      _observatory(
        entries: entries,
        now: now,
        rosterState: FamilyRosterState(
          members: [
            _currentMember,
            _relative('noura', 'Noura', 'clay'),
            _relative('mariam', 'Mariam', 'sea'),
            _relative('layla', 'Layla', 'sage'),
          ],
          hasLoadedLocal: true,
        ),
        presenceSnapshot: WeeklyFamilyPresenceSnapshot.observed(
          nearbyMemberIds: const {'noura', 'mariam', 'layla'},
          observedAt: now.toUtc().subtract(const Duration(minutes: 1)),
        ),
        weeklyMemoryLoader: (_) async {
          loadCalls += 1;
          return const [];
        },
      ),
    );
    await tester.pump();

    tester
        .widget<FamilyWheelScreen>(find.byType(FamilyWheelScreen))
        .onEnterWeeklyWaitingRoom!
        .call();
    await tester.pump();

    expect(find.text('1 of 4 family members are here'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('weekly-waiting-room-start')),
      findsNothing,
    );
    expect(loadCalls, 0);
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
  AsyncValue<List<CapsuleAssignment>> capsuleAssignments =
      const AsyncValue.data(<CapsuleAssignment>[]),
  LocalIdentity identity = _identity,
  MediaQueryData? mediaQuery,
  FamilyRosterState? rosterState,
  _ObservatoryRosterStateController? rosterController,
  FamilyRosterRefresh? refreshRoster,
  _ObservatoryFamilyCodeController? codeController,
  CloudFamilyGateway? cloudGateway,
  _ObservatoryJoinRequestsController? requestsController,
  FamilyJoinCompletionRecovery? recoverJoin,
  Future<List<OpenedMemory>> Function(List<VaultEntryMetadata>)?
  weeklyMemoryLoader,
  WeeklyFamilyPresenceSnapshot? presenceSnapshot,
  WeeklyFamilyPresenceSessionActions? presenceActions,
  DateTime? now,
  DateTime Function()? nowProvider,
  Future<void> Function()? onUseAnotherAccount,
}) => _observatoryWithOverride(
  vaultEntriesProvider.overrideWithValue(AsyncValue.data(entries)),
  capsuleAssignments: capsuleAssignments,
  identity: identity,
  mediaQuery: mediaQuery,
  rosterState: rosterState,
  rosterController: rosterController,
  refreshRoster: refreshRoster,
  codeController: codeController,
  cloudGateway: cloudGateway,
  requestsController: requestsController,
  recoverJoin: recoverJoin,
  weeklyMemoryLoader: weeklyMemoryLoader,
  presenceSnapshot: presenceSnapshot,
  presenceActions: presenceActions,
  now: now,
  nowProvider: nowProvider,
  onUseAnotherAccount: onUseAnotherAccount,
);

Widget _observatoryWithOverride(
  dynamic override, {
  AsyncValue<List<CapsuleAssignment>> capsuleAssignments =
      const AsyncValue.data(<CapsuleAssignment>[]),
  LocalIdentity identity = _identity,
  MediaQueryData? mediaQuery,
  Future<EntryMetadata?> Function(BuildContext)? showCapture,
  InviteShareService? shareService,
  FamilyRosterState? rosterState,
  _ObservatoryRosterStateController? rosterController,
  FamilyRosterRefresh? refreshRoster,
  _ObservatoryFamilyCodeController? codeController,
  CloudFamilyGateway? cloudGateway,
  _ObservatoryJoinRequestsController? requestsController,
  FamilyJoinCompletionRecovery? recoverJoin,
  Future<List<OpenedMemory>> Function(List<VaultEntryMetadata>)?
  weeklyMemoryLoader,
  WeeklyFamilyPresenceSnapshot? presenceSnapshot,
  WeeklyFamilyPresenceSessionActions? presenceActions,
  DateTime? now,
  DateTime Function()? nowProvider,
  Future<void> Function()? onUseAnotherAccount,
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
      capsuleAssignmentsProvider.overrideWithValue(capsuleAssignments),
      _observatoryRosterStateProvider.overrideWith(
        () => effectiveRosterController,
      ),
      familyRosterProvider(identity.familyId).overrideWithBuild(
        (ref, notifier) => ref.watch(_observatoryRosterStateProvider),
      ),
      familyRosterRefreshProvider(identity.familyId)
          .overrideWithValue(refreshRoster ?? () async {}),
      familyCodeControllerProvider(identity.familyId)
          .overrideWith(() => effectiveCode),
      if (cloudGateway != null)
        cloudFamilyGatewayProvider.overrideWithValue(cloudGateway),
      familyJoinRequestsControllerProvider(identity.familyId)
          .overrideWith(() => effectiveRequests),
      familyJoinCompletionRecoveryProvider.overrideWithValue(
        recoverJoin ?? () async => const PendingJoinCompletionState(),
      ),
      if (nowProvider != null)
        utcNowProvider.overrideWithValue(nowProvider)
      else if (now != null)
        utcNowProvider.overrideWithValue(() => now.toUtc()),
      if (shareService != null)
        inviteShareServiceProvider.overrideWithValue(shareService),
      if (presenceSnapshot != null)
        weeklyFamilyPresenceProvider(identity.familyId)
            .overrideWithValue(presenceSnapshot),
      weeklyFamilyPresenceSessionActionsProvider(
        identity.familyId,
      ).overrideWithValue(presenceActions ?? _RecordingWeeklyPresenceActions()),
    ],
    child: MaterialApp(
      theme: KeepersTheme.dark(),
      home: MediaQuery(
        data: mediaQuery ?? const MediaQueryData(disableAnimations: true),
        child: ObservatoryScreen(
          identity: identity,
          onUseAnotherAccount: onUseAnotherAccount ?? () async {},
          showCapture: showCapture,
          weeklyMemoryLoader: weeklyMemoryLoader,
        ),
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

final class _ObservatoryCloudGateway implements CloudFamilyGateway {
  const _ObservatoryCloudGateway(this.accountId);

  final String accountId;

  @override
  String? get authenticatedAccountId => accountId;

  @override
  String? get authenticatedEmail => 'owner@example.com';

  @override
  bool get isConfigured => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

final class _WeeklyPresenceStartCall {
  const _WeeklyPresenceStartCall({
    required this.identity,
    required this.rosterMemberIds,
  });

  final LocalIdentity identity;
  final Set<String> rosterMemberIds;
}

final class _RecordingWeeklyPresenceActions
    implements WeeklyFamilyPresenceSessionActions {
  final List<_WeeklyPresenceStartCall> starts = [];
  final List<Set<String>> rosterUpdates = [];
  var stopCalls = 0;
  void Function()? onStop;

  @override
  Future<void> start({
    required LocalIdentity identity,
    required Iterable<String> rosterMemberIds,
  }) async {
    starts.add(
      _WeeklyPresenceStartCall(
        identity: identity,
        rosterMemberIds: Set.unmodifiable(rosterMemberIds),
      ),
    );
  }

  @override
  Future<void> updateRoster(Iterable<String> rosterMemberIds) async {
    rosterUpdates.add(Set.unmodifiable(rosterMemberIds));
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    onStop?.call();
  }
}

final class _ObservatoryFamilyCodeController extends FamilyCodeController {
  _ObservatoryFamilyCodeController({
    this.initial = const FamilyCodeState(
      phase: FamilyCodePhase.ready,
      displayCode: 'K7M4-P2Q8',
      codeVersion: 1,
      isOffline: true,
    ),
  }) : super(_identity.familyId);

  final FamilyCodeState initial;

  var loadCalls = 0;

  @override
  FamilyCodeState build() => initial;

  void emit(FamilyCodeState next) => state = next;

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

CapsuleAssignment _capsuleAssignment({
  required String id,
  required String contentEntryId,
  required String authorId,
  required CapsuleAssignmentState state,
  String? unlockTask,
}) => CapsuleAssignment(
  id: id,
  familyId: 'family-1',
  authorId: authorId,
  targetId: 'member-1',
  contentEntryId: contentEntryId,
  unlockTask: unlockTask,
  state: state,
  createdAt: DateTime.utc(2026, 8, 9),
  openedAt: state == CapsuleAssignmentState.opened
      ? DateTime.utc(2026, 8, 10)
      : null,
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

ArchiveMemorySummary _archiveMemory(
  VaultEntryMetadata metadata, {
  String? id,
}) => ArchiveMemorySummary(
  id: id ?? metadata.id,
  title: '${metadata.format.vaultLabel} fixture',
  authorName: 'Chris',
  theme: 'Fixture theme',
  formatLabel: metadata.format.vaultLabel,
  createdAt: metadata.createdAt,
);
