import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';

const keepersEnabledDestinations = <KeepersNavDestination>{
  KeepersNavDestination.wheel,
  KeepersNavDestination.ceremony,
  KeepersNavDestination.archive,
  KeepersNavDestination.settings,
};

final class KeepersDestinationScaffold extends StatefulWidget {
  const KeepersDestinationScaffold({
    required this.destination,
    required this.kicker,
    required this.title,
    required this.child,
    required this.onDestinationSelected,
    this.onCapture,
    this.subtitle,
    this.trailing,
    this.compactHeader = false,
    super.key,
  });

  final KeepersNavDestination destination;
  final String kicker;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final bool compactHeader;
  final ValueChanged<KeepersNavDestination> onDestinationSelected;
  final VoidCallback? onCapture;

  @override
  State<KeepersDestinationScaffold> createState() =>
      _KeepersDestinationScaffoldState();
}

final class _KeepersDestinationScaffoldState
    extends State<KeepersDestinationScaffold> {
  @override
  Widget build(BuildContext context) {
    const foreground = KeepersColors.ink;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: widget.compactHeader
                          ? const EdgeInsets.fromLTRB(24, 6, 24, 8)
                          : const EdgeInsets.fromLTRB(24, 18, 24, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                KeepersText(
                                  widget.kicker,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: foreground.withValues(
                                          alpha: .72,
                                        ),
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 2.2,
                                      ),
                                ),
                                const SizedBox(height: 5),
                                KeepersText(
                                  widget.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: KeepersType.heading.copyWith(
                                    color: foreground,
                                  ),
                                ),
                                if (widget.subtitle case final subtitle?) ...[
                                  const SizedBox(height: 5),
                                  KeepersText(
                                    subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: foreground.withValues(
                                            alpha: .68,
                                          ),
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (widget.trailing case final trailing?) ...[
                            const SizedBox(width: 12),
                            trailing,
                          ],
                        ],
                      ),
                    ),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ),
            KeepersBottomNav(
              selected: widget.destination,
              enabledDestinations: keepersEnabledDestinations,
              onCapture: widget.onCapture,
              onSelected: widget.onDestinationSelected,
            ),
          ],
        ),
      ),
    );
  }
}
