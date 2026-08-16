import 'package:flutter/material.dart';
import 'package:humation_flutter/humation_flutter.dart';
import 'package:keepers/features/members/domain/avatar_catalog.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/theme/keepers_theme.dart';

enum KeepersAvatarCrop { compact, detail }

const _fullCharacterCropId = 'keepers-full-character';

final _fullCharacterManifest = HumationManifest(
  schemaVersion: humation1Manifest.schemaVersion,
  template: humation1Manifest.template,
  defaults: humation1Manifest.defaults,
  colors: humation1Manifest.colors,
  crops: {
    ...humation1Manifest.crops,
    // Humation's Bottom layer reaches y=192. This square keeps the full
    // character proportional while retaining the bundled crop's top padding.
    _fullCharacterCropId: const ViewBox(
      x: -60.25,
      y: -4.5,
      width: 200.5,
      height: 200.5,
    ),
  },
  selectionSlots: humation1Manifest.selectionSlots,
  uiGroups: humation1Manifest.uiGroups,
  layerSlots: humation1Manifest.layerSlots,
  parts: humation1Manifest.parts,
  aliases: humation1Manifest.aliases,
);

/// Keepers' sole reusable boundary for local Humation artwork.
final class KeepersAvatar extends StatelessWidget {
  const KeepersAvatar({
    super.key,
    required this.config,
    required this.size,
    this.crop = KeepersAvatarCrop.compact,
    this.semanticLabel,
  });

  final AvatarConfig config;
  final double size;
  final KeepersAvatarCrop crop;
  final String? semanticLabel;

  /// Exercised only by the widget regression test for the scoped build guard.
  @visibleForTesting
  static VoidCallback? debugBeforeHumationBuild;

  @override
  Widget build(BuildContext context) {
    final safeConfig = avatarCatalog.sanitize(
      config,
      fallbackSeed: config.seed,
    );
    final artwork = SizedBox.square(
      dimension: size,
      child: RepaintBoundary(
        child: ClipRect(
          child: Transform.scale(
            scale: switch (crop) {
              KeepersAvatarCrop.compact => 1.18,
              KeepersAvatarCrop.detail => 1,
            },
            alignment: switch (crop) {
              KeepersAvatarCrop.compact => const Alignment(0, -0.06),
              KeepersAvatarCrop.detail => Alignment.center,
            },
            child: _SafeHumationAvatar(
              seed: safeConfig.seed,
              selections: safeConfig.selections,
              colors: safeConfig.colors,
              size: size,
              crop: crop == KeepersAvatarCrop.detail
                  ? _fullCharacterCropId
                  : null,
              manifest: crop == KeepersAvatarCrop.detail
                  ? _fullCharacterManifest
                  : null,
              fallback: _fallback(),
            ),
          ),
        ),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: artwork);
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(child: artwork),
    );
  }

  Widget _fallback() => SizedBox.square(
    dimension: size,
    child: const Center(
      child: Icon(Icons.person_outline, color: KeepersColors.inkMuted),
    ),
  );
}

final class _SafeHumationAvatar extends HumationAvatar {
  const _SafeHumationAvatar({
    required super.seed,
    required super.selections,
    required super.colors,
    required super.size,
    super.crop,
    super.manifest,
    required this.fallback,
  });

  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    try {
      KeepersAvatar.debugBeforeHumationBuild?.call();
      return super.build(context);
    } catch (_) {
      return fallback;
    }
  }
}

final class KeepersAvatarSurface extends StatelessWidget {
  const KeepersAvatarSurface({
    super.key,
    required this.size,
    required this.accent,
    required this.child,
    this.padding = 6,
  });

  final double size;
  final Color accent;
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ClipOval(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            accent.withValues(alpha: .1),
            KeepersColors.auraIvory,
          ),
          border: Border.all(
            color: Color.alphaBlend(
              accent.withValues(alpha: .18),
              KeepersColors.homeLine,
            ),
            width: 1.1,
          ),
          shape: BoxShape.circle,
        ),
        child: Padding(padding: EdgeInsets.all(padding), child: child),
      ),
    ),
  );
}
