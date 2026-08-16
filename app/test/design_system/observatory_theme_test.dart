import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/theme/keepers_theme.dart';

void main() {
  test('home profile accents use the approved bright pastel palette', () {
    expect(KeepersColors.homeClay, const Color(0xFFFF7A72));
    expect(KeepersColors.homeGreen, const Color(0xFF5BD5AA));
    expect(KeepersColors.homeBlue, const Color(0xFF78A8FF));
    expect(KeepersColors.homeMauve, const Color(0xFFC99CFF));
    expect(KeepersColors.homeAvatarGold, const Color(0xFFFFD563));
  });

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
      KeepersType.primary,
    );
    expect(
      Theme.of(context).textTheme.headlineMedium!.fontFamily,
      KeepersType.primary,
    );

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

  test('daylight resolves every persisted member color token explicitly', () {
    const expectedColors = <String, Color>{
      'ochre': Color(0xFF765015),
      'sage': Color(0xFF48643A),
      'clay': Color(0xFF854331),
      'sea': Color(0xFF2E6173),
      'green': Color(0xFF3F722F),
      'rose': Color(0xFF9A4050),
      'orange': Color(0xFF985315),
      'teal': Color(0xFF247267),
      'blue': Color(0xFF3B6597),
      'purple': Color(0xFF704C99),
    };
    final tokens = KeepersTheme.daylight().extension<ObservatoryTokens>()!;

    expect(tokens.memberColors.keys.toSet(), expectedColors.keys.toSet());
    for (final entry in expectedColors.entries) {
      expect(tokens.memberColors[entry.key], entry.value);
      expect(tokens.memberColor(entry.key), entry.value);
      expect(
        _contrastRatio(entry.value, tokens.ground),
        greaterThanOrEqualTo(3),
        reason: '${entry.key} must remain legible on the daylight ground',
      );
    }
  });
}

double _contrastRatio(Color a, Color b) {
  final lighter = max(a.computeLuminance(), b.computeLuminance());
  final darker = min(a.computeLuminance(), b.computeLuminance());
  return (lighter + .05) / (darker + .05);
}
