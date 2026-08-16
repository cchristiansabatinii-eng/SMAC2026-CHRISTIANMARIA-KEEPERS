import 'package:flutter_test/flutter_test.dart';
import 'package:humation_flutter/humation_flutter.dart';
import 'package:keepers/features/members/domain/avatar_catalog.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';

void main() {
  test('catalog exposes the complete Humation editor order', () {
    expect(avatarCatalog.categories, const [
      AvatarCategory.head,
      AvatarCategory.body,
      AvatarCategory.bottom,
      AvatarCategory.item,
      AvatarCategory.glasses,
      AvatarCategory.colors,
    ]);
  });

  test('part option IDs exactly match their bundled manifest slots', () {
    const base = AvatarConfig.defaults(seed: 'm');
    const slots = <AvatarCategory, String>{
      AvatarCategory.head: HumationSlot.head,
      AvatarCategory.body: HumationSlot.body,
      AvatarCategory.bottom: HumationSlot.bottom,
      AvatarCategory.item: HumationSlot.item,
      AvatarCategory.glasses: HumationSlot.glasses,
    };
    for (final entry in slots.entries) {
      final options = avatarCatalog.optionsFor(entry.key);
      expect(
        options.map((option) => option.id),
        getPartsForSlot(
          Humation.manifest,
          entry.value,
        ).map((part) => part.id).toList(),
        reason: entry.key.name,
      );
      for (final option in options) {
        final applied = option.apply(base);
        expect(
          avatarCatalog.sanitize(applied, fallbackSeed: 'm'),
          applied,
          reason: '${entry.key.name}/${option.id}',
        );
      }
    }
  });

  test('fixed color options select supported normalized swatches', () {
    const base = AvatarConfig.defaults(seed: 'm');
    final options = avatarCatalog.optionsFor(AvatarCategory.colors);

    expect(options, isNotEmpty);
    final colorSlots = options
        .map((option) => option.id.split('-').first)
        .toSet();
    expect(colorSlots, {'hair', 'skin', 'clothes', 'bottom'});
    for (final option in options) {
      final applied = option.apply(base);
      expect(avatarCatalog.sanitize(applied, fallbackSeed: 'm'), applied);
    }
  });

  test(
    'fresh and migrated recipes expose every option rendered by Humation',
    () {
      const fresh = AvatarConfig.defaults(seed: 'member-1');
      final migrated = AvatarConfig.decode(
        '{"schemaVersion":1,"styleId":"keepers-lorelei","seed":"old"}',
        fallbackSeed: 'member-1',
      );
      final rendered = Humation.resolve('member-1');
      const partSlots = <AvatarCategory, String>{
        AvatarCategory.head: HumationSlot.head,
        AvatarCategory.body: HumationSlot.body,
        AvatarCategory.bottom: HumationSlot.bottom,
        AvatarCategory.item: HumationSlot.item,
        AvatarCategory.glasses: HumationSlot.glasses,
      };

      for (final config in [fresh, migrated]) {
        for (final entry in partSlots.entries) {
          final selected = avatarCatalog
              .optionsFor(entry.key)
              .where((option) => option.isSelected(config))
              .single;

          expect(selected.id, rendered.selections[entry.value]);
          expect(selected.apply(config), same(config));
        }

        for (final slot in const [
          HumationColorSlot.hair,
          HumationColorSlot.skin,
          HumationColorSlot.clothes,
          HumationColorSlot.bottom,
        ]) {
          final selected = avatarCatalog
              .optionsFor(AvatarCategory.colors)
              .where(
                (option) =>
                    option.id.startsWith('$slot-') && option.isSelected(config),
              )
              .single;

          expect(selected.id, '$slot-${rendered.colors[slot]!.toLowerCase()}');
          expect(selected.apply(config), same(config));
        }
      }
    },
  );

  test('a new choice becomes effective across every editor category', () {
    const fresh = AvatarConfig.defaults(seed: 'member-1');

    for (final category in avatarCatalog.categories) {
      final option = avatarCatalog
          .optionsFor(category)
          .firstWhere((candidate) => !candidate.isSelected(fresh));
      final applied = option.apply(fresh);

      expect(applied, isNot(fresh), reason: category.name);
      expect(option.isSelected(applied), isTrue, reason: category.name);
      expect(option.apply(applied), same(applied), reason: category.name);
    }
  });

  test('sanitize removes unknown values while preserving valid selections and colors', () {
    final knownHead = avatarCatalog.optionsFor(AvatarCategory.head).first.id;
    final sanitized = avatarCatalog.sanitize(
      AvatarConfig.defaults(seed: 'member-1').copyWith(
        selections: {'head': knownHead, 'unknown': 'missing'},
        colors: {'hair': '#4A3728', 'unknown': '#ffffff'},
      ),
      fallbackSeed: 'fallback',
    );

    expect(sanitized.seed, 'member-1');
    expect(sanitized.selections, {'head': knownHead});
    expect(sanitized.colors, {'hair': '4a3728'});
  });
}
