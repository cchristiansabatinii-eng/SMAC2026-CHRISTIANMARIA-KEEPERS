import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:keepers/design_system/observatory/motion_policy.dart';
import 'package:keepers/theme/keepers_theme.dart';

final class WeeklyPhotoProgress extends StatelessWidget {
  const WeeklyPhotoProgress({
    required this.weeklyPhotoCount,
    required this.requiredWeeklyPhotos,
    super.key,
  });

  final int weeklyPhotoCount;
  final int requiredWeeklyPhotos;

  @override
  Widget build(BuildContext context) {
    final photoGoal = math.max(1, requiredWeeklyPhotos);
    final displayedPhotoCount = weeklyPhotoCount.clamp(0, photoGoal);
    final missingPhotos = math.max(0, photoGoal - weeklyPhotoCount);
    final status = _statusCopy(missingPhotos: missingPhotos);

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
                    boxShadow: index < displayedPhotoCount
                        ? KeepersEffects.progressGlow(
                            _progressColors[index % _progressColors.length],
                          )
                        : null,
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
    required this.weeklyPhotoCount,
    required this.requiredWeeklyPhotos,
    required this.onEnterWaitingRoom,
    super.key,
  });

  final int weeklyPhotoCount;
  final int requiredWeeklyPhotos;
  final VoidCallback? onEnterWaitingRoom;

  bool get _ready => weeklyPhotoCount >= requiredWeeklyPhotos;

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    final canEnter = ready && onEnterWaitingRoom != null;
    final panelLabel = canEnter
        ? 'Enter weekly waiting room'
        : ready
        ? 'Weekly waiting room unavailable'
        : 'Weekly experience locked';
    final borderColor = canEnter
        ? KeepersColors.homeGold
        : KeepersColors.homeActionLine;

    return Column(
      key: const ValueKey('weekly-recap-mode'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: panelLabel,
          child: AnimatedContainer(
            key: const ValueKey('weekly-recap-glow'),
            duration: keepersReduceMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: canEnter
                  ? [
                      BoxShadow(
                        color: KeepersColors.homeGold.withValues(alpha: .22),
                        blurRadius: 26,
                        spreadRadius: 3,
                      ),
                    ]
                  : const [],
            ),
            child: SizedBox(
              height: 104,
              child: OutlinedButton(
                key: const ValueKey('weekly-recap-open'),
                onPressed: canEnter ? onEnterWaitingRoom : null,
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
                        color: canEnter
                            ? KeepersColors.homeGold.withValues(alpha: .72)
                            : KeepersColors.homeActionLine.withValues(
                                alpha: .82,
                              ),
                      ),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: SizedBox.expand(
                      child: Center(child: WeeklyKeyMedallion(ready: canEnter)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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

String _statusCopy({required int missingPhotos}) => switch (missingPhotos) {
  0 => 'Ready to gather',
  1 => '1 photo needed',
  _ => '$missingPhotos photos needed',
};

final class WeeklyKeyMedallion extends StatelessWidget {
  const WeeklyKeyMedallion({required this.ready, this.size = 64, super.key});

  final bool ready;
  final double size;

  @override
  Widget build(BuildContext context) {
    final frameColor = ready
        ? KeepersColors.homeGold
        : KeepersColors.homeActionLine;
    final iconColor = ready
        ? KeepersColors.homeGoldText
        : KeepersColors.homeTaupe;
    final reduceMotion = keepersReduceMotion(context);
    return AnimatedContainer(
      width: size,
      height: size,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      padding: EdgeInsets.all(size * 6 / 64),
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
            size: size * 25 / 64,
          ),
        ),
      ),
    );
  }
}
