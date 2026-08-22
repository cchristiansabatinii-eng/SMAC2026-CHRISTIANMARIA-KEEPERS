import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/motion_policy.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';

void main() {
  testWidgets('platform disableAnimations removes drift and travel', (
    tester,
  ) async {
    late MotionPolicy policy;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            policy = MotionPolicy.fromMediaQuery(
              MediaQuery.of(context),
              _tokens(),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(policy.idleDrift, 0);
    expect(policy.parallax, 0);
    expect(policy.useSealTravel, isFalse);
    expect(policy.sealDuration, const Duration(milliseconds: 168));
  });

  testWidgets('accessible navigation also selects reduced motion', (
    tester,
  ) async {
    late MotionPolicy policy;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(accessibleNavigation: true),
        child: Builder(
          builder: (context) {
            policy = MotionPolicy.fromMediaQuery(
              MediaQuery.of(context),
              _tokens(),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(policy.isReduced, isTrue);
    expect(policy.idleDrift, 0);
    expect(policy.useSealTravel, isFalse);
  });

  testWidgets('platform reduce motion is honored outside launch', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    late bool reduced;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Builder(
          builder: (context) {
            reduced = keepersReduceMotion(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(reduced, isTrue);
  });

  testWidgets('default policy uses bounded v0 Observatory motion', (
    tester,
  ) async {
    late MotionPolicy policy;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Builder(
          builder: (context) {
            policy = MotionPolicy.fromMediaQuery(
              MediaQuery.of(context),
              _tokens(idleDrift: 9, sealDuration: const Duration(seconds: 1)),
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(policy.isReduced, isFalse);
    expect(policy.idleDrift, 9);
    expect(policy.parallax, 0);
    expect(policy.useSealTravel, isTrue);
    expect(policy.sealDuration, const Duration(seconds: 1));
    expect(policy.idlePeriod, const Duration(seconds: 16));
  });
}

ObservatoryTokens _tokens({
  double idleDrift = 4,
  Duration sealDuration = const Duration(milliseconds: 420),
}) => ObservatoryTokens(
  brass: Colors.amber,
  ground: Colors.black,
  memorySurface: Colors.white,
  memberColors: const {'ochre': Colors.orange},
  idleDrift: idleDrift,
  sealDuration: sealDuration,
);
