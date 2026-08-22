import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/ceremony/presentation/weekly_experience_card.dart';

void main() {
  testWidgets('shows only capped segments while semantics describe progress', (
    tester,
  ) async {
    for (final scenario in const [
      (
        photoCount: 0,
        semanticsValue: '0 of 5 photos. 5 photos needed. 1 more family member needs to be present',
      ),
      (
        photoCount: 3,
        semanticsValue: '3 of 5 photos. 2 photos needed. 1 more family member needs to be present',
      ),
      (
        photoCount: 8,
        semanticsValue:
            '5 of 5 photos. 1 more family member needs to be present',
      ),
    ]) {
      final photoCount = scenario.photoCount;
      await _pumpProgress(
        tester,
        photoCount: photoCount,
        presentMemberCount: 1,
      );

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

  testWidgets('semantics name whichever weekly requirements remain', (
    tester,
  ) async {
    for (final scenario in const [
      (
        photoCount: 3,
        presentMemberCount: 1,
        status: '2 photos needed. 1 more family member needs to be present',
      ),
      (photoCount: 3, presentMemberCount: 2, status: '2 photos needed'),
      (
        photoCount: 5,
        presentMemberCount: 1,
        status: '1 more family member needs to be present',
      ),
      (photoCount: 5, presentMemberCount: 2, status: 'Ready to open together'),
    ]) {
      await _pumpProgress(
        tester,
        photoCount: scenario.photoCount,
        presentMemberCount: scenario.presentMemberCount,
      );

      final progress = find.bySemanticsLabel('Weekly photo progress');
      expect(
        tester.getSemantics(progress).getSemanticsData().value,
        '${scenario.photoCount} of 5 photos. ${scenario.status}',
        reason:
            '${scenario.photoCount} photos, '
            '${scenario.presentMemberCount} family members present',
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
    await _pumpProgress(tester, photoCount: 3, presentMemberCount: 1);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('weekly-photo-progress')),
        matching: find.byType(AnimatedContainer),
      ),
      findsNWidgets(5),
    );
  });

  testWidgets('photo count has one accessibility announcement', (tester) async {
    await _pumpProgress(tester, photoCount: 3, presentMemberCount: 1);

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
    await _pumpProgress(tester, photoCount: 3, presentMemberCount: 1);

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

Future<void> _pumpProgress(
  WidgetTester tester, {
  required int photoCount,
  required int presentMemberCount,
}) => tester.pumpWidget(
  MaterialApp(
    theme: KeepersTheme.dark(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: WeeklyPhotoProgress(
            weeklyPhotoCount: photoCount,
            requiredWeeklyPhotos: 5,
            presentMemberCount: presentMemberCount,
            requiredPresentMembers: 2,
          ),
        ),
      ),
    ),
  ),
);
