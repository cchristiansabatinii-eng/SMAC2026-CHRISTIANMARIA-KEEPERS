import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:keepers/design_system/observatory/motion_policy.dart';
import 'package:keepers/theme/keepers_theme.dart';

final class WeeklyPhotoProgress extends StatelessWidget {
  const WeeklyPhotoProgress({
    required this.weeklyPhotoCount,
    required this.requiredWeeklyPhotos,
    required this.presentMemberCount,
    required this.requiredPresentMembers,
    super.key,
  });

  final int weeklyPhotoCount;
  final int requiredWeeklyPhotos;
  final int presentMemberCount;
  final int requiredPresentMembers;

  @override
  Widget build(BuildContext context) {
    final photoGoal = math.max(1, requiredWeeklyPhotos);
    final displayedPhotoCount = weeklyPhotoCount.clamp(0, photoGoal);
    final missingPhotos = math.max(0, photoGoal - weeklyPhotoCount);
    final missingMembers = math.max(
      0,
      requiredPresentMembers - presentMemberCount,
    );
    final status = _statusCopy(
      missingPhotos: missingPhotos,
      missingMembers: missingMembers,
    );

    return Semantics(
      key: const ValueKey('weekly-photo-progress'),
      label: 'Weekly photo progress',
      value: '$displayedPhotoCount of $photoGoal photos. $status',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var index = 0; index < photoGoal; index++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: keepersReduceMotion(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  curve: Curves.easeInOut,
                  height: 6,
                  decoration: BoxDecoration(
                    color: index < displayedPhotoCount
                        ? _progressColors[index % _progressColors.length]
                        : KeepersColors.auraIvory,
                    border: Border.all(
                      color: index < displayedPhotoCount
                          ? _progressColors[index % _progressColors.length]
                          : KeepersColors.homeLine,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              if (index < photoGoal - 1) const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }
}

final class WeeklyExperienceCard extends StatelessWidget {
  const WeeklyExperienceCard({
    required this.presentMemberCount,
    required this.requiredPresentMembers,
    required this.weeklyPhotoCount,
    required this.requiredWeeklyPhotos,
    required this.onOpen,
    this.onPreview,
    super.key,
  });

  final int presentMemberCount;
  final int requiredPresentMembers;
  final int weeklyPhotoCount;
  final int requiredWeeklyPhotos;
  final VoidCallback? onOpen;
  final VoidCallback? onPreview;

  bool get _ready =>
      weeklyPhotoCount >= requiredWeeklyPhotos &&
      presentMemberCount >= requiredPresentMembers;

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    final canOpen = ready && onOpen != null;
    final panelLabel = canOpen
        ? 'Open weekly experience'
        : ready
        ? 'Weekly experience unavailable'
        : 'Weekly experience locked';
    final borderColor = canOpen
        ? KeepersColors.homeGold.withValues(alpha: .82)
        : KeepersColors.homeActionLine;

    return Column(
      key: const ValueKey('weekly-recap-mode'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: panelLabel,
          child: SizedBox(
            height: 104,
            child: OutlinedButton(
              key: const ValueKey('weekly-recap-open'),
              onPressed: canOpen ? onOpen : null,
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
                backgroundColor: const WidgetStatePropertyAll(
                  KeepersColors.auraIvory,
                ),
                foregroundColor: WidgetStatePropertyAll(borderColor),
                overlayColor: WidgetStatePropertyAll(
                  KeepersColors.homeGold.withValues(alpha: .08),
                ),
                side: WidgetStateProperty.resolveWith(
                  (states) => BorderSide(
                    color: states.contains(WidgetState.focused)
                        ? KeepersColors.homeInk
                        : borderColor,
                    width: states.contains(WidgetState.focused) ? 1.75 : 1.25,
                  ),
                ),
                shape: const WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(30)),
                  ),
                ),
              ),
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: canOpen
                          ? KeepersColors.homeGold.withValues(alpha: .34)
                          : KeepersColors.homeActionLine.withValues(alpha: .82),
                    ),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: SizedBox.expand(
                    child: Center(child: _KeyMedallion(ready: canOpen)),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (onPreview case final preview?) ...[
          const SizedBox(height: 2),
          TextButton.icon(
            key: const ValueKey('weekly-recap-preview'),
            onPressed: preview,
            icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
            label: const KeepersText('Preview weekly experience'),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: KeepersColors.homeInk,
            ),
          ),
        ],
      ],
    );
  }
}

const _progressColors = <Color>[
  KeepersColors.homeGold,
  KeepersColors.homeClay,
  KeepersColors.homeGreen,
  KeepersColors.homeBlue,
  KeepersColors.homeMauve,
];

int requiredWeeklyFamilyPresence(int familySize) {
  final normalizedFamilySize = math.max(1, familySize);
  return (normalizedFamilySize * 3 + 3) ~/ 4;
}

String _statusCopy({required int missingPhotos, required int missingMembers}) {
  final photoCopy = switch (missingPhotos) {
    0 => null,
    1 => '1 photo',
    _ => '$missingPhotos photos',
  };
  final presenceCopy = switch (missingMembers) {
    0 => null,
    1 => '1 more family member needs to be present',
    _ => '$missingMembers more family members need to be present',
  };
  return switch ((photoCopy, presenceCopy)) {
    (null, null) => 'Ready to open together',
    (final photos?, null) => '$photos needed',
    (null, final presence?) => presence,
    (final photos?, final presence?) => '$photos needed. $presence',
  };
}

final class _KeyMedallion extends StatelessWidget {
  const _KeyMedallion({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final frameColor = ready
        ? KeepersColors.homeGold
        : KeepersColors.homeActionLine;
    final iconColor = ready ? KeepersColors.homeGold : KeepersColors.homeTaupe;
    final reduceMotion = keepersReduceMotion(context);
    return AnimatedContainer(
      width: 64,
      height: 64,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: frameColor, width: 1.75),
        boxShadow: ready
            ? [
                BoxShadow(
                  color: KeepersColors.homeGold.withValues(alpha: .3),
                  blurRadius: 18,
                  spreadRadius: 3,
                ),
              ]
            : const [],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: frameColor.withValues(alpha: ready ? .48 : .82),
          ),
        ),
        child: Center(
          child: Icon(
            ready ? Icons.key_rounded : Icons.lock_outline_rounded,
            color: iconColor,
            size: 25,
          ),
        ),
      ),
    );
  }
}
