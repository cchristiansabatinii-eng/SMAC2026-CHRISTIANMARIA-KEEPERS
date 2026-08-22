import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/theme/keepers_theme.dart';

void main() {
  test('every application text role uses Modern Society', () {
    expect(KeepersType.primary, 'ModernSociety');

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
        'ModernSociety',
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

  test('Modern Society headings use restrained title-scale tracking', () {
    expect(KeepersType.heading.fontFamily, KeepersType.primary);
    expect(KeepersType.heading.fontSize, 20);
    expect(KeepersType.heading.fontWeight, FontWeight.w600);
    expect(KeepersType.heading.height, 1);
    expect(KeepersType.heading.letterSpacing, lessThanOrEqualTo(1));

    for (final theme in [KeepersTheme.dark(), KeepersTheme.daylight()]) {
      final appBarTitle = theme.appBarTheme.titleTextStyle;
      expect(appBarTitle?.fontFamily, KeepersType.primary);
      expect(appBarTitle?.fontSize, 20);
      expect(appBarTitle?.fontWeight, FontWeight.w600);
      expect(appBarTitle?.height, 1);
      expect(appBarTitle?.letterSpacing, KeepersType.heading.letterSpacing);
      expect(
        theme.textTheme.titleLarge?.letterSpacing,
        KeepersType.heading.letterSpacing,
      );
    }
  });

  test('small accent copy meets AA contrast on daylight surfaces', () {
    final archiveSurface = Color.alphaBlend(
      KeepersColors.auraBlush.withValues(alpha: .5),
      KeepersColors.auraGround,
    );

    expect(
      _contrastRatio(KeepersColors.homeGoldText, archiveSurface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(KeepersColors.legacyOliveText, KeepersColors.auraIvory),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets(
    'KeepersText paints title-case Modern Society while preserving weight',
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
      expect(span.toPlainText(includeSemanticsLabels: false), 'Quiet Memory');
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

double _contrastRatio(Color first, Color second) {
  final light = math.max(first.computeLuminance(), second.computeLuminance());
  final dark = math.min(first.computeLuminance(), second.computeLuminance());
  return (light + .05) / (dark + .05);
}
