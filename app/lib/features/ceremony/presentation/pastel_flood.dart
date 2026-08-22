import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:keepers/theme/keepers_theme.dart';

final class PastelFloodPainter extends CustomPainter {
  const PastelFloodPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final eased = Curves.easeOutCubic.transform(progress);
    final longest = math.max(size.width, size.height);
    final colors = <Color>[
      KeepersColors.memberPalette[1],
      KeepersColors.memberPalette[5],
      KeepersColors.memberPalette[3],
      KeepersColors.memberPalette[2],
      const Color(0xFFF2D86B),
    ];
    final centers = <Offset>[
      Offset(size.width * .08, size.height * .72),
      Offset(size.width * .88, size.height * .64),
      Offset(size.width * .22, size.height * .28),
      Offset(size.width * .76, size.height * .22),
      Offset(size.width * .5, size.height * .48),
    ];
    final floodPath = Path();
    for (var index = 0; index < colors.length; index++) {
      final stagger = (eased - index * .045).clamp(0.0, 1.0);
      final radius = longest * stagger * (.82 + index * .025);
      floodPath.addOval(
        Rect.fromCircle(center: centers[index], radius: radius),
      );
    }
    final pastels = [
      for (final color in colors) Color.lerp(color, Colors.white, .48)!,
    ];
    canvas.save();
    canvas.clipPath(floodPath);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pastels,
          stops: const [0, .22, .47, .72, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PastelFloodPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
