import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/launch/presentation/keepers_launch_sequence.dart';

void main() {
  testWidgets('plays the approved Keepers phrase sequence in order', (
    tester,
  ) async {
    var readyCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: KeepersLaunchSequence(
          onCompleted: () {},
          onReady: () => readyCount += 1,
        ),
      ),
    );
    await _finishLogoPrecache(tester);

    expect(find.byKey(const ValueKey('keepers-launch-logo')), findsOneWidget);
    expect(find.byKey(const ValueKey('keepers-launch-phrase')), findsNothing);
    expect(readyCount, 1);

    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Be present.'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Be present.')).style?.decoration,
      TextDecoration.none,
    );

    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('Be authentic.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Be bold.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Be you.'), findsOneWidget);
    expect(find.textContaining('perfect', findRichText: true), findsNothing);
    expect(readyCount, 1);
  });

  testWidgets('the authentic phase gathers the cream memory field', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: KeepersLaunchSequence(onCompleted: () {})),
    );
    await _finishLogoPrecache(tester);

    await tester.pump(const Duration(milliseconds: 2000));

    expect(
      find.byKey(const ValueKey('keepers-launch-memory-field')),
      findsOneWidget,
    );
  });

  testWidgets('a tap skips the sequence exactly once', (tester) async {
    var completionCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: KeepersLaunchSequence(onCompleted: () => completionCount += 1),
      ),
    );
    await _finishLogoPrecache(tester);
    await tester.pump(const Duration(milliseconds: 900));

    await tester.tap(find.byKey(const ValueKey('keepers-launch-sequence')));
    await tester.tap(find.byKey(const ValueKey('keepers-launch-sequence')));
    await tester.pump();

    expect(completionCount, 1);
  });

  testWidgets('iOS Reduce Motion bypasses the animated sequence', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    var completionCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: KeepersLaunchSequence(onCompleted: () => completionCount += 1),
      ),
    );
    await tester.pump();

    expect(completionCount, 1);
  });

  testWidgets('disabled animations bypass the animated sequence', (
    tester,
  ) async {
    var completionCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: KeepersLaunchSequence(onCompleted: () => completionCount += 1),
        ),
      ),
    );
    await tester.pump();

    expect(completionCount, 1);
  });
}

Future<void> _finishLogoPrecache(WidgetTester tester) async {
  await tester.runAsync(
    () => precacheImage(
      const AssetImage(keepersLaunchWordmarkAsset),
      tester.element(find.byType(KeepersLaunchSequence)),
    ),
  );
  await tester.pump();
  await tester.pump();
}
