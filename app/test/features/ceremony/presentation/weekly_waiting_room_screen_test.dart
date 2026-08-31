import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/ceremony/presentation/weekly_waiting_room_screen.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/theme/keepers_theme.dart';

void main() {
  group('WeeklyWaitingRoomAttendance', () {
    test('uses a ceiling three-quarter quorum for every family size', () {
      expect(
        [
          for (var familySize = 0; familySize <= 8; familySize++)
            WeeklyWaitingRoomAttendance.fromMemberIds(
              rosterMemberIds: [
                for (var index = 0; index < familySize; index++) 'm$index',
              ],
              presentMemberIds: const [],
            ).requiredMemberCount,
        ],
        [1, 1, 2, 3, 3, 4, 5, 6, 6],
      );
    });

    test('deduplicates the roster and intersects observed presence', () {
      final attendance = WeeklyWaitingRoomAttendance.fromMemberIds(
        rosterMemberIds: const ['me', 'alex', 'alex', 'sam'],
        presentMemberIds: const ['me', 'alex', 'alex', 'outsider'],
        currentMemberId: 'me',
      );

      expect(attendance.totalMemberCount, 3);
      expect(attendance.presentMemberCount, 2);
      expect(attendance.requiredMemberCount, 3);
      expect(attendance.membersStillNeeded, 1);
      expect(attendance.presentMemberIds, {'me', 'alex'});
      expect(attendance.canStart, isFalse);
    });

    test('counts the signed-in member once even without a presence signal', () {
      final attendance = WeeklyWaitingRoomAttendance.fromMemberIds(
        rosterMemberIds: const ['me', 'me', 'alex'],
        presentMemberIds: const [],
        currentMemberId: 'me',
      );

      expect(attendance.totalMemberCount, 2);
      expect(attendance.presentMemberCount, 1);
      expect(attendance.membersStillNeeded, 1);
    });

    test('an unknown roster fails closed', () {
      final attendance = WeeklyWaitingRoomAttendance.fromMemberIds(
        rosterMemberIds: const [],
        presentMemberIds: const ['outsider'],
        currentMemberId: 'me',
      );

      expect(attendance.totalMemberCount, 0);
      expect(attendance.presentMemberCount, 0);
      expect(attendance.requiredMemberCount, 1);
      expect(attendance.canStart, isFalse);
    });
  });

  testWidgets('below quorum shows truthful attendance without a start action', (
    tester,
  ) async {
    var nudgeCount = 0;
    await _pumpRoom(
      tester,
      members: _members(total: 4, present: 2),
      onNudgeMissingMembers: () => nudgeCount += 1,
    );

    expect(find.byKey(const ValueKey('weekly-waiting-room')), findsOneWidget);
    expect(find.text('2 of 4 family members are here'), findsOneWidget);
    expect(find.text('1 more family member needs to join'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('weekly-waiting-room-start')),
      findsNothing,
    );
    expect(find.text('Start weekly experience'), findsNothing);
    expect(find.text('Here'), findsNWidgets(2));
    expect(find.text('Waiting'), findsNWidgets(2));

    final nudge = find.text('Ask family to join');
    await tester.ensureVisible(nudge);
    await tester.pump();
    await tester.tap(nudge);
    await tester.pump();
    expect(nudgeCount, 1);
  });

  testWidgets('an in-progress nudge remains visible and disabled', (
    tester,
  ) async {
    await _pumpRoom(
      tester,
      members: _members(total: 4, present: 2),
      nudgeInProgress: true,
      onNudgeMissingMembers: () {},
    );

    expect(find.text('Opening share…'), findsOneWidget);
    expect(find.text('Ask family to join'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final nudge = find.ancestor(
      of: find.text('Opening share…'),
      matching: find.byType(OutlinedButton),
    );
    expect(nudge, findsOneWidget);
    expect(tester.widget<OutlinedButton>(nudge).onPressed, isNull);
  });

  testWidgets('preserves the shared app background behind the waiting room', (
    tester,
  ) async {
    await _pumpRoom(tester, members: _members(total: 4, present: 2));

    final scaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('weekly-waiting-room')),
    );
    expect(scaffold.backgroundColor, Colors.transparent);
  });

  testWidgets('quorum reveals the exact start action', (tester) async {
    var startCount = 0;
    await _pumpRoom(
      tester,
      members: _members(total: 4, present: 3),
      onStart: () {
        startCount += 1;
        return true;
      },
    );

    expect(find.text('3 of 4 family members are here'), findsOneWidget);
    final start = find.byKey(const ValueKey('weekly-waiting-room-start'));
    expect(start, findsOneWidget);
    expect(
      find.descendant(
        of: start,
        matching: find.text('Start weekly experience'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(start);
    await tester.pump();
    await tester.tap(start);
    await tester.pump();
    expect(startCount, 1);
  });

  testWidgets('a rejected start remains available for a safe retry', (
    tester,
  ) async {
    var accepted = false;
    var startCount = 0;
    await _pumpRoom(
      tester,
      members: _members(total: 4, present: 3),
      onStart: () {
        startCount += 1;
        return accepted;
      },
    );
    final start = find.byKey(const ValueKey('weekly-waiting-room-start'));
    await tester.ensureVisible(start);
    await tester.pump();

    await tester.tap(start);
    await tester.pump();
    expect(startCount, 1);
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
    expect(find.text('Starting weekly experience…'), findsNothing);

    accepted = true;
    await tester.tap(start);
    await tester.pump();
    expect(startCount, 2);
    expect(start, findsNothing);
    expect(find.text('Starting weekly experience…'), findsOneWidget);
    expect(find.bySemanticsLabel('Weekly experience starting'), findsOneWidget);
    expect(find.bySemanticsLabel('Starting weekly experience…'), findsNothing);
  }, semanticsEnabled: true);

  testWidgets('revoked photo eligibility removes Start without trapping room', (
    tester,
  ) async {
    var closeCount = 0;
    await _pumpRoom(
      tester,
      members: _members(total: 4, present: 3),
      weeklyProgressComplete: false,
      onClose: () => closeCount += 1,
    );

    expect(
      find.byKey(const ValueKey('weekly-waiting-room-start')),
      findsNothing,
    );
    expect(
      find.text(
        'Weekly progress changed. Return to the Wheel to finish five photos.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Close waiting room'));
    await tester.pump();
    expect(closeCount, 1);
  });

  testWidgets('attendance summary is one live semantic region', (tester) async {
    await _pumpRoom(tester, members: _members(total: 4, present: 2));

    final summary = find.byKey(
      const ValueKey('weekly-waiting-room-attendance'),
    );
    final semantics = tester.getSemantics(summary).getSemanticsData();

    expect(summary, findsOneWidget);
    expect(semantics.flagsCollection.isLiveRegion, isTrue);
    expect(semantics.label, 'Family attendance');
    expect(
      semantics.value,
      '2 of 4 family members are here. '
      '1 more family member needs to join.',
    );
  }, semanticsEnabled: true);

  testWidgets('always explains how to remain present in the waiting room', (
    tester,
  ) async {
    await _pumpRoom(tester, members: _members(total: 4, present: 3));

    expect(find.text('Keep this room open and Bluetooth on.'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Keep this room open and Bluetooth on to stay present.',
      ),
      findsOneWidget,
    );
  }, semanticsEnabled: true);

  testWidgets('announces the waiting room as a named route', (tester) async {
    await _pumpRoom(tester, members: _members(total: 4, present: 2));

    final route = find.byKey(
      const ValueKey('weekly-waiting-room-route-semantics'),
    );
    final semantics = tester.getSemantics(route).getSemanticsData();
    expect(semantics.label, 'Weekly waiting room — Keepers');
    expect(semantics.flagsCollection.namesRoute, isTrue);
    expect(semantics.flagsCollection.scopesRoute, isTrue);
  }, semanticsEnabled: true);

  testWidgets('Waiting status uses contrast-safe ink', (tester) async {
    await _pumpRoom(tester, members: _members(total: 4, present: 2));

    for (final waiting in tester.widgetList<Text>(find.text('Waiting'))) {
      expect(waiting.style?.color, KeepersColors.homeInk);
    }
  });

  testWidgets('empty member names use the same visual and semantic fallback', (
    tester,
  ) async {
    final member = _members(total: 1, present: 1).single;
    await _pumpRoom(
      tester,
      members: [
        WeeklyWaitingRoomMember(
          id: member.id,
          name: '   ',
          color: member.color,
          avatar: member.avatar,
          isPresent: true,
          isCurrentMember: true,
        ),
      ],
    );

    expect(find.text('Family member'), findsOneWidget);
    expect(find.bySemanticsLabel('Family member, you. Here'), findsOneWidget);
  }, semanticsEnabled: true);

  testWidgets('duplicate taps invoke start once after the 560 ms reveal', (
    tester,
  ) async {
    expect(weeklyWaitingRoomRevealDuration, const Duration(milliseconds: 560));
    var startCount = 0;
    var closeCount = 0;
    await _pumpRoom(
      tester,
      members: _members(total: 4, present: 3),
      disableAnimations: false,
      onStart: () {
        startCount += 1;
        return true;
      },
      onClose: () => closeCount += 1,
    );
    final start = find.byKey(const ValueKey('weekly-waiting-room-start'));

    await tester.ensureVisible(start);
    await tester.pump();
    await tester.tap(start);
    await tester.pump();
    final startingButton = tester.widget<FilledButton>(start);
    expect(find.text('Starting…'), findsOneWidget);
    expect(
      startingButton.style?.backgroundColor?.resolve(const {
        WidgetState.disabled,
      }),
      KeepersColors.homeInk,
    );
    expect(
      startingButton.style?.foregroundColor?.resolve(const {
        WidgetState.disabled,
      }),
      KeepersColors.auraIvory,
    );
    await tester.tap(start, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 559));
    expect(startCount, 0);

    await tester.pumpAndSettle();
    expect(startCount, 1);
    expect(start, findsNothing);
    expect(find.text('Starting weekly experience…'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('weekly-waiting-room-pastel-flood')),
      findsNothing,
    );

    final close = find.byTooltip('Close waiting room');
    await tester.ensureVisible(close);
    await tester.pump();
    await tester.tap(close);
    expect(closeCount, 1);
  });

  testWidgets('close and back cancel the reveal before Start is dispatched', (
    tester,
  ) async {
    for (final useSystemBack in const [false, true]) {
      var closeCount = 0;
      var startCount = 0;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _pumpRoom(
        tester,
        members: _members(total: 4, present: 3),
        disableAnimations: false,
        onClose: () => closeCount += 1,
        onStart: () {
          startCount += 1;
          return true;
        },
      );
      final start = find.byKey(const ValueKey('weekly-waiting-room-start'));
      await tester.ensureVisible(start);
      await tester.pump();
      await tester.tap(start);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('weekly-waiting-room-pastel-flood')),
        findsOneWidget,
      );
      if (useSystemBack) {
        await tester.binding.handlePopRoute();
      } else {
        final close = find.byTooltip('Close waiting room');
        await tester.ensureVisible(close);
        await tester.pump();
        await tester.tap(close);
      }
      await tester.pump();
      await tester.pump(weeklyWaitingRoomRevealDuration);

      expect(closeCount, 1, reason: 'system back: $useSystemBack');
      expect(startCount, 0, reason: 'system back: $useSystemBack');
    }
  });

  testWidgets('reduced motion starts immediately without painting the flood', (
    tester,
  ) async {
    var startCount = 0;
    await _pumpRoom(
      tester,
      members: _members(total: 1, present: 1),
      onStart: () {
        startCount += 1;
        return true;
      },
    );

    await tester.tap(find.byKey(const ValueKey('weekly-waiting-room-start')));
    await tester.pump();

    expect(startCount, 1);
    expect(
      find.byKey(const ValueKey('weekly-waiting-room-pastel-flood')),
      findsNothing,
    );
  });

  testWidgets('close button and system back both return to the wheel', (
    tester,
  ) async {
    var closeCount = 0;
    await _pumpRoom(
      tester,
      members: _members(total: 4, present: 2),
      onClose: () => closeCount += 1,
    );

    await tester.tap(find.byTooltip('Close waiting room'));
    await tester.pump();
    expect(closeCount, 1);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(closeCount, 2);
  });

  testWidgets('small screens and large text can scroll to every action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpRoom(
      tester,
      members: _members(total: 8, present: 6),
      mediaQuery: const MediaQueryData(
        disableAnimations: true,
        textScaler: TextScaler.linear(2),
      ),
    );

    final start = find.byKey(const ValueKey('weekly-waiting-room-start'));
    await tester.scrollUntilVisible(
      start,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(start, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('action region stays stable when quorum changes at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const mediaQuery = MediaQueryData(
      disableAnimations: true,
      textScaler: TextScaler.linear(2),
    );

    await _pumpRoom(
      tester,
      members: _members(total: 4, present: 2),
      mediaQuery: mediaQuery,
      onNudgeMissingMembers: () {},
    );
    final actions = find.byKey(const ValueKey('weekly-waiting-room-actions'));
    final waitingHeight = tester.getSize(actions).height;

    await _pumpRoom(
      tester,
      members: _members(total: 4, present: 3),
      mediaQuery: mediaQuery,
      onNudgeMissingMembers: () {},
    );
    final readyHeight = tester.getSize(actions).height;

    expect(readyHeight, waitingHeight);
    expect(readyHeight, lessThanOrEqualTo(180));
  });
}

List<WeeklyWaitingRoomMember> _members({
  required int total,
  required int present,
}) => [
  for (var index = 0; index < total; index++)
    WeeklyWaitingRoomMember(
      id: 'member-$index',
      name: index == 0 ? 'You' : 'Member $index',
      color: KeepersColors
          .memberPalette[index % KeepersColors.memberPalette.length],
      avatar: AvatarConfig.defaults(seed: 'member-$index'),
      isPresent: index < present,
      isCurrentMember: index == 0,
    ),
];

Future<void> _pumpRoom(
  WidgetTester tester, {
  required List<WeeklyWaitingRoomMember> members,
  VoidCallback? onClose,
  WeeklyStartRequest? onStart,
  VoidCallback? onNudgeMissingMembers,
  bool nudgeInProgress = false,
  bool weeklyProgressComplete = true,
  bool disableAnimations = true,
  MediaQueryData? mediaQuery,
}) => tester.pumpWidget(
  MaterialApp(
    theme: KeepersTheme.daylight(),
    home: MediaQuery(
      data: mediaQuery ?? MediaQueryData(disableAnimations: disableAnimations),
      child: WeeklyWaitingRoomScreen(
        familyName: 'The Keepers',
        members: members,
        weeklyProgressComplete: weeklyProgressComplete,
        onClose: onClose ?? () {},
        onStart: onStart ?? () => true,
        onNudgeMissingMembers: onNudgeMissingMembers,
        nudgeInProgress: nudgeInProgress,
      ),
    ),
  ),
);
