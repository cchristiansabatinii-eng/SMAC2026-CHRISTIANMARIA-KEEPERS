import 'dart:convert';

enum AvatarCategory { head, body, bottom, item, glasses, colors }

/// The persisted, renderer-independent Humation avatar recipe.
final class AvatarConfig {
  static const currentSchemaVersion = 2;
  static const currentStyleId = 'humation-1';
  static const currentStyleRevision = 1;

  factory AvatarConfig({
    required int schemaVersion,
    required String styleId,
    required int styleRevision,
    required String seed,
    required Map<String, String> selections,
    required Map<String, String> colors,
  }) => AvatarConfig._(
    schemaVersion: schemaVersion,
    styleId: styleId,
    styleRevision: styleRevision,
    seed: seed,
    selections: _immutableMap(selections),
    colors: _immutableMap(colors),
  );

  const AvatarConfig._({
    required this.schemaVersion,
    required this.styleId,
    required this.styleRevision,
    required this.seed,
    required this.selections,
    required this.colors,
  });

  const AvatarConfig.defaults({required this.seed})
    : schemaVersion = currentSchemaVersion,
      styleId = currentStyleId,
      styleRevision = currentStyleRevision,
      selections = const {},
      colors = const {};

  final int schemaVersion;
  final String styleId;
  final int styleRevision;
  final String seed;
  final Map<String, String> selections;
  final Map<String, String> colors;

  factory AvatarConfig.decode(String raw, {required String fallbackSeed}) {
    final fallback = AvatarConfig.defaults(seed: fallbackSeed);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return fallback;
      final json = Map<Object?, Object?>.from(decoded);
      if (json['schemaVersion'] != currentSchemaVersion ||
          json['styleId'] != currentStyleId ||
          json['styleRevision'] != currentStyleRevision ||
          json['seed'] is! String ||
          (json['seed'] as String).isEmpty) {
        return fallback;
      }

      return AvatarConfig(
        schemaVersion: currentSchemaVersion,
        styleId: currentStyleId,
        styleRevision: currentStyleRevision,
        seed: json['seed'] as String,
        selections: _normalizeStrings(json['selections']),
        colors: _normalizeColors(json['colors']),
      );
    } catch (_) {
      return fallback;
    }
  }

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'styleId': styleId,
    'styleRevision': styleRevision,
    'seed': seed,
    'selections': _sorted(selections),
    'colors': _sorted(colors),
  };

  String encode() => jsonEncode(toJson());

  String get renderKey => encode();

  AvatarConfig copyWith({
    Map<String, String>? selections,
    Map<String, String>? colors,
  }) => AvatarConfig(
    schemaVersion: schemaVersion,
    styleId: styleId,
    styleRevision: styleRevision,
    seed: seed,
    selections: selections ?? this.selections,
    colors: colors ?? this.colors,
  );

  AvatarConfig withSelection(String slot, String partId) =>
      copyWith(selections: {...selections, slot: partId});

  AvatarConfig withColor(String slot, String hex) =>
      copyWith(colors: {...colors, slot: hex});

  @override
  bool operator ==(Object other) =>
      other is AvatarConfig &&
      schemaVersion == other.schemaVersion &&
      styleId == other.styleId &&
      styleRevision == other.styleRevision &&
      seed == other.seed &&
      _mapsEqual(selections, other.selections) &&
      _mapsEqual(colors, other.colors);

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    styleId,
    styleRevision,
    seed,
    _mapHash(selections),
    _mapHash(colors),
  );

  static Map<String, String> _normalizeStrings(Object? raw) =>
      _normalizeMap(raw, (value) => value.trim());

  static Map<String, String> _normalizeColors(Object? raw) =>
      _normalizeMap(raw, _normalizeHex);

  static Map<String, String> _normalizeMap(
    Object? raw,
    String? Function(String value) normalizeValue,
  ) {
    if (raw is! Map) return const {};
    final normalized = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! String) continue;
      final key = (entry.key as String).trim().toLowerCase();
      final value = normalizeValue(entry.value as String);
      if (key.isNotEmpty && value != null && value.isNotEmpty) {
        normalized[key] = value;
      }
    }
    return _sorted(normalized);
  }

  static String? normalizeHex(String raw) => _normalizeHex(raw);

  static String? _normalizeHex(String raw) {
    final hex = raw.trim().replaceFirst(RegExp(r'^#'), '').toLowerCase();
    return RegExp(r'^[0-9a-f]{6}$').hasMatch(hex) ? hex : null;
  }

  static Map<String, String> _sorted(Map<String, String> map) {
    final entries = map.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return Map<String, String>.unmodifiable(Map.fromEntries(entries));
  }

  static Map<String, String> _immutableMap(Map<String, String> map) =>
      Map<String, String>.unmodifiable(Map<String, String>.from(map));

  static bool _mapsEqual(Map<String, String> left, Map<String, String> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  static int _mapHash(Map<String, String> map) {
    final entries = map.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return Object.hashAll(
      entries.map((entry) => Object.hash(entry.key, entry.value)),
    );
  }
}
