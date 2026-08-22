import 'package:flutter/material.dart';

const keepersWordmarkAsset = 'assets/brand/keepers-wordmark.png';

/// The supplied raster wordmark with its white canvas converted to
/// transparency and the remaining ink tinted at paint time.
final class KeepersWordmark extends StatelessWidget {
  const KeepersWordmark({
    this.width = 196,
    this.height = 78,
    this.inkColor = Colors.black,
    super.key,
  });

  final double width;
  final double height;
  final Color inkColor;

  static const _inkFromLuminance = ColorFilter.matrix(<double>[
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    -.2126,
    -.7152,
    -.0722,
    0,
    255,
  ]);

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Keepers',
    child: ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRect(
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(inkColor, BlendMode.srcIn),
            child: ColorFiltered(
              colorFilter: _inkFromLuminance,
              child: Image.asset(
                keepersWordmarkAsset,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
