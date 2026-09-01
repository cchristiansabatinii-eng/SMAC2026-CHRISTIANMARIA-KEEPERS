import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';

void main() {
  testWidgets('Observatory themes expose stable identity and typography', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: KeepersTheme.dark(), home: const SizedBox()),
    );
    final context = tester.element(find.byType(SizedBox));
    final tokens = Theme.of(context).extension<ObservatoryTokens>()!;

    expect(tokens.brass, const Color(0xFFC9A227));
    expect(tokens.memberColors['ochre'], isNotNull);
    expect(
      Theme.of(context).textTheme.bodyMedium!.fontFamily,
      'Schibsted Grotesk',
    );
    expect(Theme.of(context).textTheme.headlineMedium!.fontFamily, 'Fraunces');

    final daylight = KeepersTheme.daylight();
    expect(daylight.brightness, Brightness.light);
    expect(daylight.extension<ObservatoryTokens>()!.brass, tokens.brass);
    for (final theme in [KeepersTheme.dark(), KeepersTheme.daylight()]) {
      final values = theme.extension<ObservatoryTokens>()!;
      for (final color in values.memberColors.values) {
        expect(_contrastRatio(color, values.ground), greaterThanOrEqualTo(3));
      }
    }
  });
}

double _contrastRatio(Color a, Color b) {
  final lighter = max(a.computeLuminance(), b.computeLuminance());
  final darker = min(a.computeLuminance(), b.computeLuminance());
  return (lighter + .05) / (darker + .05);
}
