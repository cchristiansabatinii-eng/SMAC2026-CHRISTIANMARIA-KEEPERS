import 'package:flutter/material.dart';
import 'package:keepers/theme/keepers_theme.dart';

const keepersBackgroundAsset = 'assets/backgrounds/keepers-background-flat.png';

/// The single app-owned background used behind every Keepers route.
final class KeepersAppBackground extends StatelessWidget {
  const KeepersAppBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: KeepersColors.backgroundFlatFallback,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          keepersBackgroundAsset,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          excludeFromSemantics: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) =>
              const ColoredBox(color: KeepersColors.backgroundFlatFallback),
        ),
        Material(type: MaterialType.transparency, child: child),
      ],
    ),
  );
}
