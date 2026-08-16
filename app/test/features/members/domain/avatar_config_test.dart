import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';

void main() {
  test('Humation config round-trips canonically', () {
    final config = AvatarConfig(
      schemaVersion: 2,
      styleId: 'humation-1',
      styleRevision: 1,
      seed: 'member-1',
      selections: {'head': 'hm1-p-000001', 'body': 'hm1-p-000020'},
      colors: {'hair': '4a3728', 'skin': 'f4c9a8'},
    );

    expect(
      AvatarConfig.decode(config.encode(), fallbackSeed: 'fallback'),
      config,
    );
  });

  test(
    'previous Lorelei JSON resets to a Humation default with the member seed',
    () {
      const previous =
          '{"schemaVersion":1,"styleId":"keepers-lorelei","seed":"old"}';

      expect(
        AvatarConfig.decode(previous, fallbackSeed: 'member-1'),
        const AvatarConfig.defaults(seed: 'member-1'),
      );
    },
  );

  test('decode normalizes selection keys and hexadecimal colors', () {
    final raw = jsonEncode({
      'schemaVersion': 2,
      'styleId': 'humation-1',
      'styleRevision': 1,
      'seed': 'member-1',
      'selections': {' HEAD ': 'hm1-p-000001'},
      'colors': {' Hair ': '#4A3728'},
    });

    expect(
      AvatarConfig.decode(raw, fallbackSeed: 'fallback'),
      AvatarConfig(
        schemaVersion: 2,
        styleId: 'humation-1',
        styleRevision: 1,
        seed: 'member-1',
        selections: {'head': 'hm1-p-000001'},
        colors: {'hair': '4a3728'},
      ),
    );
  });

  test(
    'decode rejects a mismatched schema, style, revision, or empty seed',
    () {
      for (final raw in [
        _encodedConfig({'schemaVersion': 1}),
        _encodedConfig({'styleId': 'other'}),
        _encodedConfig({'styleRevision': 2}),
        _encodedConfig({'seed': ''}),
      ]) {
        expect(
          AvatarConfig.decode(raw, fallbackSeed: 'member-1'),
          const AvatarConfig.defaults(seed: 'member-1'),
          reason: raw,
        );
      }
    },
  );

  test('copyWith replaces maps and equality is structural', () {
    final original = AvatarConfig(
      schemaVersion: 2,
      styleId: 'humation-1',
      styleRevision: 1,
      seed: 'member-1',
      selections: {'head': 'hm1-p-000001'},
      colors: {'hair': '4a3728'},
    );

    final updated = original.copyWith(
      selections: {'body': 'hm1-p-000020'},
      colors: {'skin': 'f4c9a8'},
    );

    expect(
      updated,
      AvatarConfig(
        schemaVersion: 2,
        styleId: 'humation-1',
        styleRevision: 1,
        seed: 'member-1',
        selections: {'body': 'hm1-p-000020'},
        colors: {'skin': 'f4c9a8'},
      ),
    );
    expect(updated.hashCode, updated.copyWith().hashCode);
  });

  test(
    'constructor and copyWith retain immutable snapshots of supplied maps',
    () {
      final selections = <String, String>{'head': 'hm1-p-000001'};
      final colors = <String, String>{'hair': '4a3728'};
      final config = AvatarConfig(
        schemaVersion: 2,
        styleId: 'humation-1',
        styleRevision: 1,
        seed: 'member-1',
        selections: selections,
        colors: colors,
      );

      selections['head'] = 'mutated';
      colors['hair'] = 'ffffff';
      expect(config.selections, {'head': 'hm1-p-000001'});
      expect(config.colors, {'hair': '4a3728'});
      expect(
        () => config.selections['body'] = 'hm1-p-000020',
        throwsUnsupportedError,
      );
      expect(() => config.colors['skin'] = 'f4c9a8', throwsUnsupportedError);

      final replacements = <String, String>{'body': 'hm1-p-000020'};
      final copied = config.copyWith(selections: replacements);
      replacements['body'] = 'mutated';

      expect(copied.selections, {'body': 'hm1-p-000020'});
      expect(
        () => copied.selections['head'] = 'hm1-p-000001',
        throwsUnsupportedError,
      );
    },
  );
}

String _encodedConfig(Map<String, Object> overrides) => jsonEncode({
  'schemaVersion': 2,
  'styleId': 'humation-1',
  'styleRevision': 1,
  'seed': 'member-1',
  'selections': <String, String>{},
  'colors': <String, String>{},
  ...overrides,
});
