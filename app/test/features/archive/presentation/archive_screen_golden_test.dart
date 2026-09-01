import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/archive/presentation/archive_screen.dart';
import 'package:keepers/ui/keepers_app_background.dart';

void main() {
  testWidgets('archive gallery keeps its approved phone composition', (
    tester,
  ) async {
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
    final iconFontLoader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconFontLoader.load();

    final photoAssets = <String, Uint8List>{};
    for (final entry in const {
      'photo-one': 'assets/memories/weekly_reference_1.png',
      'photo-two': 'assets/memories/weekly_reference_2.png',
      'photo-three': 'assets/memories/weekly_reference_3.png',
    }.entries) {
      final data = await rootBundle.load(entry.value);
      photoAssets[entry.key] = Uint8List.fromList(data.buffer.asUint8List());
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 24, bottom: 24),
            disableAnimations: true,
          ),
          child: KeepersAppBackground(
            child: ArchiveScreen(
              familyName: 'Sabatini',
              memories: _galleryMemories,
              loadPhotoPreview: (memory) async {
                return photoAssets[memory.id];
              },
              onDestinationSelected: (_) {},
              onOpenMemory: (_) {},
            ),
          ),
        ),
      ),
    );
    final archiveContext = tester.element(find.byType(ArchiveScreen));
    await tester.runAsync(() async {
      for (final bytes in photoAssets.values) {
        await precacheImage(
          ResizeImage(
            MemoryImage(bytes),
            width: 512,
            height: 512,
            policy: ResizeImagePolicy.fit,
            allowUpscaling: false,
          ),
          archiveContext,
        );
      }
    });
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KeepersAppBackground),
      matchesGoldenFile('goldens/archive_gallery_390x844.png'),
    );

    await tester.drag(
      find.byKey(const ValueKey('archive-gallery')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(KeepersAppBackground),
      matchesGoldenFile('goldens/archive_gallery_scrolled_390x844.png'),
    );
  });
}

final _galleryMemories = <ArchiveMemorySummary>[
  ArchiveMemorySummary(
    id: 'photo-one',
    title: 'Beach morning',
    authorName: 'Christian',
    theme: 'Photographs',
    formatLabel: 'Photo',
    createdAt: DateTime(2026, 9, 8),
  ),
  ArchiveMemorySummary(
    id: 'photo-two',
    title: 'Birthday candles',
    authorName: 'Noura',
    theme: 'Celebrations',
    formatLabel: 'Photo',
    createdAt: DateTime(2026, 9, 7),
  ),
  ArchiveMemorySummary(
    id: 'voice-one',
    title: 'Grandma\'s kitchen story',
    authorName: 'Mariam',
    theme: 'Stories',
    formatLabel: 'Voice',
    createdAt: DateTime(2026, 9, 6),
  ),
  ArchiveMemorySummary(
    id: 'text-one',
    title: 'First school morning',
    authorName: 'Youssef',
    theme: 'Milestones',
    formatLabel: 'Text',
    createdAt: DateTime(2026, 9, 5),
  ),
  ArchiveMemorySummary(
    id: 'photo-three',
    title: 'Evening walk',
    authorName: 'Layla',
    theme: 'Everyday',
    formatLabel: 'Photo',
    createdAt: DateTime(2026, 9, 4),
  ),
  ArchiveMemorySummary(
    id: 'voice-two',
    title: 'The old neighborhood',
    authorName: 'Christian',
    theme: 'Stories',
    formatLabel: 'Voice',
    createdAt: DateTime(2026, 9, 3),
  ),
  ArchiveMemorySummary(
    id: 'text-two',
    title: 'A note from last summer',
    authorName: 'Noura',
    theme: 'Notes',
    formatLabel: 'Text',
    createdAt: DateTime(2025, 8, 14),
  ),
];
