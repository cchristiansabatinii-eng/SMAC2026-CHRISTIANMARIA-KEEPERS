import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/archive/presentation/archive_screen.dart';
import 'package:keepers/theme/keepers_theme.dart';

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

    await tester.tap(
      find.descendant(
        of: find.bySemanticsLabel('Person filter'),
        matching: find.text('Amina'),
      ),
    );
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
    expect(span.toPlainText(), 'Sabati Archive');
    expect(span.style?.fontFamily, 'ModernSociety');
    expect(span.style?.fontSize, 20);
    expect(span.style?.fontWeight, FontWeight.w600);
    expect(span.style?.letterSpacing, KeepersType.heading.letterSpacing);
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
    expect(find.text('Random Memory'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('2025'),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('archive-gallery')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('2025'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.bySemanticsLabel('Person filter'),
        matching: find.text('Amina'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kitchen story'), findsOneWidget);
    expect(find.text('Lantern walk'), findsNothing);
  });

  testWidgets('archive draw opens one of the kept memories', (tester) async {
    ArchiveMemorySummary? opened;
    final memory = ArchiveMemorySummary(
      id: 'one',
      title: 'Lantern walk',
      authorName: 'Chris',
      theme: 'Traditions',
      formatLabel: 'Photo',
      createdAt: DateTime(2026, 8, 3),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ArchiveScreen(
            familyName: 'Sabati',
            memories: [memory],
            onDestinationSelected: (_) {},
            onOpenMemory: (value) => opened = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('random-memory-mode')));
    expect(opened?.id, memory.id);
  });

  testWidgets('archive draw avoids immediately repeating a memory', (
    tester,
  ) async {
    final opened = <String>[];
    final memories = [
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
        createdAt: DateTime(2026, 8, 2),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ArchiveScreen(
            familyName: 'Sabati',
            memories: memories,
            onDestinationSelected: (_) {},
            onOpenMemory: (value) => opened.add(value.id),
          ),
        ),
      ),
    );

    final draw = find.byKey(const ValueKey('random-memory-mode'));
    await tester.tap(draw);
    await tester.tap(draw);

    expect(opened, hasLength(2));
    expect(opened.first, isNot(opened.last));
  });

  testWidgets('archive draw respects the combined person and theme filters', (
    tester,
  ) async {
    ArchiveMemorySummary? opened;
    await _pumpArchive(
      tester,
      memories: [
        _memory(id: 'amina-story', authorName: 'Amina', theme: 'Stories'),
        _memory(
          id: 'amina-tradition',
          authorName: 'Amina',
          theme: 'Traditions',
        ),
        _memory(id: 'chris-story', authorName: 'Chris', theme: 'Stories'),
      ],
      onOpenMemory: (memory) => opened = memory,
    );

    await tester.tap(
      find.descendant(
        of: find.bySemanticsLabel('Person filter'),
        matching: find.text('Amina'),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.bySemanticsLabel('Theme filter'),
        matching: find.text('Traditions'),
      ),
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Draw a random memory'));

    expect(opened?.id, 'amina-tradition');
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
    final randomMode = find.byKey(const ValueKey('random-memory-mode'));
    expect(randomMode, findsOneWidget);
    expect(find.text('Random Memory'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Draw a random memory'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Draw a random memory'))
          .getSemanticsData()
          .flagsCollection
          .isEnabled,
      Tristate.isFalse,
    );
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
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
    expect(find.text('Random Memory'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Draw a random memory'))
          .getSemanticsData()
          .flagsCollection
          .isEnabled,
      Tristate.isFalse,
    );

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
    expect(find.text('Random Memory'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Draw a random memory'))
          .getSemanticsData()
          .flagsCollection
          .isEnabled,
      Tristate.isFalse,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    expect(retried, isTrue);
  });

  testWidgets(
    'archive keeps Random Memory fixed across loaded loading and error states',
    (tester) async {
      Future<double> pumpState({
        bool loading = false,
        String? errorMessage,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: KeepersTheme.daylight(),
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: ArchiveScreen(
                familyName: 'Sabati',
                memories: [_memory(id: 'one')],
                loading: loading,
                errorMessage: errorMessage,
                onDestinationSelected: (_) {},
                onOpenMemory: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        return tester
            .getTopLeft(find.byKey(const ValueKey('random-memory-mode')))
            .dy;
      }

      final loadedTop = await pumpState();
      final loadingTop = await pumpState(loading: true);
      expect(
        find.bySemanticsLabel('Kept memory count loading'),
        findsOneWidget,
      );
      final errorTop = await pumpState(
        errorMessage: 'The archive could not be opened safely.',
      );
      expect(
        find.bySemanticsLabel('Kept memory count unavailable'),
        findsOneWidget,
      );

      expect(loadingTop, closeTo(loadedTop, .01));
      expect(errorTop, closeTo(loadedTop, .01));
    },
  );

  testWidgets(
    'archive lays out newest memories in three square columns with exact gutters',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final memories = [
        _memory(
          id: 'oldest',
          createdAt: DateTime(2026, 1, 1),
          formatLabel: 'Text',
        ),
        _memory(
          id: 'newest',
          createdAt: DateTime(2026, 8, 3),
          formatLabel: 'Photo',
        ),
        _memory(
          id: 'middle',
          createdAt: DateTime(2026, 4, 2),
          formatLabel: 'Voice',
        ),
        _memory(
          id: 'next-row',
          createdAt: DateTime(2026, 2, 1),
          formatLabel: 'Text',
        ),
        _memory(
          id: 'prior-year',
          createdAt: DateTime(2025, 12, 31),
          formatLabel: 'Voice',
        ),
      ];

      await _pumpArchive(tester, memories: memories);

      final newest = find.byKey(
        const ValueKey<String>('archive-memory-newest'),
      );
      final middle = find.byKey(
        const ValueKey<String>('archive-memory-middle'),
      );
      final nextRow = find.byKey(
        const ValueKey<String>('archive-memory-next-row'),
      );
      final oldest = find.byKey(
        const ValueKey<String>('archive-memory-oldest'),
      );
      expect(newest, findsOneWidget);
      expect(middle, findsOneWidget);
      expect(nextRow, findsOneWidget);
      expect(oldest, findsOneWidget);

      final newestRect = tester.getRect(newest);
      final middleRect = tester.getRect(middle);
      final nextRowRect = tester.getRect(nextRow);
      final oldestRect = tester.getRect(oldest);
      expect(newestRect.left, 24);
      expect(390 - nextRowRect.right, closeTo(24, .01));
      expect(newestRect.width, closeTo(newestRect.height, .01));
      expect(middleRect.left - newestRect.right, closeTo(4, .01));
      expect(nextRowRect.left - middleRect.right, closeTo(4, .01));
      expect(oldestRect.top - newestRect.bottom, closeTo(4, .01));

      final year2026 = tester.getTopLeft(find.text('2026'));
      final year2025 = tester.getTopLeft(find.text('2025'));
      expect(year2026.dy, lessThan(newestRect.top));
      expect(year2025.dy, greaterThan(oldestRect.bottom));
    },
  );

  testWidgets('archive keeps three square columns at 430dp and 1.4x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(1.4),
            disableAnimations: true,
          ),
          child: ArchiveScreen(
            familyName: 'Sabati',
            memories: List.generate(
              4,
              (index) => _memory(
                id: 'wide-$index',
                title: 'A long family memory title $index',
                authorName: 'Amina Al Sabati',
                theme: 'Family traditions across generations',
                formatLabel: index.isEven ? 'Voice' : 'Text',
                createdAt: DateTime(2026, 8, 4 - index),
              ),
            ),
            onDestinationSelected: (_) {},
            onOpenMemory: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final first = tester.getRect(
      find.byKey(const ValueKey<String>('archive-memory-wide-0')),
    );
    final third = tester.getRect(
      find.byKey(const ValueKey<String>('archive-memory-wide-2')),
    );
    final fourth = tester.getRect(
      find.byKey(const ValueKey<String>('archive-memory-wide-3')),
    );
    expect(first.width, closeTo((430 - 48 - 8) / 3, .01));
    expect(first.width, closeTo(first.height, .01));
    expect(430 - third.right, closeTo(24, .01));
    expect(fourth.top - first.bottom, closeTo(4, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('archive uses the compact outlined Random Memory pill', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpArchive(tester, memories: [_memory(id: 'one')]);

    final pill = find.byKey(const ValueKey('random-memory-mode'));
    expect(pill, findsOneWidget);
    expect(tester.getSize(pill), const Size(342, 48));
    expect(find.bySemanticsLabel('Draw a random memory'), findsOneWidget);
    final label = tester.widget<KeepersText>(find.text('Random Memory'));
    expect(label.style?.fontFamily, KeepersType.primary);
    expect(label.style?.fontSize, 14);
    expect(label.style?.fontWeight, FontWeight.w600);
    expect(label.style?.height, 1);
    expect(label.style?.letterSpacing, 1.8);
    final shuffle = tester.widget<Icon>(find.byIcon(Icons.shuffle_rounded));
    expect(shuffle.size, 28);

    final button = tester.widget<OutlinedButton>(
      find.descendant(of: pill, matching: find.byType(OutlinedButton)),
    );
    expect(
      button.style?.padding?.resolve(const <WidgetState>{}),
      const EdgeInsets.symmetric(horizontal: 24),
    );
    expect(
      button.style?.backgroundColor?.resolve(const <WidgetState>{}),
      Colors.transparent,
    );
    expect(
      button.style?.side?.resolve(const <WidgetState>{})?.color,
      KeepersColors.homeTaupe,
    );
    expect(button.style?.side?.resolve(const <WidgetState>{})?.width, 1);
    final shape = button.style?.shape?.resolve(const <WidgetState>{});
    expect(shape, isA<RoundedRectangleBorder>());
    expect(
      (shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(24),
    );
  });

  testWidgets('archive filter chips are visibly compact in 48dp tap targets', (
    tester,
  ) async {
    await _pumpArchive(
      tester,
      memories: [_memory(id: 'one', authorName: 'A', theme: 'Stories')],
    );

    expect(tester.getSize(find.bySemanticsLabel('Person filter')).height, 48);
    expect(tester.getSize(find.bySemanticsLabel('Theme filter')).height, 48);
    final personRail = find.bySemanticsLabel('Person filter');
    final allVisual = find.byKey(
      const ValueKey<String>('archive-filter-person-all-visual'),
    );
    expect(tester.getRect(allVisual).left, 24);
    expect(tester.getSize(allVisual).height, 32);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('archive-filter-person-all-target'),
            ),
          )
          .height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.bySemanticsLabel('A')).width,
      greaterThanOrEqualTo(48),
    );
    final chips = find.descendant(
      of: personRail,
      matching: find.byType(ChoiceChip),
    );
    expect(chips, findsNWidgets(2));
    final allChip = tester.widget<ChoiceChip>(chips.first);
    expect(
      allChip.shape,
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    expect(allChip.backgroundColor, Colors.transparent);
    expect(allChip.selectedColor, KeepersColors.ink);
    expect(allChip.side?.color, KeepersColors.ink);
    final chipLabel = allChip.label as KeepersText;
    expect(chipLabel.style?.fontSize, 12);
    expect(chipLabel.style?.fontFamily, KeepersType.primary);
    expect(chipLabel.style?.fontWeight, FontWeight.w600);
    expect(chipLabel.style?.letterSpacing, .7);
    expect(
      tester.getRect(chips.at(1)).left - tester.getRect(chips.first).right,
      closeTo(4, .01),
    );
  });

  testWidgets(
    'voice and text memories use explicit square cards and still open',
    (tester) async {
      ArchiveMemorySummary? opened;
      await _pumpArchive(
        tester,
        memories: [
          _memory(id: 'voice', formatLabel: 'Voice'),
          _memory(id: 'text', formatLabel: 'Text'),
        ],
        onOpenMemory: (memory) => opened = memory,
      );

      final voice = find.byKey(const ValueKey<String>('archive-memory-voice'));
      final text = find.byKey(const ValueKey<String>('archive-memory-text'));
      expect(tester.getSize(voice).aspectRatio, closeTo(1, .01));
      expect(tester.getSize(text).aspectRatio, closeTo(1, .01));
      expect(
        find.descendant(of: voice, matching: find.text('Voice')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: text, matching: find.text('Text')),
        findsOneWidget,
      );
      final voiceIcon = tester.widget<Icon>(
        find.descendant(
          of: voice,
          matching: find.byIcon(Icons.graphic_eq_rounded),
        ),
      );
      final textIcon = tester.widget<Icon>(
        find.descendant(of: text, matching: find.byIcon(Icons.notes_rounded)),
      );
      expect(voiceIcon.size, 28);
      expect(textIcon.size, 28);
      final voiceSurface = tester
          .widgetList<Material>(
            find.descendant(of: voice, matching: find.byType(Material)),
          )
          .singleWhere((material) => material.borderRadius != null);
      expect(voiceSurface.borderRadius, BorderRadius.circular(4));
      expect(
        tester
            .getSemantics(voice)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(text);
      expect(opened?.id, 'text');
    },
  );

  testWidgets('photo tile lazily renders real preview bytes and still opens', (
    tester,
  ) async {
    final previewBytes = _onePixelPng();
    final loadedIds = <String>[];
    ArchiveMemorySummary? opened;
    await _pumpArchive(
      tester,
      memories: [
        _memory(id: 'photo', formatLabel: 'Photo'),
        _memory(id: 'voice', formatLabel: 'Voice'),
      ],
      loadPhotoPreview: (memory) async {
        loadedIds.add(memory.id);
        return previewBytes;
      },
      onOpenMemory: (memory) => opened = memory,
    );
    await tester.pumpAndSettle();

    expect(loadedIds, ['photo']);
    final photo = find.byKey(const ValueKey<String>('archive-photo-photo'));
    expect(photo, findsOneWidget);
    final image = tester.widget<Image>(photo);
    expect(image.image, isA<ResizeImage>());
    final resizedProvider = image.image as ResizeImage;
    expect(resizedProvider.width, 512);
    expect(resizedProvider.height, 512);
    expect(resizedProvider.policy, ResizeImagePolicy.fit);
    expect(resizedProvider.allowUpscaling, isFalse);
    expect(resizedProvider.imageProvider, isA<MemoryImage>());
    expect(
      (resizedProvider.imageProvider as MemoryImage).bytes,
      same(previewBytes),
    );
    expect(image.fit, BoxFit.cover);
    expect(image.filterQuality, FilterQuality.medium);
    expect(image.gaplessPlayback, isTrue);
    final photoTile = find.byKey(
      const ValueKey<String>('archive-memory-photo'),
    );
    expect(tester.getRect(photo), tester.getRect(photoTile));
    expect(
      find.descendant(of: photoTile, matching: find.text('Photo')),
      findsNothing,
    );
    expect(
      find.descendant(of: photoTile, matching: find.text('Family memory')),
      findsNothing,
    );
    final borderedDecorations = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: photoTile, matching: find.byType(DecoratedBox)),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where((decoration) => decoration.border != null);
    expect(borderedDecorations, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey<String>('archive-memory-photo')),
    );
    expect(opened?.id, 'photo');
  });

  testWidgets('photo tile lease evicts and zeroizes completed preview bytes', (
    tester,
  ) async {
    final previewBytes = _onePixelPng();
    await _pumpArchive(
      tester,
      memories: [_memory(id: 'photo')],
      loadPhotoPreview: (_) async => previewBytes,
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('archive-photo-photo')),
    );
    final provider = image.image;
    expect(provider, isA<ResizeImage>());
    final cacheKey = await provider.obtainKey(ImageConfiguration.empty);
    expect(PaintingBinding.instance.imageCache.containsKey(cacheKey), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(previewBytes, everyElement(0));
    expect(PaintingBinding.instance.imageCache.containsKey(cacheKey), isFalse);
  });

  testWidgets(
    'photo tile lease zeroizes preview bytes that arrive after dispose',
    (tester) async {
      final pendingPreview = Completer<Uint8List?>();
      final previewBytes = _onePixelPng();
      await _pumpArchive(
        tester,
        memories: [_memory(id: 'photo')],
        loadPhotoPreview: (_) => pendingPreview.future,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      pendingPreview.complete(previewBytes);
      await tester.pump();
      await tester.pump();

      expect(previewBytes, everyElement(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('photo previews load only as their lazy grid tiles are built', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final loadedIds = <String>[];
    final memories = List.generate(
      30,
      (index) =>
          _memory(id: 'photo-$index', createdAt: DateTime(2026, 8, 30 - index)),
    );
    await _pumpArchive(
      tester,
      memories: memories,
      loadPhotoPreview: (memory) async {
        loadedIds.add(memory.id);
        return null;
      },
    );
    await tester.pump();

    expect(loadedIds, isNotEmpty);
    expect(loadedIds.length, lessThan(memories.length));
    expect(loadedIds, isNot(contains('photo-29')));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('archive-memory-photo-29')),
      240,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('archive-gallery')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();

    expect(loadedIds, contains('photo-29'));
  });

  testWidgets('photo preview source bytes are capped and cleared', (
    tester,
  ) async {
    final oversized = Uint8List(archivePhotoPreviewMaxSourceBytes + 1);
    oversized.first = 1;
    oversized.last = 2;
    await _pumpArchive(
      tester,
      memories: [_memory(id: 'photo')],
      loadPhotoPreview: (_) async => oversized,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('archive-photo-photo')),
      findsNothing,
    );
    expect(oversized.first, 0);
    expect(oversized.last, 0);
  });

  testWidgets('photo preview decryptions stay concurrency bounded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = <Completer<Uint8List?>>[];
    var active = 0;
    var peakActive = 0;
    var starts = 0;
    final memories = List.generate(
      30,
      (index) =>
          _memory(id: 'photo-$index', createdAt: DateTime(2026, 8, 30 - index)),
    );
    await _pumpArchive(
      tester,
      memories: memories,
      loadPhotoPreview: (_) {
        starts++;
        active++;
        peakActive = math.max(peakActive, active);
        final completion = Completer<Uint8List?>();
        pending.add(completion);
        return completion.future.whenComplete(() => active--);
      },
    );
    await tester.pump();

    expect(starts, archivePhotoPreviewMaxConcurrentLoads);
    expect(peakActive, archivePhotoPreviewMaxConcurrentLoads);

    await tester.drag(
      find.byKey(const ValueKey<String>('archive-gallery')),
      const Offset(0, -500),
    );
    await tester.pump();
    expect(starts, archivePhotoPreviewMaxConcurrentLoads);
    expect(peakActive, archivePhotoPreviewMaxConcurrentLoads);

    await tester.pumpWidget(const SizedBox.shrink());
    for (final completion in pending) {
      if (!completion.isCompleted) completion.complete(null);
    }
    await tester.pump();
    await tester.pump();
    expect(starts, archivePhotoPreviewMaxConcurrentLoads);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling a photo tile away clears its preview lease', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previews = <String, Uint8List>{};
    final memories = List.generate(
      30,
      (index) =>
          _memory(id: 'photo-$index', createdAt: DateTime(2026, 8, 30 - index)),
    );
    await _pumpArchive(
      tester,
      memories: memories,
      loadPhotoPreview: (memory) async =>
          previews.putIfAbsent(memory.id, _onePixelPng),
    );
    await tester.pumpAndSettle();
    final firstPreview = previews['photo-0']!;
    expect(firstPreview, isNot(everyElement(0)));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('archive-memory-photo-29')),
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('archive-gallery')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(firstPreview, everyElement(0));
  });

  testWidgets(
    'a parent rebuild keeps one preview load and byte lease per tile',
    (tester) async {
      final previewBytes = _onePixelPng();
      var loadCount = 0;
      late StateSetter rebuildHost;
      await tester.pumpWidget(
        MaterialApp(
          theme: KeepersTheme.daylight(),
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuildHost = setState;
              return ArchiveScreen(
                familyName: 'Sabati',
                memories: [_memory(id: 'photo')],
                loadPhotoPreview: (_) async {
                  loadCount++;
                  return previewBytes;
                },
                onDestinationSelected: (_) {},
                onOpenMemory: (_) {},
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(loadCount, 1);

      rebuildHost(() {});
      await tester.pumpAndSettle();

      expect(loadCount, 1);
      expect(previewBytes, isNot(everyElement(0)));
      expect(
        find.byKey(const ValueKey<String>('archive-photo-photo')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(previewBytes, everyElement(0));
    },
  );
}

Future<void> _pumpArchive(
  WidgetTester tester, {
  required List<ArchiveMemorySummary> memories,
  ValueChanged<ArchiveMemorySummary>? onOpenMemory,
  Future<Uint8List?> Function(ArchiveMemorySummary)? loadPhotoPreview,
}) => tester.pumpWidget(
  MaterialApp(
    theme: KeepersTheme.daylight(),
    home: ArchiveScreen(
      familyName: 'Sabati',
      memories: memories,
      loadPhotoPreview: loadPhotoPreview,
      onDestinationSelected: (_) {},
      onOpenMemory: onOpenMemory ?? (_) {},
    ),
  ),
);

ArchiveMemorySummary _memory({
  required String id,
  String title = 'Family memory',
  String authorName = 'Chris',
  String theme = 'Stories',
  String formatLabel = 'Photo',
  DateTime? createdAt,
}) => ArchiveMemorySummary(
  id: id,
  title: title,
  authorName: authorName,
  theme: theme,
  formatLabel: formatLabel,
  createdAt: createdAt ?? DateTime(2026, 8, 3),
);

Uint8List _onePixelPng() => Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);
