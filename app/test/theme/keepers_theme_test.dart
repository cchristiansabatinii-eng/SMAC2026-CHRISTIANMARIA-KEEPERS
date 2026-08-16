import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/theme/keepers_theme.dart';

void main() {
  test('every application text role uses Schibsted Grotesk', () {
    for (final theme in [KeepersTheme.dark(), KeepersTheme.daylight()]) {
      final textTheme = theme.textTheme;
      final styles = <TextStyle?>[
        textTheme.displayLarge,
        textTheme.displayMedium,
        textTheme.displaySmall,
        textTheme.headlineLarge,
        textTheme.headlineMedium,
        textTheme.headlineSmall,
        textTheme.titleLarge,
        textTheme.titleMedium,
        textTheme.titleSmall,
        textTheme.bodyLarge,
        textTheme.bodyMedium,
        textTheme.bodySmall,
        textTheme.labelLarge,
        textTheme.labelMedium,
        textTheme.labelSmall,
      ];

      expect(styles, everyElement(isNotNull));
      expect(styles.map((style) => style!.fontFamily).toSet(), {
        'SchibstedGrotesk',
      });
    }
  });

  testWidgets('the app theme renders the directive ground and font roles', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: KeepersTheme.dark(), home: const Scaffold()),
    );

    final context = tester.element(find.byType(Scaffold));
    final theme = Theme.of(context);
    expect(theme.scaffoldBackgroundColor, KeepersColors.ground);
    expect(theme.textTheme.bodyMedium?.fontFamily, KeepersType.primary);
    expect(theme.textTheme.headlineMedium?.fontFamily, KeepersType.primary);
  });

  test('page headings match the family heading treatment', () {
    expect(KeepersType.heading.fontFamily, KeepersType.primary);
    expect(KeepersType.heading.fontSize, 20);
    expect(KeepersType.heading.fontWeight, FontWeight.w600);
    expect(KeepersType.heading.height, 1);
    expect(KeepersType.heading.letterSpacing, 4.1);

    for (final theme in [KeepersTheme.dark(), KeepersTheme.daylight()]) {
      final appBarTitle = theme.appBarTheme.titleTextStyle;
      expect(appBarTitle?.fontFamily, KeepersType.primary);
      expect(appBarTitle?.fontSize, 20);
      expect(appBarTitle?.fontWeight, FontWeight.w600);
      expect(appBarTitle?.height, 1);
      expect(appBarTitle?.letterSpacing, 4.1);
    }
  });

  testWidgets(
    'KeepersText paints uppercase Schibsted while preserving lighter weight',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: KeepersTheme.daylight(),
          home: const Scaffold(
            body: KeepersText.rich(
              TextSpan(
                text: 'Quiet ',
                children: [
                  TextSpan(
                    text: 'memory',
                    style: TextStyle(fontWeight: FontWeight.w300),
                  ),
                ],
              ),
              style: TextStyle(fontWeight: FontWeight.w400),
            ),
          ),
        ),
      );

      final source = find.text('Quiet memory');
      expect(source, findsOneWidget);
      final richText = tester.widget<RichText>(
        find.descendant(of: source, matching: find.byType(RichText)),
      );
      final span = richText.text as TextSpan;
      expect(span.toPlainText(includeSemanticsLabels: false), 'QUIET MEMORY');
      expect(span.style?.fontFamily, KeepersType.primary);
      expect(span.style?.fontWeight, FontWeight.w400);
      final transformedRoot = span.children!.single as TextSpan;
      expect(transformedRoot.style?.fontFamily, KeepersType.primary);
      final transformedChild = transformedRoot.children!.single as TextSpan;
      expect(transformedChild.style?.fontFamily, KeepersType.primary);
      expect(transformedChild.style?.fontWeight, FontWeight.w300);
      expect(find.bySemanticsLabel('Quiet memory'), findsOneWidget);
    },
  );
}
