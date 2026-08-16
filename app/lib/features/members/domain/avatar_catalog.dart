import 'package:humation_flutter/humation_flutter.dart';

import 'avatar_config.dart';

final class AvatarOption {
  AvatarOption({
    required this.id,
    required this.label,
    required this.category,
    required this.apply,
    required this.isSelected,
  });

  final String id;
  final String label;
  final AvatarCategory category;
  final AvatarConfig Function(AvatarConfig) apply;
  final bool Function(AvatarConfig) isSelected;
}

abstract interface class AvatarCatalog {
  const AvatarCatalog();

  List<AvatarCategory> get categories;
  List<AvatarOption> optionsFor(AvatarCategory category);
  bool isAllowed(AvatarConfig config);
  AvatarConfig sanitize(AvatarConfig config, {required String fallbackSeed});
}

const AvatarCatalog avatarCatalog = HumationAvatarCatalog();

final class HumationAvatarCatalog implements AvatarCatalog {
  const HumationAvatarCatalog();

  static const _categories = [
    AvatarCategory.head,
    AvatarCategory.body,
    AvatarCategory.bottom,
    AvatarCategory.item,
    AvatarCategory.glasses,
    AvatarCategory.colors,
  ];

  static const _slotForCategory = {
    AvatarCategory.head: HumationSlot.head,
    AvatarCategory.body: HumationSlot.body,
    AvatarCategory.bottom: HumationSlot.bottom,
    AvatarCategory.item: HumationSlot.item,
    AvatarCategory.glasses: HumationSlot.glasses,
  };

  static final _colorSwatches = {
    HumationColorSlot.hair: _withDefaultColor(HumationColorSlot.hair, const [
      '4a3728',
      '1d1712',
      '8a5a3c',
      'd4a76a',
    ]),
    HumationColorSlot.skin: _withDefaultColor(HumationColorSlot.skin, const [
      'f4c9a8',
      'e0a17a',
      'b97555',
      '7b4937',
    ]),
    HumationColorSlot.clothes: _withDefaultColor(
      HumationColorSlot.clothes,
      const ['39526d', '8f5d58', '6a7b51', 'e2b66e'],
    ),
    HumationColorSlot.bottom: _withDefaultColor(
      HumationColorSlot.bottom,
      const ['243447', '4f5d75', '745140', '3e493c'],
    ),
  };

  @override
  List<AvatarCategory> get categories => _categories;

  @override
  List<AvatarOption> optionsFor(AvatarCategory category) {
    if (category == AvatarCategory.colors) return _colorOptions;
    final slot = _slotForCategory[category];
    if (slot == null) return const [];
    return getPartsForSlot(Humation.manifest, slot)
        .map(
          (part) => AvatarOption(
            id: part.id,
            label: _humanize(part.name ?? part.id),
            category: category,
            apply: (config) => _effectivePart(config, slot) == part.id
                ? config
                : config.withSelection(slot, part.id),
            isSelected: (config) => _effectivePart(config, slot) == part.id,
          ),
        )
        .toList(growable: false);
  }

  @override
  bool isAllowed(AvatarConfig config) {
    if (config.schemaVersion != AvatarConfig.currentSchemaVersion ||
        config.styleId != AvatarConfig.currentStyleId ||
        config.styleRevision != AvatarConfig.currentStyleRevision ||
        config.seed.isEmpty) {
      return false;
    }

    final validPartIds = _validPartIdsBySlot;
    for (final entry in config.selections.entries) {
      if (validPartIds[entry.key]?.contains(entry.value) != true) return false;
    }
    for (final entry in config.colors.entries) {
      if (!_colorSwatches.containsKey(entry.key) ||
          AvatarConfig.normalizeHex(entry.value) != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  AvatarConfig sanitize(AvatarConfig config, {required String fallbackSeed}) {
    final validPartIds = _validPartIdsBySlot;
    final selections = <String, String>{
      for (final entry in config.selections.entries)
        if (validPartIds[entry.key]?.contains(entry.value) == true)
          entry.key: entry.value,
    };
    final colors = <String, String>{
      for (final entry in config.colors.entries)
        if (_colorSwatches.containsKey(entry.key))
          entry.key: ?AvatarConfig.normalizeHex(entry.value),
    };
    return AvatarConfig(
      schemaVersion: AvatarConfig.currentSchemaVersion,
      styleId: AvatarConfig.currentStyleId,
      styleRevision: AvatarConfig.currentStyleRevision,
      seed: config.seed.isEmpty ? fallbackSeed : config.seed,
      selections: selections,
      colors: colors,
    );
  }

  static final _validPartIdsBySlot = {
    for (final slot in _slotForCategory.values)
      slot: getPartsForSlot(
        Humation.manifest,
        slot,
      ).map((part) => part.id).toSet(),
  };

  static final _seededPartIdsBySlot = {
    for (final slot in _slotForCategory.values)
      slot: Humation.manifest
          .partsInSlot(slot)
          .map((part) => part.id)
          .toList(growable: false),
  };

  static final _colorOptions = List<AvatarOption>.unmodifiable([
    for (final entry in _colorSwatches.entries)
      for (final hex in entry.value)
        AvatarOption(
          id: '${entry.key}-$hex',
          label: '${_humanize(entry.key)} ${hex.toUpperCase()}',
          category: AvatarCategory.colors,
          apply: (config) => _effectiveColor(config, entry.key) == hex
              ? config
              : config.withColor(entry.key, hex),
          isSelected: (config) => _effectiveColor(config, entry.key) == hex,
        ),
  ]);

  static String? _effectivePart(AvatarConfig config, String slot) {
    final explicit = config.selections[slot];
    if (_validPartIdsBySlot[slot]?.contains(explicit) == true) return explicit;

    final seededParts = _seededPartIdsBySlot[slot];
    if (seededParts == null || seededParts.isEmpty) return null;
    return seededParts[fnv1a('${config.seed}:$slot') % seededParts.length];
  }

  static String? _effectiveColor(AvatarConfig config, String slot) {
    final explicit = AvatarConfig.normalizeHex(config.colors[slot] ?? '');
    if (explicit != null) return explicit;
    return AvatarConfig.normalizeHex(
      Humation.manifest.defaults.colors[slot] ?? '',
    );
  }

  static List<String> _withDefaultColor(String slot, List<String> swatches) {
    final defaultColor = AvatarConfig.normalizeHex(
      Humation.manifest.defaults.colors[slot] ?? '',
    );
    return List.unmodifiable({?defaultColor, ...swatches});
  }

  static String _humanize(String value) => value
      .replaceAll(RegExp(r'[-_]'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
