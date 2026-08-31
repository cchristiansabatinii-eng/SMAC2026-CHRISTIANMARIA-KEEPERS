import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';

void main() {
  test('navigation domain has no separate Locks destination', () {
    expect(
      KeepersNavDestination.values.map((destination) => destination.name),
      isNot(contains('locks')),
    );
  });

  testWidgets('navigation is a full-width five-action app bar', (tester) async {
    KeepersNavDestination? selected;
    var captures = 0;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: Scaffold(
          bottomNavigationBar: KeepersBottomNav(
            selected: KeepersNavDestination.wheel,
            enabledDestinations: KeepersNavDestination.values.toSet(),
            onCapture: () => captures += 1,
            onSelected: (destination) => selected = destination,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Wheel, selected'), findsOneWidget);
    expect(find.bySemanticsLabel('Memory Key'), findsOneWidget);
    expect(find.bySemanticsLabel('Keep a memory'), findsOneWidget);
    expect(find.bySemanticsLabel('Archive'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
    expect(find.bySemanticsLabel('Locks'), findsNothing);
    expect(find.byIcon(Icons.filter_none_rounded), findsOneWidget);

    for (final destination in const ['ceremony', 'archive', 'settings']) {
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(ValueKey('keepers-nav-$destination')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.color, KeepersColors.ink);
    }

    final bar = find.byKey(const ValueKey('keepers-bottom-nav'));
    expect(bar, findsOneWidget);
    expect(tester.getSize(bar).width, 390);
    final decoration =
        tester.widget<Container>(bar).decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.zero);
    expect(decoration.boxShadow, isNull);

    final centers =
        [
              'Wheel, selected',
              'Memory Key',
              'Keep a memory',
              'Archive',
              'Settings',
            ]
            .map((label) => tester.getCenter(find.bySemanticsLabel(label)).dx)
            .toList();
    expect(centers, orderedEquals(centers.toList()..sort()));

    await tester.tap(find.bySemanticsLabel('Memory Key'));
    expect(selected, KeepersNavDestination.ceremony);
    await tester.tap(find.bySemanticsLabel('Keep a memory'));
    expect(captures, 1);
    await tester.tap(find.bySemanticsLabel('Archive'));
    expect(selected, KeepersNavDestination.archive);
  });

  testWidgets('bottom navigation identifies the current and future surfaces', (
    tester,
  ) async {
    KeepersNavDestination? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.dark(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: KeepersBottomNav(
              selected: KeepersNavDestination.wheel,
              enabledDestinations: const {KeepersNavDestination.wheel},
              onSelected: (destination) => selected = destination,
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Wheel, selected'), findsOneWidget);
    expect(find.bySemanticsLabel('Memory Key, unavailable'), findsOneWidget);
    expect(find.bySemanticsLabel('Archive, unavailable'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings, unavailable'), findsOneWidget);
    expect(find.bySemanticsLabel('Locks, unavailable'), findsNothing);
    expect(
      find.byKey(const ValueKey('keepers-nav-wheel-indicator')),
      findsOneWidget,
    );

    expect(find.byIcon(Icons.key_rounded), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Memory Key, unavailable'));
    expect(selected, isNull);

    await tester.tap(find.bySemanticsLabel('Wheel, selected'));
    expect(selected, KeepersNavDestination.wheel);
  });

  testWidgets('center Keep a memory action is independent of destinations', (
    tester,
  ) async {
    KeepersNavDestination? selected;
    var captures = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: KeepersBottomNav(
              selected: KeepersNavDestination.archive,
              enabledDestinations: KeepersNavDestination.values.toSet(),
              onCapture: () => captures += 1,
              onSelected: (destination) => selected = destination,
            ),
          ),
        ),
      ),
    );

    final add = find.bySemanticsLabel('Keep a memory');
    expect(add, findsOneWidget);
    expect(tester.getSize(add).shortestSide, greaterThanOrEqualTo(44));

    await tester.tap(add);
    expect(captures, 1);
    expect(selected, isNull);
    expect(find.bySemanticsLabel('Archive, selected'), findsOneWidget);
  });
}
