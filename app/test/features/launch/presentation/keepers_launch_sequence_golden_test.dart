import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/launch/presentation/keepers_launch_sequence.dart';

void main() {
  testWidgets('launch sequence keeps its composition at phone size', (
    tester,
  ) async {
    expect(debugPaintBaselinesEnabled, isFalse);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fontLoader = FontLoader('ModernSociety')
      ..addFont(
        rootBundle.load(
          'assets/fonts/modern_society/modernsociety-regular.otf',
        ),
      );
    await fontLoader.load();

    await tester.pumpWidget(
      MaterialApp(home: KeepersLaunchSequence(onCompleted: () {})),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(keepersLaunchWordmarkAsset),
        tester.element(find.byType(KeepersLaunchSequence)),
      ),
    );
    await tester.pump();
    await tester.pump();
    await expectLater(
      find.byKey(const ValueKey('keepers-launch-sequence')),
      matchesGoldenFile('goldens/keepers_launch_logo_390x844.png'),
    );

    await tester.pump(const Duration(milliseconds: 900));
    await expectLater(
      find.byKey(const ValueKey('keepers-launch-sequence')),
      matchesGoldenFile('goldens/keepers_launch_present_390x844.png'),
    );

    await tester.pump(const Duration(milliseconds: 1100));
    await expectLater(
      find.byKey(const ValueKey('keepers-launch-sequence')),
      matchesGoldenFile('goldens/keepers_launch_authentic_390x844.png'),
    );

    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(
      find.byKey(const ValueKey('keepers-launch-sequence')),
      matchesGoldenFile('goldens/keepers_launch_bold_390x844.png'),
    );

    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(
      find.byKey(const ValueKey('keepers-launch-sequence')),
      matchesGoldenFile('goldens/keepers_launch_you_390x844.png'),
    );
  }, tags: 'golden');
}
