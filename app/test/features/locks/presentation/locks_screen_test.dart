import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/locks/presentation/locks_screen.dart';
import 'package:keepers/theme/keepers_theme.dart';

void main() {
  testWidgets('legacy approval requires a full two-second hold', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: LocksScreen(
            familyName: 'Sabati',
            onDestinationSelected: (_) {},
            onOpenMemorialPreview: () {},
          ),
        ),
      ),
    );

    expect(find.text('Legacy Locks'), findsOneWidget);
    expect(find.bySemanticsLabel('Memory Key, selected'), findsOneWidget);
    expect(find.text('PREVIEW'), findsOneWidget);
    final hold = find.byKey(const ValueKey('legacy-approval-hold'));
    final gesture = await tester.startGesture(tester.getCenter(hold));
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('Approved for preview'), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Approved for preview'), findsOneWidget);
  });

  testWidgets('locks empty state uses the shared heading treatment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: LocksScreen(
            familyName: 'Sabati',
            onDestinationSelected: (_) {},
            onOpenMemorialPreview: () {},
          ),
        ),
      ),
    );

    final source = find.text('No real Legacy Locks yet');
    await tester.scrollUntilVisible(source, 200);
    final richText = tester.widget<RichText>(
      find.descendant(of: source, matching: find.byType(RichText)),
    );
    final headingStyle = (richText.text as TextSpan).style;
    expect(headingStyle?.fontSize, 20);
    expect(headingStyle?.fontWeight, FontWeight.w600);
    expect(headingStyle?.letterSpacing, KeepersType.heading.letterSpacing);
  });
}
