// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keepers/app.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'clean setup saves default-reveal text and reopens it after app restart',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: KeepersApp()));
      await _pumpUntilFound(tester, find.byKey(const Key('family-name')));

      expect(find.byKey(const Key('member-name')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('family-name')),
        'Device Gate Family',
      );
      await tester.enterText(
        find.byKey(const Key('member-name')),
        'Gate Member',
      );
      await tester.tap(find.text('Enter the Observatory'));
      await _pumpUntilFound(tester, find.text('Add a memory'));

      await tester.tap(find.text('Add a memory'));
      await _pumpUntilFound(tester, find.text('Text'));
      await tester.tap(find.text('Text'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('memory-text')),
        'Persists after provider restart',
      );
      await tester.enterText(
        find.byKey(const Key('memory-caption')),
        'Encrypted caption',
      );
      expect(
        tester
            .widget<RadioListTile<PrivacyTier>>(
              find.byKey(const Key('privacy-reveal')),
            )
            .groupValue,
        PrivacyTier.reveal,
      );
      final sealMemory = find.widgetWithText(FilledButton, 'Seal memory');
      await tester.ensureVisible(sealMemory);
      await tester.pump();
      await tester.tap(sealMemory);
      await _pumpUntilFound(tester, find.text('Text memory'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));

      // Unmounting disposes the first ProviderScope and its database-backed
      // providers, matching the persistence boundary crossed by an app launch.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const ProviderScope(child: KeepersApp()));
      await _pumpUntilFound(
        tester,
        find.bySemanticsLabel('Current member Gate Member'),
      );

      final savedMemory = find.text('Text memory');
      await tester.ensureVisible(savedMemory);
      await tester.pump();
      await tester.tap(savedMemory);
      await _pumpUntilFound(
        tester,
        find.text('Persists after provider restart'),
      );
      expect(find.text('Encrypted caption'), findsOneWidget);
    },
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 100,
}) async {
  for (var pump = 0; pump < maxPumps; pump += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}
