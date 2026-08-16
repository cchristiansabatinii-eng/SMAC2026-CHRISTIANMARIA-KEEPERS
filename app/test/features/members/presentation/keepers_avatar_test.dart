import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humation_flutter/humation_flutter.dart';
import 'package:keepers/features/members/domain/avatar_catalog.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/theme/keepers_theme.dart';

void main() {
  const config = AvatarConfig.defaults(seed: 'member-1');

  testWidgets(
    'KeepersAvatar renders the configured Humation identity locally',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: KeepersAvatar(config: config, size: 96)),
      );

      final avatar = tester.widget<HumationAvatar>(
        find.bySubtype<HumationAvatar>(),
      );
      expect(avatar.seed, 'member-1');
      expect(avatar.selections, config.selections);
      expect(avatar.colors, config.colors);
      expect(avatar.size, 96);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets('KeepersAvatar keeps a square decorative footprint', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: KeepersAvatar(config: config, size: 92)),
    );

    expect(_squareWithin(find.byType(KeepersAvatar), 92), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(KeepersAvatar),
        matching: find.byType(ExcludeSemantics),
      ),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('KeepersAvatar sanitizes malformed selections before rendering', (
    tester,
  ) async {
    final malformed = AvatarConfig(
      schemaVersion: AvatarConfig.currentSchemaVersion,
      styleId: AvatarConfig.currentStyleId,
      styleRevision: AvatarConfig.currentStyleRevision,
      seed: 'member-1',
      selections: const {
        'head': 'not-a-bundled-part',
        'unknown-slot': 'hm1-p-000001',
      },
      colors: const {},
    );
    final sanitized = avatarCatalog.sanitize(
      malformed,
      fallbackSeed: 'member-1',
    );

    await tester.pumpWidget(
      MaterialApp(home: KeepersAvatar(config: malformed, size: 92)),
    );

    expect(tester.takeException(), isNull);
    expect(_squareWithin(find.byType(KeepersAvatar), 92), findsOneWidget);
    final avatar = tester.widget<HumationAvatar>(
      find.bySubtype<HumationAvatar>(),
    );
    expect(avatar.seed, sanitized.seed);
    expect(avatar.selections, sanitized.selections);
    expect(avatar.colors, sanitized.colors);
  });

  testWidgets(
    'KeepersAvatar keeps its neutral fallback on a Humation build failure',
    (tester) async {
      KeepersAvatar.debugBeforeHumationBuild = () {
        throw StateError('forced package build failure');
      };
      addTearDown(() => KeepersAvatar.debugBeforeHumationBuild = null);

      await tester.pumpWidget(
        const MaterialApp(home: KeepersAvatar(config: config, size: 92)),
      );

      expect(tester.takeException(), isNull);
      expect(_squareWithin(find.byType(KeepersAvatar), 92), findsNWidgets(2));
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    },
  );

  testWidgets('KeepersAvatar exposes its optional image label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: KeepersAvatar(
          config: config,
          size: 64,
          semanticLabel: 'Mariam portrait',
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(KeepersAvatar)),
      matchesSemantics(isImage: true, label: 'Mariam portrait'),
    );
  });

  testWidgets('detail crop visibly distinguishes Bottom selections', (
    tester,
  ) async {
    final widePants = config.withSelection(HumationSlot.bottom, 'hm1-p-000033');
    final longSkirt = config.withSelection(HumationSlot.bottom, 'hm1-p-000036');

    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            KeepersAvatar(
              config: widePants,
              size: 120,
              crop: KeepersAvatarCrop.detail,
            ),
            KeepersAvatar(
              config: longSkirt,
              size: 120,
              crop: KeepersAvatarCrop.detail,
            ),
          ],
        ),
      ),
    );

    final avatars = tester
        .widgetList<HumationAvatar>(find.bySubtype<HumationAvatar>())
        .toList(growable: false);
    expect(avatars.map((avatar) => avatar.selections![HumationSlot.bottom]), [
      'hm1-p-000033',
      'hm1-p-000036',
    ]);

    for (final avatar in avatars) {
      final manifest = avatar.manifest ?? humation1Manifest;
      final crop = manifest.crops[avatar.crop ?? manifest.defaults.crop]!;
      final bottom = manifest.layerSlotById(HumationSlot.bottom)!;
      expect(crop.y, lessThanOrEqualTo(bottom.offset.y));
      expect(
        crop.y + crop.height,
        greaterThanOrEqualTo(bottom.offset.y + bottom.size.height),
      );
    }
  });

  testWidgets('surface owns exact opaque Wheel tokens without a shadow', (
    tester,
  ) async {
    const accent = Color(0xFF5BD5AA);
    await tester.pumpWidget(
      const MaterialApp(
        home: KeepersAvatarSurface(
          size: 80,
          accent: accent,
          child: SizedBox.expand(),
        ),
      ),
    );

    final decorated = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final decoration = decorated.decoration as BoxDecoration;
    expect(
      decoration.color,
      Color.alphaBlend(accent.withValues(alpha: .1), KeepersColors.auraIvory),
    );
    expect(decoration.border, isA<Border>());
    final border = decoration.border! as Border;
    expect(
      border.top.color,
      Color.alphaBlend(accent.withValues(alpha: .18), KeepersColors.homeLine),
    );
    expect(border.top.width, 1.1);
    expect(decoration.boxShadow, isNull);
    expect(find.byType(ClipOval), findsOneWidget);
    expect(
      _squareWithin(find.byType(KeepersAvatarSurface), 80),
      findsOneWidget,
    );
  });
}

Finder _squareWithin(Finder parent, double size) => find.descendant(
  of: parent,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is SizedBox && widget.width == size && widget.height == size,
  ),
);
