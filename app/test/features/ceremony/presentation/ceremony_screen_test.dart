import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/capsule/domain/capsule_models.dart';
import 'package:keepers/features/capture/data/audio_playback_adapter.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/ceremony/presentation/ceremony_screen.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';

void main() {
  testWidgets('memory key is one Capsule list with no Legacy preview route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Rahman',
            currentMemberName: 'Chris',
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('memory-key-legacy-entry')), findsNothing);
    expect(find.textContaining('Legacy'), findsNothing);
    expect(find.textContaining('PREVIEW'), findsNothing);
    expect(find.text('Capsule'), findsOneWidget);
    expect(find.text('No Capsule memories for you yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('weekly-recap-mode')), findsNothing);
    expect(find.byKey(const ValueKey('random-memory-mode')), findsNothing);
  });

  testWidgets('memory key keeps loading and error states stable with Retry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Rahman',
            currentMemberName: 'Chris',
            capsuleLoading: true,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('capsule-loading')), findsOneWidget);
    expect(find.text('Loading Capsule memories…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Rahman',
            currentMemberName: 'Chris',
            capsuleErrorMessage: 'Capsule memories could not be loaded.',
            onRetryCapsules: () => retries += 1,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('capsule-error')), findsOneWidget);
    expect(find.text('Capsule memories could not be loaded.'), findsOneWidget);
    final retry = find.widgetWithText(FilledButton, 'Retry');
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
    await tester.tap(retry);
    expect(retries, 1);
  });

  testWidgets('memory key partitions locked and available Capsule memories', (
    tester,
  ) async {
    CapsuleAssignment? opened;
    final locked = _capsuleAssignment(
      id: 'locked',
      contentEntryId: 'locked-entry',
      unlockTask: 'Call Grandma together.',
      state: CapsuleAssignmentState.locked,
    );
    final ready = _capsuleAssignment(
      id: 'ready',
      contentEntryId: 'ready-entry',
      state: CapsuleAssignmentState.ready,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Rahman',
            currentMemberName: 'Chris',
            capsuleAssignments: [locked, ready],
            capsuleEntries: {
              'locked-entry': _capsuleMetadata(
                id: 'locked-entry',
                format: MemoryFormat.photo,
              ),
              'ready-entry': _capsuleMetadata(
                id: 'ready-entry',
                format: MemoryFormat.voice,
              ),
            },
            capsuleAuthorNames: const {'member-2': 'Layla'},
            onCompleteCapsuleTask: (_) async => true,
            onOpenCapsule: (value) => opened = value,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Locked by family'), findsOneWidget);
    expect(find.text('Capsule'), findsOneWidget);
    expect(find.text('Call Grandma together.'), findsOneWidget);
    expect(find.text('Photo memory · 07 Sep 2026'), findsOneWidget);
    expect(find.text('Voice memory · 07 Sep 2026'), findsOneWidget);
    expect(find.text('From Layla'), findsNWidgets(2));
    expect(find.text('Complete task'), findsOneWidget);
    final open = find.widgetWithText(FilledButton, 'Open memory');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pump();
    expect(opened?.id, ready.id);
  });

  testWidgets('memory key owns the selected slot in the five-control dock', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Rahman',
            currentMemberName: 'Chris',
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('keepers-nav-wheel')), findsOneWidget);
    expect(find.byKey(const ValueKey('keepers-nav-ceremony')), findsOneWidget);
    expect(find.byKey(const ValueKey('keepers-nav-capture')), findsOneWidget);
    expect(find.byKey(const ValueKey('keepers-nav-archive')), findsOneWidget);
    expect(find.byKey(const ValueKey('keepers-nav-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('keepers-nav-locks')), findsNothing);
    expect(find.bySemanticsLabel('Memory Key, selected'), findsOneWidget);

    final dock = tester.widget<KeepersBottomNav>(find.byType(KeepersBottomNav));
    expect(dock.selected, KeepersNavDestination.ceremony);
  });

  testWidgets('memory key entries begin directly beneath the compact header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            disableAnimations: true,
          ),
          child: CeremonyScreen(
            familyName: 'Rahman',
            currentMemberName: 'Chris',
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    final headerBottom = tester.getBottomLeft(find.text('Memory Key')).dy;
    final entriesTop = tester
        .getTopLeft(find.byKey(const ValueKey('capsule-locked-section')))
        .dy;
    expect(entriesTop - headerBottom, lessThan(48));
  });

  testWidgets('weekly playback exits back to the family wheel', (tester) async {
    KeepersNavDestination? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            startInWeekly: true,
            navigationDestination: KeepersNavDestination.wheel,
            onDestinationSelected: (destination) => selected = destination,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('ceremony-reel')), findsOneWidget);
    expect(find.text('Memory Key'), findsNothing);
    expect(find.byType(KeepersBottomNav), findsNothing);

    await tester.tap(find.byTooltip('Close weekly memories'));
    expect(selected, KeepersNavDestination.wheel);
  });

  testWidgets('live weekly playback renders decrypted current-week memories', (
    tester,
  ) async {
    final decisions = <WeeklyMemoryDisposition>[];
    final memory = OpenedMemory(
      metadata: VaultEntryMetadata(
        id: 'live-text',
        familyId: 'family-1',
        authorId: 'member-2',
        createdAt: DateTime.utc(2026, 9, 7, 12),
        format: MemoryFormat.text,
        privacy: PrivacyTier.reveal,
        blobRef: 'entries/blobs/live-text.keeper',
        state: 'pending',
      ),
      payload: const EntryPayload(
        format: MemoryFormat.text,
        primaryBytes: null,
        text: 'Mariam taught us the old card game after dinner.',
        caption: 'After dinner',
        mediaExtension: null,
        mediaDurationMs: null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            startInWeekly: true,
            weeklyPreview: false,
            weeklyMemories: Future.value([memory]),
            weeklyAuthorNames: const {'member-2': 'Mariam'},
            onWeeklyDecision: (metadata, disposition) async {
              expect(metadata.id, 'live-text');
              decisions.add(disposition);
            },
            navigationDestination: KeepersNavDestination.wheel,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Mariam taught us the old card game after dinner.'),
      findsOneWidget,
    );
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('REHEARSAL MODE'), findsNothing);
    expect(find.text('A small moment'), findsNothing);
    expect(find.text('16 May, 2025'), findsNothing);

    final keeping = find.widgetWithText(FilledButton, 'Begin keeping');
    await tester.ensureVisible(keeping);
    await tester.tap(keeping);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Keep this memory'));
    await tester.pumpAndSettle();

    expect(decisions, [WeeklyMemoryDisposition.keep]);
    expect(find.text('KEPT'), findsOneWidget);
  });

  testWidgets(
    'weekly conversation spark offers light and deeper questions without blocking the ritual',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final memory = OpenedMemory(
        metadata: _weeklyMetadata(
          id: 'family-dinner',
          format: MemoryFormat.text,
        ),
        payload: const EntryPayload(
          format: MemoryFormat.text,
          primaryBytes: null,
          text: 'We made pizza together after dinner.',
          caption: 'Family dinner',
          mediaExtension: null,
          mediaDurationMs: null,
        ),
      );

      await tester.pumpWidget(_liveMemoryCeremony(memory: memory));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('weekly-conversation-spark')),
        findsOneWidget,
      );
      expect(find.text('AI conversation spark'), findsOneWidget);
      expect(
        find.text('What was on the table that everyone kept reaching for?'),
        findsOneWidget,
      );

      final deeper = find.widgetWithText(OutlinedButton, 'Go deeper');
      await tester.ensureVisible(deeper);
      await tester.tap(deeper);
      await tester.pump();
      expect(
        find.text('Which family tradition would you like this meal to become?'),
        findsOneWidget,
      );

      final skip = find.widgetWithText(TextButton, 'Skip question');
      await tester.tap(skip);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('weekly-conversation-spark')),
        findsNothing,
      );
      final keeping = find.widgetWithText(FilledButton, 'Begin keeping');
      await tester.ensureVisible(keeping);
      expect(keeping.hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'disposing live voice while playback starts still requests teardown',
    (tester) async {
      final playback = _ControllablePlaybackAdapter();
      addTearDown(playback.releasePlayback);
      await tester.pumpWidget(_liveVoiceCeremony(playback: playback));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Play Voice Memory'));
      await playback.playStarted.future;

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(playback.stopCalls, 1);

      playback.releasePlayback();
      await playback.stopFinished.future;
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('live voice teardown absorbs playback cleanup failures', (
    tester,
  ) async {
    final playback = _ControllablePlaybackAdapter(
      stopError: StateError('cleanup failed'),
    );
    addTearDown(playback.releasePlayback);
    await tester.pumpWidget(_liveVoiceCeremony(playback: playback));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Play Voice Memory'));
    await playback.playStarted.future;
    playback.releasePlayback();
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await playback.stopFinished.future;
    await tester.pump();

    expect(playback.stopCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview decisions never call the live persistence callback', (
    tester,
  ) async {
    var writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            startInKeeping: true,
            onWeeklyDecision: (_, _) async => writes += 1,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Keep this memory'));
    await tester.pumpAndSettle();

    expect(writes, 0);
    expect(find.text('REHEARSAL MODE'), findsOneWidget);
    expect(find.text('KEPT'), findsOneWidget);
  });

  testWidgets('live release uses the released persistence disposition', (
    tester,
  ) async {
    WeeklyMemoryDisposition? disposition;
    final memory = OpenedMemory(
      metadata: VaultEntryMetadata(
        id: 'release-text',
        familyId: 'family-1',
        authorId: 'member-2',
        createdAt: DateTime.utc(2026, 9, 7, 12),
        format: MemoryFormat.text,
        privacy: PrivacyTier.reveal,
        blobRef: 'entries/blobs/release-text.keeper',
        state: 'pending',
      ),
      payload: const EntryPayload(
        format: MemoryFormat.text,
        primaryBytes: null,
        text: 'A current-week note.',
        caption: null,
        mediaExtension: null,
        mediaDurationMs: null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            startInWeekly: true,
            weeklyPreview: false,
            weeklyMemories: Future.value([memory]),
            onWeeklyDecision: (_, value) async => disposition = value,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final keeping = find.widgetWithText(FilledButton, 'Begin keeping');
    await tester.ensureVisible(keeping);
    await tester.tap(keeping);
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Release this memory'),
    );
    await tester.pumpAndSettle();

    expect(disposition, WeeklyMemoryDisposition.release);
    expect(find.text('RELEASED'), findsOneWidget);
  });

  testWidgets('weekly playback uses the focused cream gallery composition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            disableAnimations: true,
          ),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            startInWeekly: true,
            navigationDestination: KeepersNavDestination.wheel,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    final shell = tester.widget<Scaffold>(
      find.byKey(const ValueKey('weekly-experience-shell')),
    );
    expect(shell.backgroundColor, Colors.transparent);
    expect(find.byKey(const ValueKey('weekly-gallery-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('weekly-gallery-hero')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('weekly-gallery-filmstrip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('weekly-gallery-thumbnail-0')),
      findsOneWidget,
    );
    expect(find.text('16 May, 2025'), findsOneWidget);
    expect(find.byType(KeepersBottomNav), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly thumbnails keep the hero and date synchronized', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            startInWeekly: true,
            navigationDestination: KeepersNavDestination.wheel,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('weekly-gallery-thumbnail-1')));
    await tester.pumpAndSettle();

    expect(find.text('Voice memory'), findsOneWidget);
    expect(find.text('18 May, 2025'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Voice memory, selected, 2 of 3'),
      findsOneWidget,
    );
  });

  testWidgets(
    'weekly hero swipe advances the memory without a hidden gesture',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: KeepersTheme.daylight(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: CeremonyScreen(
              familyName: 'Sabati',
              currentMemberName: 'Chris',
              startInWeekly: true,
              navigationDestination: KeepersNavDestination.wheel,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      );

      await tester.drag(
        find.byKey(const ValueKey('weekly-gallery-hero')),
        const Offset(-220, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voice memory'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('weekly-gallery-thumbnail-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('weekly recap moves through every format into keeping', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            startInWeekly: true,
            navigationDestination: KeepersNavDestination.wheel,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Photo memory'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('weekly-gallery-thumbnail-1')));
    await tester.pumpAndSettle();
    expect(find.text('Voice memory'), findsOneWidget);
    await tester.tap(find.byTooltip('Play Rehearsal Voice Memory'));
    await tester.pump();
    expect(find.byTooltip('Pause Rehearsal Voice Memory'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('weekly-gallery-thumbnail-2')));
    await tester.pumpAndSettle();
    expect(find.text('Text memory'), findsOneWidget);
    expect(find.text('An echo from before'), findsOneWidget);

    final echoButton = find.widgetWithText(OutlinedButton, 'Open echo');
    await tester.ensureVisible(echoButton);
    await tester.tap(echoButton);
    await tester.pumpAndSettle();
    expect(
      find.text('A memory from another season rises beneath it.'),
      findsOneWidget,
    );

    final keepingButton = find.widgetWithText(FilledButton, 'Begin keeping');
    await tester.ensureVisible(keepingButton);
    await tester.tap(keepingButton);
    await tester.pumpAndSettle();
    expect(find.text('Keep this memory'), findsOneWidget);
    expect(find.text('Release this memory'), findsOneWidget);
  });

  testWidgets('task completion requires app-owned confirmation', (
    tester,
  ) async {
    final completed = <CapsuleAssignment>[];
    final locked = _capsuleAssignment(
      id: 'locked',
      contentEntryId: 'locked-entry',
      unlockTask: 'Finish the walk together.',
      state: CapsuleAssignmentState.locked,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            capsuleAssignments: [locked],
            capsuleEntries: {
              'locked-entry': _capsuleMetadata(
                id: 'locked-entry',
                format: MemoryFormat.photo,
              ),
            },
            capsuleAuthorNames: const {'member-2': 'Dana'},
            onCompleteCapsuleTask: (assignment) async {
              completed.add(assignment);
              return true;
            },
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    final complete = find.byKey(const ValueKey('capsule-complete-locked'));
    await tester.ensureVisible(complete);
    expect(tester.getSize(complete).height, greaterThanOrEqualTo(48));
    await tester.tap(complete);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Complete this task?'), findsOneWidget);
    expect(find.text('Finish the walk together.'), findsWidgets);
    expect(completed, isEmpty);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(completed, isEmpty);

    await tester.tap(complete);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('capsule-complete-confirm')));
    await tester.pumpAndSettle();
    expect(completed.map((assignment) => assignment.id), ['locked']);
  });

  testWidgets('failed completion leaves the Capsule locked with Retry', (
    tester,
  ) async {
    final locked = _capsuleAssignment(
      id: 'locked',
      contentEntryId: 'locked-entry',
      unlockTask: 'Finish the walk together.',
      state: CapsuleAssignmentState.locked,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            capsuleAssignments: [locked],
            capsuleEntries: {
              'locked-entry': _capsuleMetadata(
                id: 'locked-entry',
                format: MemoryFormat.photo,
              ),
            },
            onCompleteCapsuleTask: (_) async => false,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('capsule-complete-locked')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('capsule-complete-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('Task could not be completed. Try again.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('capsule-complete-locked')),
      findsOneWidget,
    );
    expect(find.text('Open memory'), findsNothing);
  });

  testWidgets('ready Capsule opens through the existing pastel flood', (
    tester,
  ) async {
    CapsuleAssignment? opened;
    final ready = _capsuleAssignment(
      id: 'ready',
      contentEntryId: 'ready-entry',
      state: CapsuleAssignmentState.ready,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: CeremonyScreen(
          familyName: 'Sabati',
          currentMemberName: 'Chris',
          capsuleAssignments: [ready],
          capsuleEntries: {
            'ready-entry': _capsuleMetadata(
              id: 'ready-entry',
              format: MemoryFormat.photo,
            ),
          },
          onOpenCapsule: (value) => opened = value,
          onDestinationSelected: (_) {},
        ),
      ),
    );

    final open = find.byKey(const ValueKey('capsule-open-ready'));
    await tester.ensureVisible(open);
    expect(tester.getSize(open).height, greaterThanOrEqualTo(48));
    await tester.tap(open);
    await tester.pump();
    expect(find.byKey(const ValueKey('pastel-flood')), findsOneWidget);
    expect(opened, isNull);

    await tester.pump(const Duration(milliseconds: 600));
    expect(opened?.id, ready.id);
  });

  testWidgets('memory key reflows on a narrow phone at 1.4x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(1.4),
            disableAnimations: true,
          ),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Legacy'), findsNothing);
    expect(find.textContaining('PREVIEW'), findsNothing);
    expect(find.text('Capsule'), findsOneWidget);
    expect(find.text('Locked by family'), findsOneWidget);
  });

  testWidgets('keeping exposes non-gesture actions and a sealed result', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            startInKeeping: true,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Keep this memory'));
    await tester.pumpAndSettle();
    expect(find.text('KEPT'), findsOneWidget);
    expect(find.text('Sealed into the family archive'), findsOneWidget);
  });

  testWidgets('keeping status and release action remain legible on cream', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            startInKeeping: true,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    final status = tester.widget<Text>(find.text('1 PRESENT · PREVIEW ONLY'));
    expect(status.style?.color, KeepersColors.inkMuted);

    final release = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Release this memory'),
    );
    expect(
      release.style?.foregroundColor?.resolve(<WidgetState>{}),
      KeepersColors.ink,
    );

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Release this memory'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Leaves your view after 30 days'), findsOneWidget);
  });

  testWidgets('next decision advances through the weekly memories', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            startInKeeping: true,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('A small moment, held in the light.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Keep this memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next decision'));
    await tester.pumpAndSettle();
    expect(find.text('A voice the room can hear together.'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Release this memory'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next decision'));
    await tester.pumpAndSettle();
    expect(
      find.text('What should this family remember from this week?'),
      findsOneWidget,
    );
  });

  testWidgets('keeping reflows on a narrow phone at 1.4x text', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(1.4),
            disableAnimations: true,
          ),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            startInKeeping: true,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Keep this memory'), findsOneWidget);
    expect(find.text('Release this memory'), findsOneWidget);
  });
}

Widget _liveVoiceCeremony({required AudioPlaybackAdapter playback}) {
  final memory = OpenedMemory(
    metadata: VaultEntryMetadata(
      id: 'live-voice',
      familyId: 'family-1',
      authorId: 'member-2',
      createdAt: DateTime.utc(2026, 9, 7, 12),
      format: MemoryFormat.voice,
      privacy: PrivacyTier.reveal,
      blobRef: 'entries/blobs/live-voice.keeper',
      state: 'pending',
    ),
    payload: EntryPayload(
      format: MemoryFormat.voice,
      primaryBytes: Uint8List.fromList([1, 2, 3]),
      text: null,
      caption: 'A voice from this week',
      mediaExtension: 'm4a',
      mediaDurationMs: 1200,
    ),
  );
  return MaterialApp(
    theme: KeepersTheme.daylight(),
    home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: CeremonyScreen(
        familyName: 'Sabati',
        currentMemberName: 'Chris',
        startInWeekly: true,
        weeklyPreview: false,
        weeklyMemories: Future.value([memory]),
        weeklyPlayback: playback,
        onWeeklyDecision: (_, _) async {},
        onDestinationSelected: (_) {},
      ),
    ),
  );
}

Widget _liveMemoryCeremony({required OpenedMemory memory}) => MaterialApp(
  theme: KeepersTheme.daylight(),
  home: MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: CeremonyScreen(
      familyName: 'Sabati',
      currentMemberName: 'Chris',
      startInWeekly: true,
      weeklyPreview: false,
      weeklyMemories: Future.value([memory]),
      onWeeklyDecision: (_, _) async {},
      onDestinationSelected: (_) {},
    ),
  ),
);

VaultEntryMetadata _weeklyMetadata({
  required String id,
  required MemoryFormat format,
}) => VaultEntryMetadata(
  id: id,
  familyId: 'family-1',
  authorId: 'member-2',
  createdAt: DateTime.utc(2026, 9, 7, 12),
  format: format,
  privacy: PrivacyTier.reveal,
  blobRef: 'entries/blobs/$id.keeper',
  state: 'pending',
);

CapsuleAssignment _capsuleAssignment({
  required String id,
  required String contentEntryId,
  required CapsuleAssignmentState state,
  String? unlockTask,
}) => CapsuleAssignment(
  id: id,
  familyId: 'family-1',
  authorId: 'member-2',
  targetId: 'member-1',
  contentEntryId: contentEntryId,
  unlockTask: unlockTask,
  state: state,
  createdAt: DateTime.utc(2026, 9, 7, 12),
  openedAt: state == CapsuleAssignmentState.opened
      ? DateTime.utc(2026, 9, 8, 12)
      : null,
);

VaultEntryMetadata _capsuleMetadata({
  required String id,
  required MemoryFormat format,
}) => _weeklyMetadata(
  id: id,
  format: format,
).copyWith(privacy: PrivacyTier.capsule);

final class _ControllablePlaybackAdapter implements AudioPlaybackAdapter {
  _ControllablePlaybackAdapter({this.stopError});

  final Object? stopError;
  final Completer<void> playStarted = Completer<void>();
  final Completer<void> _playReleased = Completer<void>();
  final Completer<void> stopFinished = Completer<void>();
  var stopCalls = 0;

  void releasePlayback() {
    if (!_playReleased.isCompleted) _playReleased.complete();
  }

  @override
  Future<void> playBytes(Uint8List bytes) async {
    if (!playStarted.isCompleted) playStarted.complete();
    await _playReleased.future;
  }

  @override
  Future<void> playFile(String path) async {}

  @override
  Future<void> stop() async {
    stopCalls += 1;
    try {
      await _playReleased.future;
      if (stopError case final error?) throw error;
    } finally {
      if (!stopFinished.isCompleted) stopFinished.complete();
    }
  }

  @override
  Future<void> dispose() async {}
}
