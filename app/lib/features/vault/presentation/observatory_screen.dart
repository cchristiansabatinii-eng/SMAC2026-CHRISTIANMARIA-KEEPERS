import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/design_system/observatory/motion_policy.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/design_system/observatory/observatory_view.dart';
import 'package:keepers/design_system/observatory/orbit_scene.dart';
import 'package:keepers/features/capture/application/capture_providers.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/capture/presentation/capture_sheet.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/application/vault_controller.dart';
import 'package:keepers/features/vault/application/vault_providers.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/features/vault/presentation/memory_viewer.dart';
import 'package:keepers/features/vault/presentation/vault_list.dart';

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _sealController;
  String? _sealedMemoryId;
  bool _captureInFlight = false;

  @override
  void initState() {
    super.initState();
    _sealController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _sealController.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_captureInFlight) return;
    setState(() => _captureInFlight = true);
    try {
      final saved = await (widget.showCapture ?? CaptureSheet.show)(context);
      if (saved == null || !mounted) return;
      ref.invalidate(vaultEntriesProvider);
      final entries = await ref.read(vaultEntriesProvider.future);
      if (!mounted || !entries.any((entry) => entry.id == saved.id)) return;

      final tokens = Theme.of(context).extension<ObservatoryTokens>()!;
      final policy = MotionPolicy.fromMediaQuery(
        MediaQuery.of(context),
        tokens,
      );
      _sealController.duration = policy.sealDuration;
      setState(() => _sealedMemoryId = saved.id);
      await _sealController.forward(from: 0);
      if (!mounted || _sealedMemoryId != saved.id) return;
      await HapticFeedback.selectionClick();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted) await HapticFeedback.selectionClick();
    } on Object {
      // Capture and refresh surfaces own retry states. Never infer success here.
    } finally {
      if (mounted) setState(() => _captureInFlight = false);
    }
  }

  Future<void> _openMemory(VaultEntryMetadata entry) async {
    final playback = ref.read(audioPlaybackAdapterProvider);
    Future<MemoryOpenResult> memory;
    try {
      final controller = await ref.read(vaultControllerProvider.future);
      memory = controller.open(entry);
    } on Object {
      memory = Future.value(
        const UnavailableMemory(VaultController.unavailableMessage),
      );
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MemoryViewer(memory: memory, playback: playback),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ObservatoryTokens>()!;
    final policy = MotionPolicy.fromMediaQuery(MediaQuery.of(context), tokens);
    final entriesState = ref.watch(vaultEntriesProvider);
    final entries = entriesState.asData?.value ?? const <VaultEntryMetadata>[];
    final byId = {for (final entry in entries) entry.id: entry};
    final scene = OrbitSceneModel(
      member: OrbitMemberNode(
        id: widget.identity.memberId,
        name: widget.identity.memberName,
        colorToken: widget.identity.colorToken,
      ),
      memories: entries
          .map(
            (entry) => OrbitMemoryMark(
              id: entry.id,
              format: entry.format,
              privacy: entry.privacy,
              createdAt: entry.createdAt,
              colorToken: widget.identity.colorToken,
            ),
          )
          .toList(growable: false),
    );

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'The Observatory',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.identity.familyName,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AnimatedBuilder(
                    animation: _sealController,
                    builder: (context, _) => ObservatoryView(
                      scene: scene,
                      policy: policy,
                      onAddMemory: _captureInFlight ? null : _capture,
                      onOpenMemory: (id) {
                        final entry = byId[id];
                        if (entry != null) unawaited(_openMemory(entry));
                      },
                      sealedMemoryId: _sealedMemoryId,
                      sealProgress: _sealController.value,
                    ),
                  ),
                ),
              ),
              entriesState.when(
                loading: () => const _VaultStatus(
                  icon: Icons.lock_clock_rounded,
                  message: 'Opening the local vault…',
                  loading: true,
                ),
                error: (_, _) => _VaultStatus(
                  icon: Icons.lock_outline_rounded,
                  message: 'Vault unavailable.',
                  onRetry: () => ref.invalidate(vaultEntriesProvider),
                ),
                data: (loaded) => VaultList(
                  entries: loaded,
                  onOpen: (entry) => unawaited(_openMemory(entry)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _VaultStatus extends StatelessWidget {
  const _VaultStatus({
    required this.icon,
    required this.message,
    this.loading = false,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const CircularProgressIndicator()
          else
            Icon(icon, size: 36),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry case final retry?) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: retry, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}
