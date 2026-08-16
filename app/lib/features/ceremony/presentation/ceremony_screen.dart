import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/family_wheel_screen.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';
import 'package:keepers/ui/keepers_destination_scaffold.dart';

enum _CeremonyStage { key, reel, keeping, randomEmpty }

enum _RehearsalFormat { photo, voice, text }

@immutable
final class _RehearsalMemory {
  const _RehearsalMemory({
    required this.author,
    required this.format,
    required this.caption,
    required this.color,
  });

  final String author;
  final _RehearsalFormat format;
  final String caption;
  final Color color;
}

enum LockedMemoryChallengeState { locked, submitted, approved }

@immutable
final class LockedMemoryChallenge {
  const LockedMemoryChallenge({
    required this.id,
    required this.title,
    required this.task,
    required this.assignedBy,
    required this.approvalBy,
    required this.state,
    this.preview = false,
    this.memoryCount = 1,
  });

  final String id;
  final String title;
  final String task;
  final String assignedBy;
  final String approvalBy;
  final LockedMemoryChallengeState state;
  final bool preview;
  final int memoryCount;
}

@immutable
final class MemoryKeyMemory {
  const MemoryKeyMemory({
    required this.id,
    required this.title,
    required this.formatLabel,
  });

  final String id;
  final String title;
  final String formatLabel;
}

@immutable
final class MemoryKeyMember {
  const MemoryKeyMember({
    required this.name,
    this.id,
    this.avatar,
    this.color = KeepersColors.homeClay,
  });

  factory MemoryKeyMember.from(FamilyWheelMember member) => MemoryKeyMember(
    id: member.id,
    name: member.name,
    avatar: member.avatar,
    color: member.color,
  );

  final String? id;
  final String name;
  final AvatarConfig? avatar;
  final Color color;
}

@immutable
final class MemoryKeyCapsule {
  const MemoryKeyCapsule({
    required this.from,
    required this.title,
    required this.openingLabel,
    required this.daysRemaining,
  });

  final String from;
  final String title;
  final String openingLabel;
  final int daysRemaining;
}

final class CeremonyScreen extends StatefulWidget {
  const CeremonyScreen({
    required this.familyName,
    required this.currentMemberName,
    required this.onDestinationSelected,
    this.onCapture,
    this.startInKeeping = false,
    this.weeklyPreviewEnabled = false,
    this.nearbyDeviceCount = 1,
    this.requiredNearbyDevices = 2,
    this.weeklyMemoryCount = 0,
    this.randomMemories = const [],
    this.members = const [],
    this.lockedMemories = const [],
    this.timeCapsule,
    this.onOpenRandomMemory,
    this.onOpenLockedMemory,
    this.onAddMember,
    this.onNudgeMissingMembers,
    super.key,
  });

  final String familyName;
  final String currentMemberName;
  final ValueChanged<KeepersNavDestination> onDestinationSelected;
  final VoidCallback? onCapture;
  final bool startInKeeping;
  final bool weeklyPreviewEnabled;
  final int nearbyDeviceCount;
  final int requiredNearbyDevices;
  final int weeklyMemoryCount;
  final List<MemoryKeyMemory> randomMemories;
  final List<MemoryKeyMember> members;
  final List<LockedMemoryChallenge> lockedMemories;
  final MemoryKeyCapsule? timeCapsule;
  final ValueChanged<MemoryKeyMemory>? onOpenRandomMemory;
  final ValueChanged<LockedMemoryChallenge>? onOpenLockedMemory;
  final VoidCallback? onAddMember;
  final VoidCallback? onNudgeMissingMembers;

  @override
  State<CeremonyScreen> createState() => _CeremonyScreenState();
}

final class _CeremonyScreenState extends State<CeremonyScreen>
    with SingleTickerProviderStateMixin {
  late _CeremonyStage _stage = widget.startInKeeping
      ? _CeremonyStage.keeping
      : _CeremonyStage.key;
  late final PageController _pageController = PageController();
  late final AnimationController _pastelFlood = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  final math.Random _random = math.Random();
  int _memoryIndex = 0;
  int? _lastRandomIndex;
  bool _echoOpen = false;
  bool _flooding = false;

  late final List<_RehearsalMemory> _memories = [
    const _RehearsalMemory(
      author: 'A family member',
      format: _RehearsalFormat.photo,
      caption: 'A small moment, held in the light.',
      color: Color(0xFFE4626F),
    ),
    const _RehearsalMemory(
      author: 'A family member',
      format: _RehearsalFormat.voice,
      caption: 'A voice the room can hear together.',
      color: Color(0xFF3EB8A5),
    ),
    _RehearsalMemory(
      author: widget.currentMemberName,
      format: _RehearsalFormat.text,
      caption: 'What should this family remember from this week?',
      color: const Color(0xFF9B6BD5),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _pastelFlood.dispose();
    super.dispose();
  }

  Future<void> _openWithPastelFlood(VoidCallback open) async {
    if (_flooding) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      open();
      return;
    }
    setState(() => _flooding = true);
    await _pastelFlood.forward(from: 0);
    if (!mounted) return;
    open();
    if (!mounted) return;
    setState(() => _flooding = false);
    _pastelFlood.reset();
  }

  void _openRandomMemory() {
    if (widget.randomMemories.isEmpty) {
      setState(() => _stage = _CeremonyStage.randomEmpty);
      return;
    }
    final length = widget.randomMemories.length;
    var index = _random.nextInt(length);
    if (length > 1 && index == _lastRandomIndex) {
      index = (index + 1) % length;
    }
    _lastRandomIndex = index;
    widget.onOpenRandomMemory?.call(widget.randomMemories[index]);
  }

  void _addMember() => widget.onAddMember?.call();

  void _nudgeMissingMembers() => widget.onNudgeMissingMembers?.call();

  Future<void> _nextMemory() async {
    if (_memoryIndex >= _memories.length - 1) return;
    final next = _memoryIndex + 1;
    setState(() {
      _memoryIndex = next;
      _echoOpen = false;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(next);
    } else {
      await _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _previousMemory() async {
    if (_memoryIndex == 0) return;
    final previous = _memoryIndex - 1;
    setState(() {
      _memoryIndex = previous;
      _echoOpen = false;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(previous);
    } else {
      await _pageController.animateToPage(
        previous,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = KeepersDestinationScaffold(
      destination: KeepersNavDestination.ceremony,
      kicker: _stage == _CeremonyStage.key
          ? 'Open together'
          : _stage == _CeremonyStage.reel
          ? 'Family reel'
          : _stage == _CeremonyStage.keeping
          ? 'The keeping'
          : 'From the vault',
      title: _stage == _CeremonyStage.key
          ? 'Memory Key'
          : _stage == _CeremonyStage.reel
          ? widget.familyName
          : _stage == _CeremonyStage.keeping
          ? 'What stays with us?'
          : 'Random memory',
      subtitle: _stage == _CeremonyStage.keeping
          ? 'Swipe or use the named actions below.'
          : null,
      compactHeader: _stage == _CeremonyStage.key,
      onDestinationSelected: widget.onDestinationSelected,
      onCapture: widget.onCapture,
      trailing:
          _stage == _CeremonyStage.key || _stage == _CeremonyStage.randomEmpty
          ? null
          : const _RehearsalBadge(),
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 260),
        child: switch (_stage) {
          _CeremonyStage.key => _MemoryKeyLanding(
            key: const ValueKey('memory-key-landing'),
            nearbyDeviceCount: widget.nearbyDeviceCount,
            requiredNearbyDevices: widget.requiredNearbyDevices,
            weeklyMemoryCount: widget.weeklyMemoryCount,
            randomMemoryCount: widget.randomMemories.length,
            members: widget.members,
            lockedMemories: widget.lockedMemories,
            timeCapsule: widget.timeCapsule,
            weeklyPreviewEnabled: widget.weeklyPreviewEnabled,
            onWeekly: () => unawaited(
              _openWithPastelFlood(
                () => setState(() => _stage = _CeremonyStage.reel),
              ),
            ),
            onRandom: () => unawaited(_openWithPastelFlood(_openRandomMemory)),
            onAddMember: _addMember,
            onNudgeMissingMembers: _nudgeMissingMembers,
            onOpenLocks: () =>
                widget.onDestinationSelected(KeepersNavDestination.locks),
            onOpenLockedMemory: widget.onOpenLockedMemory == null
                ? null
                : (challenge) => unawaited(
                    _openWithPastelFlood(
                      () => widget.onOpenLockedMemory!(challenge),
                    ),
                  ),
          ),
          _CeremonyStage.reel => _Reel(
            key: const ValueKey('ceremony-reel'),
            controller: _pageController,
            memories: _memories,
            currentIndex: _memoryIndex,
            echoOpen: _echoOpen,
            onEcho: () => setState(() => _echoOpen = true),
            onBack: _previousMemory,
            onNext: _nextMemory,
            onKeeping: () => setState(() => _stage = _CeremonyStage.keeping),
          ),
          _CeremonyStage.keeping => _KeepingView(
            key: const ValueKey('ceremony-keeping'),
            memories: _memories,
          ),
          _CeremonyStage.randomEmpty => _RandomMemoryEmpty(
            key: const ValueKey('random-memory-empty'),
            onBack: () => setState(() => _stage = _CeremonyStage.key),
          ),
        },
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        scaffold,
        if (_flooding)
          Positioned.fill(
            child: IgnorePointer(
              key: const ValueKey('pastel-flood'),
              child: AnimatedBuilder(
                animation: _pastelFlood,
                builder: (context, _) => CustomPaint(
                  painter: _PastelFloodPainter(progress: _pastelFlood.value),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

final class _PastelFloodPainter extends CustomPainter {
  const _PastelFloodPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final eased = Curves.easeOutCubic.transform(progress);
    final longest = math.max(size.width, size.height);
    final colors = <Color>[
      KeepersColors.memberPalette[1],
      KeepersColors.memberPalette[5],
      KeepersColors.memberPalette[3],
      KeepersColors.memberPalette[2],
      const Color(0xFFF2D86B),
    ];
    final centers = <Offset>[
      Offset(size.width * .08, size.height * .72),
      Offset(size.width * .88, size.height * .64),
      Offset(size.width * .22, size.height * .28),
      Offset(size.width * .76, size.height * .22),
      Offset(size.width * .5, size.height * .48),
    ];
    final floodPath = Path();
    for (var index = 0; index < colors.length; index++) {
      final stagger = (eased - index * .045).clamp(0.0, 1.0);
      final radius = longest * stagger * (.82 + index * .025);
      floodPath.addOval(
        Rect.fromCircle(center: centers[index], radius: radius),
      );
    }
    final pastels = [
      for (final color in colors) Color.lerp(color, Colors.white, .48)!,
    ];
    canvas.save();
    canvas.clipPath(floodPath);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pastels,
          stops: const [0, .22, .47, .72, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PastelFloodPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

final class _RehearsalBadge extends StatelessWidget {
  const _RehearsalBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      border: Border.all(color: KeepersColors.brass.withValues(alpha: .7)),
      borderRadius: BorderRadius.circular(18),
    ),
    child: const KeepersText(
      'REHEARSAL MODE',
      style: TextStyle(
        color: KeepersColors.brassLight,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    ),
  );
}

final class _MemoryKeyLanding extends StatelessWidget {
  const _MemoryKeyLanding({
    required this.nearbyDeviceCount,
    required this.requiredNearbyDevices,
    required this.weeklyMemoryCount,
    required this.randomMemoryCount,
    required this.members,
    required this.lockedMemories,
    required this.timeCapsule,
    required this.weeklyPreviewEnabled,
    required this.onWeekly,
    required this.onRandom,
    required this.onAddMember,
    required this.onNudgeMissingMembers,
    required this.onOpenLocks,
    required this.onOpenLockedMemory,
    super.key,
  });

  final int nearbyDeviceCount;
  final int requiredNearbyDevices;
  final int weeklyMemoryCount;
  final int randomMemoryCount;
  final List<MemoryKeyMember> members;
  final List<LockedMemoryChallenge> lockedMemories;
  final MemoryKeyCapsule? timeCapsule;
  final bool weeklyPreviewEnabled;
  final VoidCallback onWeekly;
  final VoidCallback onRandom;
  final VoidCallback onAddMember;
  final VoidCallback onNudgeMissingMembers;
  final VoidCallback onOpenLocks;
  final ValueChanged<LockedMemoryChallenge>? onOpenLockedMemory;

  @override
  Widget build(BuildContext context) {
    final weeklyReady = nearbyDeviceCount >= requiredNearbyDevices;
    return SingleChildScrollView(
      key: const ValueKey('memory-key-scroll'),
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MemoryKeyPresenceStack(
            members: members,
            nearbyDeviceCount: nearbyDeviceCount,
            onInvite: onAddMember,
          ),
          const SizedBox(height: 8),
          KeepersText(
            _presenceSentence(
              members: members,
              nearbyDeviceCount: nearbyDeviceCount,
              requiredNearbyDevices: requiredNearbyDevices,
            ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: KeepersColors.inkMuted, height: 1.25),
          ),
          const SizedBox(height: 16),
          _WeeklyGatheringCard(
            nearbyDeviceCount: nearbyDeviceCount,
            requiredNearbyDevices: requiredNearbyDevices,
            weeklyMemoryCount: weeklyMemoryCount,
            ready: weeklyReady,
            onOpen: onWeekly,
            onPreview: weeklyPreviewEnabled && !weeklyReady ? onWeekly : null,
            onAskFamily: onNudgeMissingMembers,
          ),
          const SizedBox(height: 10),
          _RandomDrawCard(memoryCount: randomMemoryCount, onDraw: onRandom),
          const SizedBox(height: 20),
          KeepersText(
            'Locked by family',
            style: KeepersType.heading.copyWith(color: KeepersColors.ink),
          ),
          const SizedBox(height: 4),
          const KeepersText(
            'Someone set a condition. Finish it, and they open it.',
            style: TextStyle(color: KeepersColors.inkMuted, height: 1.4),
          ),
          const SizedBox(height: 10),
          if (lockedMemories.isEmpty)
            const _NoLockedMemories()
          else
            for (final challenge in lockedMemories) ...[
              _LockedMemoryCard(
                challenge: challenge,
                onOpen: challenge.state == LockedMemoryChallengeState.approved
                    ? onOpenLockedMemory
                    : null,
                onManage: onOpenLocks,
              ),
              const SizedBox(height: 10),
            ],
          if (timeCapsule case final capsule?) ...[
            _TimeCapsuleCard(capsule: capsule, onOpen: onOpenLocks),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

String _presenceSentence({
  required List<MemoryKeyMember> members,
  required int nearbyDeviceCount,
  required int requiredNearbyDevices,
}) {
  final nearbyRelatives = math.min(
    members.length,
    math.max(0, nearbyDeviceCount - 1),
  );
  if (nearbyRelatives == 0) {
    final remaining = math.max(0, requiredNearbyDevices - nearbyDeviceCount);
    if (remaining == 0) return 'You are here. The family key is ready.';
    if (remaining == 1) {
      return 'You are here. One more device turns the key.';
    }
    return 'You are here. $remaining more family devices turn the key.';
  }
  final names = members.take(nearbyRelatives).map((member) => member.name);
  return '${_joinNames(['You', ...names])} are here.';
}

String _joinNames(List<String> names) {
  if (names.length == 1) return names.single;
  if (names.length == 2) return '${names.first} and ${names.last}';
  return '${names.take(names.length - 1).join(', ')} and ${names.last}';
}

final class _MemoryKeyPresenceStack extends StatelessWidget {
  const _MemoryKeyPresenceStack({
    required this.members,
    required this.nearbyDeviceCount,
    required this.onInvite,
  });

  final List<MemoryKeyMember> members;
  final int nearbyDeviceCount;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final nearbyRelatives = math.max(0, nearbyDeviceCount - 1);
    return Semantics(
      container: true,
      label: 'Family presence',
      child: ExcludeSemantics(
        excluding: false,
        child: SizedBox(
          key: const ValueKey('memory-key-presence-stack'),
          height: 104,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth * .175).clamp(56.0, 64.0);
              final cardHeight = cardWidth * 1.32;
              final count = members.length + 1;
              final fittedStep = count <= 1
                  ? 0.0
                  : (constraints.maxWidth - cardWidth) /
                        (math.min(count, 6) - 1);
              final step = math.max(cardWidth * .74, fittedStep);
              final contentWidth = math.max(
                constraints.maxWidth,
                cardWidth + step * (count - 1),
              );
              const turns = <double>[-.026, -.015, -.006, .006, .015, .025];
              const rises = <double>[14, 11, 8, 4, 1, 6];
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width: contentWidth,
                  height: 104,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        top: rises.first,
                        child: Transform.rotate(
                          angle: turns.first * math.pi,
                          child: _InvitePresenceCard(
                            width: cardWidth,
                            height: cardHeight,
                            onTap: onInvite,
                          ),
                        ),
                      ),
                      for (var index = 0; index < members.length; index++)
                        Positioned(
                          left: step * (index + 1),
                          top: rises[(index + 1) % rises.length],
                          child: Transform.rotate(
                            angle: turns[(index + 1) % turns.length] * math.pi,
                            child: _MemberPresenceCard(
                              member: members[index],
                              width: cardWidth,
                              height: cardHeight,
                              nearby: index < nearbyRelatives,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

final class _InvitePresenceCard extends StatelessWidget {
  const _InvitePresenceCard({
    required this.width,
    required this.height,
    required this.onTap,
  });

  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Invite a family member',
    onTap: onTap,
    child: ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          color: KeepersColors.auraIvory.withValues(alpha: .56),
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: KeepersColors.homeTaupe.withValues(alpha: .48),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 27,
                  color: KeepersColors.homeTaupe,
                ),
                SizedBox(height: 8),
                KeepersText(
                  'INVITE',
                  style: TextStyle(
                    color: KeepersColors.homeTaupe,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class _MemberPresenceCard extends StatelessWidget {
  const _MemberPresenceCard({
    required this.member,
    required this.width,
    required this.height,
    required this.nearby,
  });

  final MemoryKeyMember member;
  final double width;
  final double height;
  final bool nearby;

  @override
  Widget build(BuildContext context) {
    final accent = nearby ? member.color : KeepersColors.homeTaupe;
    final avatar =
        member.avatar ?? AvatarConfig.defaults(seed: member.id ?? member.name);
    return Semantics(
      image: true,
      label: '${member.name}, ${nearby ? 'here' : 'away'}',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: nearby ? 1 : .7,
          child: Container(
            width: width,
            height: height,
            padding: const EdgeInsets.fromLTRB(5, 6, 5, 5),
            decoration: BoxDecoration(
              color: KeepersColors.auraIvory.withValues(alpha: .9),
              border: Border.all(
                color: KeepersColors.homeLine.withValues(alpha: .9),
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: KeepersColors.homeInk.withValues(alpha: .07),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Center(
                          child: KeepersAvatar(
                            key: ValueKey(
                              'memory-key-avatar-${member.id ?? member.name}',
                            ),
                            config: avatar,
                            size: width * .68,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 12,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: KeepersText(
                          member.name.toUpperCase(),
                          maxLines: 1,
                          style: TextStyle(
                            color: accent,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.35,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: nearby ? .82 : .38,
                        child: Container(
                          height: 1.5,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  right: 1,
                  top: 1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: nearby
                          ? accent
                          : KeepersColors.auraIvory.withValues(alpha: .85),
                      shape: BoxShape.circle,
                      border: Border.all(color: accent, width: 1.3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _WeeklyGatheringCard extends StatelessWidget {
  const _WeeklyGatheringCard({
    required this.nearbyDeviceCount,
    required this.requiredNearbyDevices,
    required this.weeklyMemoryCount,
    required this.ready,
    required this.onOpen,
    required this.onPreview,
    required this.onAskFamily,
  });

  final int nearbyDeviceCount;
  final int requiredNearbyDevices;
  final int weeklyMemoryCount;
  final bool ready;
  final VoidCallback onOpen;
  final VoidCallback? onPreview;
  final VoidCallback onAskFamily;

  @override
  Widget build(BuildContext context) {
    final waitingCopy = weeklyMemoryCount == 0
        ? 'No memories waiting yet.'
        : weeklyMemoryCount == 1
        ? '1 memory, waiting.'
        : '$weeklyMemoryCount memories, waiting.';
    final remaining = math.max(0, requiredNearbyDevices - nearbyDeviceCount);
    final keyCopy = ready
        ? 'The family key is ready.'
        : remaining == 1
        ? 'One more device turns the key.'
        : '$remaining more devices turn the key.';
    return Container(
      key: const ValueKey('weekly-recap-mode'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: KeepersColors.auraIvory.withValues(alpha: .84),
        border: Border.all(color: KeepersColors.homeLine),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: KeepersColors.homeInk.withValues(alpha: .055),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            key: const ValueKey('weekly-recap-open'),
            onPressed: ready ? onOpen : null,
            style: OutlinedButton.styleFrom(
              alignment: Alignment.topLeft,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              foregroundColor: KeepersColors.ink,
              disabledForegroundColor: KeepersColors.ink,
              side: BorderSide.none,
              shape: const RoundedRectangleBorder(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RoundLineIcon(
                      icon: ready ? Icons.key_rounded : Icons.lock_outline,
                      color: KeepersColors.homeGold,
                    ),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _EditorialEyebrow('THE WEEK'),
                          SizedBox(height: 2),
                          KeepersText(
                            'Kept since Monday',
                            style: TextStyle(
                              color: KeepersColors.inkMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 118),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: KeepersText(
                          '$nearbyDeviceCount of $requiredNearbyDevices devices',
                          style: const TextStyle(
                            color: KeepersColors.homeTaupe,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                KeepersText(
                  waitingCopy,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: KeepersColors.ink,
                    fontFamily: KeepersType.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Divider(height: 1, color: KeepersColors.homeLine),
                const SizedBox(height: 7),
                Row(
                  children: [
                    _PresenceDots(
                      nearby: nearbyDeviceCount,
                      required: requiredNearbyDevices,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: KeepersText(
                        keyCopy,
                        style: const TextStyle(
                          color: KeepersColors.inkMuted,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: ready ? onOpen : onAskFamily,
            icon: Icon(
              ready ? Icons.key_rounded : Icons.person_add_alt_1_rounded,
              size: 18,
            ),
            label: KeepersText(ready ? 'Open this week' : 'Ask family to come'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              backgroundColor: ready
                  ? KeepersColors.ink
                  : KeepersColors.auraBlush,
              foregroundColor: KeepersColors.ink,
              elevation: 0,
              side: BorderSide(
                color: KeepersColors.homeGold.withValues(alpha: .5),
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
                foregroundColor: KeepersColors.ink,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _RandomDrawCard extends StatelessWidget {
  const _RandomDrawCard({required this.memoryCount, required this.onDraw});

  final int memoryCount;
  final VoidCallback onDraw;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: const ValueKey('random-memory-mode'),
    child: OutlinedButton(
      onPressed: onDraw,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 48),
        foregroundColor: KeepersColors.ink,
        backgroundColor: KeepersColors.auraBlush.withValues(alpha: .5),
        side: BorderSide(color: KeepersColors.homeGold.withValues(alpha: .48)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Row(
        children: [
          const _RoundLineIcon(
            icon: Icons.style_outlined,
            color: KeepersColors.homeGold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _EditorialEyebrow('ANY TIME'),
                const SizedBox(height: 1),
                KeepersText(
                  'Draw a memory',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: KeepersColors.ink,
                    fontFamily: KeepersType.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                KeepersText(
                  memoryCount == 0
                      ? 'Your kept archive is ready to grow'
                      : '$memoryCount kept — one comes back at random',
                  style: const TextStyle(
                    color: KeepersColors.inkMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: KeepersColors.ink,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const KeepersText(
              'DRAW',
              style: TextStyle(
                color: KeepersColors.auraIvory,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.7,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _RoundLineIcon extends StatelessWidget {
  const _RoundLineIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color.withValues(alpha: .42)),
    ),
    child: Icon(icon, color: color, size: 20),
  );
}

final class _EditorialEyebrow extends StatelessWidget {
  const _EditorialEyebrow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => KeepersText(
    label,
    style: const TextStyle(
      color: KeepersColors.homeGold,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 2,
    ),
  );
}

final class _PresenceDots extends StatelessWidget {
  const _PresenceDots({required this.nearby, required this.required});

  final int nearby;
  final int required;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$nearby of $required devices nearby',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < required; index++) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: index < nearby
                    ? KeepersColors.memberPalette[index %
                          KeepersColors.memberPalette.length]
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: index < nearby
                      ? Colors.transparent
                      : KeepersColors.homeTaupe.withValues(alpha: .55),
                ),
              ),
            ),
            if (index < required - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    ),
  );
}

final class _LockedMemoryCard extends StatelessWidget {
  const _LockedMemoryCard({
    required this.challenge,
    required this.onOpen,
    required this.onManage,
  });

  final LockedMemoryChallenge challenge;
  final ValueChanged<LockedMemoryChallenge>? onOpen;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (challenge.state) {
      LockedMemoryChallengeState.locked => (
        'LOCKED',
        KeepersColors.legacyOlive,
      ),
      LockedMemoryChallengeState.submitted => (
        'AWAITING APPROVAL',
        KeepersColors.memberPalette[2],
      ),
      LockedMemoryChallengeState.approved => (
        'READY TO OPEN',
        KeepersColors.memberPalette[3],
      ),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: KeepersColors.auraIvory.withValues(alpha: .86),
        border: Border.all(color: KeepersColors.homeLine),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: KeepersColors.homeInk.withValues(alpha: .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RoundLineIcon(icon: Icons.lock_outline_rounded, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeepersText(
                      challenge.assignedBy.toUpperCase(),
                      style: const TextStyle(
                        color: KeepersColors.homeGold,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    KeepersText(
                      challenge.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: KeepersColors.ink,
                        fontFamily: KeepersType.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    KeepersText(
                      challenge.task,
                      style: const TextStyle(
                        color: KeepersColors.inkMuted,
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: KeepersColors.homeLine),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (challenge.state !=
                            LockedMemoryChallengeState.locked)
                          KeepersText(
                            label,
                            style: TextStyle(
                              color: color,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        KeepersText(
                          '${challenge.memoryCount} ${challenge.memoryCount == 1 ? 'MEMORY' : 'MEMORIES'} INSIDE',
                          style: const TextStyle(
                            color: KeepersColors.homeTaupe,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                    if (!challenge.preview) ...[
                      const SizedBox(height: 2),
                      KeepersText(
                        challenge.approvalBy,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: KeepersColors.inkMuted,
                          fontSize: 9,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (onOpen != null)
                FilledButton(
                  onPressed: () => onOpen!(challenge),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: KeepersColors.ink,
                    foregroundColor: KeepersColors.auraIvory,
                  ),
                  child: const KeepersText('Open memory'),
                )
              else
                OutlinedButton(
                  onPressed:
                      challenge.state == LockedMemoryChallengeState.locked
                      ? onManage
                      : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    foregroundColor: KeepersColors.legacyOlive,
                    side: BorderSide(color: color.withValues(alpha: .62)),
                  ),
                  child: KeepersText(
                    challenge.state == LockedMemoryChallengeState.locked
                        ? 'Submit proof'
                        : 'Awaiting approval',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _TimeCapsuleCard extends StatelessWidget {
  const _TimeCapsuleCard({required this.capsule, required this.onOpen});

  final MemoryKeyCapsule capsule;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${capsule.title}. ${capsule.openingLabel}',
    child: ExcludeSemantics(
      child: Material(
        color: KeepersColors.auraIvory.withValues(alpha: .84),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: KeepersColors.homeLine),
          borderRadius: BorderRadius.circular(18),
        ),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                const _RoundLineIcon(
                  icon: Icons.hourglass_empty_rounded,
                  color: KeepersColors.homeGold,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _EditorialEyebrow('Time capsule'),
                      const SizedBox(height: 3),
                      KeepersText(
                        capsule.title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: KeepersColors.ink,
                              fontFamily: KeepersType.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          KeepersText(
                            '${capsule.from} ·',
                            style: const TextStyle(
                              color: KeepersColors.inkMuted,
                              fontSize: 11,
                            ),
                          ),
                          KeepersText(
                            capsule.openingLabel,
                            style: const TextStyle(
                              color: KeepersColors.inkMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KeepersText(
                      '${capsule.daysRemaining}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: KeepersColors.ink,
                        fontFamily: KeepersType.primary,
                      ),
                    ),
                    const KeepersText(
                      'DAYS',
                      style: TextStyle(
                        color: KeepersColors.homeTaupe,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class _NoLockedMemories extends StatelessWidget {
  const _NoLockedMemories();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: KeepersColors.auraIvory.withValues(alpha: .62),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: KeepersColors.homeLine),
    ),
    child: const KeepersText(
      'No family tasks are holding a memory right now.',
      style: TextStyle(color: KeepersColors.inkMuted),
    ),
  );
}

final class _RandomMemoryEmpty extends StatelessWidget {
  const _RandomMemoryEmpty({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shuffle_rounded,
            color: KeepersColors.memberPalette[5],
            size: 54,
          ),
          const SizedBox(height: 18),
          KeepersText(
            'No kept memories yet',
            textAlign: TextAlign.center,
            style: KeepersType.heading.copyWith(color: KeepersColors.ink),
          ),
          const SizedBox(height: 8),
          const KeepersText(
            'After your family keeps a memory, the Key can draw it at any time.',
            textAlign: TextAlign.center,
            style: TextStyle(color: KeepersColors.inkMuted, height: 1.4),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const KeepersText('Back to Memory Key'),
          ),
        ],
      ),
    ),
  );
}

final class _Reel extends StatelessWidget {
  const _Reel({
    required this.controller,
    required this.memories,
    required this.currentIndex,
    required this.echoOpen,
    required this.onEcho,
    required this.onBack,
    required this.onNext,
    required this.onKeeping,
    super.key,
  });

  final PageController controller;
  final List<_RehearsalMemory> memories;
  final int currentIndex;
  final bool echoOpen;
  final VoidCallback onEcho;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onKeeping;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
        child: Row(
          children: [
            KeepersText(
              '${currentIndex + 1} of ${memories.length}',
              style: const TextStyle(color: KeepersColors.brassLight),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: LinearProgressIndicator(
                value: (currentIndex + 1) / memories.length,
                minHeight: 2,
                backgroundColor: KeepersColors.cream.withValues(alpha: .12),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: PageView.builder(
          key: const ValueKey('ceremony-host-page-view'),
          controller: controller,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: memories.length,
          itemBuilder: (context, index) => _MemoryReelCard(
            memory: memories[index],
            showEcho: index == memories.length - 1,
            echoOpen: index == currentIndex && echoOpen,
            onEcho: onEcho,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
        child: Row(
          children: [
            if (currentIndex > 0)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: KeepersColors.cream,
                ),
                onPressed: onBack,
                child: const Icon(Icons.arrow_back_rounded),
              )
            else
              const SizedBox(width: 48),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: KeepersColors.brass,
                  foregroundColor: KeepersColors.ground,
                ),
                onPressed: currentIndex == memories.length - 1
                    ? onKeeping
                    : onNext,
                child: KeepersText(
                  currentIndex == memories.length - 1
                      ? 'Begin keeping'
                      : 'Next memory',
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

final class _MemoryReelCard extends StatelessWidget {
  const _MemoryReelCard({
    required this.memory,
    required this.showEcho,
    required this.echoOpen,
    required this.onEcho,
  });

  final _RehearsalMemory memory;
  final bool showEcho;
  final bool echoOpen;
  final VoidCallback onEcho;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Container(
            width: math.min(constraints.maxWidth, 420),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: KeepersColors.groundVignette.withValues(alpha: .9),
              border: Border.all(color: memory.color, width: 1.5),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: memory.color.withValues(alpha: .16),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeepersText(
                  memory.author.toUpperCase(),
                  style: TextStyle(
                    color: memory.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.7,
                  ),
                ),
                const SizedBox(height: 16),
                switch (memory.format) {
                  _RehearsalFormat.photo => _PhotoRehearsal(memory: memory),
                  _RehearsalFormat.voice => _VoiceRehearsal(memory: memory),
                  _RehearsalFormat.text => _TextRehearsal(memory: memory),
                },
                if (showEcho) ...[
                  const SizedBox(height: 22),
                  const Divider(color: Color(0x33EFE7D4)),
                  const SizedBox(height: 10),
                  KeepersText(
                    'An echo from before',
                    style: KeepersType.heading.copyWith(
                      color: KeepersColors.brassLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!echoOpen)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KeepersColors.cream,
                        minimumSize: const Size.fromHeight(46),
                      ),
                      onPressed: onEcho,
                      child: const KeepersText('Open echo'),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: KeepersColors.brass.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const KeepersText(
                        'A memory from another season rises beneath it.',
                        style: TextStyle(
                          color: KeepersColors.cream,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class _PhotoRehearsal extends StatelessWidget {
  const _PhotoRehearsal({required this.memory});
  final _RehearsalMemory memory;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const KeepersText(
        'Photo memory',
        style: TextStyle(color: KeepersColors.cream),
      ),
      const SizedBox(height: 12),
      AspectRatio(
        aspectRatio: 4 / 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                memory.color.withValues(alpha: .8),
                const Color(0xFF20170F),
              ],
            ),
          ),
          child: const Icon(
            Icons.landscape_rounded,
            size: 72,
            color: Color(0xCCEFE7D4),
          ),
        ),
      ),
      const SizedBox(height: 14),
      KeepersText(
        memory.caption,
        style: const TextStyle(color: KeepersColors.cream, height: 1.4),
      ),
    ],
  );
}

final class _VoiceRehearsal extends StatefulWidget {
  const _VoiceRehearsal({required this.memory});
  final _RehearsalMemory memory;

  @override
  State<_VoiceRehearsal> createState() => _VoiceRehearsalState();
}

final class _VoiceRehearsalState extends State<_VoiceRehearsal> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const KeepersText(
          'Voice memory',
          style: TextStyle(color: KeepersColors.cream),
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            17,
            (index) => Container(
              width: 3,
              height: 16 + math.sin(index * .9).abs() * 42,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: memory.color.withValues(alpha: _playing ? 1 : .62),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Semantics(
            label: _playing
                ? 'Pause rehearsal voice memory'
                : 'Play rehearsal voice memory',
            button: true,
            onTap: () => setState(() => _playing = !_playing),
            child: ExcludeSemantics(
              child: IconButton.filledTonal(
                tooltip: _playing
                    ? 'PAUSE REHEARSAL VOICE MEMORY'
                    : 'PLAY REHEARSAL VOICE MEMORY',
                onPressed: () => setState(() => _playing = !_playing),
                icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        KeepersText(
          memory.caption,
          style: const TextStyle(color: KeepersColors.cream, height: 1.4),
        ),
      ],
    );
  }
}

final class _TextRehearsal extends StatelessWidget {
  const _TextRehearsal({required this.memory});
  final _RehearsalMemory memory;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const KeepersText(
        'Text memory',
        style: TextStyle(color: KeepersColors.cream),
      ),
      const SizedBox(height: 22),
      KeepersText(
        memory.caption,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: KeepersColors.cream,
          fontFamily: KeepersType.primary,
          height: 1.35,
        ),
      ),
    ],
  );
}

enum _KeepingDecision { keep, release }

final class _KeepingView extends StatefulWidget {
  const _KeepingView({required this.memories, super.key});
  final List<_RehearsalMemory> memories;

  @override
  State<_KeepingView> createState() => _KeepingViewState();
}

final class _KeepingViewState extends State<_KeepingView> {
  _KeepingDecision? _decision;

  void _decide(_KeepingDecision decision) =>
      setState(() => _decision = decision);

  Widget _keepButton() => FilledButton.icon(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      backgroundColor: KeepersColors.brass,
      foregroundColor: KeepersColors.ground,
    ),
    onPressed: () => _decide(_KeepingDecision.keep),
    icon: const Icon(Icons.keyboard_arrow_up_rounded),
    label: const KeepersText('Keep this memory'),
  );

  Widget _releaseButton() => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      foregroundColor: KeepersColors.cream,
    ),
    onPressed: () => _decide(_KeepingDecision.release),
    icon: const Icon(Icons.keyboard_arrow_down_rounded),
    label: const KeepersText('Release this memory'),
  );

  @override
  Widget build(BuildContext context) {
    final memory = widget.memories.first;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        children: [
          const _VoteDots(),
          const SizedBox(height: 18),
          Semantics(
            label: 'Memory decision card. Swipe up to keep or down to release.',
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -350) _decide(_KeepingDecision.keep);
                if (velocity > 350) _decide(_KeepingDecision.release);
              },
              child: SizedBox(
                height: 300,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: -.08,
                      child: _DecisionCard(
                        color: widget.memories[2].color,
                        offset: 14,
                      ),
                    ),
                    Transform.rotate(
                      angle: .055,
                      child: _DecisionCard(
                        color: widget.memories[1].color,
                        offset: 7,
                      ),
                    ),
                    AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 300),
                      width: 270,
                      height: 270,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: _decision == _KeepingDecision.release
                            ? const Color(0xFF393735)
                            : KeepersColors.groundVignette,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _decision == _KeepingDecision.keep
                              ? KeepersColors.brassLight
                              : memory.color,
                          width: _decision == _KeepingDecision.keep ? 2.5 : 1.5,
                        ),
                      ),
                      child: _decision == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.landscape_rounded,
                                  color: memory.color,
                                  size: 58,
                                ),
                                const SizedBox(height: 18),
                                KeepersText(
                                  memory.caption,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: KeepersColors.cream,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            )
                          : _DecisionResult(decision: _decision!),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (_decision == null)
            LayoutBuilder(
              builder: (context, constraints) {
                final stackActions =
                    constraints.maxWidth < 380 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.2;
                if (stackActions) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _keepButton(),
                      const SizedBox(height: 10),
                      _releaseButton(),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: _releaseButton()),
                    const SizedBox(width: 10),
                    Expanded(child: _keepButton()),
                  ],
                );
              },
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(220, 50),
                backgroundColor: KeepersColors.brass,
                foregroundColor: KeepersColors.ground,
              ),
              onPressed: () => setState(() => _decision = null),
              child: const KeepersText('Next decision'),
            ),
        ],
      ),
    );
  }
}

final class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.color, required this.offset});
  final Color color;
  final double offset;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset(0, offset),
    child: Container(
      width: 252,
      height: 252,
      decoration: BoxDecoration(
        color: KeepersColors.groundVignette,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
    ),
  );
}

final class _DecisionResult extends StatelessWidget {
  const _DecisionResult({required this.decision});
  final _KeepingDecision decision;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(
        decision == _KeepingDecision.keep
            ? Icons.workspace_premium_rounded
            : Icons.hourglass_bottom_rounded,
        color: decision == _KeepingDecision.keep
            ? KeepersColors.brassLight
            : KeepersColors.cream.withValues(alpha: .65),
        size: 60,
      ),
      const SizedBox(height: 14),
      KeepersText(
        decision == _KeepingDecision.keep ? 'KEPT' : 'RELEASED',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: decision == _KeepingDecision.keep
              ? KeepersColors.brassLight
              : KeepersColors.cream,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
      const SizedBox(height: 8),
      KeepersText(
        decision == _KeepingDecision.keep
            ? 'Sealed into the family archive'
            : 'Fades from this device in 30 days',
        textAlign: TextAlign.center,
        style: TextStyle(color: KeepersColors.cream.withValues(alpha: .68)),
      ),
    ],
  );
}

final class _VoteDots extends StatelessWidget {
  const _VoteDots();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Rehearsal vote: one of one family members present',
    child: ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: KeepersColors.brassLight,
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: KeepersText(
              '1 PRESENT · PREVIEW ONLY',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: KeepersColors.cream.withValues(alpha: .62),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
