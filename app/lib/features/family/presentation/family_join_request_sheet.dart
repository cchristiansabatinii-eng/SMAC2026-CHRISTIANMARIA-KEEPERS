import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/family/application/family_join_requests_controller.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/keepers_app_background.dart';

final class FamilyJoinRequestSheet extends ConsumerStatefulWidget {
  const FamilyJoinRequestSheet({
    required this.familyId,
    required this.request,
    super.key,
  });

  final String familyId;
  final PendingFamilyJoinRequest request;

  static Future<void> show(
    BuildContext context, {
    required String familyId,
    required PendingFamilyJoinRequest request,
  }) async {
    final triggerFocus = FocusManager.instance.primaryFocus;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierLabel: 'Close ${request.displayName} join request',
      builder: (_) =>
          FamilyJoinRequestSheet(familyId: familyId, request: request),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (triggerFocus?.canRequestFocus ?? false) {
        triggerFocus!.requestFocus();
      }
    });
  }

  @override
  ConsumerState<FamilyJoinRequestSheet> createState() =>
      _FamilyJoinRequestSheetState();
}

enum _DecisionAction { approve, decline }

final class _FamilyJoinRequestSheetState
    extends ConsumerState<FamilyJoinRequestSheet> {
  final _approveFocus = FocusNode(debugLabel: 'approve join request');
  final _declineFocus = FocusNode(debugLabel: 'decline join request');
  _DecisionAction? _lastAction;
  var _sawAuthoritativeRequest = false;
  var _finishing = false;
  String? _resolutionAnnouncement;

  @override
  void dispose() {
    _approveFocus.dispose();
    _declineFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = familyJoinRequestsControllerProvider(widget.familyId);
    final state = ref.watch(provider);
    _sawAuthoritativeRequest =
        _sawAuthoritativeRequest || _containsRequest(state);
    ref.listen(provider, _handleStateChange);

    final resolving = state.resolvingRequestId != null;
    final resolvingThisRequest =
        state.resolvingRequestId == widget.request.requestId;
    final accent =
        Theme.of(context)
            .extension<ObservatoryTokens>()
            ?.memberColor(widget.request.colorToken) ??
        KeepersColors.memberPalette[1];

    return PopScope<void>(
      canPop: !resolving,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: KeepersAppBackground(
          child: SafeArea(
            top: false,
            child: SizedBox(
              key: const Key('family-join-request-sheet-body'),
              height: 408,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            key: const Key('close-join-request-sheet'),
                            style: TextButton.styleFrom(
                              foregroundColor: KeepersColors.ink,
                              disabledForegroundColor: KeepersColors.inkMuted
                                  .withValues(alpha: .45),
                              minimumSize: const Size(72, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            onPressed: resolving
                                ? null
                                : () => Navigator.of(context).maybePop(),
                            child: const KeepersText('Close'),
                          ),
                        ),
                        Center(
                          child: KeepersAvatarSurface(
                            size: 112,
                            accent: accent,
                            child: KeepersAvatar(
                              config: widget.request.avatar,
                              size: 100,
                              crop: KeepersAvatarCrop.detail,
                              semanticLabel:
                                  '${widget.request.displayName} profile',
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        KeepersText(
                          '${widget.request.displayName} wants to join',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: KeepersType.heading.copyWith(
                            color: KeepersColors.ink,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                key: const Key('decline-join-request'),
                                focusNode: _declineFocus,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: KeepersColors.ink,
                                  minimumSize: const Size.fromHeight(48),
                                  side: const BorderSide(
                                    color: KeepersColors.homeActionLine,
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: resolving ? null : _confirmDecline,
                                child: const KeepersText('Decline'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                key: const Key('approve-join-request'),
                                focusNode: _approveFocus,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  elevation: 0,
                                ),
                                onPressed: resolving ? null : _approve,
                                child: const KeepersText('Approve'),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: 64,
                          child: _JoinRequestStatus(
                            state: state,
                            displayName: widget.request.displayName,
                            resolvingThisRequest: resolvingThisRequest,
                            action: _lastAction,
                            resolutionAnnouncement: _resolutionAnnouncement,
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

  void _handleStateChange(
    FamilyJoinRequestsState? previous,
    FamilyJoinRequestsState next,
  ) {
    final containedBefore = previous != null && _containsRequest(previous);
    final containsNow = _containsRequest(next);
    _sawAuthoritativeRequest =
        _sawAuthoritativeRequest || containedBefore || containsNow;

    if (previous?.resolvingRequestId == widget.request.requestId &&
        next.resolvingRequestId != widget.request.requestId &&
        next.failure != null) {
      _restoreLastActionFocus();
      return;
    }
    if (_sawAuthoritativeRequest &&
        !containsNow &&
        next.failure == null &&
        !_finishing) {
      unawaited(_finishResolved());
    }
  }

  Future<void> _approve() async {
    _lastAction = _DecisionAction.approve;
    await ref
        .read(familyJoinRequestsControllerProvider(widget.familyId).notifier)
        .approve(widget.request.requestId);
    if (!mounted) return;
    final state = ref.read(
      familyJoinRequestsControllerProvider(widget.familyId),
    );
    if (!_containsRequest(state) && state.failure == null) {
      await _finishResolved();
    } else if (state.failure != null) {
      _restoreLastActionFocus();
    }
  }

  Future<void> _confirmDecline() async {
    _lastAction = _DecisionAction.decline;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: KeepersText("Decline ${widget.request.displayName}'s request?"),
        content: KeepersText(
          "${widget.request.displayName} won't join this family. They can ask again later.",
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            autofocus: true,
            style: TextButton.styleFrom(
              foregroundColor: KeepersColors.ink,
              minimumSize: const Size(88, 48),
            ),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const KeepersText('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KeepersColors.homeClay,
              foregroundColor: KeepersColors.ink,
              minimumSize: const Size(88, 48),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const KeepersText('Decline'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      _restoreLastActionFocus();
      return;
    }

    await ref
        .read(familyJoinRequestsControllerProvider(widget.familyId).notifier)
        .decline(widget.request.requestId);
    if (!mounted) return;
    final state = ref.read(
      familyJoinRequestsControllerProvider(widget.familyId),
    );
    if (!_containsRequest(state) && state.failure == null) {
      await _finishResolved();
    } else if (state.failure != null) {
      _restoreLastActionFocus();
    }
  }

  Future<void> _finishResolved() async {
    if (_finishing || !mounted) return;
    _finishing = true;
    final message = '${widget.request.displayName} request resolved';
    setState(() => _resolutionAnnouncement = message);
    await SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _restoreLastActionFocus() {
    final focus = switch (_lastAction) {
      _DecisionAction.approve => _approveFocus,
      _DecisionAction.decline => _declineFocus,
      null => null,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (focus?.canRequestFocus ?? false)) {
        focus!.requestFocus();
      }
    });
  }

  bool _containsRequest(FamilyJoinRequestsState state) => state.requests.any(
    (request) => request.requestId == widget.request.requestId,
  );
}

final class _JoinRequestStatus extends StatelessWidget {
  const _JoinRequestStatus({
    required this.state,
    required this.displayName,
    required this.resolvingThisRequest,
    required this.action,
    required this.resolutionAnnouncement,
  });

  final FamilyJoinRequestsState state;
  final String displayName;
  final bool resolvingThisRequest;
  final _DecisionAction? action;
  final String? resolutionAnnouncement;

  @override
  Widget build(BuildContext context) {
    final failure = state.failure;
    final status = switch ((
      resolutionAnnouncement,
      resolvingThisRequest,
      failure,
    )) {
      (final String resolution, _, _) => resolution,
      (_, true, _) => switch (action) {
        _DecisionAction.decline => 'Declining $displayName request',
        _DecisionAction.approve || null => 'Approving $displayName request',
      },
      (_, _, final FamilyJoinFailure currentFailure) => _failureMessage(
        currentFailure,
      ),
      _ => null,
    };

    return Semantics(
      key: const Key('join-request-status'),
      liveRegion: true,
      label: status ?? 'Ready to decide',
      child: switch ((resolutionAnnouncement, resolvingThisRequest, failure)) {
        (final String resolution, _, _) => Center(
          child: KeepersText(
            resolution,
            textAlign: TextAlign.center,
            style: const TextStyle(color: KeepersColors.inkMuted, fontSize: 13),
          ),
        ),
        (_, true, _) => const Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        (_, _, final FamilyJoinFailure currentFailure) => Center(
          child: KeepersText(
            _failureMessage(currentFailure),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: KeepersColors.inkMuted,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

String _failureMessage(FamilyJoinFailure failure) => switch (failure.code) {
  FamilyJoinFailureCode.notConfigured => 'Family sharing is not available.',
  FamilyJoinFailureCode.signedOut => 'Sign in again, then retry.',
  FamilyJoinFailureCode.networkUnavailable => 'Keepers is offline. Try again.',
  FamilyJoinFailureCode.familyNotFound => 'This family is no longer available.',
  FamilyJoinFailureCode.alreadyMember =>
    'This person is already in the family.',
  FamilyJoinFailureCode.requestExpired => 'This request expired.',
  FamilyJoinFailureCode.requestDeclined ||
  FamilyJoinFailureCode.requestCancelled =>
    'This request is no longer pending.',
  FamilyJoinFailureCode.invitationChanged ||
  FamilyJoinFailureCode.codeVersionChanged =>
    'The family invitation changed. Try again.',
  FamilyJoinFailureCode.rateLimited => 'Please wait, then try again.',
  FamilyJoinFailureCode.forbidden =>
    'You no longer have access to this family.',
  FamilyJoinFailureCode.invalidJoinKey ||
  FamilyJoinFailureCode.envelopeRejected =>
    'This request could not be approved securely.',
  FamilyJoinFailureCode.localPersistenceFailed =>
    'The family key is unavailable on this device.',
  FamilyJoinFailureCode.requestAlreadyPending ||
  FamilyJoinFailureCode.codeCollision ||
  FamilyJoinFailureCode.notCreator ||
  FamilyJoinFailureCode.unknown => 'The request could not be updated.',
};
