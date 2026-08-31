import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:keepers/design_system/observatory/motion_policy.dart';
import 'package:keepers/features/ceremony/presentation/pastel_flood.dart';
import 'package:keepers/features/ceremony/presentation/weekly_experience_card.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/theme/keepers_theme.dart';

const weeklyWaitingRoomRevealDuration = Duration(milliseconds: 560);

typedef WeeklyStartRequest = bool Function();

@immutable
final class WeeklyWaitingRoomMember {
  const WeeklyWaitingRoomMember({
    required this.id,
    required this.name,
    required this.color,
    required this.avatar,
    required this.isPresent,
    required this.isCurrentMember,
  });

  final String id;
  final String name;
  final Color color;
  final AvatarConfig avatar;
  final bool isPresent;
  final bool isCurrentMember;
}

/// A fail-closed, presentation-safe view of weekly family attendance.
///
/// Only IDs in the active roster can count. Duplicate roster, presence, and
/// current-member signals collapse to one member before quorum is evaluated.
@immutable
final class WeeklyWaitingRoomAttendance {
  const WeeklyWaitingRoomAttendance._({
    required this.totalMemberCount,
    required this.presentMemberCount,
    required this.requiredMemberCount,
    required this.presentMemberIds,
  });

  factory WeeklyWaitingRoomAttendance.fromMemberIds({
    required Iterable<String> rosterMemberIds,
    required Iterable<String> presentMemberIds,
    String? currentMemberId,
  }) {
    final roster = _normalizedIds(rosterMemberIds);
    final observedPresent = _normalizedIds(presentMemberIds)
        .intersection(roster);
    final current = currentMemberId?.trim();
    if (current != null && current.isNotEmpty && roster.contains(current)) {
      observedPresent.add(current);
    }
    final requiredCount = requiredWeeklyFamilyPresence(roster.length);

    return WeeklyWaitingRoomAttendance._(
      totalMemberCount: roster.length,
      presentMemberCount: observedPresent.length,
      requiredMemberCount: requiredCount,
      presentMemberIds: Set<String>.unmodifiable(observedPresent),
    );
  }

  final int totalMemberCount;
  final int presentMemberCount;
  final int requiredMemberCount;
  final Set<String> presentMemberIds;

  int get membersStillNeeded =>
      math.max(0, requiredMemberCount - presentMemberCount);

  bool get canStart =>
      totalMemberCount > 0 && presentMemberCount >= requiredMemberCount;
}

final class WeeklyWaitingRoomScreen extends StatefulWidget {
  const WeeklyWaitingRoomScreen({
    required this.familyName,
    required this.members,
    required this.weeklyProgressComplete,
    required this.onClose,
    required this.onStart,
    this.onNudgeMissingMembers,
    this.nudgeInProgress = false,
    this.rosterRefreshInProgress = false,
    super.key,
  });

  final String familyName;
  final List<WeeklyWaitingRoomMember> members;
  final bool weeklyProgressComplete;
  final VoidCallback onClose;
  final WeeklyStartRequest onStart;
  final VoidCallback? onNudgeMissingMembers;
  final bool nudgeInProgress;
  final bool rosterRefreshInProgress;

  @override
  State<WeeklyWaitingRoomScreen> createState() =>
      _WeeklyWaitingRoomScreenState();
}

final class _WeeklyWaitingRoomScreenState extends State<WeeklyWaitingRoomScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController;
  var _starting = false;
  var _startDispatched = false;
  var _showFlood = false;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: weeklyWaitingRoomRevealDuration,
    );
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  void _closeRoom() {
    if (_starting) {
      _revealController.stop(canceled: false);
      setState(() {
        _starting = false;
        _showFlood = false;
        _revealController.value = 0;
      });
    }
    widget.onClose();
  }

  Future<void> _beginStart() async {
    if (_starting ||
        _startDispatched ||
        !widget.weeklyProgressComplete ||
        widget.rosterRefreshInProgress ||
        !_attendanceFor(widget.members).canStart) {
      return;
    }
    final reduceMotion = keepersReduceMotion(context);
    setState(() {
      _starting = true;
      _showFlood = !reduceMotion;
    });

    if (!reduceMotion) {
      await _revealController.forward(from: 0);
      if (!mounted || !_starting) return;
      if (!widget.weeklyProgressComplete ||
          widget.rosterRefreshInProgress ||
          !_attendanceFor(widget.members).canStart) {
        setState(() {
          _starting = false;
          _showFlood = false;
          _revealController.value = 0;
        });
        return;
      }
    }

    try {
      final accepted = widget.onStart();
      if (mounted) {
        setState(() {
          _starting = false;
          _startDispatched = accepted;
          _showFlood = false;
          _revealController.value = 0;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _starting = false;
          _showFlood = false;
          _revealController.value = 0;
        });
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = _normalizedMembers(widget.members);
    final attendance = _attendanceFor(members);
    final status = !widget.weeklyProgressComplete
        ? 'Weekly progress changed. Return to the Wheel to finish five photos.'
        : widget.rosterRefreshInProgress
        ? 'Checking the latest family list…'
        : _attendanceStatus(attendance);

    return Semantics(
      key: const ValueKey('weekly-waiting-room-route-semantics'),
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      namesRoute: true,
      label: 'Weekly waiting room — Keepers',
      child: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _closeRoom();
        },
        child: Scaffold(
          key: const ValueKey('weekly-waiting-room'),
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding = constraints.maxWidth < 360
                        ? 16.0
                        : 24.0;
                    final minimumHeight = math.max(
                      0.0,
                      constraints.maxHeight - 48,
                    );
                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        12,
                        horizontalPadding,
                        36,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: 560,
                            minHeight: minimumHeight,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _WaitingRoomHeader(
                                familyName: widget.familyName,
                                onClose: _closeRoom,
                              ),
                              const SizedBox(height: 28),
                              Semantics(
                                image: true,
                                label: 'Weekly experience unlocked',
                                child: const ExcludeSemantics(
                                  child: Center(
                                    child: WeeklyKeyMedallion(
                                      ready: true,
                                      size: 96,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Semantics(
                                key: const ValueKey(
                                  'weekly-waiting-room-attendance',
                                ),
                                label: 'Family attendance',
                                value:
                                    '${_attendanceCount(attendance)}. $status.',
                                liveRegion: true,
                                child: ExcludeSemantics(
                                  child: Column(
                                    children: [
                                      KeepersText(
                                        _attendanceCount(attendance),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: KeepersColors.homeInk,
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          height: 1.15,
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      KeepersText(
                                        status,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: KeepersColors.homeInk,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const _PresenceInstruction(),
                              const SizedBox(height: 26),
                              _MemberGrid(
                                members: members,
                                presentMemberIds: attendance.presentMemberIds,
                              ),
                              const SizedBox(height: 28),
                              _ActionRegion(
                                attendance: attendance,
                                weeklyProgressComplete:
                                    widget.weeklyProgressComplete,
                                starting: _starting,
                                startDispatched: _startDispatched,
                                rosterRefreshInProgress:
                                    widget.rosterRefreshInProgress,
                                onStart: _beginStart,
                                onNudgeMissingMembers:
                                    widget.onNudgeMissingMembers,
                                nudgeInProgress: widget.nudgeInProgress,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_showFlood)
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _revealController,
                        builder: (context, _) => CustomPaint(
                          key: const ValueKey(
                            'weekly-waiting-room-pastel-flood',
                          ),
                          painter: PastelFloodPainter(
                            progress: _revealController.value,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _PresenceInstruction extends StatelessWidget {
  const _PresenceInstruction();

  @override
  Widget build(BuildContext context) => Semantics(
    key: ValueKey('weekly-waiting-room-presence-instruction'),
    label: 'Keep this room open and Bluetooth on to stay present.',
    child: const ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_rounded, size: 18, color: KeepersColors.homeInk),
          SizedBox(width: 8),
          Flexible(
            child: KeepersText(
              'Keep this room open and Bluetooth on.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: KeepersColors.homeInk,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _WaitingRoomHeader extends StatelessWidget {
  const _WaitingRoomHeader({required this.familyName, required this.onClose});

  final String familyName;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      IconButton(
        onPressed: onClose,
        tooltip: 'Close waiting room',
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        icon: const Icon(Icons.close_rounded),
        color: KeepersColors.homeInk,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const KeepersText(
                'Weekly experience',
                style: KeepersType.heading,
              ),
              const SizedBox(height: 5),
              KeepersText(
                familyName.trim().isEmpty ? 'Your family' : familyName.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KeepersColors.homeInk,
                  fontSize: 13,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

final class _MemberGrid extends StatelessWidget {
  const _MemberGrid({required this.members, required this.presentMemberIds});

  final List<WeeklyWaitingRoomMember> members;
  final Set<String> presentMemberIds;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: KeepersColors.auraIvory,
          border: Border.all(color: KeepersColors.homeLine),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const KeepersText(
          'Family roster unavailable. Try again before starting.',
          textAlign: TextAlign.center,
          style: TextStyle(color: KeepersColors.homeInk, height: 1.35),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 480
            ? 3
            : constraints.maxWidth >= 300
            ? 2
            : 1;
        const gap = 12.0;
        final cardWidth =
            (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final member in members)
              SizedBox(
                width: cardWidth,
                child: _MemberCard(
                  member: member,
                  isPresent: presentMemberIds.contains(member.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

final class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.isPresent});

  final WeeklyWaitingRoomMember member;
  final bool isPresent;

  @override
  Widget build(BuildContext context) {
    final status = isPresent ? 'Here' : 'Waiting';
    final displayName = member.name.trim().isEmpty
        ? 'Family member'
        : member.name.trim();
    final semanticsName = member.isCurrentMember
        ? '$displayName, you'
        : displayName;
    return Semantics(
      key: ValueKey('weekly-waiting-room-member-${member.id}'),
      label: '$semanticsName. $status',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            color: KeepersColors.auraIvory,
            border: Border.all(
              color: isPresent
                  ? member.color.withValues(alpha: .7)
                  : KeepersColors.homeLine,
              width: isPresent ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              KeepersAvatarSurface(
                size: 80,
                accent: member.color,
                child: KeepersAvatar(config: member.avatar, size: 68),
              ),
              const SizedBox(height: 10),
              KeepersText(
                displayName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KeepersColors.homeInk,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPresent
                        ? Icons.check_circle_rounded
                        : Icons.schedule_rounded,
                    size: 16,
                    color: isPresent ? member.color : KeepersColors.homeInk,
                  ),
                  const SizedBox(width: 5),
                  KeepersText(
                    status,
                    style: const TextStyle(
                      color: KeepersColors.homeInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ActionRegion extends StatelessWidget {
  const _ActionRegion({
    required this.attendance,
    required this.weeklyProgressComplete,
    required this.starting,
    required this.startDispatched,
    required this.rosterRefreshInProgress,
    required this.onStart,
    required this.onNudgeMissingMembers,
    required this.nudgeInProgress,
  });

  final WeeklyWaitingRoomAttendance attendance;
  final bool weeklyProgressComplete;
  final bool starting;
  final bool startDispatched;
  final bool rosterRefreshInProgress;
  final VoidCallback onStart;
  final VoidCallback? onNudgeMissingMembers;
  final bool nudgeInProgress;

  @override
  Widget build(BuildContext context) {
    const buttonStyle = TextStyle(
      fontFamily: KeepersType.primary,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final buttonTextWidth = math.max(1.0, constraints.maxWidth - 60);
        final nudgeLabel = nudgeInProgress
            ? 'Opening share…'
            : 'Ask family to join';
        final nudgeHeight = math.max(
          52.0,
          _measuredTextHeight(
                nudgeLabel,
                buttonStyle,
                buttonTextWidth,
                textScaler,
                Directionality.of(context),
              ) +
              20,
        );
        final startHeight = math.max(
          56.0,
          _measuredTextHeight(
                starting ? 'Starting…' : 'Start weekly experience',
                buttonStyle,
                buttonTextWidth,
                textScaler,
                Directionality.of(context),
              ) +
              20,
        );
        final dispatchedHeight = _measuredTextHeight(
          'Starting weekly experience…',
          buttonStyle,
          constraints.maxWidth,
          textScaler,
          Directionality.of(context),
        );
        final reservedHeight = math.max(
          nudgeHeight,
          math.max(startHeight, dispatchedHeight),
        );

        return ConstrainedBox(
          key: const ValueKey('weekly-waiting-room-actions'),
          constraints: BoxConstraints(minHeight: reservedHeight),
          child: !weeklyProgressComplete
              ? const SizedBox.shrink()
              : rosterRefreshInProgress
              ? Center(
                  child: Semantics(
                    label: 'Refreshing family list',
                    liveRegion: true,
                    child: const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: KeepersColors.homeInk,
                      ),
                    ),
                  ),
                )
              : !attendance.canStart
              ? SizedBox(
                  width: double.infinity,
                  height: nudgeHeight,
                  child: onNudgeMissingMembers == null && !nudgeInProgress
                      ? null
                      : OutlinedButton.icon(
                          onPressed: nudgeInProgress
                              ? null
                              : onNudgeMissingMembers,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            textStyle: buttonStyle,
                            foregroundColor: KeepersColors.homeInk,
                            disabledForegroundColor: KeepersColors.homeInk,
                            side: const BorderSide(
                              color: KeepersColors.homeActionLine,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          icon: nudgeInProgress
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: KeepersColors.homeInk,
                                  ),
                                )
                              : const Icon(Icons.group_add_outlined, size: 19),
                          label: KeepersText(nudgeLabel),
                        ),
                )
              : startDispatched
              ? Semantics(
                  liveRegion: true,
                  label: 'Weekly experience starting',
                  excludeSemantics: true,
                  child: const KeepersText(
                    'Starting weekly experience…',
                    textAlign: TextAlign.center,
                    style: buttonStyle,
                  ),
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: double.infinity,
                    height: startHeight,
                    child: FilledButton.icon(
                      key: const ValueKey('weekly-waiting-room-start'),
                      onPressed: starting ? null : onStart,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        textStyle: buttonStyle,
                        backgroundColor: KeepersColors.homeInk,
                        foregroundColor: KeepersColors.auraIvory,
                        disabledBackgroundColor: KeepersColors.homeInk,
                        disabledForegroundColor: KeepersColors.auraIvory,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.key_rounded, size: 20),
                      label: KeepersText(
                        starting ? 'Starting…' : 'Start weekly experience',
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

double _measuredTextHeight(
  String text,
  TextStyle style,
  double maxWidth,
  TextScaler textScaler,
  TextDirection textDirection,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  return painter.height;
}

WeeklyWaitingRoomAttendance _attendanceFor(
  List<WeeklyWaitingRoomMember> members,
) {
  final normalized = _normalizedMembers(members);
  final currentIds = normalized
      .where((member) => member.isCurrentMember)
      .map((member) => member.id)
      .toSet();
  return WeeklyWaitingRoomAttendance.fromMemberIds(
    rosterMemberIds: normalized.map((member) => member.id),
    presentMemberIds: normalized
        .where((member) => member.isPresent)
        .map((member) => member.id),
    currentMemberId: currentIds.length == 1 ? currentIds.single : null,
  );
}

List<WeeklyWaitingRoomMember> _normalizedMembers(
  Iterable<WeeklyWaitingRoomMember> members,
) {
  final byId = <String, WeeklyWaitingRoomMember>{};
  for (final member in members) {
    final id = member.id.trim();
    if (id.isEmpty) continue;
    final existing = byId[id];
    if (existing == null) {
      byId[id] = WeeklyWaitingRoomMember(
        id: id,
        name: member.name,
        color: member.color,
        avatar: member.avatar,
        isPresent: member.isPresent,
        isCurrentMember: member.isCurrentMember,
      );
      continue;
    }
    byId[id] = WeeklyWaitingRoomMember(
      id: id,
      name: existing.name,
      color: existing.color,
      avatar: existing.avatar,
      isPresent: existing.isPresent || member.isPresent,
      isCurrentMember: existing.isCurrentMember || member.isCurrentMember,
    );
  }
  return List<WeeklyWaitingRoomMember>.unmodifiable(byId.values);
}

Set<String> _normalizedIds(Iterable<String> ids) => {
  for (final id in ids)
    if (id.trim().isNotEmpty) id.trim(),
};

String _attendanceCount(WeeklyWaitingRoomAttendance attendance) {
  final memberNoun = attendance.totalMemberCount == 1
      ? 'family member is'
      : 'family members are';
  return '${attendance.presentMemberCount} of '
      '${attendance.totalMemberCount} $memberNoun here';
}

String _attendanceStatus(WeeklyWaitingRoomAttendance attendance) {
  if (attendance.totalMemberCount == 0) {
    return 'Waiting for a verified family roster';
  }
  if (attendance.canStart) return 'Enough family is here to begin';
  return switch (attendance.membersStillNeeded) {
    1 => '1 more family member needs to join',
    final count => '$count more family members need to join',
  };
}
