import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/ceremony/presentation/weekly_experience_card.dart';
import 'package:keepers/theme/keepers_theme.dart';

void main() {
  test('weekly presence threshold rounds three quarters up', () {
    expect(
      [
        for (var familySize = 1; familySize <= 8; familySize++)
          requiredWeeklyFamilyPresence(familySize),
      ],
      [1, 2, 3, 3, 4, 5, 6, 6],
    );
  });

  testWidgets(
    'five photos unlock the waiting room without a presence requirement',
    (tester) async {
      for (final scenario in const [
        (photoCount: 4, shouldEnter: false),
        (photoCount: 5, shouldEnter: true),
      ]) {
        var waitingRoomEntryCount = 0;
        await _pumpCard(
          tester,
          photoCount: scenario.photoCount,
          onEnterWaitingRoom: () => waitingRoomEntryCount += 1,
        );

        final panel = find.byKey(const ValueKey('weekly-recap-open'));
        expect(panel, findsOneWidget);
        expect(
          tester
              .getSemantics(panel)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          scenario.shouldEnter,
          reason: '${scenario.photoCount} photos',
        );

        await tester.tap(panel, warnIfMissed: false);
        await tester.pump();
        expect(waitingRoomEntryCount, scenario.shouldEnter ? 1 : 0);
      }
    },
    semanticsEnabled: true,
  );

  testWidgets('ready panel exposes one accessible tap action', (tester) async {
    await _pumpCard(tester, photoCount: 5, onEnterWaitingRoom: () {});

    expect(find.bySemanticsLabel('Weekly photo progress'), findsNothing);
    expect(find.bySemanticsLabel('Enter weekly waiting room'), findsOneWidget);
    final tapActions = tester.semantics
        .simulatedAccessibilityTraversal()
        .where((node) => node.getSemanticsData().hasAction(SemanticsAction.tap))
        .toList(growable: false);

    expect(tapActions, hasLength(1));
  }, semanticsEnabled: true);

  testWidgets('incomplete panel exposes no preview or entry action', (
    tester,
  ) async {
    var waitingRoomEntryCount = 0;
    await _pumpCard(
      tester,
      photoCount: 4,
      onEnterWaitingRoom: () => waitingRoomEntryCount += 1,
    );

    final panel = find.byKey(const ValueKey('weekly-recap-open'));
    expect(
      tester
          .getSemantics(panel)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    expect(find.byKey(const ValueKey('weekly-recap-preview')), findsNothing);
    expect(find.bySemanticsLabel('Preview weekly experience'), findsNothing);
    expect(find.text('Preview weekly experience'), findsNothing);

    await tester.tap(panel, warnIfMissed: false);
    await tester.pump();

    expect(waitingRoomEntryCount, 0);
  }, semanticsEnabled: true);

  testWidgets(
    'panel without an entry callback does not announce an entry action',
    (tester) async {
      await _pumpCard(tester, photoCount: 5);

      final panel = find.byKey(const ValueKey('weekly-recap-open'));
      final semantics = tester.getSemantics(panel).getSemanticsData();
      final entryAnnouncements = tester.semantics
          .simulatedAccessibilityTraversal()
          .where((node) {
            final data = node.getSemanticsData();
            return data.label.toLowerCase().contains('enter') ||
                data.value.toLowerCase().contains('enter');
          })
          .toList(growable: false);

      expect(semantics.hasAction(SemanticsAction.tap), isFalse);
      expect(entryAnnouncements, isEmpty);
      expect(
        find.descendant(
          of: panel,
          matching: find.byIcon(Icons.lock_outline_rounded),
        ),
        findsOneWidget,
      );
      final medallion = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.descendant(
            of: panel,
            matching: find.byType(WeeklyKeyMedallion),
          ),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((medallion.decoration! as BoxDecoration).boxShadow, isEmpty);
      final panelGlow = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('weekly-recap-glow')),
      );
      expect((panelGlow.decoration! as BoxDecoration).boxShadow, isEmpty);
    },
    semanticsEnabled: true,
  );

  testWidgets('locked panel uses warm neutral framing without a glow', (
    tester,
  ) async {
    await _pumpCard(tester, photoCount: 4, onEnterWaitingRoom: () {});

    final panel = find.byKey(const ValueKey('weekly-recap-open'));
    final button = tester.widget<OutlinedButton>(panel);
    final side = button.style!.side!.resolve(<WidgetState>{})!;
    final innerFrame = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: panel, matching: find.byType(DecoratedBox)),
        )
        .firstWhere((widget) {
          final decoration = widget.decoration as BoxDecoration;
          return decoration.borderRadius == BorderRadius.circular(25);
        });
    final medallion = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.descendant(
          of: panel,
          matching: find.byType(WeeklyKeyMedallion),
        ),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final innerDecoration = innerFrame.decoration as BoxDecoration;
    final medallionDecoration = medallion.decoration! as BoxDecoration;
    final lock = tester.widget<Icon>(
      find.descendant(
        of: panel,
        matching: find.byIcon(Icons.lock_outline_rounded),
      ),
    );

    expect(side.color, const Color(0xFFD4BBAC));
    expect(side.width, 1.25);
    expect(
      innerDecoration.border!.top.color,
      const Color(0xFFD4BBAC).withValues(alpha: .82),
    );
    expect(medallionDecoration.border!.top.color, const Color(0xFFD4BBAC));
    expect(medallionDecoration.boxShadow, isEmpty);
    final panelGlow = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('weekly-recap-glow')),
    );
    expect((panelGlow.decoration! as BoxDecoration).boxShadow, isEmpty);
    expect(lock.color, const Color(0xFF8B7E70));
  });

  testWidgets('locked panel shows a lock and ready panel shows a glowing key', (
    tester,
  ) async {
    await _pumpCard(tester, photoCount: 4, onEnterWaitingRoom: () {});

    final lockedPanel = find.byKey(const ValueKey('weekly-recap-open'));
    expect(
      find.descendant(
        of: lockedPanel,
        matching: find.byIcon(Icons.lock_outline_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: lockedPanel,
        matching: find.byIcon(Icons.key_rounded),
      ),
      findsNothing,
    );

    await _pumpCard(tester, photoCount: 5, onEnterWaitingRoom: () {});

    final readyPanel = find.byKey(const ValueKey('weekly-recap-open'));
    expect(
      find.descendant(of: readyPanel, matching: find.byIcon(Icons.key_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: readyPanel,
        matching: find.byIcon(Icons.lock_outline_rounded),
      ),
      findsNothing,
    );
    final glow = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.descendant(
          of: readyPanel,
          matching: find.byType(WeeklyKeyMedallion),
        ),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect((glow.decoration! as BoxDecoration).boxShadow, isNotEmpty);
    final panelGlow = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('weekly-recap-glow')),
    );
    expect((panelGlow.decoration! as BoxDecoration).boxShadow, isNotEmpty);
    final button = tester.widget<OutlinedButton>(readyPanel);
    expect(
      button.style!.side!.resolve(<WidgetState>{})!.color,
      KeepersColors.homeGold,
    );
    final innerFrame = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: readyPanel, matching: find.byType(DecoratedBox)),
        )
        .firstWhere((widget) {
          final decoration = widget.decoration as BoxDecoration;
          return decoration.borderRadius == BorderRadius.circular(25);
        });
    expect(
      (innerFrame.decoration as BoxDecoration).border!.top.color,
      KeepersColors.homeGold.withValues(alpha: .72),
    );
    final keyIcon = tester.widget<Icon>(
      find.descendant(of: readyPanel, matching: find.byIcon(Icons.key_rounded)),
    );
    expect(keyIcon.color, KeepersColors.homeGoldText);
  });

  testWidgets('shared key medallion exposes locked and ready visuals', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.dark(),
        home: const Row(
          children: [
            WeeklyKeyMedallion(
              key: ValueKey('locked-key-medallion'),
              ready: false,
            ),
            WeeklyKeyMedallion(
              key: ValueKey('ready-key-medallion'),
              ready: true,
              size: 96,
            ),
          ],
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('locked-key-medallion')),
        matching: find.byIcon(Icons.lock_outline_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ready-key-medallion')),
        matching: find.byIcon(Icons.key_rounded),
      ),
      findsOneWidget,
    );
    final readyMedallion = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(const ValueKey('ready-key-medallion')),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(
      readyMedallion.constraints,
      const BoxConstraints.tightFor(width: 96, height: 96),
    );
    final readyKey = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('ready-key-medallion')),
        matching: find.byIcon(Icons.key_rounded),
      ),
    );
    expect(readyKey.size, 37.5);
  });
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required int photoCount,
  VoidCallback? onEnterWaitingRoom,
}) => tester.pumpWidget(
  MaterialApp(
    theme: KeepersTheme.dark(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: WeeklyExperienceCard(
            weeklyPhotoCount: photoCount,
            requiredWeeklyPhotos: 5,
            onEnterWaitingRoom: onEnterWaitingRoom,
          ),
        ),
      ),
    ),
  ),
);
