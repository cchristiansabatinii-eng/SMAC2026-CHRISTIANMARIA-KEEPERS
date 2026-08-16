import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/application/capture_controller.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';

import 'capture_test_harness.dart';

void main() {
  testWidgets('capture remains reachable at 1.4x text scale', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = CaptureTestHarness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.sheet(
        mediaQuery: const MediaQueryData(
          size: Size(390, 844),
          textScaler: TextScaler.linear(1.4),
          viewInsets: EdgeInsets.only(bottom: 280),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await harness.container
        .read(captureControllerProvider.notifier)
        .selectFormat(MemoryFormat.text);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('memory-text')),
      'Reachable above the keyboard',
    );
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await _continueToAccess(tester);

    for (final option in <(String, Key, PrivacyTier)>[
      ('Private Journal', const Key('privacy-journal'), PrivacyTier.journal),
      ('Weekly Reveal', const Key('privacy-reveal'), PrivacyTier.reveal),
      ('Legacy Milestone', const Key('privacy-legacy'), PrivacyTier.legacy),
    ]) {
      await Scrollable.ensureVisible(
        tester.element(find.byKey(option.$2)),
        alignment: .3,
      );
      await tester.pump();
      final radio = find.descendant(
        of: find.byKey(option.$2),
        matching: find.byType(Radio<PrivacyTier>),
      );
      expect(radio, findsOneWidget);
      await tester.tapAt(tester.getCenter(radio));
      await tester.pump();
      expect(
        harness.container.read(captureControllerProvider).privacy,
        option.$3,
      );
    }
    await Scrollable.ensureVisible(
      tester.element(find.text('Keep memory')),
      alignment: .3,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.widgetWithText(FilledButton, 'Keep memory').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('voice control exposes a labeled button semantic', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = CaptureTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.sheet());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();

    final record = find.byKey(const Key('record-toggle'));
    expect(record, findsOneWidget);
    final data = tester.getSemantics(record).getSemanticsData();
    expect(data.label, 'Start voice recording');
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, Tristate.isTrue);
    expect(tester.getSize(record).shortestSide, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const Key('record-toggle')));
    await tester.pump();
    expect(
      tester
          .getSemantics(find.byKey(const Key('record-toggle')))
          .getSemanticsData()
          .label,
      'Stop voice recording',
    );
    semantics.dispose();
  });

  testWidgets('format controls use labels and minimum touch targets', (
    tester,
  ) async {
    final harness = CaptureTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.sheet());
    await tester.pump();

    for (final label in ['Photo', 'Voice', 'Text']) {
      final target = find.ancestor(
        of: find.text(label),
        matching: find.byType(TextButton),
      );
      expect(target, findsOneWidget);
      expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
    }
    expect(
      tester.getSize(find.widgetWithText(OutlinedButton, 'Camera')).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester
          .getSize(find.widgetWithText(OutlinedButton, 'Photo Library'))
          .height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('inline save failure keeps an accessible retry action', (
    tester,
  ) async {
    final harness = CaptureTestHarness(
      save: (_) async => throw StateError('storage detail'),
    );
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.sheet());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('memory-text')), 'Keep this');

    await harness.container.read(captureControllerProvider.notifier).save();
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Try again'), findsOneWidget);
  });

  testWidgets('voice announces sparse elapsed milestones', (tester) async {
    final harness = CaptureTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.sheet());
    await tester.pumpAndSettle();
    await harness.container
        .read(captureControllerProvider.notifier)
        .selectFormat(MemoryFormat.voice);
    await tester.pump();
    tester.takeAnnouncements();

    await tester.tap(find.byKey(const Key('record-toggle')));
    await tester.pump();
    expect(
      tester.takeAnnouncements().map((item) => item.message),
      contains('Recording started'),
    );

    await tester.pump(const Duration(seconds: 29));
    expect(tester.takeAnnouncements(), isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.takeAnnouncements().map((item) => item.message),
      contains('Recording 30 seconds'),
    );
    await tester.pump(const Duration(seconds: 30));
    expect(
      tester.takeAnnouncements().map((item) => item.message),
      contains('Recording 1 minute'),
    );

    await tester.tap(find.byKey(const Key('record-toggle')));
    await tester.pump();
    expect(
      tester.takeAnnouncements().map((item) => item.message),
      contains('Recording stopped'),
    );
  });

  testWidgets('settled save announces success before returning', (
    tester,
  ) async {
    final harness = CaptureTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.launcher());
    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    tester.takeAnnouncements();
    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('memory-text')), 'Announce me');
    tester.testTextInput.hide();
    await tester.pump();
    await _continueToAccess(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Keep memory'));
    await tester.pumpAndSettle();

    expect(
      tester.takeAnnouncements().map((item) => item.message),
      contains('Memory kept'),
    );
    expect(find.text('Completions: 1'), findsOneWidget);
  });

  testWidgets('failed save never announces success', (tester) async {
    final harness = CaptureTestHarness(
      save: (_) async => throw StateError('persistence failed'),
    );
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.sheet());
    await tester.pumpAndSettle();
    await harness.container
        .read(captureControllerProvider.notifier)
        .selectFormat(MemoryFormat.text);
    harness.container
        .read(captureControllerProvider.notifier)
        .updateText('Do not announce');
    tester.takeAnnouncements();

    await harness.container.read(captureControllerProvider.notifier).save();
    await tester.pumpAndSettle();

    expect(
      tester.takeAnnouncements().map((item) => item.message),
      isNot(contains('Memory kept')),
    );
  });
}

Future<void> _continueToAccess(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Continue'));
  await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
  await tester.pumpAndSettle();
}
