import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/family_code_controller.dart';
import 'package:keepers/features/family/domain/family_join_failure.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/keepers_app_background.dart';

final class FamilyInviteSheet extends ConsumerStatefulWidget {
  const FamilyInviteSheet({
    required this.familyId,
    super.key,
    @visibleForTesting this.initializeOnMount = true,
  });

  final String familyId;
  final bool initializeOnMount;

  static Future<void> show(BuildContext context, {required String familyId}) =>
      showModalBottomSheet<void>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierLabel: 'Close family invitation',
        builder: (_) => FamilyInviteSheet(familyId: familyId),
      );

  @override
  ConsumerState<FamilyInviteSheet> createState() => _FamilyInviteSheetState();
}

final class _FamilyInviteSheetState extends ConsumerState<FamilyInviteSheet> {
  final _regenerateFocus = FocusNode();
  final _shareKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (!widget.initializeOnMount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref
              .read(familyCodeControllerProvider(widget.familyId).notifier)
              .load(),
        );
      }
    });
  }

  @override
  void dispose() {
    _regenerateFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = familyCodeControllerProvider(widget.familyId);
    final state = ref.watch(provider);
    ref.listen(provider, (previous, next) {
      if (previous?.phase == FamilyCodePhase.regenerating &&
          next.phase == FamilyCodePhase.failed) {
        _restoreRegenerateFocus();
      }
    });
    final regenerating = state.phase == FamilyCodePhase.regenerating;
    final mutationBlocked =
        regenerating || state.phase == FamilyCodePhase.loading;

    return PopScope<void>(
      canPop: !regenerating,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: KeepersAppBackground(
          child: SafeArea(
            top: false,
            child: SizedBox(
              key: const Key('family-invite-sheet-body'),
              height: 448,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: KeepersText(
                                'Invite family',
                                style: KeepersType.heading.copyWith(
                                  color: KeepersColors.ink,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              constraints: const BoxConstraints.tightFor(
                                width: 48,
                                height: 48,
                              ),
                              onPressed: regenerating
                                  ? null
                                  : () => Navigator.maybePop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const KeepersText(
                          'Share this code with someone you trust. A family member must still approve their request.',
                          style: TextStyle(
                            color: KeepersColors.inkMuted,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Semantics(
                          label: state.displayCode == null
                              ? 'Family code unavailable'
                              : 'Family code ${_spokenCode(state.displayCode!)}',
                          child: ExcludeSemantics(
                            child: Text(
                              state.displayCode ?? '••••-••••',
                              key: const Key('family-code-display'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: KeepersColors.ink,
                                fontFamily: KeepersType.primary,
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2.2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _ActionRow(
                          key: _shareKey,
                          buttonKey: const Key('share-family-link'),
                          icon: Icons.ios_share_rounded,
                          label: 'Share family link',
                          onPressed: state.hasCode && !regenerating
                              ? () => ref
                                    .read(provider.notifier)
                                    .shareFamilyLink(
                                      sharePositionOrigin: _globalRect(
                                        _shareKey,
                                      ),
                                    )
                              : null,
                        ),
                        _ActionRow(
                          buttonKey: const Key('copy-family-code'),
                          icon: Icons.content_copy_rounded,
                          label: 'Copy family code',
                          onPressed: state.hasCode && !regenerating
                              ? ref.read(provider.notifier).copyFamilyCode
                              : null,
                        ),
                        _ActionRow(
                          buttonKey: const Key('copy-family-link'),
                          icon: Icons.link_rounded,
                          label: 'Copy link',
                          onPressed: state.hasCode && !regenerating
                              ? ref.read(provider.notifier).copyFamilyLink
                              : null,
                        ),
                        if (state.isCreator)
                          _ActionRow(
                            buttonKey: const Key('regenerate-family-code'),
                            focusNode: _regenerateFocus,
                            icon: Icons.refresh_rounded,
                            label: 'Regenerate code',
                            onPressed: state.hasCode && !mutationBlocked
                                ? _confirmRegeneration
                                : null,
                          ),
                        SizedBox(
                          height: 54,
                          child: _StatusSlot(
                            state: state,
                            onRetry: state.phase == FamilyCodePhase.failed
                                ? () => state.hasCode && state.isCreator
                                      ? ref.read(provider.notifier).regenerate()
                                      : ref.read(provider.notifier).load()
                                : null,
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
    );
  }

  Future<void> _confirmRegeneration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const KeepersText('Regenerate family code?'),
        content: const KeepersText(
          'The previous code and pending requests will stop working, and the previous link will no longer open this family.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const KeepersText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const KeepersText('Regenerate'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      _restoreRegenerateFocus();
      return;
    }
    await ref
        .read(familyCodeControllerProvider(widget.familyId).notifier)
        .regenerate();
    if (mounted &&
        ref.read(familyCodeControllerProvider(widget.familyId)).phase ==
            FamilyCodePhase.failed) {
      _restoreRegenerateFocus();
    }
  }

  void _restoreRegenerateFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _regenerateFocus.canRequestFocus) {
        _regenerateFocus.requestFocus();
      }
    });
  }
}

final class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.focusNode,
    super.key,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final FutureOr<void> Function()? onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => TextButton(
    key: buttonKey,
    focusNode: focusNode,
    style: TextButton.styleFrom(
      alignment: Alignment.centerLeft,
      foregroundColor: KeepersColors.ink,
      disabledForegroundColor: KeepersColors.inkMuted.withValues(alpha: .45),
      minimumSize: const Size(double.infinity, 48),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      shape: const RoundedRectangleBorder(),
    ),
    onPressed: onPressed,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: KeepersText(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

final class _StatusSlot extends StatelessWidget {
  const _StatusSlot({required this.state, required this.onRetry});

  final FamilyCodeState state;
  final FutureOr<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.phase == FamilyCodePhase.loading ||
        state.phase == FamilyCodePhase.regenerating) {
      return Semantics(
        liveRegion: true,
        label: state.phase == FamilyCodePhase.regenerating
            ? 'Regenerating family code'
            : 'Loading family code',
        child: const Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (state.phase == FamilyCodePhase.failed) {
      return Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: KeepersText(
                _failureMessage(state.failure),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KeepersColors.inkMuted,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const KeepersText('Retry')),
        ],
      );
    }
    final message =
        state.feedback ??
        (state.isOffline ? 'Showing the code saved on this device' : null);
    if (message == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        liveRegion: true,
        child: KeepersText(
          message,
          style: const TextStyle(color: KeepersColors.inkMuted, fontSize: 13),
        ),
      ),
    );
  }
}

String _failureMessage(FamilyJoinFailure? failure) => switch (failure?.code) {
  FamilyJoinFailureCode.notConfigured => 'Family sharing is not configured.',
  FamilyJoinFailureCode.signedOut => 'Sign in again, then retry.',
  FamilyJoinFailureCode.networkUnavailable => 'Keepers is offline.',
  FamilyJoinFailureCode.notCreator => 'Only the family creator can do that.',
  FamilyJoinFailureCode.codeVersionChanged =>
    'The family code changed on another device.',
  _ => 'The family code could not be updated.',
};

Rect? _globalRect(GlobalKey key) {
  final renderObject = key.currentContext?.findRenderObject();
  if (renderObject is! RenderBox ||
      !renderObject.attached ||
      !renderObject.hasSize ||
      renderObject.size.isEmpty) {
    return null;
  }
  final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
  return rect.isFinite ? rect : null;
}

String _spokenCode(String displayCode) =>
    displayCode.replaceAll('-', '').split('').join(' ');
