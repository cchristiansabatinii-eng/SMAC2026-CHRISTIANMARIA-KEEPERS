import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/archive/presentation/archive_screen.dart';

void main() {
  testWidgets('archive starts with the complete kept forever summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ArchiveScreen(
            familyName: 'Sabati',
            memories: [
              ArchiveMemorySummary(
                id: 'one',
                title: 'Lantern walk',
                authorName: 'Chris',
                theme: 'Traditions',
                formatLabel: 'Photo',
                createdAt: DateTime(2026, 8, 3),
              ),
              ArchiveMemorySummary(
                id: 'two',
                title: 'Kitchen story',
                authorName: 'Amina',
                theme: 'Stories',
                formatLabel: 'Voice',
                createdAt: DateTime(2025, 4, 1),
              ),
            ],
            onDestinationSelected: (_) {},
            onOpenMemory: (_) {},
          ),
        ),
      ),
    );

    final summary = find.bySemanticsLabel('2 memories kept forever');
    final filters = find.bySemanticsLabel('Person filter');
    expect(summary, findsOneWidget);
    expect(filters, findsOneWidget);
    expect(
      tester.getTopLeft(summary).dy,
      lessThan(tester.getTopLeft(filters).dy),
    );

    await tester.tap(find.text('Amina'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('2 memories kept forever'), findsOneWidget);
  });

  testWidgets('archive heading matches the family heading scale and weight', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ArchiveScreen(
            familyName: 'Sabati',
            memories: const [],
            onDestinationSelected: (_) {},
            onOpenMemory: (_) {},
          ),
        ),
      ),
    );

    final sourceTitle = find.text('Sabati archive');
    final paintedTitle = find.descendant(
      of: sourceTitle,
      matching: find.byType(RichText),
    );
    expect(sourceTitle, findsOneWidget);
    expect(paintedTitle, findsOneWidget);

    final richText = tester.widget<RichText>(paintedTitle);
    final span = richText.text as TextSpan;
    expect(span.toPlainText(), 'SABATI ARCHIVE');
    expect(span.style?.fontFamily, 'SchibstedGrotesk');
    expect(span.style?.fontSize, 20);
    expect(span.style?.fontWeight, FontWeight.w600);
    expect(span.style?.letterSpacing, 4.1);
    expect(span.style?.height, 1);
  });

  testWidgets('archive groups kept memories and filters by person', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ArchiveScreen(
            familyName: 'Sabati',
            memories: [
              ArchiveMemorySummary(
                id: 'one',
                title: 'Lantern walk',
                authorName: 'Chris',
                theme: 'Traditions',
                formatLabel: 'Photo',
                createdAt: DateTime(2026, 8, 3),
              ),
              ArchiveMemorySummary(
                id: 'two',
                title: 'Kitchen story',
                authorName: 'Amina',
                theme: 'Stories',
                formatLabel: 'Voice',
                createdAt: DateTime(2025, 4, 1),
              ),
            ],
            onDestinationSelected: (_) {},
            onOpenMemory: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('2026'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('Draw a memory'), findsOneWidget);

    await tester.tap(find.text('Amina'));
    await tester.pumpAndSettle();
    expect(find.text('Kitchen story'), findsOneWidget);
    expect(find.text('Lantern walk'), findsNothing);
  });

  testWidgets('archive has a deliberate kept-only empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ArchiveScreen(
            familyName: 'Sabati',
            memories: const [],
            onDestinationSelected: (_) {},
            onOpenMemory: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Nothing kept yet'), findsOneWidget);
    expect(find.bySemanticsLabel('0 memories kept forever'), findsOneWidget);
    expect(
      find.text('Released and still-sealed memories never appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('archive reserves honest loading and retry states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ArchiveScreen(
            familyName: 'Sabati',
            memories: const [],
            loading: true,
            onDestinationSelected: (_) {},
            onOpenMemory: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Opening family archive…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ArchiveScreen(
            familyName: 'Sabati',
            memories: const [],
            errorMessage: 'The archive could not be opened safely.',
            onRetry: () => retried = true,
            onDestinationSelected: (_) {},
            onOpenMemory: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    expect(retried, isTrue);
  });
}
