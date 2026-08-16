import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:keepers/theme/keepers_theme.dart';

@immutable
final class ObservatoryTokens extends ThemeExtension<ObservatoryTokens> {
  const ObservatoryTokens({
    required this.brass,
    required this.ground,
    required this.memorySurface,
    required this.memberColors,
    required this.idleDrift,
    required this.sealDuration,
  });

  final Color brass;
  final Color ground;
  final Color memorySurface;
  final Map<String, Color> memberColors;
  final double idleDrift;
  final Duration sealDuration;

  Color memberColor(String token) =>
      memberColors[token] ?? memberColors['ochre']!;

  @override
  ObservatoryTokens copyWith({
    Color? brass,
    Color? ground,
    Color? memorySurface,
    Map<String, Color>? memberColors,
    double? idleDrift,
    Duration? sealDuration,
  }) => ObservatoryTokens(
    brass: brass ?? this.brass,
    ground: ground ?? this.ground,
    memorySurface: memorySurface ?? this.memorySurface,
    memberColors: memberColors ?? this.memberColors,
    idleDrift: idleDrift ?? this.idleDrift,
    sealDuration: sealDuration ?? this.sealDuration,
  );

  @override
  ObservatoryTokens lerp(covariant ObservatoryTokens? other, double t) {
    if (other == null) return this;
    return ObservatoryTokens(
      brass: Color.lerp(brass, other.brass, t)!,
      ground: Color.lerp(ground, other.ground, t)!,
      memorySurface: Color.lerp(memorySurface, other.memorySurface, t)!,
      memberColors: memberColors,
      idleDrift: lerpDouble(idleDrift, other.idleDrift, t)!,
      sealDuration: t < .5 ? sealDuration : other.sealDuration,
    );
  }
}

final class KeepersTheme {
  static final _darkMemberColors = <String, Color>{
    'green': KeepersColors.memberPalette[0],
    'rose': KeepersColors.memberPalette[1],
    'orange': KeepersColors.memberPalette[2],
    'teal': KeepersColors.memberPalette[3],
    'blue': KeepersColors.memberPalette[4],
    'purple': KeepersColors.memberPalette[5],
    'ochre': KeepersColors.memberPalette[2],
    'sage': KeepersColors.memberPalette[0],
    'clay': KeepersColors.memberPalette[1],
    'sea': KeepersColors.memberPalette[3],
  };
  static const _daylightMemberColors = <String, Color>{
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

  static ThemeData dark() => _build(
    Brightness.dark,
    KeepersColors.ground,
    KeepersColors.groundVignette,
    _darkMemberColors,
  );

  static ThemeData daylight() => _build(
    Brightness.light,
    const Color(0xFFF4F0E5),
    const Color(0xFFFFFCF3),
    _daylightMemberColors,
  );

  static ThemeData _build(
    Brightness brightness,
    Color ground,
    Color memorySurface,
    Map<String, Color> memberColors,
  ) {
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: brightness == Brightness.dark
          ? const ColorScheme.dark(
              primary: KeepersColors.brass,
              onPrimary: KeepersColors.ground,
              secondary: KeepersColors.brassLight,
              onSecondary: KeepersColors.ground,
              surface: KeepersColors.groundVignette,
              onSurface: KeepersColors.cream,
            )
          : ColorScheme.fromSeed(
              seedColor: memberColors['sage']!,
              brightness: brightness,
            ),
      scaffoldBackgroundColor: ground,
      fontFamily: KeepersType.primary,
    );
    return base.copyWith(
      textTheme: _keepersTextTheme(base.textTheme),
      primaryTextTheme: _keepersTextTheme(base.primaryTextTheme),
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: KeepersType.heading.copyWith(
          color: base.colorScheme.onSurface,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: KeepersColors.brass,
      ),
      extensions: <ThemeExtension<dynamic>>[
        ObservatoryTokens(
          brass: KeepersColors.brass,
          ground: ground,
          memorySurface: memorySurface,
          memberColors: memberColors,
          idleDrift: 4,
          sealDuration: const Duration(milliseconds: 420),
        ),
      ],
    );
  }

  static TextTheme _keepersTextTheme(TextTheme source) => source.copyWith(
    displayLarge: _tracked(source.displayLarge, 1.1),
    displayMedium: _tracked(source.displayMedium, 1.05),
    displaySmall: _tracked(source.displaySmall, 1),
    headlineLarge: _tracked(source.headlineLarge, .95),
    headlineMedium: _tracked(source.headlineMedium, .9),
    headlineSmall: _tracked(source.headlineSmall, .85),
    titleLarge: _tracked(source.titleLarge, .8),
    titleMedium: _tracked(source.titleMedium, .75),
    titleSmall: _tracked(source.titleSmall, .7),
    bodyLarge: _tracked(source.bodyLarge, .55),
    bodyMedium: _tracked(source.bodyMedium, .5),
    bodySmall: _tracked(source.bodySmall, .5),
    labelLarge: _tracked(source.labelLarge, 1),
    labelMedium: _tracked(source.labelMedium, 1.3),
    labelSmall: _tracked(source.labelSmall, 1.7),
  );

  static TextStyle? _tracked(TextStyle? source, double letterSpacing) => source
      ?.copyWith(fontFamily: KeepersType.primary, letterSpacing: letterSpacing);
}
