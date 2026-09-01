import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

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
  static const _brass = Color(0xFFC9A227);
  static const _darkMemberColors = <String, Color>{
    'ochre': Color(0xFFD29B42),
    'sage': Color(0xFF8FA77A),
    'clay': Color(0xFFC67961),
    'sea': Color(0xFF5D93A6),
  };
  static const _daylightMemberColors = <String, Color>{
    'ochre': Color(0xFF765015),
    'sage': Color(0xFF48643A),
    'clay': Color(0xFF854331),
    'sea': Color(0xFF2E6173),
  };

  static ThemeData dark() => _build(
    Brightness.dark,
    const Color(0xFF10120F),
    const Color(0xFF1A1D18),
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
      colorScheme: ColorScheme.fromSeed(
        seedColor: memberColors['sage']!,
        brightness: brightness,
      ),
      scaffoldBackgroundColor: ground,
      fontFamily: 'Schibsted Grotesk',
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontFamily: 'Fraunces',
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontFamily: 'Fraunces',
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontFamily: 'Fraunces'),
      ),
      extensions: <ThemeExtension<dynamic>>[
        ObservatoryTokens(
          brass: _brass,
          ground: ground,
          memorySurface: memorySurface,
          memberColors: memberColors,
          idleDrift: 4,
          sealDuration: const Duration(milliseconds: 420),
        ),
      ],
    );
  }
}
