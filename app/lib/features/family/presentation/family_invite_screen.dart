import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/family_invite_controller.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/keepers_app_background.dart';

final class FamilyInviteScreen extends ConsumerStatefulWidget {
  const FamilyInviteScreen({
    super.key,
    @visibleForTesting this.initializeOnMount = true,
  });

  final bool initializeOnMount;

  @override
  ConsumerState<FamilyInviteScreen> createState() => _FamilyInviteScreenState();
}

final class _FamilyInviteScreenState extends ConsumerState<FamilyInviteScreen> {
  final _ownerEmail = TextEditingController();
  final _otp = TextEditingController();
  final _recipientEmail = TextEditingController();
  final _createKey = GlobalKey();
  final _shareKey = GlobalKey();
  final _ownerEmailFocus = FocusNode();
  final _otpFocus = FocusNode();
  final _recipientEmailFocus = FocusNode();
  String? _localError;

  @override
  void initState() {
    super.initState();
    if (!widget.initializeOnMount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(familyInviteControllerProvider.notifier).initialize(),
        );
      }
    });
  }

  @override
  void dispose() {
    _ownerEmail.dispose();
    _otp.dispose();
    _recipientEmail.dispose();
    _ownerEmailFocus.dispose();
    _otpFocus.dispose();
    _recipientEmailFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(familyInviteControllerProvider);
    _adoptSafeValues(state);
    _recoverFocus(state);
    final blocksRoute =
        state.phase == FamilyInvitePhase.creating ||
        state.phase == FamilyInvitePhase.revoking;
    return PopScope<void>(
      canPop: !blocksRoute,
      child: KeepersAppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: SingleChildScrollView(
              key: const Key('family-invite-scroll'),
              padding: EdgeInsets.fromLTRB(
                24,
                10,
                24,
                28 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _InviteHeader(
                        onBack: blocksRoute
                            ? null
                            : () => Navigator.maybePop(context),
                      ),
                      const SizedBox(height: 30),
                      KeepersText(
                        'Invite family',
                        style: KeepersType.heading.copyWith(
                          color: KeepersColors.ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const KeepersText(
                        'Memories stay encrypted. This invitation only adds a family member.',
                        style: TextStyle(
                          color: KeepersColors.inkMuted,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 30),
                      _content(state),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(FamilyInviteState state) {
    if (state.phase == FamilyInvitePhase.failed &&
        state.failure?.code == InvitationFailureCode.signedOut) {
      return _ownerEmailContent(state, error: _failureMessage(state.failure));
    }
    if (state.createdInvitation != null) return _createdContent(state);
    return switch (state.phase) {
      FamilyInvitePhase.checking => switch (state.retryPoint) {
        FamilyInviteRetryPoint.requestOtp => _ownerEmailContent(state),
        FamilyInviteRetryPoint.verifyOtp => _otpContent(state),
        _ => const _Status(message: 'Checking cloud invitations', busy: true),
      },
      FamilyInvitePhase.needsAuthentication => _ownerEmailContent(state),
      FamilyInvitePhase.awaitingOtp => _otpContent(state),
      FamilyInvitePhase.ready ||
      FamilyInvitePhase.creating => _recipientContent(state),
      FamilyInvitePhase.failed => _failedContent(state),
      FamilyInvitePhase.created ||
      FamilyInvitePhase.revoking => _createdContent(state),
    };
  }

  Widget _ownerEmailContent(FamilyInviteState state, {String? error}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      KeepersText(
        state.failure?.code == InvitationFailureCode.signedOut
            ? 'Sign in again as the family owner to continue safely.'
            : 'Sign in as the family owner to create an invitation.',
        style: const TextStyle(color: KeepersColors.inkMuted, height: 1.4),
      ),
      const SizedBox(height: 18),
      TextField(
        key: const Key('invite-owner-email'),
        controller: _ownerEmail,
        focusNode: _ownerEmailFocus,
        enabled: !state.isBusy,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.email],
        onSubmitted: state.isBusy ? null : (_) => _requestOtp(),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          label: KeepersText('Your email'),
        ),
      ),
      _FeedbackSlot(message: error ?? _localError),
      _StableButton(
        label: 'SEND CODE',
        busyLabel: 'SENDING CODE',
        busy: state.isBusy,
        onPressed: state.isBusy ? null : _requestOtp,
      ),
    ],
  );

  Widget _otpContent(FamilyInviteState state, {String? error}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      KeepersText(
        'Enter the six-digit code sent to ${_ownerEmail.text.trim()}.',
        style: const TextStyle(color: KeepersColors.inkMuted, height: 1.4),
      ),
      const SizedBox(height: 18),
      TextField(
        key: const Key('invite-owner-otp'),
        controller: _otp,
        focusNode: _otpFocus,
        enabled: !state.isBusy,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.oneTimeCode],
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: state.isBusy ? null : (_) => _verifyOtp(),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          label: KeepersText('Six-digit code'),
          counterText: '',
        ),
      ),
      _FeedbackSlot(message: error ?? _localError),
      _StableButton(
        label: 'VERIFY CODE',
        busyLabel: 'VERIFYING CODE',
        busy: state.isBusy,
        onPressed: state.isBusy ? null : _verifyOtp,
      ),
    ],
  );

  Widget _recipientContent(FamilyInviteState state, {String? error}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const KeepersText(
        'Invite one relative. Send the private link only to this address.',
        style: TextStyle(color: KeepersColors.inkMuted, height: 1.4),
      ),
      const SizedBox(height: 18),
      TextField(
        key: const Key('invite-recipient-email'),
        controller: _recipientEmail,
        focusNode: _recipientEmailFocus,
        enabled: !state.isBusy && !state.isRecipientLocked,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.email],
        onSubmitted: state.isBusy ? null : (_) => _createInvite(),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          label: const KeepersText('Relative email'),
          suffixIcon: state.isRecipientLocked
              ? const Icon(
                  Icons.lock_outline_rounded,
                  semanticLabel: 'Recipient locked for this retry',
                )
              : null,
        ),
      ),
      _FeedbackSlot(message: error ?? _localError),
      KeyedSubtree(
        key: _createKey,
        child: _StableButton(
          key: const Key('create-family-invitation'),
          label: state.isRecipientLocked
              ? 'RETRY INVITATION'
              : 'CREATE INVITATION',
          busyLabel: state.isRecipientLocked
              ? 'RETRYING INVITATION'
              : 'CREATING INVITATION',
          busy: state.phase == FamilyInvitePhase.creating,
          onPressed: state.isBusy ? null : _createInvite,
        ),
      ),
    ],
  );

  Widget _failedContent(FamilyInviteState state) {
    final message = _failureMessage(state.failure);
    if (state.failure?.code == InvitationFailureCode.notOwner) {
      return _InlineError(message);
    }
    return switch (state.retryPoint) {
      FamilyInviteRetryPoint.requestOtp => _ownerEmailContent(
        state,
        error: message,
      ),
      FamilyInviteRetryPoint.verifyOtp => _otpContent(state, error: message),
      FamilyInviteRetryPoint.create => _recipientContent(state, error: message),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InlineError(message),
          const SizedBox(height: 18),
          _StableButton(
            label: 'TRY AGAIN',
            busyLabel: 'TRYING AGAIN',
            busy: state.isBusy,
            onPressed: state.isBusy ? null : _retry,
          ),
        ],
      ),
    };
  }

  Widget _createdContent(FamilyInviteState state) {
    final created = state.createdInvitation!;
    final operationError = state.phase == FamilyInvitePhase.failed
        ? _failureMessage(state.failure)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: const KeepersText(
            'INVITATION READY',
            style: TextStyle(
              color: KeepersColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Detail(label: 'Recipient', value: state.recipientEmail.trim()),
        const SizedBox(height: 8),
        _Detail(label: 'Expires', value: _expiry(created.expiresAt)),
        const SizedBox(height: 10),
        const KeepersText(
          'Pending until your relative accepts. Send this private invitation only to them.',
          style: TextStyle(color: KeepersColors.inkMuted, height: 1.4),
        ),
        SizedBox(
          height: 124,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.isSharing)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: _Status(message: 'Opening share options', busy: true),
                ),
              if (state.shareFailure != null)
                const _InlineError(
                  'The share options could not be opened. Your invitation is still pending.',
                ),
              if (operationError != null) _InlineError(operationError),
            ],
          ),
        ),
        KeyedSubtree(
          key: _shareKey,
          child: _StableButton(
            key: const Key('share-family-invitation'),
            label: 'SHARE AGAIN',
            busyLabel: 'OPENING SHARE OPTIONS',
            busy: state.isSharing,
            onPressed: state.isBusy || state.isSharing ? null : _shareAgain,
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          label: state.phase == FamilyInvitePhase.revoking
              ? 'CANCELLING INVITATION'
              : 'CANCEL INVITATION',
          button: true,
          enabled: !state.isBusy && !state.isSharing,
          liveRegion: state.phase == FamilyInvitePhase.revoking,
          onTap: state.isBusy || state.isSharing ? null : _revoke,
          child: ExcludeSemantics(
            child: OutlinedButton(
              key: const Key('cancel-family-invitation'),
              style: OutlinedButton.styleFrom(
                fixedSize: const Size.fromHeight(48),
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: state.isBusy || state.isSharing ? null : _revoke,
              child: state.phase == FamilyInvitePhase.revoking
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const KeepersText('CANCEL INVITATION'),
            ),
          ),
        ),
      ],
    );
  }

  void _adoptSafeValues(FamilyInviteState state) {
    if (_ownerEmail.text.isEmpty && state.authenticationEmail.isNotEmpty) {
      _ownerEmail.text = state.authenticationEmail;
    }
    if (state.isRecipientLocked &&
        _recipientEmail.text != state.recipientEmail) {
      _recipientEmail.text = state.recipientEmail;
    } else if (_recipientEmail.text.isEmpty &&
        state.recipientEmail.isNotEmpty) {
      _recipientEmail.text = state.recipientEmail;
    }
  }

  Future<void> _requestOtp() async {
    if (!_looksLikeEmail(_ownerEmail.text)) {
      setState(() => _localError = 'ENTER A COMPLETE EMAIL ADDRESS.');
      _ownerEmailFocus.requestFocus();
      return;
    }
    setState(() => _localError = null);
    await ref
        .read(familyInviteControllerProvider.notifier)
        .requestEmailOtp(_ownerEmail.text);
  }

  Future<void> _verifyOtp() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_otp.text)) {
      setState(() => _localError = 'ENTER THE SIX-DIGIT CODE.');
      _otpFocus.requestFocus();
      return;
    }
    setState(() => _localError = null);
    await ref
        .read(familyInviteControllerProvider.notifier)
        .verifyEmailOtp(_otp.text);
  }

  Future<void> _createInvite() async {
    if (!_looksLikeEmail(_recipientEmail.text)) {
      setState(() => _localError = 'ENTER A COMPLETE EMAIL ADDRESS.');
      _recipientEmailFocus.requestFocus();
      return;
    }
    setState(() => _localError = null);
    await ref
        .read(familyInviteControllerProvider.notifier)
        .createInvite(
          _recipientEmail.text,
          sharePositionOrigin: _globalRect(_createKey),
        );
  }

  Future<void> _shareAgain() => ref
      .read(familyInviteControllerProvider.notifier)
      .shareAgain(sharePositionOrigin: _globalRect(_shareKey));

  Future<void> _revoke() =>
      ref.read(familyInviteControllerProvider.notifier).revokeInvite();

  Future<void> _retry() =>
      ref.read(familyInviteControllerProvider.notifier).initialize();

  void _recoverFocus(FamilyInviteState state) {
    if (state.phase != FamilyInvitePhase.failed) return;
    final target = state.failure?.code == InvitationFailureCode.signedOut
        ? _ownerEmailFocus
        : switch (state.retryPoint) {
            FamilyInviteRetryPoint.requestOtp => _ownerEmailFocus,
            FamilyInviteRetryPoint.verifyOtp => _otpFocus,
            FamilyInviteRetryPoint.create =>
              state.isRecipientLocked ? null : _recipientEmailFocus,
            _ => null,
          };
    if (target != null && !target.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) target.requestFocus();
      });
    }
  }
}

final class _InviteHeader extends StatelessWidget {
  const _InviteHeader({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: IconButton(
      key: const Key('family-invite-back'),
      tooltip: 'Back',
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      onPressed: onBack,
      icon: const Icon(Icons.arrow_back_rounded),
    ),
  );
}

final class _StableButton extends StatelessWidget {
  const _StableButton({
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.onPressed,
    super.key,
  });

  final String label;
  final String busyLabel;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: busy ? busyLabel : label,
    button: true,
    enabled: onPressed != null,
    liveRegion: busy,
    onTap: onPressed,
    child: ExcludeSemantics(
      child: FilledButton(
        style: FilledButton.styleFrom(
          fixedSize: const Size.fromHeight(48),
          elevation: 0,
        ),
        onPressed: onPressed,
        child: busy
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : KeepersText(label),
      ),
    ),
  );
}

final class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Semantics(
      liveRegion: true,
      label: message,
      child: ExcludeSemantics(
        child: KeepersText(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            height: 1.35,
          ),
        ),
      ),
    ),
  );
}

final class _FeedbackSlot extends StatelessWidget {
  const _FeedbackSlot({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 104,
    child: message == null ? null : _InlineError(message!),
  );
}

final class _Status extends StatelessWidget {
  const _Status({required this.message, required this.busy});

  final String message;
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: message,
    child: ExcludeSemantics(
      child: Row(
        children: [
          if (busy) ...[
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: KeepersText(
              message,
              style: const TextStyle(color: KeepersColors.inkMuted),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 88),
        child: KeepersText(
          label,
          style: const TextStyle(
            color: KeepersColors.inkMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            color: KeepersColors.ink,
            fontFamily: KeepersType.primary,
            height: 1.35,
          ),
        ),
      ),
    ],
  );
}

Rect? _globalRect(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) {
    return null;
  }
  final origin = box.localToGlobal(Offset.zero);
  final rect = origin & box.size;
  return rect.isFinite ? rect : null;
}

String _expiry(DateTime value) {
  final utc = value.toUtc();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)} UTC';
}

String _failureMessage(InvitationFailure? failure) => switch (failure?.code) {
  InvitationFailureCode.notConfigured =>
    'CLOUD INVITATIONS ARE NOT CONFIGURED FOR THIS BUILD.',
  InvitationFailureCode.signedOut =>
    'YOUR OWNER SESSION CHANGED. SIGN IN AND TRY AGAIN.',
  InvitationFailureCode.invalidEmail =>
    'ENTER A COMPLETE EMAIL ADDRESS AND TRY AGAIN.',
  InvitationFailureCode.invalidOtp =>
    'THAT CODE COULD NOT BE VERIFIED. CHECK IT AND TRY AGAIN.',
  InvitationFailureCode.networkUnavailable =>
    'KEEPERS COULD NOT REACH THE INVITATION SERVICE. TRY AGAIN.',
  InvitationFailureCode.forbidden || InvitationFailureCode.notOwner =>
    'ONLY THE FAMILY OWNER CAN CREATE OR CANCEL INVITATIONS.',
  InvitationFailureCode.differentFamily =>
    'THIS KEEPERS PROFILE IS CONNECTED TO A DIFFERENT ACCOUNT.',
  _ => 'THE INVITATION COULD NOT BE UPDATED SAFELY. TRY AGAIN.',
};

bool _looksLikeEmail(String value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
