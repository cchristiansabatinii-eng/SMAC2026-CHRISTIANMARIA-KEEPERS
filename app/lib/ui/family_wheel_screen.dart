import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keepers/design_system/observatory/motion_policy.dart';
import 'package:keepers/features/ceremony/presentation/pastel_flood.dart';
import 'package:keepers/features/ceremony/presentation/weekly_experience_card.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';
import 'package:keepers/ui/keepers_wordmark.dart';

enum FamilyPresence {
  near,
  far,
  away;

  String get label => switch (this) {
    FamilyPresence.near => 'near',
    FamilyPresence.far => 'far',
    FamilyPresence.away => 'away',
  };
}

/// Controls how Weekly applies the nearby-family requirement.
///
/// [temporaryAllowUntilProximityProxy] still computes the normal three-quarter
/// threshold, but treats that threshold as met until a real proximity signal
/// is available. Other presence UI continues to show only observed presence.
enum WeeklyPresencePolicy { enforceNearby, temporaryAllowUntilProximityProxy }

const _presenceToFamilyFieldGap = 16.0;

@immutable
final class FamilyWheelMember {
  const FamilyWheelMember({
    required this.id,
    required this.name,
    required this.color,
    required this.avatar,
    required this.contribution,
    required this.presence,
  });

  final String id;
  final String name;
  final Color color;
  final AvatarConfig avatar;
  final double? contribution;
  final FamilyPresence presence;
}

final class FamilyWheelScreen extends StatefulWidget {
  const FamilyWheelScreen({
    required this.familyName,
    required this.currentMemberName,
    this.currentMemberAvatar,
    required this.yourContribution,
    required this.members,
    required this.onCapture,
    required this.onMemberSelected,
    this.onCurrentMemberSelected,
    this.onAddMember,
    this.onNudgeMissingMembers,
    this.familyCode,
    this.onFamilyCodeTap,
    this.pendingJoinRequestName,
    this.onPendingJoinRequestTap,
    this.weeklyPhotoCount = 0,
    this.requiredWeeklyPhotos = 5,
    this.weeklyPresencePolicy = WeeklyPresencePolicy.enforceNearby,
    this.weeklyPreviewEnabled = false,
    this.onOpenWeeklyExperience,
    this.onPreviewWeeklyExperience,
    this.selectedDestination = KeepersNavDestination.wheel,
    this.enabledDestinations = const {KeepersNavDestination.wheel},
    this.onDestinationSelected,
    super.key,
  });

  final String familyName;
  final String currentMemberName;
  final AvatarConfig? currentMemberAvatar;
  final double yourContribution;
  final List<FamilyWheelMember> members;
  final VoidCallback onCapture;
  final VoidCallback? onCurrentMemberSelected;
  final VoidCallback? onAddMember;
  final VoidCallback? onNudgeMissingMembers;
  final String? familyCode;
  final VoidCallback? onFamilyCodeTap;
  final String? pendingJoinRequestName;
  final VoidCallback? onPendingJoinRequestTap;
  final int weeklyPhotoCount;
  final int requiredWeeklyPhotos;
  final WeeklyPresencePolicy weeklyPresencePolicy;
  final bool weeklyPreviewEnabled;
  final VoidCallback? onOpenWeeklyExperience;
  final VoidCallback? onPreviewWeeklyExperience;
  final ValueChanged<FamilyWheelMember> onMemberSelected;
  final KeepersNavDestination selectedDestination;
  final Set<KeepersNavDestination> enabledDestinations;
  final ValueChanged<KeepersNavDestination>? onDestinationSelected;

  @override
  State<FamilyWheelScreen> createState() => _FamilyWheelScreenState();
}

final class _FamilyWheelScreenState extends State<FamilyWheelScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ambientController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 32),
  );
  late final AnimationController _weeklyFloodController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  TransformationController _transformationController =
      TransformationController();
  Size? _configuredFamilyViewportSize;
  int? _configuredFamilyMemberCount;
  int _familyViewGeneration = 0;
  bool _reduceMotion = false;
  bool _isInteracting = false;
  bool _memberFocused = false;
  bool _weeklyFlooding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = keepersReduceMotion(context);
    if (_reduceMotion != next) {
      _reduceMotion = next;
      if (_reduceMotion) _ambientController.value = 0;
    }
    _syncAmbientMotion();
  }

  void _syncAmbientMotion() {
    if (_reduceMotion || _isInteracting || _memberFocused) {
      _ambientController.stop();
    } else if (!_ambientController.isAnimating) {
      _ambientController.repeat();
    }
  }

  void _startInteraction(ScaleStartDetails _) {
    setState(() => _isInteracting = true);
    _syncAmbientMotion();
  }

  void _endInteraction(ScaleEndDetails _) {
    setState(() => _isInteracting = false);
    _syncAmbientMotion();
  }

  void _setMemberFocused(bool focused) {
    if (_memberFocused == focused) return;
    setState(() => _memberFocused = focused);
    _syncAmbientMotion();
  }

  void _resetFamilyView() {
    final previousController = _transformationController;
    setState(() {
      _transformationController = TransformationController(
        _initialFamilyViewTransform(),
      );
      _familyViewGeneration += 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousController.dispose();
    });
  }

  Matrix4 _initialFamilyViewTransform() {
    final viewportSize = _configuredFamilyViewportSize;
    if (viewportSize == null) return Matrix4.identity();
    return FamilyWheelGeometry.initialTransform(
      viewportSize: viewportSize,
      memberCount: widget.members.length,
    );
  }

  void _configureFamilyView(Size viewportSize) {
    if (_configuredFamilyViewportSize == viewportSize &&
        _configuredFamilyMemberCount == widget.members.length) {
      return;
    }
    final previousController = _transformationController;
    _configuredFamilyViewportSize = viewportSize;
    _configuredFamilyMemberCount = widget.members.length;
    _transformationController = TransformationController(
      _initialFamilyViewTransform(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousController.dispose();
    });
  }

  void _openCapture() {
    _resetFamilyView();
    widget.onCapture();
  }

  void _openCurrentMember() {
    _resetFamilyView();
    (widget.onCurrentMemberSelected ?? widget.onCapture)();
  }

  void _openMember(FamilyWheelMember member) {
    _resetFamilyView();
    widget.onMemberSelected(member);
  }

  Future<void> _openWeeklyExperience(VoidCallback? open) async {
    if (open == null || _weeklyFlooding) return;
    if (_reduceMotion) {
      open();
      return;
    }
    setState(() => _weeklyFlooding = true);
    await _weeklyFloodController.forward(from: 0);
    if (!mounted) return;
    open();
    if (!mounted) return;
    setState(() => _weeklyFlooding = false);
    _weeklyFloodController.reset();
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _weeklyFloodController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nearMembers = widget.members
        .where((member) => member.presence == FamilyPresence.near)
        .toList(growable: false);
    final waitingMembers = widget.members
        .where((member) => member.presence != FamilyPresence.near)
        .toList(growable: false);
    final totalMembers = widget.members.length + 1;
    final nearbyCount = nearMembers.length + 1;
    final requiredPresentMembers = requiredWeeklyFamilyPresence(totalMembers);
    final weeklyPresentMemberCount = switch (widget.weeklyPresencePolicy) {
      WeeklyPresencePolicy.enforceNearby => nearbyCount,
      WeeklyPresencePolicy.temporaryAllowUntilProximityProxy => math.max(
        nearbyCount,
        requiredPresentMembers,
      ),
    };
    final weeklyReady =
        widget.weeklyPhotoCount >= widget.requiredWeeklyPhotos &&
        weeklyPresentMemberCount >= requiredPresentMembers;
    final needsAnotherMember = widget.members.isEmpty;
    final gatheringLabel = waitingMembers.isNotEmpty
        ? 'Ask ${_formatNames(waitingMembers.map((member) => member.name))} to come'
        : needsAnotherMember
        ? 'Ask family to come'
        : 'Everyone is here';
    final gatheringAction = waitingMembers.isNotEmpty
        ? widget.onNudgeMissingMembers
        : needsAnotherMember
        ? widget.onAddMember
        : null;
    final gatheringFirstColor = waitingMembers.isNotEmpty
        ? waitingMembers.first.color
        : needsAnotherMember
        ? KeepersColors.homeBlue
        : KeepersColors.homeGreen;
    final gatheringSecondColor = waitingMembers.length > 1
        ? waitingMembers[1].color
        : needsAnotherMember
        ? KeepersColors.homeMauve
        : KeepersColors.homeLine;
    _configureFamilyView(
      Size(
        MediaQuery.sizeOf(context).width,
        FamilyWheelGeometry.viewportHeight,
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: _weeklyFlooding,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            key: const ValueKey('family-wheel-system-ui'),
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
              systemNavigationBarColor: Colors.white,
              systemNavigationBarIconBrightness: Brightness.dark,
              systemNavigationBarDividerColor: Colors.transparent,
            ),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Column(
                children: [
                  _WheelHeader(
                    familyCode: widget.familyCode,
                    onFamilyCodeTap: widget.onFamilyCodeTap,
                  ),
                  Expanded(
                    child: CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 28),
                            child: _FamilyTitle(familyName: widget.familyName),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: _PresenceHero(
                            nearMembers: nearMembers,
                            nearbyCount: nearbyCount,
                            totalMembers: totalMembers,
                          ),
                        ),
                        if (widget.pendingJoinRequestName case final name?)
                          SliverToBoxAdapter(
                            child: _FamilyJoinRequestNotice(
                              name: name,
                              onTap: widget.onPendingJoinRequestTap,
                            ),
                          ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: _presenceToFamilyFieldGap),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: FamilyWheelGeometry.viewportHeight,
                            child: KeyedSubtree(
                              key: ValueKey(
                                'family-field-generation-$_familyViewGeneration',
                              ),
                              child: InteractiveViewer(
                                key: const ValueKey(
                                  'family-field-interactive-viewer',
                                ),
                                transformationController:
                                    _transformationController,
                                constrained: false,
                                alignment: Alignment.center,
                                minScale: .85,
                                maxScale: 1.45,
                                boundaryMargin: const EdgeInsets.all(72),
                                clipBehavior: Clip.none,
                                onInteractionStart: _startInteraction,
                                onInteractionEnd: _endInteraction,
                                child: Builder(
                                  builder: (context) {
                                    final fieldSize =
                                        FamilyWheelGeometry.fieldSizeFor(
                                          widget.members.length,
                                        );
                                    return SizedBox.fromSize(
                                      size: fieldSize,
                                      child: AnimatedBuilder(
                                        animation: _ambientController,
                                        builder: (context, _) =>
                                            FamilyWheelPainterHost(
                                              currentMemberName:
                                                  widget.currentMemberName,
                                              currentMemberAvatar:
                                                  widget.currentMemberAvatar,
                                              yourContribution:
                                                  widget.yourContribution,
                                              members: widget.members,
                                              pulse: _ambientController.value,
                                              motionEnabled: !_reduceMotion,
                                              onCurrentMemberSelected:
                                                  _openCurrentMember,
                                              onMemberSelected: _openMember,
                                              onAddMember: widget.onAddMember,
                                              onFocusChanged: _setMemberFocused,
                                            ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              KeyedSubtree(
                                key: const ValueKey('home-action-group'),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 28,
                                      ),
                                      child: WeeklyPhotoProgress(
                                        weeklyPhotoCount:
                                            widget.weeklyPhotoCount,
                                        requiredWeeklyPhotos:
                                            widget.requiredWeeklyPhotos,
                                        presentMemberCount:
                                            weeklyPresentMemberCount,
                                        requiredPresentMembers:
                                            requiredPresentMembers,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    _GatherPrompt(
                                      label: gatheringLabel,
                                      firstColor: gatheringFirstColor,
                                      secondColor: gatheringSecondColor,
                                      onTap: gatheringAction,
                                    ),
                                    const SizedBox(height: 12),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: WeeklyExperienceCard(
                                        presentMemberCount:
                                            weeklyPresentMemberCount,
                                        requiredPresentMembers:
                                            requiredPresentMembers,
                                        weeklyPhotoCount:
                                            widget.weeklyPhotoCount,
                                        requiredWeeklyPhotos:
                                            widget.requiredWeeklyPhotos,
                                        onOpen:
                                            widget.onOpenWeeklyExperience ==
                                                null
                                            ? null
                                            : () => unawaited(
                                                _openWeeklyExperience(
                                                  widget.onOpenWeeklyExperience,
                                                ),
                                              ),
                                        onPreview:
                                            widget.weeklyPreviewEnabled &&
                                                !weeklyReady &&
                                                widget.onPreviewWeeklyExperience !=
                                                    null
                                            ? () => unawaited(
                                                _openWeeklyExperience(
                                                  widget
                                                      .onPreviewWeeklyExperience,
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  KeepersBottomNav(
                    selected: widget.selectedDestination,
                    enabledDestinations: widget.enabledDestinations,
                    onCapture: _openCapture,
                    onSelected: widget.onDestinationSelected,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_weeklyFlooding)
          Positioned.fill(
            child: BlockSemantics(
              child: Semantics(
                container: true,
                liveRegion: true,
                label: 'Opening weekly experience',
                child: AbsorbPointer(
                  key: const ValueKey('weekly-pastel-flood'),
                  child: AnimatedBuilder(
                    animation: _weeklyFloodController,
                    builder: (context, _) => CustomPaint(
                      painter: PastelFloodPainter(
                        progress: _weeklyFloodController.value,
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

final class _GatherPrompt extends StatelessWidget {
  const _GatherPrompt({
    required this.label,
    required this.firstColor,
    required this.secondColor,
    required this.onTap,
  });

  final String label;
  final Color firstColor;
  final Color secondColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mediaWidth = MediaQuery.sizeOf(context).width;
    final view = View.of(context);
    final viewportWidth = mediaWidth > 0
        ? mediaWidth
        : view.physicalSize.width / view.devicePixelRatio;
    final availableWidth = math.max(0.0, viewportWidth - 56);
    final promptWidth = math.min(340.0, availableWidth * .9);

    return Padding(
      key: const ValueKey('family-gathering-prompt'),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Semantics(
        button: onTap != null,
        enabled: onTap != null,
        label: label,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Center(
            child: SizedBox(
              width: promptWidth,
              child: Material(
                color: KeepersColors.auraIvory,
                shape: const StadiumBorder(
                  side: BorderSide(
                    color: KeepersColors.homeActionLine,
                    width: 1.25,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  customBorder: const StadiumBorder(),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Stack(
                              children: [
                                _GatherDot(color: firstColor),
                                Positioned(
                                  left: 14,
                                  child: _GatherDot(color: secondColor),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: KeepersText(
                              label,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: KeepersColors.homeInk,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: onTap == null
                                ? KeepersColors.homeTaupe
                                : KeepersColors.homeActionLine,
                            size: 23,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _GatherDot extends StatelessWidget {
  const _GatherDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 23,
    height: 23,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .34),
      shape: BoxShape.circle,
      border: Border.all(color: KeepersColors.auraIvory, width: 2),
    ),
  );
}

final class _WheelHeader extends StatelessWidget {
  const _WheelHeader({required this.familyCode, required this.onFamilyCodeTap});

  final String? familyCode;
  final VoidCallback? onFamilyCodeTap;

  @override
  Widget build(BuildContext context) {
    final code = familyCode?.trim();
    return SizedBox(
      key: const ValueKey('keepers-home-brand-bar'),
      width: double.infinity,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 48,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Center(
                child: KeepersWordmark(
                  key: ValueKey('keepers-wordmark'),
                  width: 94,
                  height: 38,
                ),
              ),
              if (code != null && code.isNotEmpty)
                PositionedDirectional(
                  top: 0,
                  end: 16,
                  bottom: 0,
                  child: SizedBox(
                    key: const ValueKey('family-code-action'),
                    width: 116,
                    height: 48,
                    child: Semantics(
                      button: true,
                      enabled: onFamilyCodeTap != null,
                      label: 'Family code ${_spokenFamilyCode(code)}',
                      onTap: onFamilyCodeTap,
                      child: ExcludeSemantics(
                        child: Material(
                          color: Colors.transparent,
                          child: InkResponse(
                            onTap: onFamilyCodeTap,
                            containedInkWell: true,
                            highlightShape: BoxShape.rectangle,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  KeepersText(
                                    'Family code',
                                    maxLines: 1,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: KeepersColors.homeTaupe,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: .5,
                                          height: 1.1,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  KeepersText(
                                    code,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.fade,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: KeepersColors.homeInk,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1,
                                          height: 1.1,
                                        ),
                                  ),
                                ],
                              ),
                            ),
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

final class _FamilyJoinRequestNotice extends StatelessWidget {
  const _FamilyJoinRequestNotice({required this.name, required this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('family-join-request-notice'),
    padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
    child: Semantics(
      button: true,
      enabled: onTap != null,
      label: '$name wants to join',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: KeepersColors.homeTaupe,
                    size: 19,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: KeepersText(
                      '$name wants to join',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: KeepersColors.homeInk,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: KeepersColors.homeActionLine,
                    size: 23,
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

final class _PresenceHero extends StatelessWidget {
  const _PresenceHero({
    required this.nearMembers,
    required this.nearbyCount,
    required this.totalMembers,
  });

  final List<FamilyWheelMember> nearMembers;
  final int nearbyCount;
  final int totalMembers;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PresenceSentence(nearMembers: nearMembers),
        const SizedBox(height: 15),
        Semantics(
          label: '$nearbyCount of $totalMembers family members are here',
          child: ExcludeSemantics(
            child: SizedBox(
              height: 24,
              child: SingleChildScrollView(
                key: const ValueKey('family-presence-meter'),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    for (var index = 0; index < totalMembers; index++) ...[
                      _PresenceDot(
                        filled: index < nearbyCount,
                        color: index == 0
                            ? KeepersColors.homeGold
                            : index <= nearMembers.length
                            ? nearMembers[index - 1].color
                            : KeepersColors.homeTaupe,
                      ),
                      const SizedBox(width: 8),
                    ],
                    const SizedBox(width: 7),
                    KeepersText(
                      'OF ${_numberWord(totalMembers)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: KeepersColors.homeTaupe,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.5,
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

final class _FamilyTitle extends StatelessWidget {
  const _FamilyTitle({required this.familyName});

  final String familyName;

  @override
  Widget build(BuildContext context) {
    final familyLabel = _familyLabel(familyName);
    final displayFamilyName = familyLabel.toUpperCase();
    return Padding(
      key: const ValueKey('home-family-title'),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Semantics(
        container: true,
        label: familyLabel,
        child: ExcludeSemantics(
          child: KeepersText(
            displayFamilyName,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: KeepersType.heading.copyWith(color: KeepersColors.homeInk),
          ),
        ),
      ),
    );
  }
}

final class _PresenceSentence extends StatelessWidget {
  const _PresenceSentence({required this.nearMembers});

  final List<FamilyWheelMember> nearMembers;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (var index = 0; index < nearMembers.length; index++) {
      if (index > 0) spans.add(const TextSpan(text: ', '));
      spans.add(
        TextSpan(
          text: nearMembers[index].name.toUpperCase(),
          style: TextStyle(color: _profileInk(nearMembers[index].color)),
        ),
      );
    }
    if (nearMembers.isNotEmpty) spans.add(const TextSpan(text: ' AND '));
    spans.add(
      const TextSpan(
        text: 'YOU',
        style: TextStyle(color: KeepersColors.homeInk),
      ),
    );
    spans.add(const TextSpan(text: ' ARE HERE'));
    final semanticNames = [
      ...nearMembers.map((member) => member.name),
      'you',
    ].join(', ');
    return Semantics(
      label: '$semanticNames are here',
      child: ExcludeSemantics(
        child: KeepersText.rich(
          TextSpan(children: spans),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: KeepersColors.homeTaupe,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.05,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

final class _PresenceDot extends StatelessWidget {
  const _PresenceDot({required this.filled, required this.color});

  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: filled ? color : Colors.transparent,
      border: filled
          ? null
          : Border.all(color: KeepersColors.homeTaupe.withValues(alpha: .5)),
    ),
    child: const SizedBox.square(dimension: 8),
  );
}

final class FamilyWheelPainterHost extends StatefulWidget {
  const FamilyWheelPainterHost({
    required this.currentMemberName,
    this.currentMemberAvatar,
    required this.yourContribution,
    required this.members,
    required this.pulse,
    required this.onCurrentMemberSelected,
    required this.onMemberSelected,
    this.onAddMember,
    this.motionEnabled = true,
    this.onFocusChanged,
    super.key,
  });

  final String currentMemberName;
  final AvatarConfig? currentMemberAvatar;
  final double yourContribution;
  final List<FamilyWheelMember> members;
  final double pulse;
  final bool motionEnabled;
  final VoidCallback onCurrentMemberSelected;
  final ValueChanged<FamilyWheelMember> onMemberSelected;
  final VoidCallback? onAddMember;
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<FamilyWheelPainterHost> createState() => _FamilyWheelPainterHostState();
}

final class _FamilyWheelPainterHostState extends State<FamilyWheelPainterHost> {
  String? _focusedMemberId;
  late final Set<String> _knownMemberIds;
  final Set<String> _arrivingMemberIds = {};

  @override
  void initState() {
    super.initState();
    _knownMemberIds = widget.members.map((member) => member.id).toSet();
  }

  @override
  void didUpdateWidget(covariant FamilyWheelPainterHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentIds = widget.members.map((member) => member.id).toSet();
    _arrivingMemberIds
      ..retainAll(currentIds)
      ..addAll(currentIds.difference(_knownMemberIds));
    _knownMemberIds.addAll(currentIds);
  }

  Future<void> _focusMember(FamilyWheelMember member) async {
    if (_focusedMemberId != null) return;
    final duration = widget.motionEnabled
        ? const Duration(milliseconds: 220)
        : Duration.zero;
    widget.onFocusChanged?.call(true);
    setState(() => _focusedMemberId = member.id);
    if (duration != Duration.zero) await Future<void>.delayed(duration);
    if (!mounted) return;
    widget.onMemberSelected(member);
    setState(() => _focusedMemberId = null);
    widget.onFocusChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final fieldCenter = Offset(size.width * .5, size.height * .5);
      final positions = FamilyWheelGeometry.memberCenters(
        size: size,
        memberCount: widget.members.length + 1,
      );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          _InviteNode(center: positions.first, onTap: widget.onAddMember),
          for (var index = 0; index < widget.members.length; index++)
            _positionMember(
              index: index,
              center: positions[index + 1],
              fieldCenter: fieldCenter,
              member: widget.members[index],
            ),
          Positioned(
            left: size.width * .5 - 58,
            top: size.height * .5 - 53,
            width: 116,
            height: 160,
            child: _CurrentMemberNode(
              name: widget.currentMemberName,
              avatar:
                  widget.currentMemberAvatar ??
                  AvatarConfig.defaults(seed: 'you'),
              progress: widget.yourContribution,
              onTap: widget.onCurrentMemberSelected,
            ),
          ),
        ],
      );
    },
  );

  Widget _positionMember({
    required int index,
    required Offset center,
    required Offset fieldCenter,
    required FamilyWheelMember member,
  }) {
    final nodeSize = FamilyWheelGeometry.nodeSizeFor(index);
    const boxWidth = 96.0;
    final boxHeight = nodeSize + 38;
    final drift = _driftFor(index);
    var focusOffset = Offset.zero;
    if (_focusedMemberId != null && _focusedMemberId != member.id) {
      final vector = center - fieldCenter;
      final distance = vector.distance;
      if (distance > 0) focusOffset = vector / distance * 4;
    }
    final isFocused = _focusedMemberId == member.id;
    final memberNode = Transform.translate(
      key: ValueKey('family-member-motion-${member.id}'),
      offset: drift + focusOffset,
      child: TweenAnimationBuilder<double>(
        duration: widget.motionEnabled
            ? const Duration(milliseconds: 220)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        tween: Tween(end: isFocused ? 1.05 : 1),
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: _FamilyMemberNode(
          member: member,
          nodeSize: nodeSize,
          onTap: () => unawaited(_focusMember(member)),
        ),
      ),
    );
    return Positioned(
      key: ValueKey('family-wheel-member-${member.id}'),
      left: center.dx - boxWidth / 2,
      top: center.dy - nodeSize / 2,
      width: boxWidth,
      height: boxHeight,
      child: _arrivingMemberIds.contains(member.id)
          ? _MemberArrival(
              memberId: member.id,
              motionEnabled: widget.motionEnabled,
              onComplete: () {
                if (!mounted || !_arrivingMemberIds.remove(member.id)) return;
                setState(() {});
              },
              child: memberNode,
            )
          : memberNode,
    );
  }

  Offset _driftFor(int index) {
    if (!widget.motionEnabled) return Offset.zero;
    final phase = widget.pulse * math.pi * 2 + index * 1.37;
    final amplitude = 2.5 + index % 3 * 1.1;
    return Offset(
      math.sin(phase) * amplitude,
      math.cos(phase * .83 + index * .62) * amplitude * .72,
    );
  }
}

final class _MemberArrival extends StatefulWidget {
  const _MemberArrival({
    required this.memberId,
    required this.motionEnabled,
    required this.onComplete,
    required this.child,
  });

  final String memberId;
  final bool motionEnabled;
  final VoidCallback onComplete;
  final Widget child;

  @override
  State<_MemberArrival> createState() => _MemberArrivalState();
}

final class _MemberArrivalState extends State<_MemberArrival>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _arrival;
  var _didComplete = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.motionEnabled
          ? const Duration(milliseconds: 220)
          : const Duration(milliseconds: 90),
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_handleStatus);
    _arrival = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _didComplete) return;
    _didComplete = true;
    widget.onComplete();
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    key: ValueKey('family-member-arrival-${widget.memberId}'),
    animation: _arrival,
    child: widget.child,
    builder: (context, child) => Transform.translate(
      key: ValueKey('family-member-arrival-offset-${widget.memberId}'),
      offset: widget.motionEnabled
          ? Offset(0, (1 - _arrival.value) * 10)
          : Offset.zero,
      child: Opacity(
        key: ValueKey('family-member-arrival-opacity-${widget.memberId}'),
        opacity: _arrival.value,
        child: child,
      ),
    ),
  );
}

abstract final class FamilyWheelGeometry {
  static const viewportHeight = 318.0;
  static const _innerCapacity = 5;
  static const _outerCapacity = 10;
  static const _sparseRadius = 122.0;
  static const _innerRadius = 148.0;
  static const _ringGap = 158.0;

  static Matrix4 initialTransform({
    required Size viewportSize,
    required int memberCount,
  }) {
    if (_ringCount(memberCount + 1) == 1) return Matrix4.identity();
    final fieldSize = fieldSizeFor(memberCount);
    return Matrix4.translationValues(
      (viewportSize.width - fieldSize.width) / 2,
      (viewportSize.height - fieldSize.height) / 2,
      0,
    );
  }

  static Size fieldSizeFor(int memberCount) {
    final itemCount = memberCount + 1;
    final rings = _ringCount(itemCount);
    final outerRadius = _innerRadius + math.max(0, rings - 1) * _ringGap;
    if (rings == 1) return const Size(360, viewportHeight);
    final extent = (outerRadius + 74) * 2;
    return Size.square(extent);
  }

  static List<Offset> memberCenters({
    required Size size,
    required int memberCount,
  }) {
    if (memberCount <= 0) return const [];
    final center = Offset(size.width / 2, size.height / 2);
    if (memberCount <= _innerCapacity) {
      return List<Offset>.unmodifiable(
        _sparseConstellation(center: center, itemCount: memberCount),
      );
    }
    final result = <Offset>[];
    var remaining = memberCount;
    var start = 0;
    for (var ring = 0; remaining > 0; ring += 1) {
      final capacity = _capacityForRing(ring);
      final count = math.min(remaining, capacity);
      final isSparseInnerRing = ring == 0 && count <= 2;
      final radius = isSparseInnerRing
          ? _sparseRadius
          : _innerRadius + ring * _ringGap;
      final phase = isSparseInnerRing
          ? math.pi
          : ring == 0 && count == _innerCapacity
          ? -math.pi * 7 / 9
          : -math.pi / 2 + (ring.isOdd ? math.pi / count : 0);
      for (var index = 0; index < count; index += 1) {
        final angle = phase + math.pi * 2 * index / count;
        result.add(
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
        );
      }
      start += count;
      remaining = memberCount - start;
    }
    return List<Offset>.unmodifiable(result);
  }

  static List<Offset> _sparseConstellation({
    required Offset center,
    required int itemCount,
  }) {
    final left = center.dx - 130;
    final right = center.dx + 130;
    final upper = center.dy - 104;
    final lower = center.dy + 83;
    return switch (itemCount) {
      1 => [Offset(left, center.dy)],
      2 => [Offset(left, center.dy), Offset(right, center.dy)],
      3 => [Offset(left, upper), Offset(right, upper), Offset(left, lower)],
      4 => [
        Offset(left, upper),
        Offset(right, upper),
        Offset(left, lower),
        Offset(right, lower),
      ],
      5 => [
        Offset(left, upper),
        Offset(right, upper),
        Offset(left, lower),
        Offset(center.dx, center.dy - 132),
        Offset(right, lower),
      ],
      _ => throw StateError('Sparse constellation supports up to five items.'),
    };
  }

  static int _ringCount(int itemCount) {
    var rings = 0;
    var remaining = itemCount;
    while (remaining > 0) {
      remaining -= _capacityForRing(rings);
      rings += 1;
    }
    return math.max(1, rings);
  }

  static int _capacityForRing(int ring) => switch (ring) {
    0 => _innerCapacity,
    1 => _outerCapacity,
    _ => _outerCapacity + (ring - 1) * 6,
  };

  static double nodeSizeFor(int index) => switch (index % 8) {
    0 => 62,
    1 => 57,
    2 => 52,
    3 => 54,
    4 => 58,
    5 => 50,
    6 => 53,
    _ => 51,
  };
}

final class _CurrentMemberNode extends StatelessWidget {
  const _CurrentMemberNode({
    required this.name,
    required this.avatar,
    required this.progress,
    required this.onTap,
  });

  final String name;
  final AvatarConfig avatar;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final percent = (progress.clamp(0, 1) * 100).round();
    return Semantics(
      button: true,
      label: 'You, $name, $percent% sealed',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkResponse(
                onTap: onTap,
                radius: 55,
                customBorder: const CircleBorder(),
                child: CustomPaint(
                  painter: _ProgressRingPainter(
                    color: KeepersColors.homeGold,
                    progress: progress,
                    strokeWidth: 3.2,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: SizedBox.square(
                      dimension: 92,
                      child: _ProfileFloatingSurface(
                        profileId: 'you',
                        accent: KeepersColors.homeGold,
                        child: KeepersAvatar(
                          key: const ValueKey('family-avatar-you'),
                          config: avatar,
                          size: 71,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            KeepersText(
              'YOU',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _profileInk(KeepersColors.homeGold),
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _FamilyMemberNode extends StatelessWidget {
  const _FamilyMemberNode({
    required this.member,
    required this.nodeSize,
    required this.onTap,
  });

  final FamilyWheelMember member;
  final double nodeSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final contribution = member.contribution;
    final percent = contribution == null
        ? null
        : (contribution.clamp(0, 1) * 100).round();
    final opacity = switch (member.presence) {
      FamilyPresence.near => 1.0,
      FamilyPresence.far => .9,
      FamilyPresence.away => .76,
    };
    return Semantics(
      button: true,
      label: percent == null
          ? '${member.name}, ${member.presence.label}'
          : '${member.name}, ${member.presence.label}, $percent% sealed',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: opacity,
              child: SizedBox.square(
                dimension: nodeSize + 12,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkResponse(
                          onTap: onTap,
                          radius: nodeSize / 2 + 12,
                          customBorder: const CircleBorder(),
                          child: contribution == null
                              ? Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: _ProfileFloatingSurface(
                                    profileId: member.id,
                                    accent: member.color,
                                    child: KeepersAvatar(
                                      key: ValueKey(
                                        'family-avatar-${member.id}',
                                      ),
                                      config: member.avatar,
                                      size: nodeSize * .72,
                                    ),
                                  ),
                                )
                              : CustomPaint(
                                  painter: _ProgressRingPainter(
                                    color: member.color,
                                    progress: contribution,
                                    strokeWidth: 3,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: _ProfileFloatingSurface(
                                      profileId: member.id,
                                      accent: member.color,
                                      child: KeepersAvatar(
                                        key: ValueKey(
                                          'family-avatar-${member.id}',
                                        ),
                                        config: member.avatar,
                                        size: nodeSize * .72,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    if (member.presence == FamilyPresence.near)
                      Positioned(
                        right: 0,
                        bottom: 3,
                        child: Container(
                          width: 15,
                          height: 15,
                          decoration: BoxDecoration(
                            color: member.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: KeepersColors.auraIvory,
                              width: 2.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            KeepersText(
              member.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _profileInk(member.color),
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ProfileFloatingSurface extends StatelessWidget {
  const _ProfileFloatingSurface({
    required this.profileId,
    required this.accent,
    required this.child,
  });

  final String profileId;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) => Ink(
    key: ValueKey('family-profile-surface-$profileId'),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Color.alphaBlend(
        accent.withValues(alpha: .1),
        KeepersColors.auraIvory,
      ),
      border: Border.all(
        color: Color.alphaBlend(
          accent.withValues(alpha: .18),
          KeepersColors.homeLine,
        ),
        width: 1.1,
      ),
    ),
    child: Center(child: child),
  );
}

Color _profileInk(Color accent) =>
    Color.alphaBlend(KeepersColors.homeInk.withValues(alpha: .5), accent);

final class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.color,
    required this.progress,
    required this.strokeWidth,
  });

  final Color color;
  final double progress;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = KeepersColors.homeLine.withValues(alpha: .68)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.progress != progress ||
      oldDelegate.strokeWidth != strokeWidth;
}

final class _InviteNode extends StatelessWidget {
  const _InviteNode({required this.center, required this.onTap});

  final Offset center;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Positioned(
    left: center.dx - 44,
    top: center.dy - 41,
    width: 88,
    height: 102,
    child: Semantics(
      button: true,
      enabled: onTap != null,
      label: 'Invite family',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkResponse(
                key: const ValueKey('family-invite-node-action'),
                onTap: onTap,
                radius: 38,
                customBorder: const CircleBorder(),
                child: CustomPaint(
                  painter: const _DashedCirclePainter(),
                  child: const SizedBox.square(
                    dimension: 58,
                    child: Icon(
                      Icons.add_rounded,
                      color: KeepersColors.homeTaupe,
                      size: 31,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            KeepersText(
              'INVITE',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: KeepersColors.homeTaupe,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.1,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const dash = .16;
    const gap = .09;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = KeepersColors.homeTaupe.withValues(alpha: .5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var start = 0.0; start < math.pi * 2; start += dash + gap) {
      canvas.drawArc(rect.deflate(2), start, dash, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) => false;
}

String _formatNames(Iterable<String> names) {
  final list = names.toList(growable: false);
  if (list.isEmpty) return '';
  if (list.length == 1) return list.first;
  if (list.length == 2) return '${list.first} & ${list.last}';
  return '${list.take(list.length - 1).join(', ')} & ${list.last}';
}

String _familyLabel(String value) {
  final name = _sentenceCase(value);
  if (name.isEmpty) return 'Family';
  return name.endsWith(' family') ? name : '$name family';
}

String _sentenceCase(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  final runes = trimmed.runes.toList(growable: false);
  return '${String.fromCharCode(runes.first).toUpperCase()}'
      '${String.fromCharCodes(runes.skip(1)).toLowerCase()}';
}

String _spokenFamilyCode(String value) => value
    .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
    .toUpperCase()
    .split('')
    .join(' ');

String _numberWord(int number) => switch (number) {
  0 => 'ZERO',
  1 => 'ONE',
  2 => 'TWO',
  3 => 'THREE',
  4 => 'FOUR',
  5 => 'FIVE',
  6 => 'SIX',
  7 => 'SEVEN',
  8 => 'EIGHT',
  9 => 'NINE',
  10 => 'TEN',
  _ => '$number',
};
