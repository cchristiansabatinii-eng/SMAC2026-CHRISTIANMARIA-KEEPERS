import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:keepers/design_system/observatory/motion_policy.dart';
import 'package:keepers/features/capture/data/audio_playback_adapter.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/ceremony/presentation/pastel_flood.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';
import 'package:keepers/ui/keepers_destination_scaffold.dart';

enum _CeremonyStage { key, reel, keeping }

enum _RehearsalFormat { photo, voice, text }

typedef WeeklyMemoryDecisionCallback = Future<void> Function(
  VaultEntryMetadata metadata,
  WeeklyMemoryDisposition disposition,
);

@immutable
final class _RehearsalMemory {
  const _RehearsalMemory({
    required this.author,
    required this.format,
    required this.title,
    required this.caption,
    required this.dateLabel,
    required this.color,
    this.imageAsset,
    this.primaryBytes,
    this.metadata,
    this.preview = true,
  });

  final String author;
  final _RehearsalFormat format;
  final String title;
  final String caption;
  final String dateLabel;
  final String? imageAsset;
  final Uint8List? primaryBytes;
  final VaultEntryMetadata? metadata;
  final Color color;
  final bool preview;
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
    this.startInWeekly = false,
    this.weeklyPreview = true,
    this.weeklyMemories,
    this.weeklyAuthorNames = const {},
    this.weeklyPlayback,
    this.onWeeklyDecision,
    this.navigationDestination = KeepersNavDestination.ceremony,
    this.lockedMemories = const [],
    this.timeCapsule,
    this.onOpenLockedMemory,
    super.key,
  }) : assert(!(startInKeeping && startInWeekly)),
       assert(
         !startInWeekly ||
             weeklyPreview ||
             (weeklyMemories != null && onWeeklyDecision != null),
       );

  final String familyName;
  final String currentMemberName;
  final ValueChanged<KeepersNavDestination> onDestinationSelected;
  final VoidCallback? onCapture;
  final bool startInKeeping;
  final bool startInWeekly;
  final bool weeklyPreview;
  final Future<List<OpenedMemory>>? weeklyMemories;
  final Map<String, String> weeklyAuthorNames;
  final AudioPlaybackAdapter? weeklyPlayback;
  final WeeklyMemoryDecisionCallback? onWeeklyDecision;
  final KeepersNavDestination navigationDestination;
  final List<LockedMemoryChallenge> lockedMemories;
  final MemoryKeyCapsule? timeCapsule;
  final ValueChanged<LockedMemoryChallenge>? onOpenLockedMemory;

  @override
  State<CeremonyScreen> createState() => _CeremonyScreenState();
}

final class _CeremonyScreenState extends State<CeremonyScreen>
    with SingleTickerProviderStateMixin {
  late _CeremonyStage _stage = widget.startInKeeping
      ? _CeremonyStage.keeping
      : widget.startInWeekly
      ? _CeremonyStage.reel
      : _CeremonyStage.key;
  late final AnimationController _pastelFlood = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  int _memoryIndex = 0;
  bool _echoOpen = false;
  bool _flooding = false;

  late final List<_RehearsalMemory> _previewMemories = [
    const _RehearsalMemory(
      author: 'A family member',
      format: _RehearsalFormat.photo,
      title: 'A small moment',
      caption: 'A small moment, held in the light.',
      dateLabel: '16 May, 2025',
      imageAsset: 'assets/memories/weekly_reference_1.png',
      color: Color(0xFFE4626F),
    ),
    const _RehearsalMemory(
      author: 'A family member',
      format: _RehearsalFormat.voice,
      title: 'A voice together',
      caption: 'A voice the room can hear together.',
      dateLabel: '18 May, 2025',
      imageAsset: 'assets/memories/weekly_reference_2.png',
      color: Color(0xFF3EB8A5),
    ),
    _RehearsalMemory(
      author: widget.currentMemberName,
      format: _RehearsalFormat.text,
      title: 'What should we remember?',
      caption: 'What should this family remember from this week?',
      dateLabel: '21 May, 2025',
      imageAsset: 'assets/memories/weekly_reference_3.png',
      color: const Color(0xFF9B6BD5),
    ),
  ];

  @override
  void dispose() {
    _pastelFlood.dispose();
    super.dispose();
  }

  Future<void> _openWithPastelFlood(VoidCallback open) async {
    if (_flooding) return;
    if (keepersReduceMotion(context)) {
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

  void _selectMemory(int index, int memoryCount) {
    if (index < 0 || index >= memoryCount || index == _memoryIndex) return;
    setState(() {
      _memoryIndex = index;
      _echoOpen = false;
    });
  }

  void _nextMemory(int memoryCount) {
    if (_memoryIndex >= memoryCount - 1) return;
    _selectMemory(_memoryIndex + 1, memoryCount);
  }

  void _previousMemory(int memoryCount) {
    if (_memoryIndex == 0) return;
    _selectMemory(_memoryIndex - 1, memoryCount);
  }

  @override
  Widget build(BuildContext context) {
    if (_stage != _CeremonyStage.key) {
      if (widget.weeklyPreview) {
        return _buildWeeklyExperience(_previewMemories, preview: true);
      }
      return FutureBuilder<List<OpenedMemory>>(
        future: widget.weeklyMemories,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _weeklyStatus(
              key: const ValueKey('weekly-experience-error'),
              message: 'This week could not be opened safely.',
            );
          }
          if (!snapshot.hasData) {
            return _weeklyStatus(
              key: const ValueKey('weekly-experience-loading'),
              message: 'Opening this week…',
              loading: true,
            );
          }
          final memories = _openedMemories(snapshot.data!);
          if (memories.isEmpty) {
            return _weeklyStatus(
              key: const ValueKey('weekly-experience-empty'),
              message: 'No available memories were found for this week.',
            );
          }
          return _buildWeeklyExperience(memories, preview: false);
        },
      );
    }

    final scaffold = KeepersDestinationScaffold(
      destination: widget.navigationDestination,
      kicker: 'Open together',
      title: 'Memory Key',
      compactHeader: true,
      onDestinationSelected: widget.onDestinationSelected,
      onCapture: widget.onCapture,
      child: Align(
        key: const ValueKey('memory-key-landing'),
        alignment: Alignment.topCenter,
        child: _MemoryKeyLanding(
          lockedMemories: widget.lockedMemories,
          timeCapsule: widget.timeCapsule,
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
                  painter: PastelFloodPainter(progress: _pastelFlood.value),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWeeklyExperience(
    List<_RehearsalMemory> memories, {
    required bool preview,
  }) {
    final safeIndex = math.min(_memoryIndex, memories.length - 1);
    final weeklyTitle = _stage == _CeremonyStage.reel
        ? memories[safeIndex].title
        : 'What stays with us?';
    return _WeeklyExperienceShell(
      title: weeklyTitle,
      modeLabel: preview ? 'REHEARSAL MODE' : 'THIS WEEK',
      onClose: () => widget.onDestinationSelected(KeepersNavDestination.wheel),
      child: AnimatedSwitcher(
        duration: keepersReduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        layoutBuilder: (currentChild, previousChildren) => Stack(
          fit: StackFit.expand,
          children: [...previousChildren, ?currentChild],
        ),
        child: _stage == _CeremonyStage.reel
            ? _Reel(
                key: const ValueKey('ceremony-reel'),
                memories: memories,
                currentIndex: safeIndex,
                echoOpen: _echoOpen,
                preview: preview,
                playback: widget.weeklyPlayback,
                onEcho: () => setState(() => _echoOpen = true),
                onSelect: (index) => _selectMemory(index, memories.length),
                onBack: () => _previousMemory(memories.length),
                onNext: () => _nextMemory(memories.length),
                onKeeping: () =>
                    setState(() => _stage = _CeremonyStage.keeping),
              )
            : _KeepingView(
                key: const ValueKey('ceremony-keeping'),
                memories: memories,
                preview: preview,
                onDecision: preview ? null : widget.onWeeklyDecision,
                onComplete: () =>
                    widget.onDestinationSelected(KeepersNavDestination.wheel),
              ),
      ),
    );
  }

  Widget _weeklyStatus({
    required Key key,
    required String message,
    bool loading = false,
  }) => _WeeklyExperienceShell(
    title: 'This week',
    modeLabel: 'THIS WEEK',
    onClose: () => widget.onDestinationSelected(KeepersNavDestination.wheel),
    child: Center(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              const CircularProgressIndicator.adaptive(),
              const SizedBox(height: 20),
            ],
            KeepersText(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: KeepersColors.inkMuted),
            ),
          ],
        ),
      ),
    ),
  );

  List<_RehearsalMemory> _openedMemories(List<OpenedMemory> opened) {
    const colors = [
      KeepersColors.homeClay,
      KeepersColors.homeGreen,
      KeepersColors.homeBlue,
      KeepersColors.homeMauve,
      KeepersColors.brass,
    ];
    return List<_RehearsalMemory>.generate(opened.length, (index) {
      final memory = opened[index];
      final payload = memory.payload;
      final author =
          widget.weeklyAuthorNames[memory.metadata.authorId] ??
          'A family member';
      final caption = switch (payload.format) {
        MemoryFormat.text => _nonEmpty(payload.text) ?? 'A written memory',
        MemoryFormat.photo =>
          _nonEmpty(payload.caption) ?? 'A photo shared by $author',
        MemoryFormat.voice =>
          _nonEmpty(payload.caption) ?? 'A voice shared by $author',
      };
      final title =
          _nonEmpty(payload.caption) ??
          switch (payload.format) {
            MemoryFormat.photo => 'A photo from $author',
            MemoryFormat.voice => 'A voice from $author',
            MemoryFormat.text => 'A note from $author',
          };
      return _RehearsalMemory(
        author: author,
        format: switch (payload.format) {
          MemoryFormat.photo => _RehearsalFormat.photo,
          MemoryFormat.voice => _RehearsalFormat.voice,
          MemoryFormat.text => _RehearsalFormat.text,
        },
        title: title,
        caption: caption,
        dateLabel: _formatWeeklyDate(memory.metadata.createdAt),
        color: colors[index % colors.length],
        primaryBytes: payload.primaryBytes,
        metadata: memory.metadata,
        preview: false,
      );
    }, growable: false);
  }
}

final class _WeeklyExperienceShell extends StatelessWidget {
  const _WeeklyExperienceShell({
    required this.title,
    required this.modeLabel,
    required this.onClose,
    required this.child,
  });

  final String title;
  final String modeLabel;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('weekly-experience-shell'),
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: Column(
        children: [
          SizedBox(
            key: const ValueKey('weekly-gallery-header'),
            width: double.infinity,
            height: 68,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 10,
                  child: IconButton(
                    tooltip: 'Close weekly memories',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                    color: KeepersColors.ink,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 66),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KeepersText(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: KeepersColors.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      KeepersText(
                        modeLabel,
                        style: const TextStyle(
                          color: KeepersColors.inkMuted,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .55,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

final class _MemoryKeyLanding extends StatefulWidget {
  const _MemoryKeyLanding({
    required this.lockedMemories,
    required this.timeCapsule,
    required this.onOpenLocks,
    required this.onOpenLockedMemory,
  });

  final List<LockedMemoryChallenge> lockedMemories;
  final MemoryKeyCapsule? timeCapsule;
  final VoidCallback onOpenLocks;
  final ValueChanged<LockedMemoryChallenge>? onOpenLockedMemory;

  @override
  State<_MemoryKeyLanding> createState() => _MemoryKeyLandingState();
}

final class _MemoryKeyLandingState extends State<_MemoryKeyLanding> {
  final GlobalKey _capsuleKey = GlobalKey();

  Future<void> _showCapsule() async {
    final capsuleContext = _capsuleKey.currentContext;
    if (capsuleContext == null) return;
    await Scrollable.ensureVisible(
      capsuleContext,
      duration: keepersReduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: .1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lockedMemories = widget.lockedMemories;
    final timeCapsule = widget.timeCapsule;
    return SingleChildScrollView(
      key: const ValueKey('memory-key-scroll'),
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MemoryKeyEntries(
            legacySubtitle: lockedMemories.isEmpty
                ? 'No family condition yet'
                : '${lockedMemories.length} ${lockedMemories.length == 1 ? 'family condition' : 'family conditions'}',
            capsuleSubtitle:
                timeCapsule?.openingLabel ?? 'No capsule scheduled',
            onLegacyTap: widget.onOpenLocks,
            onCapsuleTap: timeCapsule == null ? null : _showCapsule,
          ),
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
                    ? widget.onOpenLockedMemory
                    : null,
                onManage: widget.onOpenLocks,
              ),
              const SizedBox(height: 10),
            ],
          if (timeCapsule case final capsule?) ...[
            KeyedSubtree(
              key: _capsuleKey,
              child: _TimeCapsuleCard(capsule: capsule),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

final class _MemoryKeyEntries extends StatelessWidget {
  const _MemoryKeyEntries({
    required this.legacySubtitle,
    required this.capsuleSubtitle,
    required this.onLegacyTap,
    required this.onCapsuleTap,
  });

  final String legacySubtitle;
  final String capsuleSubtitle;
  final VoidCallback onLegacyTap;
  final VoidCallback? onCapsuleTap;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _MemoryKeyShortcutCard(
            key: const ValueKey('memory-key-legacy-entry'),
            title: 'LEGACY LOCK',
            subtitle: legacySubtitle,
            icon: Icons.lock_outline_rounded,
            accent: KeepersColors.legacyOlive,
            labelAccent: KeepersColors.legacyOliveText,
            onTap: onLegacyTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MemoryKeyShortcutCard(
            key: const ValueKey('memory-key-capsule-entry'),
            title: 'CAPSULE',
            subtitle: capsuleSubtitle,
            icon: Icons.hourglass_empty_rounded,
            accent: KeepersColors.homeGold,
            labelAccent: KeepersColors.homeGoldText,
            onTap: onCapsuleTap,
          ),
        ),
      ],
    ),
  );
}

final class _MemoryKeyShortcutCard extends StatelessWidget {
  const _MemoryKeyShortcutCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.labelAccent,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color labelAccent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: '$title. $subtitle',
    onTap: onTap,
    child: ExcludeSemantics(
      child: Material(
        color: KeepersColors.auraIvory.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 74),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accent.withValues(alpha: .38)),
                    ),
                    child: Icon(icon, color: accent, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KeepersText(
                          title,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: labelAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.8,
                              ),
                        ),
                        const SizedBox(height: 3),
                        KeepersText(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: KeepersColors.homeInk,
                                fontSize: 9.2,
                                height: 1.15,
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
      color: KeepersColors.homeGoldText,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 2,
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
                        color: KeepersColors.homeGoldText,
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
  const _TimeCapsuleCard({required this.capsule});

  final MemoryKeyCapsule capsule;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${capsule.title}. ${capsule.openingLabel}',
    child: ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: KeepersColors.auraIvory.withValues(alpha: .84),
          border: Border.all(color: KeepersColors.homeLine),
          borderRadius: BorderRadius.circular(18),
        ),
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
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

final class _Reel extends StatelessWidget {
  const _Reel({
    required this.memories,
    required this.currentIndex,
    required this.echoOpen,
    required this.preview,
    required this.playback,
    required this.onEcho,
    required this.onSelect,
    required this.onBack,
    required this.onNext,
    required this.onKeeping,
    super.key,
  });

  final List<_RehearsalMemory> memories;
  final int currentIndex;
  final bool echoOpen;
  final bool preview;
  final AudioPlaybackAdapter? playback;
  final VoidCallback onEcho;
  final ValueChanged<int> onSelect;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onKeeping;

  @override
  Widget build(BuildContext context) {
    final memory = memories[currentIndex];
    final reduceMotion = keepersReduceMotion(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.min(constraints.maxWidth - 72, 340.0);
        final heroHeight = math.min(
          contentWidth / .72,
          math.max(330.0, constraints.maxHeight * .61),
        );
        return SingleChildScrollView(
          key: const ValueKey('weekly-gallery-scroll'),
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          child: Center(
            child: SizedBox(
              width: contentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GallerySwipeRegion(
                    key: const ValueKey('weekly-gallery-hero'),
                    label:
                        '${_memoryFormatLabel(memory.format)}. ${memory.title}.',
                    value: '${currentIndex + 1} of ${memories.length}',
                    increasedValue: currentIndex < memories.length - 1
                        ? '${currentIndex + 2} of ${memories.length}'
                        : null,
                    decreasedValue: currentIndex > 0
                        ? '$currentIndex of ${memories.length}'
                        : null,
                    onNext: currentIndex < memories.length - 1 ? onNext : null,
                    onBack: currentIndex > 0 ? onBack : null,
                    child: SizedBox(
                      height: heroHeight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: KeepersColors.auraIvory,
                            border: Border.all(color: KeepersColors.homeLine),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: AnimatedSwitcher(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 170),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                            layoutBuilder: (currentChild, previousChildren) =>
                                Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ...previousChildren,
                                    ?currentChild,
                                  ],
                                ),
                            child: _GalleryMemory(
                              key: ValueKey('weekly-memory-$currentIndex'),
                              memory: memory,
                              playback: playback,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 13),
                  KeepersText(
                    memory.dateLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: KeepersColors.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: .15,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      KeepersText(
                        _memoryFormatLabel(memory.format),
                        style: const TextStyle(
                          color: KeepersColors.inkMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .5,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: 18,
                          child: Divider(
                            height: 1,
                            color: KeepersColors.homeLine,
                          ),
                        ),
                      ),
                      KeepersText(
                        '${currentIndex + 1} of ${memories.length}',
                        style: const TextStyle(
                          color: KeepersColors.inkMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          letterSpacing: .35,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _GalleryFilmstrip(
                    memories: memories,
                    currentIndex: currentIndex,
                    onSelect: onSelect,
                  ),
                  if (preview && currentIndex == memories.length - 1) ...[
                    const SizedBox(height: 22),
                    _GalleryEcho(open: echoOpen, onOpen: onEcho),
                  ],
                  if (currentIndex == memories.length - 1) ...[
                    const SizedBox(height: 14),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: KeepersColors.ink,
                        foregroundColor: KeepersColors.auraIvory,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: onKeeping,
                      child: const KeepersText('Begin keeping'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _GallerySwipeRegion extends StatefulWidget {
  const _GallerySwipeRegion({
    required this.label,
    required this.value,
    required this.increasedValue,
    required this.decreasedValue,
    required this.onNext,
    required this.onBack,
    required this.child,
    super.key,
  });

  final String label;
  final String value;
  final String? increasedValue;
  final String? decreasedValue;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final Widget child;

  @override
  State<_GallerySwipeRegion> createState() => _GallerySwipeRegionState();
}

final class _GallerySwipeRegionState extends State<_GallerySwipeRegion> {
  double _dragDistance = 0;

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    value: widget.value,
    increasedValue: widget.increasedValue,
    decreasedValue: widget.decreasedValue,
    onIncrease: widget.onNext,
    onDecrease: widget.onBack,
    child: GestureDetector(
      onHorizontalDragStart: (_) => _dragDistance = 0,
      onHorizontalDragUpdate: (details) =>
          _dragDistance += details.primaryDelta ?? 0,
      onHorizontalDragCancel: () => _dragDistance = 0,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final direction = velocity.abs() >= 120 ? velocity : _dragDistance;
        if (direction <= -48) widget.onNext?.call();
        if (direction >= 48) widget.onBack?.call();
        _dragDistance = 0;
      },
      child: widget.child,
    ),
  );
}

String _memoryFormatLabel(_RehearsalFormat format) => switch (format) {
  _RehearsalFormat.photo => 'Photo memory',
  _RehearsalFormat.voice => 'Voice memory',
  _RehearsalFormat.text => 'Text memory',
};

final class _GalleryMemory extends StatelessWidget {
  const _GalleryMemory({
    required this.memory,
    required this.playback,
    super.key,
  });

  final _RehearsalMemory memory;
  final AudioPlaybackAdapter? playback;

  @override
  Widget build(BuildContext context) => switch (memory.format) {
    _RehearsalFormat.photo => _PhotoRehearsal(memory: memory),
    _RehearsalFormat.voice => _VoiceRehearsal(
      memory: memory,
      playback: playback,
    ),
    _RehearsalFormat.text => _TextRehearsal(memory: memory),
  };
}

final class _PhotoRehearsal extends StatelessWidget {
  const _PhotoRehearsal({required this.memory});
  final _RehearsalMemory memory;

  @override
  Widget build(BuildContext context) {
    final bytes = memory.primaryBytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      );
    }
    final asset = memory.imageAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
      );
    }
    return _MemoryFallback(
      color: memory.color,
      icon: Icons.photo_outlined,
      label: 'Photo unavailable',
    );
  }
}

final class _VoiceRehearsal extends StatefulWidget {
  const _VoiceRehearsal({required this.memory, required this.playback});
  final _RehearsalMemory memory;
  final AudioPlaybackAdapter? playback;

  @override
  State<_VoiceRehearsal> createState() => _VoiceRehearsalState();
}

final class _VoiceRehearsalState extends State<_VoiceRehearsal> {
  bool _playing = false;
  bool _playbackStarting = false;

  Future<void> _stopPlaybackSafely(AudioPlaybackAdapter playback) async {
    try {
      await playback.stop();
    } on Object {
      // Teardown is best effort; cleanup failures must not escape disposal.
    }
  }

  Future<void> _togglePlayback() async {
    final memory = widget.memory;
    final playback = widget.playback;
    final bytes = memory.primaryBytes;
    if (memory.preview || playback == null || bytes == null) {
      setState(() => _playing = !_playing);
      return;
    }
    try {
      if (_playing) {
        await _stopPlaybackSafely(playback);
      } else {
        _playbackStarting = true;
        try {
          await playback.playBytes(bytes);
        } finally {
          _playbackStarting = false;
        }
      }
      if (mounted) setState(() => _playing = !_playing);
    } on Object {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  void dispose() {
    if ((_playing || _playbackStarting) && !widget.memory.preview) {
      final playback = widget.playback;
      if (playback != null) unawaited(_stopPlaybackSafely(playback));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (memory.imageAsset case final asset?)
          Image.asset(
            asset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
          )
        else
          _VoiceBackdrop(memory: memory, playing: _playing),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Material(
            color: KeepersColors.auraIvory.withValues(alpha: .96),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        KeepersText(
                          memory.caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: KeepersColors.ink,
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 20,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: List.generate(
                              17,
                              (index) => Container(
                                width: 2,
                                height: 4 + math.sin(index * .9).abs() * 14,
                                margin: const EdgeInsets.only(right: 3),
                                decoration: BoxDecoration(
                                  color: memory.color.withValues(
                                    alpha: _playing ? 1 : .62,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    label: _playing
                        ? 'Pause voice memory'
                        : 'Play voice memory',
                    button: true,
                    onTap: _togglePlayback,
                    child: ExcludeSemantics(
                      child: IconButton.filled(
                        tooltip: _playing
                            ? memory.preview
                                  ? 'Pause Rehearsal Voice Memory'
                                  : 'Pause Voice Memory'
                            : memory.preview
                            ? 'Play Rehearsal Voice Memory'
                            : 'Play Voice Memory',
                        style: IconButton.styleFrom(
                          backgroundColor: KeepersColors.ink,
                          foregroundColor: KeepersColors.auraIvory,
                        ),
                        onPressed: _togglePlayback,
                        icon: Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _TextRehearsal extends StatelessWidget {
  const _TextRehearsal({required this.memory});
  final _RehearsalMemory memory;

  @override
  Widget build(BuildContext context) {
    if (!memory.preview) {
      return DecoratedBox(
        decoration: BoxDecoration(color: memory.color.withValues(alpha: .13)),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: KeepersText(
              memory.caption,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: KeepersColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          memory.imageAsset!,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KeepersColors.auraIvory.withValues(alpha: .96),
              borderRadius: BorderRadius.circular(14),
            ),
            child: KeepersText(
              memory.caption,
              style: const TextStyle(
                color: KeepersColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _GalleryFilmstrip extends StatelessWidget {
  const _GalleryFilmstrip({
    required this.memories,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<_RehearsalMemory> memories;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('weekly-gallery-filmstrip'),
    height: 78,
    child: Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < memories.length; index++) ...[
              if (index > 0) const SizedBox(width: 10),
              _GalleryThumbnail(
                key: ValueKey('weekly-gallery-thumbnail-$index'),
                memory: memories[index],
                index: index,
                count: memories.length,
                selected: index == currentIndex,
                onTap: () => onSelect(index),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

final class _GalleryThumbnail extends StatelessWidget {
  const _GalleryThumbnail({
    required this.memory,
    required this.index,
    required this.count,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final _RehearsalMemory memory;
  final int index;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    selected: selected,
    label:
        '${_memoryFormatLabel(memory.format)}, ${selected ? 'selected' : 'not selected'}, ${index + 1} of $count',
    onTap: onTap,
    child: ExcludeSemantics(
      child: AnimatedScale(
        duration: keepersReduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 170),
        scale: selected ? 1.06 : .94,
        child: Material(
          color: KeepersColors.auraIvory,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: 62,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? KeepersColors.ink : KeepersColors.homeLine,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _MemoryThumbnail(memory: memory),
                  if (memory.format != _RehearsalFormat.photo)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Container(
                        margin: const EdgeInsets.all(5),
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: KeepersColors.auraIvory,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          memory.format == _RehearsalFormat.voice
                              ? Icons.graphic_eq_rounded
                              : Icons.notes_rounded,
                          size: 14,
                          color: KeepersColors.ink,
                        ),
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

final class _MemoryThumbnail extends StatelessWidget {
  const _MemoryThumbnail({required this.memory});

  final _RehearsalMemory memory;

  @override
  Widget build(BuildContext context) {
    final bytes = memory.primaryBytes;
    if (memory.format == _RehearsalFormat.photo && bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      );
    }
    final asset = memory.imageAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    }
    return ColoredBox(
      color: memory.color.withValues(alpha: .16),
      child: Icon(
        switch (memory.format) {
          _RehearsalFormat.photo => Icons.photo_outlined,
          _RehearsalFormat.voice => Icons.graphic_eq_rounded,
          _RehearsalFormat.text => Icons.notes_rounded,
        },
        color: memory.color,
        size: 26,
      ),
    );
  }
}

final class _VoiceBackdrop extends StatelessWidget {
  const _VoiceBackdrop({required this.memory, required this.playing});

  final _RehearsalMemory memory;
  final bool playing;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: memory.color.withValues(alpha: .14),
    child: Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(
          19,
          (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 3,
            height: 16 + math.sin(index * .82).abs() * (playing ? 62 : 38),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: memory.color.withValues(alpha: playing ? .95 : .7),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    ),
  );
}

final class _MemoryFallback extends StatelessWidget {
  const _MemoryFallback({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color.withValues(alpha: .13),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: color),
          const SizedBox(height: 12),
          KeepersText(
            label,
            style: const TextStyle(color: KeepersColors.inkMuted),
          ),
        ],
      ),
    ),
  );
}

final class _GalleryEcho extends StatelessWidget {
  const _GalleryEcho({required this.open, required this.onOpen});

  final bool open;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
    decoration: BoxDecoration(
      color: KeepersColors.auraIvory.withValues(alpha: .82),
      border: Border.all(color: KeepersColors.homeLine),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KeepersText(
          'An echo from before',
          style: TextStyle(
            color: KeepersColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (!open)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: KeepersColors.ink,
              minimumSize: const Size.fromHeight(46),
              side: const BorderSide(color: KeepersColors.homeActionLine),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onOpen,
            child: const KeepersText('Open echo'),
          )
        else
          const KeepersText(
            'A memory from another season rises beneath it.',
            style: TextStyle(
              color: KeepersColors.inkMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
      ],
    ),
  );
}

enum _KeepingDecision { keep, release }

final class _KeepingView extends StatefulWidget {
  const _KeepingView({
    required this.memories,
    required this.preview,
    required this.onDecision,
    required this.onComplete,
    super.key,
  });
  final List<_RehearsalMemory> memories;
  final bool preview;
  final WeeklyMemoryDecisionCallback? onDecision;
  final VoidCallback onComplete;

  @override
  State<_KeepingView> createState() => _KeepingViewState();
}

final class _KeepingViewState extends State<_KeepingView> {
  _KeepingDecision? _decision;
  int _memoryIndex = 0;
  int _resolvedCount = 0;
  bool _saving = false;
  String? _errorMessage;

  Future<void> _decide(_KeepingDecision decision) async {
    if (_saving || _decision != null) return;
    if (widget.preview) {
      setState(() => _decision = decision);
      return;
    }
    final memory = widget.memories[_memoryIndex];
    final metadata = memory.metadata;
    final onDecision = widget.onDecision;
    if (metadata == null || onDecision == null) {
      setState(() {
        _errorMessage = 'This decision could not be saved safely.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await onDecision(
        metadata,
        decision == _KeepingDecision.keep
            ? WeeklyMemoryDisposition.keep
            : WeeklyMemoryDisposition.release,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _decision = decision;
        _resolvedCount += 1;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = 'This decision was not saved. Try again.';
      });
    }
  }

  void _nextDecision() {
    if (!widget.preview && _resolvedCount >= widget.memories.length) {
      widget.onComplete();
      return;
    }
    setState(() {
      _memoryIndex = (_memoryIndex + 1) % widget.memories.length;
      _decision = null;
      _errorMessage = null;
    });
  }

  Widget _keepButton() => FilledButton.icon(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      backgroundColor: KeepersColors.brass,
      foregroundColor: KeepersColors.ground,
    ),
    onPressed: _saving ? null : () => unawaited(_decide(_KeepingDecision.keep)),
    icon: const Icon(Icons.keyboard_arrow_up_rounded),
    label: const KeepersText('Keep this memory'),
  );

  Widget _releaseButton() => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      foregroundColor: KeepersColors.ink,
      side: const BorderSide(color: KeepersColors.homeActionLine),
    ),
    onPressed: _saving
        ? null
        : () => unawaited(_decide(_KeepingDecision.release)),
    icon: const Icon(Icons.keyboard_arrow_down_rounded),
    label: const KeepersText('Release this memory'),
  );

  @override
  Widget build(BuildContext context) {
    final memory = widget.memories[_memoryIndex];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        children: [
          _VoteDots(preview: widget.preview),
          const SizedBox(height: 18),
          Semantics(
            label: 'Memory decision card. Swipe up to keep or down to release.',
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if (_saving) return;
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -350) {
                  unawaited(_decide(_KeepingDecision.keep));
                }
                if (velocity > 350) {
                  unawaited(_decide(_KeepingDecision.release));
                }
              },
              child: SizedBox(
                height: 300,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: -.08,
                      child: _DecisionCard(
                        color: widget
                            .memories[(_memoryIndex + 2) %
                                widget.memories.length]
                            .color,
                        offset: 14,
                      ),
                    ),
                    Transform.rotate(
                      angle: .055,
                      child: _DecisionCard(
                        color: widget
                            .memories[(_memoryIndex + 1) %
                                widget.memories.length]
                            .color,
                        offset: 7,
                      ),
                    ),
                    AnimatedContainer(
                      duration: keepersReduceMotion(context)
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
          if (_saving) ...[
            Semantics(
              liveRegion: true,
              label: 'Saving decision',
              child: const CircularProgressIndicator.adaptive(),
            ),
            const SizedBox(height: 12),
          ],
          if (_errorMessage case final error?) ...[
            Semantics(
              liveRegion: true,
              child: KeepersText(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: KeepersColors.inkMuted),
              ),
            ),
            const SizedBox(height: 12),
          ],
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
              onPressed: _nextDecision,
              child: KeepersText(
                !widget.preview && _resolvedCount >= widget.memories.length
                    ? 'Finish this week'
                    : 'Next decision',
              ),
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
            : 'Leaves your view after 30 days',
        textAlign: TextAlign.center,
        style: TextStyle(color: KeepersColors.cream.withValues(alpha: .68)),
      ),
    ],
  );
}

final class _VoteDots extends StatelessWidget {
  const _VoteDots({required this.preview});

  final bool preview;

  @override
  Widget build(BuildContext context) => Semantics(
    label: preview
        ? 'Rehearsal vote: one of one family members present'
        : 'This week: family decision',
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
              preview ? '1 PRESENT · PREVIEW ONLY' : 'THIS WEEK · KEEPING',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: KeepersColors.inkMuted,
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

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _formatWeeklyDate(DateTime value) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final date = value.toLocal();
  return '${date.day} ${months[date.month - 1]}, ${date.year}';
}
