import 'package:flutter/widgets.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';

bool keepersReduceMotion(BuildContext context) {
  final media = MediaQuery.maybeOf(context);
  final platform = View.of(context).platformDispatcher.accessibilityFeatures;
  return (media?.disableAnimations ?? false) ||
      (media?.accessibleNavigation ?? false) ||
      platform.reduceMotion;
}

final class MotionPolicy {
  const MotionPolicy({
    required this.idleDrift,
    required this.parallax,
    required this.useSealTravel,
    required this.sealDuration,
  });

  factory MotionPolicy.fromMediaQuery(
    MediaQueryData mediaQuery,
    ObservatoryTokens tokens,
  ) {
    final reduced =
        mediaQuery.disableAnimations || mediaQuery.accessibleNavigation;
    return MotionPolicy(
      idleDrift: reduced ? 0 : tokens.idleDrift,
      parallax: 0,
      useSealTravel: !reduced,
      sealDuration: reduced ? tokens.sealDuration * .4 : tokens.sealDuration,
    );
  }

  final double idleDrift;
  final double parallax;
  final bool useSealTravel;
  final Duration sealDuration;

  bool get isReduced => !useSealTravel;
  Duration get idlePeriod => sealDuration * 16;
}
