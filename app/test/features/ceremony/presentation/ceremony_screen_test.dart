import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/ceremony/presentation/ceremony_screen.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';

void main() {
  testWidgets('presence Invite card exposes semantic activation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            onAddMember: () {},
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    final data = tester
        .getSemantics(find.bySemanticsLabel(RegExp('Invite a family member')))
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets('presence invite adds a member while weekly action only nudges', (
    tester,
  ) async {
    var added = 0;
    var nudged = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            onAddMember: () => added += 1,
            onNudgeMissingMembers: () => nudged += 1,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(
      find.ancestor(of: find.text('INVITE'), matching: find.byType(InkWell)),
    );
    expect(added, 1);
    expect(nudged, 0);

    await tester.tap(find.text('Ask family to come'));

    expect(added, 1);
    expect(nudged, 1);
  });

  testWidgets('memory key locks weekly recap but keeps random access open', (
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
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Memory Key'), findsOneWidget);
    expect(find.text('THE WEEK'), findsOneWidget);
    expect(find.text('1 of 2 devices'), findsOneWidget);
    expect(find.text('Draw a memory'), findsOneWidget);
    expect(find.text('ANY TIME'), findsOneWidget);
    expect(find.text('Locked by family'), findsOneWidget);
    expect(find.byKey(const ValueKey('weekly-recap-preview')), findsNothing);

    final weekly = tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byKey(const ValueKey('weekly-recap-mode')),
        matching: find.byType(OutlinedButton),
      ),
    );
    final random = tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byKey(const ValueKey('random-memory-mode')),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(weekly.onPressed, isNull);
    expect(random.onPressed, isNotNull);
  });

  testWidgets(
    'waiting recap keeps its live threshold and weekly count visible',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: KeepersTheme.daylight(),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: CeremonyScreen(
              familyName: 'Rahman',
              currentMemberName: 'Chris',
              nearbyDeviceCount: 1,
              requiredNearbyDevices: 2,
              weeklyMemoryCount: 4,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      );

      expect(
        find.text('You are here. One more device turns the key.'),
        findsOneWidget,
      );
      final weeklyCard = find.byKey(const ValueKey('weekly-recap-mode'));
      expect(weeklyCard, findsOneWidget);
      expect(
        find.descendant(
          of: weeklyCard,
          matching: find.textContaining('1 of 2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: weeklyCard,
          matching: find.textContaining('4 memories'),
        ),
        findsOneWidget,
      );

      final weekly = tester.widget<OutlinedButton>(
        find.descendant(of: weeklyCard, matching: find.byType(OutlinedButton)),
      );
      expect(weekly.onPressed, isNull);
    },
  );

  testWidgets('presence stack lists family without overstating who is nearby', (
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
            nearbyDeviceCount: 3,
            requiredNearbyDevices: 2,
            members: const [
              MemoryKeyMember(name: 'Layla'),
              MemoryKeyMember(name: 'Omar'),
              MemoryKeyMember(name: 'Yusuf'),
              MemoryKeyMember(name: 'Karim'),
              MemoryKeyMember(name: 'Hana'),
            ],
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    final stack = find.byKey(const ValueKey('memory-key-presence-stack'));
    expect(stack, findsOneWidget);
    for (final name in ['Layla', 'Omar', 'Yusuf', 'Karim', 'Hana']) {
      expect(
        find.descendant(
          of: stack,
          matching: find.bySemanticsLabel(
            '$name, ${name == 'Layla' || name == 'Omar' ? 'here' : 'away'}',
          ),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('You, Layla and Omar are here.'), findsOneWidget);
    expect(find.text('You, Layla, Omar and Yusuf are here.'), findsNothing);
  });

  testWidgets('draw a memory stays available while the recap is waiting', (
    tester,
  ) async {
    MemoryKeyMemory? opened;
    const memory = MemoryKeyMemory(
      id: 'kept-1',
      title: 'Sunday in the kitchen',
      formatLabel: 'Voice memory',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Rahman',
            currentMemberName: 'Chris',
            nearbyDeviceCount: 1,
            requiredNearbyDevices: 2,
            randomMemories: const [memory],
            onOpenRandomMemory: (value) => opened = value,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    final drawAction = find.descendant(
      of: find.byKey(const ValueKey('random-memory-mode')),
      matching: find.text('Draw a memory'),
    );
    expect(drawAction, findsOneWidget);

    await tester.ensureVisible(drawAction);
    await tester.tap(drawAction);
    await tester.pump();

    expect(opened?.id, memory.id);
  });

  testWidgets('landing carries a family challenge and a dated time capsule', (
    tester,
  ) async {
    LockedMemoryChallenge? opened;
    const challenge = LockedMemoryChallenge(
      id: 'recipe',
      title: 'Nana\'s Sunday recipe',
      task: 'Cook the recipe together and keep a photo.',
      assignedBy: 'Assigned by Layla',
      approvalBy: 'Approved by Layla',
      state: LockedMemoryChallengeState.approved,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Rahman',
            currentMemberName: 'Chris',
            lockedMemories: const [challenge],
            timeCapsule: const MemoryKeyCapsule(
              from: 'From Hana',
              title: 'For your birthday',
              openingLabel: 'Opens 12 October',
              daysRemaining: 41,
            ),
            onOpenLockedMemory: (value) => opened = value,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('ASSIGNED BY LAYLA'), findsOneWidget);
    expect(find.text(challenge.title), findsOneWidget);
    expect(find.text(challenge.task), findsOneWidget);
    expect(find.text('Time capsule'), findsOneWidget);
    expect(find.text('Opens 12 October'), findsOneWidget);

    final openChallenge = find.widgetWithText(FilledButton, 'Open memory');
    await tester.ensureVisible(openChallenge);
    await tester.tap(openChallenge);
    await tester.pump();

    expect(opened?.id, challenge.id);
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

  testWidgets('two nearby devices unlock recap through a pastel flood', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: CeremonyScreen(
          familyName: 'Sabati',
          currentMemberName: 'Chris',
          nearbyDeviceCount: 2,
          weeklyMemoryCount: 3,
          onDestinationSelected: (_) {},
        ),
      ),
    );

    expect(find.text('3 memories, waiting.'), findsOneWidget);
    final weeklyButton = tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byKey(const ValueKey('weekly-recap-mode')),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(weeklyButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('weekly-recap-mode')));
    await tester.pump();
    expect(find.byKey(const ValueKey('pastel-flood')), findsOneWidget);
    expect(find.text('Photo memory'), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Photo memory'), findsOneWidget);
  });

  testWidgets('random mode avoids repeating the same kept memory', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            randomMemories: const [
              MemoryKeyMemory(
                id: 'kept-1',
                title: 'Kitchen story',
                formatLabel: 'Voice memory',
              ),
              MemoryKeyMemory(
                id: 'kept-2',
                title: 'Garden story',
                formatLabel: 'Photo memory',
              ),
            ],
            onOpenRandomMemory: (memory) => opened.add(memory.id),
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('random-memory-mode')),
    );
    await tester.tap(find.byKey(const ValueKey('random-memory-mode')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('random-memory-mode')),
    );
    await tester.tap(find.byKey(const ValueKey('random-memory-mode')));
    await tester.pump();

    expect(opened, hasLength(2));
    expect(opened[1], isNot(opened[0]));
  });

  testWidgets('weekly recap moves through each memory format into keeping', (
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
            nearbyDeviceCount: 2,
            weeklyMemoryCount: 3,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Memory Key'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('weekly-recap-mode')));
    await tester.pumpAndSettle();
    expect(find.text('Photo memory'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Next memory'));
    await tester.pumpAndSettle();
    expect(find.text('Voice memory'), findsOneWidget);
    await tester.tap(find.byTooltip('PLAY REHEARSAL VOICE MEMORY'));
    await tester.pump();
    expect(find.byTooltip('PAUSE REHEARSAL VOICE MEMORY'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Next memory'));
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

  testWidgets('random mode opens an honest empty vault state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('random-memory-mode')),
    );
    await tester.tap(find.byKey(const ValueKey('random-memory-mode')));
    await tester.pump();

    expect(find.text('No kept memories yet'), findsOneWidget);
    expect(find.text('Back to Memory Key'), findsOneWidget);
  });

  testWidgets('only an approved family task can open its locked memory', (
    tester,
  ) async {
    LockedMemoryChallenge? opened;
    const locked = LockedMemoryChallenge(
      id: 'locked',
      title: 'Still waiting',
      task: 'Finish the walk together.',
      assignedBy: 'Assigned by Dana',
      approvalBy: 'Dana must approve it',
      state: LockedMemoryChallengeState.locked,
    );
    const approved = LockedMemoryChallenge(
      id: 'approved',
      title: 'Ready for you',
      task: 'Finish the recipe together.',
      assignedBy: 'Assigned by Dana',
      approvalBy: 'Approved by Dana',
      state: LockedMemoryChallengeState.approved,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: CeremonyScreen(
            familyName: 'Sabati',
            currentMemberName: 'Chris',
            lockedMemories: const [locked, approved],
            onOpenLockedMemory: (challenge) => opened = challenge,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Open memory'), findsOneWidget);
    await tester.ensureVisible(find.text('Open memory'));
    await tester.tap(find.widgetWithText(FilledButton, 'Open memory'));
    await tester.pump();

    expect(opened?.id, 'approved');
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
    expect(find.text('THE WEEK'), findsOneWidget);
    expect(find.text('Draw a memory'), findsOneWidget);
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
