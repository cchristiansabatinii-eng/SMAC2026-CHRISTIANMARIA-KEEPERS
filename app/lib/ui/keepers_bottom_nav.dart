import 'package:flutter/material.dart';
import 'package:keepers/theme/keepers_theme.dart';

enum KeepersNavDestination {
  wheel('Wheel', Icons.bubble_chart_outlined),
  ceremony('Memory Key', Icons.key_rounded),
  archive('Archive', Icons.filter_none_rounded),
  settings('Settings', Icons.person_outline_rounded);

  const KeepersNavDestination(this.label, this.icon);

  final String label;
  final IconData icon;
}

final class KeepersBottomNav extends StatelessWidget {
  const KeepersBottomNav({
    required this.selected,
    required this.enabledDestinations,
    this.onCapture,
    this.onSelected,
    super.key,
  });

  final KeepersNavDestination selected;
  final Set<KeepersNavDestination> enabledDestinations;
  final VoidCallback? onCapture;
  final ValueChanged<KeepersNavDestination>? onSelected;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('keepers-bottom-nav'),
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.zero,
      border: Border(
        top: BorderSide(color: KeepersColors.ink.withValues(alpha: .12)),
      ),
    ),
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            for (final destination in const [
              KeepersNavDestination.wheel,
              KeepersNavDestination.ceremony,
            ])
              Expanded(
                child: _DestinationButton(
                  destination: destination,
                  selected: destination == selected,
                  enabled: enabledDestinations.contains(destination),
                  onTap: () => onSelected?.call(destination),
                ),
              ),
            Expanded(
              child: Center(child: _CaptureButton(onTap: onCapture)),
            ),
            for (final destination in const [
              KeepersNavDestination.archive,
              KeepersNavDestination.settings,
            ])
              Expanded(
                child: _DestinationButton(
                  destination: destination,
                  selected: destination == selected,
                  enabled: enabledDestinations.contains(destination),
                  onTap: () => onSelected?.call(destination),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

final class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onTap != null,
    label: 'Keep a memory',
    onTap: onTap,
    child: ExcludeSemantics(
      child: Tooltip(
        message: 'Keep A Memory',
        child: Material(
          key: const ValueKey('keepers-nav-capture'),
          color: KeepersColors.ink,
          shape: CircleBorder(
            side: BorderSide(
              color: KeepersColors.auraBlush.withValues(alpha: .9),
              width: 2,
            ),
          ),
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: InkResponse(
            onTap: onTap,
            customBorder: const CircleBorder(),
            radius: 28,
            child: SizedBox.square(
              dimension: 54,
              child: Icon(
                Icons.add_rounded,
                size: 31,
                color: KeepersColors.auraIvory.withValues(
                  alpha: onTap == null ? .46 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _DestinationButton extends StatelessWidget {
  const _DestinationButton({
    required this.destination,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final KeepersNavDestination destination;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semanticsLabel = selected
        ? '${destination.label}, selected'
        : enabled
        ? destination.label
        : '${destination.label}, unavailable';
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: selected,
      label: semanticsLabel,
      onTap: enabled ? onTap : null,
      child: ExcludeSemantics(
        child: Tooltip(
          message: keepersTitleCase(destination.label),
          child: Material(
            key: ValueKey('keepers-nav-${destination.name}'),
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkResponse(
              onTap: enabled ? onTap : null,
              customBorder: const CircleBorder(),
              radius: 30,
              child: SizedBox.square(
                dimension: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      destination.icon,
                      size: selected ? 29 : 27,
                      color: enabled
                          ? KeepersColors.ink
                          : KeepersColors.ink.withValues(alpha: .28),
                    ),
                    if (selected)
                      Positioned(
                        bottom: 3,
                        child: DecoratedBox(
                          key: ValueKey(
                            'keepers-nav-${destination.name}-indicator',
                          ),
                          decoration: const BoxDecoration(
                            color: KeepersColors.ink,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: 4),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
