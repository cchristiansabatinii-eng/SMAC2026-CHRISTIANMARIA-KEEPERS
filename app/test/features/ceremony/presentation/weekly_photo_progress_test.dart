import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/ceremony/presentation/weekly_experience_card.dart';
import 'package:keepers/theme/keepers_theme.dart';

void main() {
  testWidgets('shows only capped segments while semantics describe progress', (
    tester,
  ) async {
    for (final scenario in const [
      (photoCount: 0, semanticsValue: '0 of 5 photos. 5 photos needed'),
      (photoCount: 3, semanticsValue: '3 of 5 photos. 2 photos needed'),
      (photoCount: 8, semanticsValue: '5 of 5 photos. Ready to gather'),
    ]) {
      final photoCount = scenario.photoCount;
      await _pumpProgress(tester, photoCount: photoCount);

      final progress = find.bySemanticsLabel('Weekly photo progress');
      expect(progress, findsOneWidget, reason: 'photoCount=$photoCount');
      expect(
        tester.getSemantics(progress).getSemanticsData().value,
        scenario.semanticsValue,
        reason: 'photoCount=$photoCount',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('weekly-photo-progress')),
          matching: find.byType(RichText),
        ),
        findsNothing,
        reason: 'the segmented bar should not paint explanatory copy',
      );
    }
  }, semanticsEnabled: true);

  testWidgets('completed photo progress invites the family to gather', (
    tester,
  ) async {
    for (final scenario in const [
      (photoCount: 3, status: '2 photos needed'),
      (photoCount: 5, status: 'Ready to gather'),
    ]) {
      await _pumpProgress(tester, photoCount: scenario.photoCount);

      final progress = find.bySemanticsLabel('Weekly photo progress');
      expect(
        tester.getSemantics(progress).getSemanticsData().value,
        '${scenario.photoCount} of 5 photos. ${scenario.status}',
        reason: '${scenario.photoCount} photos',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('weekly-photo-progress')),
          matching: find.byType(RichText),
        ),
        findsNothing,
      );
    }
  }, semanticsEnabled: true);

  testWidgets('renders one segment for every required weekly photo', (
    tester,
  ) async {
    await _pumpProgress(tester, photoCount: 3);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('weekly-photo-progress')),
        matching: find.byType(AnimatedContainer),
      ),
      findsNWidgets(5),
    );
  });

  testWidgets('filled segments use the current-member yellow first', (
    tester,
  ) async {
    await _pumpProgress(tester, photoCount: 5);

    final decorations = _progressDecorations(tester);
    expect(decorations.first.color, KeepersColors.homeAvatarGold);
    expect(decorations.first.border?.top.color, KeepersColors.homeAvatarGold);
  });

  testWidgets('only filled segments carry restrained matching glows', (
    tester,
  ) async {
    await _pumpProgress(tester, photoCount: 2);

    final decorations = _progressDecorations(tester);
    for (final decoration in decorations.take(2)) {
      final shadows = decoration.boxShadow;
      expect(shadows, hasLength(1));
      final shadow = shadows!.single;
      expect(shadow.color.r, closeTo(decoration.color!.r, .001));
      expect(shadow.color.g, closeTo(decoration.color!.g, .001));
      expect(shadow.color.b, closeTo(decoration.color!.b, .001));
      expect(shadow.color.a, inExclusiveRange(.15, .4));
      expect(shadow.blurRadius, inInclusiveRange(4, 12));
      expect(shadow.spreadRadius, lessThanOrEqualTo(1));
    }
    for (final decoration in decorations.skip(2)) {
      expect(decoration.boxShadow, isNull);
    }
  });

  testWidgets('photo count has one accessibility announcement', (tester) async {
    await _pumpProgress(tester, photoCount: 3);

    final countAnnouncements = tester.semantics
        .simulatedAccessibilityTraversal()
        .where((node) {
          final data = node.getSemanticsData();
          return data.label.contains('3 of 5 photos') ||
              data.value.contains('3 of 5 photos');
        })
        .toList(growable: false);

    expect(countAnnouncements, hasLength(1));
  }, semanticsEnabled: true);

  testWidgets('weekly progress and gate status share one live region', (
    tester,
  ) async {
    await _pumpProgress(tester, photoCount: 3);

    final progress = find.bySemanticsLabel('Weekly photo progress');
    expect(progress, findsOneWidget);
    expect(
      tester
          .getSemantics(progress)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
  }, semanticsEnabled: true);
}

List<BoxDecoration> _progressDecorations(WidgetTester tester) => tester
    .widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byKey(const ValueKey('weekly-photo-progress')),
        matching: find.byType(AnimatedContainer),
      ),
    )
    .map((segment) => segment.decoration! as BoxDecoration)
    .toList(growable: false);

Future<void> _pumpProgress(WidgetTester tester, {required int photoCount}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: WeeklyPhotoProgress(
                weeklyPhotoCount: photoCount,
                requiredWeeklyPhotos: 5,
              ),
            ),
          ),
        ),
      ),
    );
