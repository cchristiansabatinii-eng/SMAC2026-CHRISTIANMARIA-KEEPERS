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
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/family/data/invite_share_service.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/family/presentation/family_invite_screen.dart';
import 'package:keepers/features/locks/presentation/locks_screen.dart';
import 'package:keepers/features/members/presentation/member_page_screen.dart';
import 'package:keepers/features/members/presentation/your_memories_screen.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/settings/presentation/settings_screen.dart';
import 'package:keepers/features/vault/application/vault_providers.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/features/vault/presentation/memory_viewer.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/family_wheel_screen.dart';
import 'package:keepers/ui/keepers_bottom_nav.dart';
import 'package:keepers/ui/keepers_destination_scaffold.dart';

typedef CaptureSheetLauncher = Future<EntryMetadata?> Function(
  BuildContext context,
);

final class ObservatoryScreen extends ConsumerStatefulWidget {
  const ObservatoryScreen({
    required this.identity,
    this.showCapture,
    super.key,
  });

  final LocalIdentity identity;
  final CaptureSheetLauncher? showCapture;

  @override
  ConsumerState<ObservatoryScreen> createState() => _ObservatoryScreenState();
}

final class _ObservatoryScreenState extends ConsumerState<ObservatoryScreen>
    with WidgetsBindingObserver {
  bool _captureInFlight = false;
  KeepersNavDestination _selectedDestination = KeepersNavDestination.wheel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshRoster());
    }
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
    if (_selectedDestination == destination) return;
    setState(() => _selectedDestination = destination);
  }

  Future<void> _addMember() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/family/invite'),
        builder: (context) => Theme(
          data: KeepersTheme.daylight(),
          child: const FamilyInviteScreen(),
        ),
      ),
    );
    if (mounted) await _refreshRoster();
  }

  void _nudgeMissingMembers() {
    unawaited(
      ref
          .read(inviteShareServiceProvider)
          .shareGatheringNudge()
          .onError((_, _) {}),
    );
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
    final rosterState = ref.watch(
      familyRosterProvider(widget.identity.familyId),
    );
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
    final keptEntries = entries
        .where((entry) => entry.state == 'kept')
        .toList();
    final startOfWeek = _startOfWeek(DateTime.now().toUtc());
    final weeklyMemoryCount = entries
        .where(
          (entry) =>
              entry.privacy == PrivacyTier.reveal &&
              entry.state == 'pending' &&
              !entry.createdAt.isBefore(startOfWeek),
        )
        .length;
    final contribution = math.min(
      1.0,
      entries
              .where((entry) => entry.authorId == widget.identity.memberId)
              .length /
          5,
    );
    final members = _presentationMembers(context, rosterState.members);

    final destination = switch (_selectedDestination) {
      KeepersNavDestination.wheel => FamilyWheelScreen(
        familyName: widget.identity.familyName,
        currentMemberName: widget.identity.memberName,
        currentMemberAvatar: widget.identity.avatar,
        yourContribution: contribution,
        requiredPresence: 2,
        members: members,
        onCapture: _captureInFlight ? () {} : () => unawaited(_capture()),
        onCurrentMemberSelected: () => _openYourMemories(entries),
        onMemberSelected: (member) => _openMember(member, entries),
        onAddMember: _addMember,
        onNudgeMissingMembers: _nudgeMissingMembers,
        selectedDestination: _selectedDestination,
        enabledDestinations: keepersEnabledDestinations,
        onDestinationSelected: _selectDestination,
      ),
      KeepersNavDestination.ceremony => CeremonyScreen(
        familyName: widget.identity.familyName,
        currentMemberName: widget.identity.memberName,
        weeklyPreviewEnabled: true,
        nearbyDeviceCount: 1,
        weeklyMemoryCount: weeklyMemoryCount,
        members: [for (final member in members) MemoryKeyMember.from(member)],
        lockedMemories: const [],
        timeCapsule: null,
        randomMemories: keptEntries.map(_memoryKeySummary).toList(),
        onOpenRandomMemory: (summary) {
          final metadata = keptEntries.firstWhere(
            (entry) => entry.id == summary.id,
          );
          _openMemory(metadata);
        },
        onAddMember: _addMember,
        onNudgeMissingMembers: _nudgeMissingMembers,
        onCapture: _captureInFlight ? () {} : () => unawaited(_capture()),
        onDestinationSelected: _selectDestination,
      ),
      KeepersNavDestination.archive => Theme(
        data: KeepersTheme.daylight(),
        child: ArchiveScreen(
          familyName: widget.identity.familyName,
          memories: entries
              .where((entry) => entry.state == 'kept')
              .map((entry) => _archiveSummary(entry, widget.identity))
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
              contribution: null,
              presence: FamilyPresence.away,
            ),
          ),
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
  LocalIdentity identity,
) => ArchiveMemorySummary(
  id: entry.id,
  title: '${entry.format.vaultLabel} · ${_shortDate(entry.createdAt)}',
  authorName: entry.authorId == identity.memberId
      ? identity.memberName
      : 'Family member',
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

MemoryKeyMemory _memoryKeySummary(VaultEntryMetadata entry) => MemoryKeyMemory(
  id: entry.id,
  title: '${entry.format.vaultLabel} · ${_shortDate(entry.createdAt)}',
  formatLabel: entry.format.vaultLabel,
);

DateTime _startOfWeek(DateTime value) {
  final day = DateTime.utc(value.year, value.month, value.day);
  return day.subtract(Duration(days: value.weekday - DateTime.monday));
}
