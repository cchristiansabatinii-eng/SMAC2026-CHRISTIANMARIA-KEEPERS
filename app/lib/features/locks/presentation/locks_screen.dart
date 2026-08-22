import 'dart:async';

import 'package:flutter/material.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';
import 'package:keepers/ui/keepers_destination_scaffold.dart';

final class LocksScreen extends StatelessWidget {
  const LocksScreen({
    required this.familyName,
    required this.onDestinationSelected,
    required this.onOpenMemorialPreview,
    this.onCapture,
    super.key,
  });

  final String familyName;
  final ValueChanged<KeepersNavDestination> onDestinationSelected;
  final VoidCallback onOpenMemorialPreview;
  final VoidCallback? onCapture;

  @override
  Widget build(BuildContext context) => KeepersDestinationScaffold(
    destination: KeepersNavDestination.ceremony,
    kicker: 'Milestones & legacy',
    title: 'Legacy Locks',
    subtitle: '$familyName · sealed with family approval',
    onDestinationSelected: onDestinationSelected,
    onCapture: onCapture,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
      children: [
        const _PreviewNotice(),
        const SizedBox(height: 18),
        const _LegacyApprovalCard(),
        const SizedBox(height: 26),
        KeepersText(
          'Memorial pages',
          style: KeepersType.heading.copyWith(color: KeepersColors.ink),
        ),
        const SizedBox(height: 10),
        Material(
          color: const Color(0xFFF1E4C4).withValues(alpha: .82),
          borderRadius: BorderRadius.circular(26),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpenMemorialPreview,
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    Icons.local_florist_outlined,
                    color: KeepersColors.memorialGold,
                    size: 36,
                  ),
                  SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KeepersText(
                          'Preview the memorial layout',
                          style: TextStyle(
                            color: KeepersColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 5),
                        KeepersText(
                          'Gold, complete, and ordered across a whole life.',
                          style: TextStyle(
                            color: KeepersColors.inkMuted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: KeepersColors.inkMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        KeepersText(
          'Sealed shelf',
          style: KeepersType.heading.copyWith(color: KeepersColors.ink),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: KeepersColors.auraIvory.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: KeepersColors.ink.withValues(alpha: .1)),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.shelves,
                color: KeepersColors.inkMuted,
                size: 40,
              ),
              const SizedBox(height: 12),
              KeepersText(
                'No real Legacy Locks yet',
                textAlign: TextAlign.center,
                style: KeepersType.heading.copyWith(color: KeepersColors.ink),
              ),
              const SizedBox(height: 5),
              const KeepersText(
                'Approved milestone memories will appear here as sealed brass cards.',
                textAlign: TextAlign.center,
                style: TextStyle(color: KeepersColors.inkMuted, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: KeepersColors.ink,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: KeepersColors.brass,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const KeepersText(
            'PREVIEW',
            style: TextStyle(
              color: KeepersColors.ground,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: KeepersText(
            'Practice the approval gesture. Nothing is saved or shared.',
            style: TextStyle(
              color: KeepersColors.cream.withValues(alpha: .76),
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );
}

final class _LegacyApprovalCard extends StatefulWidget {
  const _LegacyApprovalCard();

  @override
  State<_LegacyApprovalCard> createState() => _LegacyApprovalCardState();
}

final class _LegacyApprovalCardState extends State<_LegacyApprovalCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  bool _approved = false;
  int? _pointer;
  Timer? _approvalTimer;

  void _start(PointerDownEvent event) {
    if (_approved || _pointer != null) return;
    _pointer = event.pointer;
    _hold.forward(from: 0);
    _approvalTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _pointer == null) return;
      _hold.value = 1;
      setState(() => _approved = true);
    });
  }

  void _stop(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _approvalTimer?.cancel();
    _approvalTimer = null;
    if (!_approved) _hold.reverse();
  }

  @override
  void dispose() {
    _approvalTimer?.cancel();
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: const Color(0xFF1A1712),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: KeepersColors.brass.withValues(alpha: .7)),
      boxShadow: [
        BoxShadow(
          color: KeepersColors.brass.withValues(alpha: .12),
          blurRadius: 36,
        ),
      ],
    ),
    child: Column(
      children: [
        const Icon(
          Icons.lock_clock_outlined,
          color: KeepersColors.brassLight,
          size: 42,
        ),
        const SizedBox(height: 13),
        KeepersText(
          'A future milestone',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: KeepersColors.cream,
            fontFamily: KeepersType.primary,
          ),
        ),
        const SizedBox(height: 6),
        KeepersText(
          'Family approval is deliberate. A tap can never approve a Legacy Lock.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: KeepersColors.cream.withValues(alpha: .64),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        Semantics(
          button: true,
          label: _approved
              ? 'Approved for preview'
              : 'Hold 2 seconds to approve preview',
          hint: 'Press and keep holding until the ring completes',
          child: Listener(
            key: const ValueKey('legacy-approval-hold'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: _start,
            onPointerUp: _stop,
            onPointerCancel: _stop,
            child: AnimatedBuilder(
              animation: _hold,
              builder: (context, _) => SizedBox(
                width: 148,
                height: 148,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: _approved ? 1 : _hold.value,
                      strokeWidth: 5,
                      backgroundColor: KeepersColors.cream.withValues(
                        alpha: .12,
                      ),
                      color: KeepersColors.brassLight,
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _approved
                                ? Icons.check_rounded
                                : Icons.touch_app_outlined,
                            color: KeepersColors.brassLight,
                            size: 34,
                          ),
                          const SizedBox(height: 8),
                          KeepersText(
                            _approved
                                ? 'Approved for preview'
                                : 'Hold 2 seconds\nto approve',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: KeepersColors.cream,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
