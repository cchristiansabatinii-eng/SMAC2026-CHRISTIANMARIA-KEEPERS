import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/family_wheel_screen.dart';

@immutable
final class MemberMemorySummary {
  const MemberMemorySummary({
    required this.id,
    required this.title,
    required this.formatLabel,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String formatLabel;
  final DateTime createdAt;
}

final class MemberPageScreen extends StatefulWidget {
  const MemberPageScreen({
    required this.member,
    this.sealedCount,
    required this.keptMemories,
    required this.onOpenMemory,
    this.showLegacyLock = false,
    super.key,
  });

  final FamilyWheelMember member;
  final int? sealedCount;
  final List<MemberMemorySummary> keptMemories;
  final ValueChanged<MemberMemorySummary> onOpenMemory;
  final bool showLegacyLock;

  @override
  State<MemberPageScreen> createState() => _MemberPageScreenState();
}

final class _MemberPageScreenState extends State<MemberPageScreen> {
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: KeepersColors.auraGround.withValues(alpha: .9),
              surfaceTintColor: Colors.transparent,
              foregroundColor: KeepersColors.ink,
              title: const KeepersText('Member'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 40),
              sliver: SliverList.list(
                children: [
                  _MemberIdentity(member: widget.member),
                  const SizedBox(height: 28),
                  if (widget.sealedCount case final sealedCount?) ...[
                    _SealedWeek(count: sealedCount, color: widget.member.color),
                    const SizedBox(height: 30),
                  ],
                  _KeptHistory(
                    memories: widget.keptMemories,
                    color: widget.member.color,
                    onOpenMemory: widget.onOpenMemory,
                  ),
                  if (widget.showLegacyLock) ...[
                    const SizedBox(height: 28),
                    const _LegacyLockCard(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _MemberIdentity extends StatelessWidget {
  const _MemberIdentity({required this.member});
  final FamilyWheelMember member;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _MemberAvatar(member: member, size: 132),
      const SizedBox(height: 16),
      KeepersText(
        member.name,
        style: KeepersType.heading.copyWith(color: KeepersColors.ink),
      ),
      if (member.contribution case final contribution?) ...[
        const SizedBox(height: 5),
        KeepersText(
          '${(contribution.clamp(0, 1) * 100).round()}% of this week sealed',
          style: const TextStyle(color: KeepersColors.inkMuted),
        ),
      ],
    ],
  );
}

final class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member, required this.size});
  final FamilyWheelMember member;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: member.color, width: 3),
    ),
    child: ClipOval(
      child: ColoredBox(
        color: KeepersColors.auraIvory,
        child: KeepersAvatar(
          config: member.avatar,
          size: size - 14,
          crop: KeepersAvatarCrop.detail,
          semanticLabel: '${member.name} avatar',
        ),
      ),
    ),
  );
}

final class _SealedWeek extends StatelessWidget {
  const _SealedWeek({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: KeepersColors.auraIvory.withValues(alpha: .76),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: KeepersColors.ink.withValues(alpha: .1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: KeepersText(
                '$count sealed this week',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: KeepersColors.ink,
                  fontFamily: KeepersType.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.lock_outline_rounded, color: KeepersColors.ink),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: List.generate(
            math.max(count, 1),
            (index) => Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: count == 0
                    ? Colors.transparent
                    : color.withValues(alpha: .16 + (index % 3) * .08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: count == 0
                      ? KeepersColors.ink.withValues(alpha: .12)
                      : color.withValues(alpha: .48),
                ),
              ),
              child: count == 0
                  ? const Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: KeepersColors.inkMuted,
                    )
                  : const Icon(
                      Icons.lock_rounded,
                      size: 14,
                      color: KeepersColors.ink,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 13),
        const KeepersText(
          'Current-week memories stay closed until ceremony.',
          style: TextStyle(color: KeepersColors.inkMuted, height: 1.4),
        ),
      ],
    ),
  );
}

final class _KeptHistory extends StatelessWidget {
  const _KeptHistory({
    required this.memories,
    required this.color,
    required this.onOpenMemory,
  });

  final List<MemberMemorySummary> memories;
  final Color color;
  final ValueChanged<MemberMemorySummary> onOpenMemory;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      KeepersText(
        'Kept memories',
        style: KeepersType.heading.copyWith(color: KeepersColors.ink),
      ),
      const SizedBox(height: 12),
      if (memories.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: const KeepersText(
            'No memories have been kept for this member yet.',
            style: TextStyle(color: KeepersColors.inkMuted),
          ),
        )
      else
        for (final memory in memories)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: KeepersColors.auraIvory.withValues(alpha: .74),
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onOpenMemory(memory),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: color, width: 4)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            KeepersText(
                              memory.title,
                              style: const TextStyle(
                                color: KeepersColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            KeepersText(
                              '${memory.formatLabel} · ${_memberDate(memory.createdAt)}',
                              style: const TextStyle(
                                color: KeepersColors.inkMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: KeepersColors.inkMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
    ],
  );
}

final class _LegacyLockCard extends StatelessWidget {
  const _LegacyLockCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: KeepersColors.ink,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: KeepersColors.memorialGold),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.lock_outline_rounded,
          color: KeepersColors.brassLight,
          size: 32,
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeepersText(
                'Legacy Lock',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: KeepersColors.cream,
                  fontFamily: KeepersType.primary,
                ),
              ),
              const SizedBox(height: 4),
              KeepersText(
                'Milestone memories remain sealed until their family-approved date.',
                style: TextStyle(
                  color: KeepersColors.cream.withValues(alpha: .68),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

String _memberDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

final class MemorialPageScreen extends StatelessWidget {
  const MemorialPageScreen({
    required this.memberName,
    required this.dateRange,
    required this.memories,
    this.preview = false,
    super.key,
  });

  final String memberName;
  final String dateRange;
  final List<MemberMemorySummary> memories;
  final bool preview;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: KeepersColors.ink,
        toolbarHeight: preview ? 72 : null,
        title: KeepersText(
          preview ? 'Memorial preview' : 'Memorial',
          maxLines: preview ? 2 : 1,
          softWrap: preview,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        children: [
          const Icon(
            Icons.local_florist_outlined,
            size: 46,
            color: KeepersColors.memorialGold,
          ),
          const SizedBox(height: 18),
          KeepersText(
            memberName,
            textAlign: TextAlign.center,
            style: KeepersType.heading.copyWith(color: KeepersColors.ink),
          ),
          const SizedBox(height: 8),
          KeepersText(
            dateRange,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: KeepersColors.inkMuted,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 30),
          if (memories.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              decoration: BoxDecoration(
                color: KeepersColors.auraIvory.withValues(alpha: .72),
                border: Border.all(
                  color: KeepersColors.memorialGold.withValues(alpha: .58),
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.auto_stories_outlined,
                    size: 34,
                    color: KeepersColors.memorialGold,
                  ),
                  const SizedBox(height: 14),
                  KeepersText(
                    'A life story gathers here',
                    textAlign: TextAlign.center,
                    style: KeepersType.heading.copyWith(
                      color: KeepersColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const KeepersText(
                    'Kept memories will appear here in time order.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: KeepersColors.inkMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          for (final memory in memories)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: KeepersColors.auraIvory.withValues(alpha: .8),
                border: Border.all(
                  color: KeepersColors.memorialGold.withValues(alpha: .7),
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KeepersText(
                    memory.title,
                    style: const TextStyle(
                      color: KeepersColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  KeepersText(
                    '${memory.formatLabel} · ${_memberDate(memory.createdAt)}',
                    style: const TextStyle(color: KeepersColors.inkMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
