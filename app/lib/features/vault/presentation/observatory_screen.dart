import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/archive/presentation/archive_screen.dart';
import 'package:keepers/features/capture/application/capture_providers.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/capture/presentation/capture_sheet.dart';
import 'package:keepers/features/ceremony/presentation/ceremony_screen.dart';
import 'package:keepers/features/ceremony/presentation/weekly_waiting_room_screen.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_code_controller.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/family_join_requests_controller.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/family/data/invite_share_service.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/family/presentation/family_invite_sheet.dart';
import 'package:keepers/features/family/presentation/family_join_request_sheet.dart';
import 'package:keepers/features/locks/presentation/locks_screen.dart';
import 'package:keepers/features/members/presentation/member_page_screen.dart';
import 'package:keepers/features/members/presentation/your_memories_screen.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/onboarding/presentation/account_conflict_screen.dart';
import 'package:keepers/features/settings/presentation/settings_screen.dart';
import 'package:keepers/features/vault/application/vault_providers.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/features/vault/presentation/memory_viewer.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/sync/weekly_family_presence_provider.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/family_wheel_screen.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';
import 'package:keepers/ui/keepers_destination_scaffold.dart';

typedef CaptureSheetLauncher = Future<EntryMetadata?> Function(
  BuildContext context,
);

enum _WeeklyExperienceMode { waiting, live }

typedef WeeklyMemoryLoader = Future<List<OpenedMemory>> Function(
  List<VaultEntryMetadata> entries,
);

final class WeeklyMemoryLoadFailure implements Exception {
  const WeeklyMemoryLoadFailure({
    this.attemptedCount = 0,
    this.openedCount = 0,
    this.openedPhotoCount = 0,
    this.unavailableCount = 0,
  });

  final int attemptedCount;
  final int openedCount;
  final int openedPhotoCount;
  final int unavailableCount;

  @override
  String toString() =>
      'WeeklyMemoryLoadFailure('
      'attempted: $attemptedCount, opened: $openedCount, '
      'photos: $openedPhotoCount, unavailable: $unavailableCount)';
}

@visibleForTesting
Future<List<OpenedMemory>> loadWeeklyMemoriesSequentially(
  Iterable<VaultEntryMetadata> entries,
  Future<MemoryOpenResult> Function(VaultEntryMetadata metadata) open, {
  int minimumOpenedPhotos = 0,
}) async {
  final opened = <OpenedMemory>[];
  var attemptedCount = 0;
  var unavailableCount = 0;
  try {
    for (final entry in entries) {
      attemptedCount += 1;
      final result = await open(entry);
      switch (result) {
        case OpenedMemory():
          opened.add(result);
        case UnavailableMemory():
          unavailableCount += 1;
          continue;
      }
    }
    final openedPhotoCount = opened
        .where((memory) => memory.metadata.format == MemoryFormat.photo)
        .length;
    if ((attemptedCount > 0 && opened.isEmpty) ||
        openedPhotoCount < minimumOpenedPhotos) {
      throw WeeklyMemoryLoadFailure(
        attemptedCount: attemptedCount,
        openedCount: opened.length,
        openedPhotoCount: openedPhotoCount,
        unavailableCount: unavailableCount,
      );
    }
    return List<OpenedMemory>.unmodifiable(opened);
  } on WeeklyMemoryLoadFailure {
    _clearOpenedPrimaryBytes(opened);
    rethrow;
  } on Object {
    _clearOpenedPrimaryBytes(opened);
    throw WeeklyMemoryLoadFailure(
      attemptedCount: attemptedCount,
      openedCount: opened.length,
      openedPhotoCount: opened
          .where((memory) => memory.metadata.format == MemoryFormat.photo)
          .length,
      unavailableCount: unavailableCount,
    );
  }
}

void _clearOpenedPrimaryBytes(Iterable<OpenedMemory> opened) {
  for (final memory in opened) {
    final bytes = memory.payload.primaryBytes;
    bytes?.fillRange(0, bytes.length, 0);
  }
}

/// Owns decrypted Weekly media for exactly one on-screen experience.
///
/// A late load is cleared too, so closing while decryption is in flight cannot
/// leave private image or voice bytes retained by the completed future.
@visibleForTesting
final class WeeklyMemoryPayloadLease {
  List<OpenedMemory>? _opened;
  bool _released = false;

  Future<List<OpenedMemory>> own(Future<List<OpenedMemory>> loading) async {
    final opened = await loading;
    if (_released) {
      _clearOpenedPrimaryBytes(opened);
    } else {
      _opened = opened;
    }
    return opened;
  }

  void release() {
    if (_released) return;
    _released = true;
    final opened = _opened;
    _opened = null;
    if (opened != null) _clearOpenedPrimaryBytes(opened);
  }
}

final class ObservatoryScreen extends ConsumerStatefulWidget {
  const ObservatoryScreen({
    required this.identity,
    required this.onUseAnotherAccount,
    this.showCapture,
    this.weeklyMemoryLoader,
    super.key,
  });

  final LocalIdentity identity;
  final Future<void> Function() onUseAnotherAccount;
  final CaptureSheetLauncher? showCapture;
  final WeeklyMemoryLoader? weeklyMemoryLoader;

  @override
  ConsumerState<ObservatoryScreen> createState() => _ObservatoryScreenState();
}

final class _ObservatoryScreenState extends ConsumerState<ObservatoryScreen>
    with WidgetsBindingObserver {
  static const _activationRefreshInterval = Duration(minutes: 5);

  bool _captureInFlight = false;
  bool _nudgeInFlight = false;
  KeepersNavDestination _selectedDestination = KeepersNavDestination.wheel;
  _WeeklyExperienceMode? _weeklyExperienceMode;
  Future<List<OpenedMemory>>? _weeklyMemories;
  WeeklyMemoryPayloadLease? _weeklyPayloadLease;
  Timer? _weeklyPresenceExpiryTimer;
  DateTime? _weeklyPresenceExpiryAt;
  bool _weeklyPresenceSessionActive = false;
  bool _weeklyRosterRefreshInFlight = false;
  bool _appIsForeground = true;
  WeeklyFamilyPresenceSessionActions? _activeWeeklyPresenceActions;
  var _weeklyRosterRefreshEpoch = 0;  final Set<String> _awaitingActivationMemberIds = {};
  Timer? _activationRefreshTimer;
  String? _activationFamilyId;
  String? _activationAccountId;
  int? _activationRefreshInFlightEpoch;
  var _activationEpoch = 0;

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _appIsForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _invalidateWeeklyRosterRefresh();
    _stopActivationReconciliation();
    _stopWeeklyPresence();
    _releaseWeeklyPayloads();
    _cancelWeeklyPresenceExpiry();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ObservatoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity.familyId != widget.identity.familyId ||
        oldWidget.identity.accountId != widget.identity.accountId ||
        oldWidget.identity.memberId != widget.identity.memberId) {
      _stopActivationReconciliation();
      _invalidateWeeklyRosterRefresh();
      _stopWeeklyPresence();
      _cancelWeeklyPresenceExpiry();
      _releaseWeeklyPayloads();
      _weeklyExperienceMode = null;
      _weeklyMemories = null;
      _selectedDestination = KeepersNavDestination.wheel;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setAppForeground(true);
      _startWeeklyPresenceIfNeeded();
      ref.invalidate(vaultEntriesProvider);
      unawaited(_refreshRoster());
      unawaited(
        ref
            .read(
              familyCodeControllerProvider(widget.identity.familyId).notifier,
            )
            .load(),
      );
      unawaited(ref.read(familyJoinCompletionRecoveryProvider)());
      unawaited(
        ref
            .read(
              familyJoinRequestsControllerProvider(widget.identity.familyId)
                  .notifier,
            )
            .refresh(),
      );
    } else {
      _setAppForeground(false);
      _stopWeeklyPresence();
    }
  }

  void _setAppForeground(bool isForeground) {
    if (_appIsForeground == isForeground) return;
    if (!mounted) {
      _appIsForeground = isForeground;
      return;
    }
    setState(() => _appIsForeground = isForeground);
  }

  Future<void> _refreshRoster() =>
      ref.read(familyRosterRefreshProvider(widget.identity.familyId))();

  Future<void> _capture() async {
    if (_captureInFlight) return;
    setState(() => _captureInFlight = true);
    try {
      final saved = await (widget.showCapture ?? CaptureSheet.show)(context);
      if (saved == null || !mounted) return;
      ref.invalidate(vaultEntriesProvider);
      final entries = await ref.read(vaultEntriesProvider.future);
      if (!mounted || !entries.any((entry) => entry.id == saved.id)) return;
      await HapticFeedback.selectionClick();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted) await HapticFeedback.selectionClick();
    } on Object {
      // Capture and refresh surfaces own their retry states.
    } finally {
      if (mounted) setState(() => _captureInFlight = false);
    }
  }

  void _selectDestination(KeepersNavDestination destination) {
    if (_selectedDestination == destination) {
      if (destination != KeepersNavDestination.ceremony ||
          _weeklyExperienceMode == null) {
        return;
      }
      _invalidateWeeklyRosterRefresh();
      _stopWeeklyPresence();
      _releaseWeeklyPayloads();
      setState(() {
        _weeklyExperienceMode = null;
        _weeklyMemories = null;
      });
      return;
    }
    _invalidateWeeklyRosterRefresh();
    _stopWeeklyPresence();
    _releaseWeeklyPayloads();
    setState(() {
      _selectedDestination = destination;
      _weeklyExperienceMode = null;
      _weeklyMemories = null;
    });
  }

  void _enterWeeklyWaitingRoom() {
    _releaseWeeklyPayloads();
    final refreshEpoch = ++_weeklyRosterRefreshEpoch;
    setState(() {
      _weeklyExperienceMode = _WeeklyExperienceMode.waiting;
      _weeklyMemories = null;
      _weeklyRosterRefreshInFlight = true;
      _selectedDestination = KeepersNavDestination.ceremony;
    });
    _startWeeklyPresenceIfNeeded();
    unawaited(_refreshWaitingRoomRoster(refreshEpoch));
  }

  Future<void> _refreshWaitingRoomRoster(int refreshEpoch) async {
    try {
      await _refreshRoster();
    } on Object {
      // The roster controller maps ordinary cloud and persistence failures to
      // its cached-roster state. An injected boundary may still throw; cached
      // membership remains the honest offline fallback in that case too.
    } finally {
      final isCurrentWaitingRoom =
          mounted &&
          refreshEpoch == _weeklyRosterRefreshEpoch &&
          _weeklyExperienceMode == _WeeklyExperienceMode.waiting;
      if (isCurrentWaitingRoom) {
        setState(() => _weeklyRosterRefreshInFlight = false);
      }
    }
  }

  void _invalidateWeeklyRosterRefresh() {
    _weeklyRosterRefreshEpoch += 1;
    _weeklyRosterRefreshInFlight = false;
  }

  void _openWeeklyExperience(List<VaultEntryMetadata> entries) {
    if (_weeklyExperienceMode != _WeeklyExperienceMode.waiting ||
        _weeklyPayloadLease != null) {
      return;
    }
    _invalidateWeeklyRosterRefresh();
    _stopWeeklyPresence();
    _releaseWeeklyPayloads();
    final lease = WeeklyMemoryPayloadLease();
    _weeklyPayloadLease = lease;
    final memories = lease.own(_loadWeeklyMemories(entries));
    setState(() {
      _weeklyExperienceMode = _WeeklyExperienceMode.live;
      _weeklyMemories = memories;
      _selectedDestination = KeepersNavDestination.ceremony;
    });
  }

  bool _startWeeklyExperience() {
    if (_weeklyExperienceMode != _WeeklyExperienceMode.waiting ||
        _weeklyPayloadLease != null ||
        _weeklyRosterRefreshInFlight) {
      return false;
    }

    final currentEntriesState = ref.read(vaultEntriesProvider);
    final currentEntries =
        currentEntriesState.isLoading || currentEntriesState.hasError
        ? null
        : currentEntriesState.asData?.value;
    final freshNow = ref.read(utcNowProvider)().toUtc();
    final freshWeeklyEntries = currentEntries == null
        ? const <VaultEntryMetadata>[]
        : _weeklyEntriesAt(currentEntries, freshNow);
    final freshPhotoCount = freshWeeklyEntries
        .where((entry) => entry.format == MemoryFormat.photo)
        .length;

    if (freshPhotoCount < 5) {
      // Rebuild with the fresh clock so a room left open across the weekly
      // boundary fails closed and explains that progress changed.
      setState(() {});
      return false;
    }

    final rosterState = ref.read(
      familyRosterProvider(widget.identity.familyId),
    );
    if (!rosterState.hasLoadedLocal || rosterState.isRefreshing) {
      setState(() {});
      return false;
    }
    final trustedNearbyMemberIds = ref
        .read(weeklyFamilyPresenceProvider(widget.identity.familyId))
        .trustedNearbyMemberIds(at: freshNow);
    final attendance = WeeklyWaitingRoomAttendance.fromMemberIds(
      rosterMemberIds: rosterState.hasLoadedLocal
          ? rosterState.members.map((member) => member.id)
          : const <String>[],
      presentMemberIds: trustedNearbyMemberIds,
      currentMemberId: widget.identity.memberId,
    );
    if (!attendance.canStart) {
      // Rebuild so an observation that expired while this room was open is
      // immediately reflected in the member cards and attendance copy.
      setState(() {});
      return false;
    }

    _openWeeklyExperience(freshWeeklyEntries);
    return true;
  }

  void _releaseWeeklyPayloads() {
    _weeklyPayloadLease?.release();
    _weeklyPayloadLease = null;
  }

  void _scheduleWeeklyPresenceExpiry(
    WeeklyFamilyPresenceSnapshot snapshot,
    DateTime now,
  ) {
    final expiryAt = snapshot.nextExpiryAt(at: now);
    if (expiryAt == null) {
      _cancelWeeklyPresenceExpiry();
      return;
    }
    final delay = expiryAt.difference(now.toUtc());
    if (delay <= Duration.zero) {
      _cancelWeeklyPresenceExpiry();
      return;
    }
    if (_weeklyPresenceExpiryTimer?.isActive == true &&
        _weeklyPresenceExpiryAt == expiryAt) {
      return;
    }

    _cancelWeeklyPresenceExpiry();
    _weeklyPresenceExpiryAt = expiryAt;
    _weeklyPresenceExpiryTimer = Timer(delay, () {
      _weeklyPresenceExpiryTimer = null;
      _weeklyPresenceExpiryAt = null;
      if (mounted) setState(() {});
    });
  }

  void _cancelWeeklyPresenceExpiry() {
    _weeklyPresenceExpiryTimer?.cancel();
    _weeklyPresenceExpiryTimer = null;
    _weeklyPresenceExpiryAt = null;
  }

  void _startWeeklyPresenceIfNeeded() {
    if (!_appIsForeground ||
        _weeklyExperienceMode != _WeeklyExperienceMode.waiting ||
        _weeklyPresenceSessionActive) {
      return;
    }
    final rosterState = ref.read(
      familyRosterProvider(widget.identity.familyId),
    );
    if (!rosterState.hasLoadedLocal) return;
    final actions = ref.read(
      weeklyFamilyPresenceSessionActionsProvider(widget.identity.familyId),
    );
    _weeklyPresenceSessionActive = true;
    _activeWeeklyPresenceActions = actions;
    unawaited(
      actions.start(
        identity: widget.identity,
        rosterMemberIds: rosterState.members
            .where((member) => member.familyId == widget.identity.familyId)
            .map((member) => member.id),
      ),
    );
  }

  void _stopWeeklyPresence() {
    if (!_weeklyPresenceSessionActive) return;
    _weeklyPresenceSessionActive = false;
    final actions = _activeWeeklyPresenceActions;
    _activeWeeklyPresenceActions = null;
    if (actions != null) unawaited(actions.stop());
  }

  Future<List<OpenedMemory>> _loadWeeklyMemories(
    List<VaultEntryMetadata> entries,
  ) async {
    final injectedLoader = widget.weeklyMemoryLoader;
    if (injectedLoader != null) return injectedLoader(entries);
    final controller = await ref.read(vaultControllerProvider.future);
    return loadWeeklyMemoriesSequentially(
      entries,
      controller.open,
      minimumOpenedPhotos: 5,
    );
  }

  Future<void> _resolveWeeklyMemory(
    VaultEntryMetadata metadata,
    WeeklyMemoryDisposition disposition,
  ) async {
    final database = await ref.read(databaseProvider.future);
    final updated = await ref
        .read(vaultRepositoryProvider)
        .resolveWeeklyEntry(
          database,
          entry: metadata,
          disposition: disposition,
          decidedAt: ref.read(utcNowProvider)().toUtc(),
        );
    if (!updated) {
      throw StateError('The Weekly memory was already resolved.');
    }
    ref.invalidate(vaultEntriesProvider);
  }

  Future<void> _addMember() async {
    await FamilyInviteSheet.show(context, familyId: widget.identity.familyId);
    if (mounted) await _refreshRoster();
  }

  Future<void> _openJoinRequest(PendingFamilyJoinRequest request) =>
      FamilyJoinRequestSheet.show(
        context,
        familyId: widget.identity.familyId,
        request: request,
      );

  void _handleJoinRequestsChanged(
    FamilyJoinRequestsState? previous,
    FamilyJoinRequestsState next,
  ) {
    final previousCandidates =
        previous?.activationCandidateMemberIds ?? const <String>{};
    final newCandidates = next.activationCandidateMemberIds.where(
      (memberId) => !previousCandidates.contains(memberId),
    );
    if (newCandidates.isNotEmpty) {
      _beginActivationReconciliation(newCandidates);
    }
  }

  void _beginActivationReconciliation(
    Iterable<String> activationCandidateMemberIds,
  ) {
    final identityAccountId = widget.identity.accountId;
    final rosterAccountId = ref
        .read(cloudFamilyGatewayProvider)
        .authenticatedAccountId;
    final requestsAccountId = ref
        .read(familyCodeJoinGatewayProvider)
        .authenticatedAccountId;
    if (identityAccountId != rosterAccountId ||
        identityAccountId != requestsAccountId) {
      _stopActivationReconciliation();
      return;
    }

    final familyId = widget.identity.familyId;
    if (_activationFamilyId != familyId ||
        _activationAccountId != identityAccountId) {
      _stopActivationReconciliation();
      _activationFamilyId = familyId;
      _activationAccountId = identityAccountId;
    }
    _awaitingActivationMemberIds.addAll(activationCandidateMemberIds);
    _pruneActivatedMembers(ref.read(familyRosterProvider(familyId)).members);
    if (_awaitingActivationMemberIds.isEmpty) return;

    _activationRefreshTimer?.cancel();
    _activationRefreshTimer = null;
    final epoch = _activationEpoch;
    unawaited(_refreshAwaitingActivationRoster());
    _scheduleActivationRefresh(epoch);
  }

  void _scheduleActivationRefresh(int epoch) {
    if (epoch != _activationEpoch ||
        _activationRefreshTimer != null ||
        _awaitingActivationMemberIds.isEmpty ||
        !_activationScopeIsCurrent) {
      return;
    }
    late final Timer timer;
    timer = Timer(_activationRefreshInterval, () {
      if (!identical(_activationRefreshTimer, timer)) return;
      _activationRefreshTimer = null;
      if (epoch != _activationEpoch) return;
      if (!_activationScopeIsCurrent) {
        _stopActivationReconciliation();
        return;
      }
      unawaited(_refreshAwaitingActivationRoster());
      _scheduleActivationRefresh(epoch);
    });
    _activationRefreshTimer = timer;
  }

  Future<void> _refreshAwaitingActivationRoster() async {
    final epoch = _activationEpoch;
    if (_activationRefreshInFlightEpoch == epoch ||
        _awaitingActivationMemberIds.isEmpty ||
        !_activationScopeIsCurrent) {
      return;
    }
    _activationRefreshInFlightEpoch = epoch;
    try {
      await _refreshRoster();
    } on Object {
      // The roster state owns its retry affordance. This refresh is only an
      // activation hint after an authoritative approved/installed decision.
    } finally {
      if (_activationRefreshInFlightEpoch == epoch) {
        _activationRefreshInFlightEpoch = null;
      }
      if (mounted && epoch == _activationEpoch && _activationScopeIsCurrent) {
        _pruneActivatedMembers(
          ref.read(familyRosterProvider(widget.identity.familyId)).members,
        );
      }
    }
  }

  bool get _activationScopeIsCurrent {
    if (!mounted || _activationFamilyId != widget.identity.familyId) {
      return false;
    }
    final accountId = _activationAccountId;
    return widget.identity.accountId == accountId &&
        ref.read(cloudFamilyGatewayProvider).authenticatedAccountId ==
            accountId &&
        ref.read(familyCodeJoinGatewayProvider).authenticatedAccountId ==
            accountId;
  }

  void _handleRosterChanged(
    FamilyRosterState? previous,
    FamilyRosterState next,
  ) {
    if (_weeklyPresenceSessionActive &&
        _weeklyExperienceMode == _WeeklyExperienceMode.waiting &&
        next.hasLoadedLocal) {
      final actions = _activeWeeklyPresenceActions;
      if (actions != null) {
        unawaited(
          actions.updateRoster(
            next.members
                .where((member) => member.familyId == widget.identity.familyId)
                .map((member) => member.id),
          ),
        );
      }
    }
    if (_awaitingActivationMemberIds.isNotEmpty) {
      _pruneActivatedMembers(next.members);
    }
  }

  void _pruneActivatedMembers(Iterable<FamilyMember> members) {
    final familyId = _activationFamilyId;
    if (familyId == null) return;
    final activeIds = members
        .where((member) => member.familyId == familyId)
        .map((member) => member.id)
        .toSet();
    _awaitingActivationMemberIds.removeAll(activeIds);
    if (_awaitingActivationMemberIds.isEmpty) {
      _stopActivationReconciliation();
    }
  }

  void _stopActivationReconciliation() {
    _activationEpoch += 1;
    _activationRefreshTimer?.cancel();
    _activationRefreshTimer = null;
    _awaitingActivationMemberIds.clear();
    _activationFamilyId = null;
    _activationAccountId = null;
  }

  Future<void> _nudgeMissingMembers() async {
    if (_nudgeInFlight) return;
    setState(() => _nudgeInFlight = true);
    try {
      await ref.read(inviteShareServiceProvider).shareGatheringNudge();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: KeepersText('Sharing could not be opened. Try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _nudgeInFlight = false);
      } else {
        _nudgeInFlight = false;
      }
    }
  }

  void _openMember(FamilyWheelMember member, List<VaultEntryMetadata> entries) {
    final kept = entries
        .where((entry) => entry.authorId == member.id && entry.state == 'kept')
        .map(_memberSummary)
        .toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Theme(
          data: KeepersTheme.daylight(),
          child: MemberPageScreen(
            member: member,
            keptMemories: kept,
            onOpenMemory: (summary) {
              final metadata = entries.firstWhere(
                (entry) => entry.id == summary.id,
              );
              _openMemory(metadata);
            },
          ),
        ),
      ),
    );
  }

  void _openMemory(VaultEntryMetadata metadata) {
    final controller = ref.read(vaultControllerProvider.future);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MemoryViewer(
          memory: controller.then((value) => value.open(metadata)),
          playback: ref.read(audioPlaybackAdapterProvider),
        ),
      ),
    );
  }

  void _openYourMemories(List<VaultEntryMetadata> entries) {
    final memories =
        entries
            .where((entry) => entry.authorId == widget.identity.memberId)
            .map(_yourMemorySummary)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Theme(
          data: KeepersTheme.daylight(),
          child: YourMemoriesScreen(
            memberName: widget.identity.memberName,
            memories: memories,
            onOpenMemory: (summary) {
              final metadata = entries.firstWhere(
                (entry) => entry.id == summary.id,
              );
              _openMemory(metadata);
            },
          ),
        ),
      ),
    );
  }

  void _openMemorialPreview(List<VaultEntryMetadata> entries) {
    final memories = entries
        .where((entry) => entry.state == 'kept')
        .map(_memberSummary)
        .toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Theme(
          data: KeepersTheme.daylight(),
          child: MemorialPageScreen(
            memberName: widget.identity.memberName,
            dateRange: 'Life dates supplied by family',
            memories: memories,
            preview: true,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final codeProvider = familyCodeControllerProvider(widget.identity.familyId);
    final requestsProvider = familyJoinRequestsControllerProvider(
      widget.identity.familyId,
    );
    final familyCode = ref.watch(codeProvider);
    if (familyCode.failure?.code ==
        FamilyJoinFailureCode.accountFamilyConflict) {
      return AccountConflictScreen(
        kind: AccountConflictKind.accountAlreadyHasFamily,
        onUseAnotherAccount: widget.onUseAnotherAccount,
      );
    }
    final joinRequests = ref.watch(requestsProvider);
    ref.listen(requestsProvider, _handleJoinRequestsChanged);
    final rosterProvider = familyRosterProvider(widget.identity.familyId);
    final rosterState = ref.watch(rosterProvider);
    ref.listen(rosterProvider, _handleRosterChanged);
    if (!rosterState.hasLoadedLocal) {
      return _RosterGate(
        failure: rosterState.refreshFailure,
        onRetry: () => unawaited(
          ref
              .read(familyRosterProvider(widget.identity.familyId).notifier)
              .load(),
        ),
      );
    }
    final entriesState = ref.watch(vaultEntriesProvider);
    final entries = entriesState.asData?.value ?? const [];
    final now = ref.watch(utcNowProvider)().toUtc();
    final weeklyEntries = entriesState.isLoading || entriesState.hasError
        ? const <VaultEntryMetadata>[]
        : _weeklyEntriesAt(entries, now);
    final weeklyPhotos = weeklyEntries
        .where((entry) => entry.format == MemoryFormat.photo)
        .toList(growable: false);
    final weeklyPhotoCount = weeklyPhotos.length;
    final weeklyPhotoCountsByAuthor = <String, int>{};
    for (final entry in weeklyPhotos) {
      weeklyPhotoCountsByAuthor.update(
        entry.authorId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final contribution = math.min(
      1.0,
      (weeklyPhotoCountsByAuthor[widget.identity.memberId] ?? 0) / 5,
    );
    final weeklyPresence = ref.watch(
      weeklyFamilyPresenceProvider(widget.identity.familyId),
    );
    _scheduleWeeklyPresenceExpiry(weeklyPresence, now);
    final trustedNearbyMemberIds = weeklyPresence.trustedNearbyMemberIds(
      at: now,
    );
    final members = _presentationMembers(
      context,
      rosterState.members,
      trustedNearbyMemberIds,
      weeklyPhotoCountsByAuthor,
    );
    final pendingJoinRequest = joinRequests.requests.isEmpty
        ? null
        : joinRequests.requests.first;
    final authorNames = <String, String>{
      for (final member in rosterState.members) member.id: member.name,
      widget.identity.memberId: widget.identity.memberName,
    };

    final destination = switch (_selectedDestination) {
      KeepersNavDestination.wheel => FamilyWheelScreen(
        familyName: widget.identity.familyName,
        currentMemberName: widget.identity.memberName,
        currentMemberAvatar: widget.identity.avatar,
        yourContribution: contribution,
        members: members,
        onCapture: _captureInFlight ? () {} : () => unawaited(_capture()),
        onCurrentMemberSelected: () => _openYourMemories(entries),
        onMemberSelected: (member) => _openMember(member, entries),
        onAddMember: _addMember,
        familyCode: familyCode.displayCode,
        onFamilyCodeTap: _addMember,
        pendingJoinRequestName: pendingJoinRequest?.displayName,
        onPendingJoinRequestTap: pendingJoinRequest == null
            ? null
            : () => unawaited(_openJoinRequest(pendingJoinRequest)),
        onNudgeMissingMembers: _nudgeInFlight
            ? null
            : () => unawaited(_nudgeMissingMembers()),
        weeklyPhotoCount: weeklyPhotoCount,
        onEnterWeeklyWaitingRoom: _enterWeeklyWaitingRoom,
        selectedDestination: _selectedDestination,
        enabledDestinations: keepersEnabledDestinations,
        onDestinationSelected: _selectDestination,
      ),
      KeepersNavDestination.ceremony
          when _weeklyExperienceMode == _WeeklyExperienceMode.waiting =>
        WeeklyWaitingRoomScreen(
          familyName: widget.identity.familyName,
          weeklyProgressComplete: weeklyPhotoCount >= 5,
          members: _weeklyWaitingRoomMembers(
            context,
            rosterState.members,
            members,
          ),
          onClose: () => _selectDestination(KeepersNavDestination.wheel),
          onStart: _startWeeklyExperience,
          rosterRefreshInProgress:
              _weeklyRosterRefreshInFlight || rosterState.isRefreshing,
          onNudgeMissingMembers: () => unawaited(_nudgeMissingMembers()),
          nudgeInProgress: _nudgeInFlight,
        ),
      KeepersNavDestination.ceremony => CeremonyScreen(
        key: ValueKey(
          _weeklyExperienceMode != null ? 'weekly-experience' : 'memory-key',
        ),
        familyName: widget.identity.familyName,
        currentMemberName: widget.identity.memberName,
        startInWeekly: _weeklyExperienceMode != null,
        weeklyPreview: false,
        weeklyMemories: _weeklyMemories,
        weeklyAuthorNames: authorNames,
        weeklyPlayback: ref.read(audioPlaybackAdapterProvider),
        onWeeklyDecision: _resolveWeeklyMemory,
        navigationDestination: _weeklyExperienceMode != null
            ? KeepersNavDestination.wheel
            : KeepersNavDestination.ceremony,
        lockedMemories: const [],
        timeCapsule: null,
        onCapture: _captureInFlight ? () {} : () => unawaited(_capture()),
        onDestinationSelected: _selectDestination,
      ),
      KeepersNavDestination.archive => Theme(
        data: KeepersTheme.daylight(),
        child: ArchiveScreen(
          familyName: widget.identity.familyName,
          memories: entries
              .where((entry) => entry.state == 'kept')
              .map((entry) => _archiveSummary(entry, authorNames))
              .toList(),
          loading: entriesState.isLoading,
          errorMessage: entriesState.hasError
              ? 'The archive could not be opened safely.'
              : null,
          onRetry: () => ref.invalidate(vaultEntriesProvider),
          onCapture: _captureInFlight ? () {} : () => unawaited(_capture()),
          onDestinationSelected: _selectDestination,
          onOpenMemory: (summary) {
            final metadata = entries.firstWhere(
              (entry) => entry.id == summary.id,
            );
            _openMemory(metadata);
          },
        ),
      ),
      KeepersNavDestination.locks => Theme(
        data: KeepersTheme.daylight(),
        child: LocksScreen(
          familyName: widget.identity.familyName,
          onCapture: _captureInFlight ? () {} : () => unawaited(_capture()),
          onDestinationSelected: _selectDestination,
          onOpenMemorialPreview: () => _openMemorialPreview(entries),
        ),
      ),
      KeepersNavDestination.settings => SettingsScreen(
        identity: widget.identity,
        onCapture: _captureInFlight ? () {} : () => unawaited(_capture()),
        onDestinationSelected: _selectDestination,
      ),
    };
    if (rosterState.refreshFailure == null) return destination;
    return Stack(
      fit: StackFit.expand,
      children: [
        destination,
        _RosterRefreshNotice(onRetry: () => unawaited(_refreshRoster())),
      ],
    );
  }

  List<FamilyWheelMember> _presentationMembers(
    BuildContext context,
    List<FamilyMember> roster,
    Set<String> trustedNearbyMemberIds,
    Map<String, int> weeklyPhotoCountsByAuthor,
  ) {
    final tokens = Theme.of(context).extension<ObservatoryTokens>();
    return List<FamilyWheelMember>.unmodifiable(
      roster
          .where((member) => member.id != widget.identity.memberId)
          .map(
            (member) => FamilyWheelMember(
              id: member.id,
              name: member.name,
              color:
                  tokens?.memberColor(member.colorToken) ??
                  KeepersColors.homeGold,
              avatar: member.avatar,
              contribution: math.min(
                1.0,
                (weeklyPhotoCountsByAuthor[member.id] ?? 0) / 5,
              ),
              presence: trustedNearbyMemberIds.contains(member.id)
                  ? FamilyPresence.near
                  : FamilyPresence.away,
            ),
          ),
    );
  }

  List<WeeklyWaitingRoomMember> _weeklyWaitingRoomMembers(
    BuildContext context,
    List<FamilyMember> roster,
    List<FamilyWheelMember> presentationMembers,
  ) {
    final tokens = Theme.of(context).extension<ObservatoryTokens>();
    final presentMemberIds = <String>{
      for (final member in presentationMembers)
        if (member.presence == FamilyPresence.near) member.id,
    };
    final membersById = <String, FamilyMember>{};
    for (final member in roster) {
      if (member.id.trim().isNotEmpty) {
        membersById.putIfAbsent(member.id, () => member);
      }
    }
    final currentMember = membersById.remove(widget.identity.memberId);
    final orderedMembers = membersById.values.toList(growable: true);
    if (currentMember != null) orderedMembers.insert(0, currentMember);
    return List<WeeklyWaitingRoomMember>.unmodifiable(
      orderedMembers.map((member) {
        final isCurrentMember = member.id == widget.identity.memberId;
        return WeeklyWaitingRoomMember(
          id: member.id,
          name: member.name,
          color:
              tokens?.memberColor(member.colorToken) ?? KeepersColors.homeGold,
          avatar: member.avatar,
          isPresent: isCurrentMember || presentMemberIds.contains(member.id),
          isCurrentMember: isCurrentMember,
        );
      }),
    );
  }
}

final class _RosterGate extends StatelessWidget {
  const _RosterGate({required this.failure, required this.onRetry});

  final InvitationFailure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: failure == null
              ? Semantics(
                  label: 'Loading family',
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : Semantics(
                  liveRegion: true,
                  container: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const KeepersText(
                        'YOUR FAMILY COULD NOT BE OPENED',
                        textAlign: TextAlign.center,
                        style: KeepersType.heading,
                      ),
                      const SizedBox(height: 12),
                      const KeepersText(
                        'Your local memories are unchanged. Try opening the family again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: KeepersColors.inkMuted),
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: onRetry,
                        child: const KeepersText('TRY AGAIN'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    ),
  );
}

final class _RosterRefreshNotice extends StatelessWidget {
  const _RosterRefreshNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 82),
      child: Semantics(
        liveRegion: true,
        container: true,
        label: 'Family update unavailable. Cached family is still shown.',
        child: Material(
          color: KeepersColors.auraIvory,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: KeepersColors.homeInk.withValues(alpha: .18),
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: KeepersText(
                    'FAMILY UPDATE UNAVAILABLE',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: onRetry,
                  child: const KeepersText('RETRY'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

ArchiveMemorySummary _archiveSummary(
  VaultEntryMetadata entry,
  Map<String, String> authorNames,
) => ArchiveMemorySummary(
  id: entry.id,
  title: '${entry.format.vaultLabel} · ${_shortDate(entry.createdAt)}',
  authorName: authorNames[entry.authorId] ?? 'Family member',
  theme: switch (entry.format) {
    MemoryFormat.photo => 'Photographs',
    MemoryFormat.voice => 'Voices',
    MemoryFormat.text => 'Notes',
  },
  formatLabel: entry.format.vaultLabel,
  createdAt: entry.createdAt,
);

MemberMemorySummary _memberSummary(VaultEntryMetadata entry) =>
    MemberMemorySummary(
      id: entry.id,
      title: '${entry.format.vaultLabel} · ${_shortDate(entry.createdAt)}',
      formatLabel: entry.format.vaultLabel,
      createdAt: entry.createdAt,
    );

YourMemorySummary _yourMemorySummary(VaultEntryMetadata entry) =>
    YourMemorySummary(
      id: entry.id,
      title: '${entry.format.vaultLabel} · ${_shortDate(entry.createdAt)}',
      formatLabel: entry.format.vaultLabel,
      privacyLabel: entry.privacy.vaultLabel,
      statusLabel: switch ((entry.privacy, entry.state)) {
        (_, 'kept') => 'Available now',
        (PrivacyTier.journal, _) => 'Private to you',
        (PrivacyTier.reveal, _) => 'Waiting for reveal',
        (PrivacyTier.legacy, _) => 'Waiting for milestone',
      },
      createdAt: entry.createdAt,
    );

String _shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

DateTime _startOfLocalWeek(DateTime value) {
  final local = value.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  return day.subtract(Duration(days: local.weekday - DateTime.monday));
}

List<VaultEntryMetadata> _weeklyEntriesAt(
  Iterable<VaultEntryMetadata> entries,
  DateTime now,
) {
  final utcNow = now.toUtc();
  final startOfWeek = _startOfLocalWeek(utcNow).toUtc();
  return entries
      .where(
        (entry) =>
            entry.privacy == PrivacyTier.reveal &&
            entry.state == 'pending' &&
            !entry.createdAt.toUtc().isBefore(startOfWeek) &&
            !entry.createdAt.toUtc().isAfter(utcNow),
      )
      .toList(growable: false)
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
}
