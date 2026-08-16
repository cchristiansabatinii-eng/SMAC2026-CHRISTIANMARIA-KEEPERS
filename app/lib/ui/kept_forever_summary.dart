import 'package:flutter/material.dart';
import 'package:keepers/theme/keepers_theme.dart';

/// The archive's durable total, independent of the active person/theme filter.
final class KeptForeverSummary extends StatelessWidget {
  const KeptForeverSummary({required this.count, super.key});

  final int count;

  static const _formats = <(IconData, Color)>[
    (Icons.image_outlined, KeepersColors.homeClay),
    (Icons.graphic_eq_rounded, KeepersColors.homeGreen),
    (Icons.notes_rounded, KeepersColors.homeBlue),
    (Icons.format_align_left_rounded, KeepersColors.homeMauve),
    (Icons.multitrack_audio_rounded, KeepersColors.homeGold),
  ];

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: count == 1
        ? '1 memory kept forever'
        : '$count memories kept forever',
    child: ExcludeSemantics(
      child: Container(
        key: const ValueKey('kept-forever-summary'),
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: KeepersColors.auraIvory.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: KeepersColors.homeLine.withValues(alpha: .62),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: KeepersText(
                      'Kept forever',
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: KeepersColors.homeTaupe,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  KeepersText(
                    '$count',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: KeepersColors.homeInk,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < _formats.length; index++) ...[
                      _KeptFormatTile(
                        key: ValueKey('kept-format-tile-$index'),
                        icon: _formats[index].$1,
                        accent: _formats[index].$2,
                      ),
                      if (index != _formats.length - 1)
                        const SizedBox(width: 4),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _KeptFormatTile extends StatelessWidget {
  const _KeptFormatTile({super.key, required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 36,
    decoration: BoxDecoration(
      color: Color.alphaBlend(
        accent.withValues(alpha: .08),
        KeepersColors.auraIvory,
      ),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: accent.withValues(alpha: .32)),
    ),
    alignment: Alignment.center,
    child: Icon(icon, color: accent, size: 22),
  );
}
