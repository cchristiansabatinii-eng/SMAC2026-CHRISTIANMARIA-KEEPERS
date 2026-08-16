import 'package:flutter/material.dart';

const keepersWordmarkAsset = 'assets/brand/keepers-wordmark.png';

/// The supplied raster wordmark, rendered as black ink with its white canvas
/// converted to transparency at paint time.
final class KeepersWordmark extends StatelessWidget {
  const KeepersWordmark({this.width = 196, this.height = 78, super.key});

  final double width;
  final double height;

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
  );
}
