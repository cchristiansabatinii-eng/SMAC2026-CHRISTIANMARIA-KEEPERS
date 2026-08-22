import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/ceremony/presentation/weekly_experience_card.dart';

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
    'weekly reveal opens only after five photos and enough family are present',
    (tester) async {
      for (final scenario in const [
        (photoCount: 4, presentMemberCount: 3, shouldOpen: false),
        (photoCount: 5, presentMemberCount: 2, shouldOpen: false),
        (photoCount: 5, presentMemberCount: 3, shouldOpen: true),
      ]) {
        var openCount = 0;
        await _pumpCard(
          tester,
          photoCount: scenario.photoCount,
          presentMemberCount: scenario.presentMemberCount,
          onOpen: () => openCount += 1,
        );

        final panel = find.byKey(const ValueKey('weekly-recap-open'));
        expect(panel, findsOneWidget);
        expect(
          tester
              .getSemantics(panel)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          scenario.shouldOpen,
          reason:
              '${scenario.photoCount} photos, '
              '${scenario.presentMemberCount} family members present',
        );

        await tester.tap(panel, warnIfMissed: false);
        await tester.pump();
        expect(openCount, scenario.shouldOpen ? 1 : 0);
      }
    },
    semanticsEnabled: true,
  );

  testWidgets('ready panel exposes one accessible tap action', (tester) async {
    await _pumpCard(
      tester,
      photoCount: 5,
      presentMemberCount: 3,
      onOpen: () {},
    );

    expect(find.bySemanticsLabel('Weekly photo progress'), findsNothing);
    final tapActions = tester.semantics
        .simulatedAccessibilityTraversal()
        .where((node) => node.getSemanticsData().hasAction(SemanticsAction.tap))
        .toList(growable: false);

    expect(tapActions, hasLength(1));
  }, semanticsEnabled: true);

  testWidgets('preview stays separately labeled without unlocking the panel', (
    tester,
  ) async {
    var openCount = 0;
    var previewCount = 0;
    await _pumpCard(
      tester,
      photoCount: 4,
      presentMemberCount: 3,
      onOpen: () => openCount += 1,
      onPreview: () => previewCount += 1,
    );

    final panel = find.byKey(const ValueKey('weekly-recap-open'));
    final preview = find.bySemanticsLabel('Preview weekly experience');
    expect(
      tester
          .getSemantics(panel)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    expect(preview, findsOneWidget);

    await tester.tap(panel, warnIfMissed: false);
    await tester.tap(preview);
    await tester.pump();

    expect(openCount, 0);
    expect(previewCount, 1);
  }, semanticsEnabled: true);

  testWidgets(
    'panel without an open callback does not announce an open action',
    (tester) async {
      await _pumpCard(tester, photoCount: 5, presentMemberCount: 3);

      final panel = find.byKey(const ValueKey('weekly-recap-open'));
      final semantics = tester.getSemantics(panel).getSemanticsData();
      final openAnnouncements = tester.semantics
          .simulatedAccessibilityTraversal()
          .where((node) {
            final data = node.getSemanticsData();
            return data.label.toLowerCase().contains('open') ||
                data.value.toLowerCase().contains('open');
          })
          .toList(growable: false);

      expect(semantics.hasAction(SemanticsAction.tap), isFalse);
      expect(openAnnouncements, isEmpty);
    },
    semanticsEnabled: true,
  );

  testWidgets('locked panel uses warm neutral framing without a glow', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      photoCount: 4,
      presentMemberCount: 3,
      onOpen: () {},
    );

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
      find.descendant(of: panel, matching: find.byType(AnimatedContainer)),
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
    expect(lock.color, const Color(0xFF8B7E70));
  });

  testWidgets('locked panel shows a lock and ready panel shows a glowing key', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      photoCount: 4,
      presentMemberCount: 3,
      onOpen: () {},
    );

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

    await _pumpCard(
      tester,
      photoCount: 5,
      presentMemberCount: 3,
      onOpen: () {},
    );

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
      find.descendant(of: readyPanel, matching: find.byType(AnimatedContainer)),
    );
    expect((glow.decoration! as BoxDecoration).boxShadow, isNotEmpty);
  });
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required int photoCount,
  required int presentMemberCount,
  VoidCallback? onOpen,
  VoidCallback? onPreview,
}) => tester.pumpWidget(
  MaterialApp(
    theme: KeepersTheme.dark(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: WeeklyExperienceCard(
            presentMemberCount: presentMemberCount,
            requiredPresentMembers: 3,
            weeklyPhotoCount: photoCount,
            requiredWeeklyPhotos: 5,
            onOpen: onOpen,
            onPreview: onPreview,
          ),
        ),
      ),
    ),
  ),
);
