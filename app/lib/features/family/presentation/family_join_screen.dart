import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/members/domain/avatar_catalog.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/theme/keepers_theme.dart';

enum _FamilyJoinEntry { manual, code, malformed }

final class FamilyJoinScreen extends ConsumerStatefulWidget {
  const FamilyJoinScreen.manual({
    super.key,
    this.onCompleted,
    this.onAbandoned,
    this.resumePendingRequest = false,
  }) : code = null,
       _entry = _FamilyJoinEntry.manual;

  const FamilyJoinScreen.forCode(
    this.code, {
    super.key,
    this.onCompleted,
    this.onAbandoned,
  }) : resumePendingRequest = false,
       _entry = _FamilyJoinEntry.code;

  const FamilyJoinScreen.malformed({super.key, this.onAbandoned})
    : code = null,
      onCompleted = null,
      resumePendingRequest = false,
      _entry = _FamilyJoinEntry.malformed;

  final FamilyCode? code;
  final VoidCallback? onCompleted;
  final VoidCallback? onAbandoned;
  final bool resumePendingRequest;
  final _FamilyJoinEntry _entry;

  @override
  ConsumerState<FamilyJoinScreen> createState() => _FamilyJoinScreenState();
}

final class _FamilyJoinScreenState extends ConsumerState<FamilyJoinScreen>
    with WidgetsBindingObserver {
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _name = TextEditingController();
  final _codeFocus = FocusNode(debugLabel: 'family code');
  final _emailFocus = FocusNode(debugLabel: 'join email');
  final _otpFocus = FocusNode(debugLabel: 'join email code');
  final _nameFocus = FocusNode(debugLabel: 'join profile name');
  final _actionFocus = FocusNode(debugLabel: 'join recovery action');
  final _retryFocus = FocusNode(debugLabel: 'retry family join');
  AvatarConfig? _avatar;
  AvatarCategory _avatarCategory = AvatarCategory.head;
  String? _localMessage;
  var _completionHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget._entry == _FamilyJoinEntry.malformed) return;
      final controller = ref.read(familyJoinControllerProvider.notifier);
      final code = widget.code;
      if (code != null) {
        unawaited(controller.loadCode(code));
      } else if (widget.resumePendingRequest) {
        unawaited(controller.refreshStatus());
      } else if (widget._entry == _FamilyJoinEntry.manual) {
        _codeFocus.requestFocus();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget._entry != _FamilyJoinEntry.malformed) {
      unawaited(ref.read(familyJoinControllerProvider.notifier).onResumed());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _code.dispose();
    _email.dispose();
    _otp.dispose();
    _name.dispose();
    _codeFocus.dispose();
    _emailFocus.dispose();
    _otpFocus.dispose();
    _nameFocus.dispose();
    _actionFocus.dispose();
    _retryFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget._entry == _FamilyJoinEntry.malformed) {
      return _frame(context, _terminal('Family not found'));
    }

    final state = ref.watch(familyJoinControllerProvider);
    ref.listen(familyJoinControllerProvider, (previous, next) {
      _syncDraft(next);
      if (previous?.phase != next.phase || previous?.failure != next.failure) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _recoverFocus(next);
        });
      }
      if (next.phase == FamilyJoinPhase.complete && !_completionHandled) {
        _completionHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final callback = widget.onCompleted;
          if (callback != null) {
            callback();
          } else {
            Navigator.of(context).maybePop();
          }
        });
      }
    });
    _syncDraft(state);
    final canAbandon =
        _isResolvedTerminal(state.phase) ||
        (!widget.resumePendingRequest && !_hasUnresolvedJoin(state));

    return PopScope<void>(
      canPop: canAbandon && widget.onAbandoned == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && canAbandon) widget.onAbandoned?.call();
      },
      child: _frame(context, _content(state), showBack: canAbandon),
    );
  }

  Widget _frame(BuildContext context, Widget content, {bool showBack = true}) =>
      Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                18,
                24,
                28 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showBack)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          key: const Key('leave-family-join'),
                          tooltip: 'Back',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          onPressed: _abandon,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      )
                    else
                      const SizedBox(height: 48),
                    const SizedBox(height: 20),
                    content,
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _content(FamilyJoinState state) {
    if (_terminalMessage(state) case final message?) return _terminal(message);
    return switch (state.phase) {
      FamilyJoinPhase.enteringCode =>
        widget._entry == _FamilyJoinEntry.manual
            ? _codeEntry(state)
            : _checking('Finding your family'),
      FamilyJoinPhase.checking => _checking('Finding your family'),
      FamilyJoinPhase.needsAuthentication => _emailEntry(state),
      FamilyJoinPhase.awaitingOtp => _otpEntry(state),
      FamilyJoinPhase.preview ||
      FamilyJoinPhase.requesting ||
      FamilyJoinPhase.installing => _preview(state),
      FamilyJoinPhase.pending => _pending(state),
      FamilyJoinPhase.complete => _terminal("You're in"),
      FamilyJoinPhase.declined ||
      FamilyJoinPhase.cancelled ||
      FamilyJoinPhase.expired ||
      FamilyJoinPhase.invitationChanged ||
      FamilyJoinPhase.failed => _recoverableFailure(state),
    };
  }

  Widget _codeEntry(FamilyJoinState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _Title('Join a family'),
      const SizedBox(height: 12),
      const KeepersText(
        'Enter the code shared by someone in your family.',
        style: TextStyle(color: KeepersColors.inkMuted, height: 1.4),
      ),
      const SizedBox(height: 28),
      TextField(
        key: const Key('family-code-field'),
        controller: _code,
        focusNode: _codeFocus,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        onSubmitted: (_) => _submitCode(),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          label: KeepersText('Family code'),
          hintText: 'K7M4-P2Q8',
        ),
      ),
      _feedbackSlot(state),
      _ActionButton(
        key: const Key('continue-family-code'),
        label: 'Continue',
        busy: state.isBusy,
        focusNode: _actionFocus,
        onPressed: state.isBusy ? null : _submitCode,
      ),
    ],
  );

  Widget _emailEntry(FamilyJoinState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _Title('Sign in to request access'),
      const SizedBox(height: 12),
      const KeepersText(
        'Use your email to continue with this family code.',
        style: TextStyle(color: KeepersColors.inkMuted, height: 1.4),
      ),
      const SizedBox(height: 28),
      TextField(
        key: const Key('join-email'),
        controller: _email,
        focusNode: _emailFocus,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.email],
        onSubmitted: (_) => _requestOtp(),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          label: KeepersText('Email'),
        ),
      ),
      _feedbackSlot(state),
      _ActionButton(
        label: 'Send code',
        busy: state.isBusy,
        focusNode: _actionFocus,
        onPressed: state.isBusy ? null : _requestOtp,
      ),
    ],
  );

  Widget _otpEntry(FamilyJoinState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _Title('Check your email'),
      const SizedBox(height: 12),
      const KeepersText(
        'Open the sign-in link or enter the six-digit code. This family code will stay ready.',
        style: TextStyle(color: KeepersColors.inkMuted, height: 1.4),
      ),
      const SizedBox(height: 28),
      TextField(
        key: const Key('join-email-otp'),
        controller: _otp,
        focusNode: _otpFocus,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.oneTimeCode],
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _verifyOtp(),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          label: KeepersText('Email code'),
          counterText: '',
        ),
      ),
      _feedbackSlot(state),
      _ActionButton(
        label: 'Verify code',
        busy: state.isBusy,
        focusNode: _actionFocus,
        onPressed: state.isBusy ? null : _verifyOtp,
      ),
      const SizedBox(height: 8),
      TextButton(
        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: state.isBusy
            ? null
            : () => ref
                  .read(familyJoinControllerProvider.notifier)
                  .changeAuthenticationEmail(),
        child: const KeepersText('Change email'),
      ),
    ],
  );

  Widget _preview(FamilyJoinState state) {
    final preview = state.preview;
    final avatar = _avatar ?? state.proposedAvatar;
    if (preview == null || avatar == null) {
      return _checking('Finding your family');
    }
    final busy =
        state.phase == FamilyJoinPhase.requesting ||
        state.phase == FamilyJoinPhase.installing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title(preview.familyName),
        const SizedBox(height: 12),
        const KeepersText(
          'Make sure this looks like the right family.',
          style: TextStyle(color: KeepersColors.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var index = 0; index < preview.members.length; index += 1)
              ExcludeSemantics(
                child: Container(
                  key: Key('family-preview-avatar-$index'),
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: KeepersColors.auraIvory,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: KeepersColors.homeLine),
                  ),
                  child: KeepersAvatar(
                    config: avatarCatalog.sanitize(
                      preview.members[index].avatar,
                      fallbackSeed: preview.members[index].id,
                    ),
                    size: 56,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        TextField(
          key: const Key('join-member-name'),
          controller: _name,
          focusNode: _nameFocus,
          enabled: !busy,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.name],
          inputFormatters: [LengthLimitingTextInputFormatter(100)],
          onSubmitted: (_) => _requestJoin(),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            label: KeepersText('Your name'),
          ),
        ),
        const SizedBox(height: 20),
        _JoinAvatarPicker(
          config: avatar,
          category: _avatarCategory,
          enabled: !busy,
          onCategorySelected: (category) =>
              setState(() => _avatarCategory = category),
          onSelected: (option) => setState(() {
            _avatar = avatarCatalog.sanitize(
              option.apply(avatar),
              fallbackSeed: avatar.seed,
            );
          }),
        ),
        _feedbackSlot(state),
        _ActionButton(
          key: const Key('join-family-submit'),
          label: state.phase == FamilyJoinPhase.installing
              ? 'Joining family'
              : 'Request to join',
          busy: busy,
          focusNode: _actionFocus,
          onPressed: busy ? null : _requestJoin,
        ),
      ],
    );
  }

  Widget _pending(FamilyJoinState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _Title('Request sent'),
      const SizedBox(height: 16),
      const KeepersText(
        'Waiting for a family member to let you in',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: KeepersColors.inkMuted,
          fontSize: 18,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 18),
      const Center(child: CircularProgressIndicator()),
      _feedbackSlot(state),
      OutlinedButton(
        key: const Key('cancel-join-request'),
        focusNode: _actionFocus,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: state.isBusy
            ? null
            : () => unawaited(
                ref.read(familyJoinControllerProvider.notifier).cancel(),
              ),
        child: const KeepersText('Cancel'),
      ),
    ],
  );

  Widget _checking(String message) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: 48),
      const CircularProgressIndicator(),
      const SizedBox(height: 20),
      Semantics(
        liveRegion: true,
        child: KeepersText(message, textAlign: TextAlign.center),
      ),
      const SizedBox(height: 48),
    ],
  );

  Widget _terminal(String message) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Icons.family_restroom_rounded, size: 48),
      const SizedBox(height: 20),
      Semantics(
        liveRegion: true,
        label: message,
        child: ExcludeSemantics(
          child: KeepersText(
            message,
            textAlign: TextAlign.center,
            style: KeepersType.heading.copyWith(color: KeepersColors.ink),
          ),
        ),
      ),
      const SizedBox(height: 28),
      OutlinedButton(
        focusNode: _actionFocus,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _abandon,
        child: const KeepersText('Back'),
      ),
    ],
  );

  Widget _recoverableFailure(FamilyJoinState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _Title('We could not continue'),
      const SizedBox(height: 12),
      const KeepersText(
        'Your family code and request details are still here.',
        style: TextStyle(color: KeepersColors.inkMuted, height: 1.4),
      ),
      _feedbackSlot(state),
      OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _abandon,
        child: const KeepersText('Back'),
      ),
    ],
  );

  Widget _feedbackSlot(FamilyJoinState state) {
    final message = _localMessage ?? _recoverableMessage(state.failure?.code);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 120),
      child: message == null
          ? null
          : Center(
              child: Semantics(
                liveRegion: true,
                label: message,
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: KeepersText(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: KeepersColors.inkMuted,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (state.retryPoint != null) ...[
                        const SizedBox(height: 2),
                        TextButton(
                          focusNode: _retryFocus,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(96, 48),
                          ),
                          onPressed: state.isBusy
                              ? null
                              : () => unawaited(
                                  ref
                                      .read(
                                        familyJoinControllerProvider.notifier,
                                      )
                                      .retry(),
                                ),
                          child: const KeepersText('Retry'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  void _syncDraft(FamilyJoinState state) {
    if (_email.text.isEmpty && state.authenticationEmail.isNotEmpty) {
      _email.text = state.authenticationEmail;
    }
    _avatar ??= state.proposedAvatar;
    final request = state.request;
    if (_name.text.isEmpty && request != null) _name.text = request.displayName;
  }

  void _submitCode() {
    try {
      final parsed = FamilyCode.parse(_code.text);
      setState(() => _localMessage = null);
      unawaited(
        ref.read(familyJoinControllerProvider.notifier).loadCode(parsed),
      );
    } on FormatException {
      setState(
        () => _localMessage = 'Enter a valid eight-character family code.',
      );
      _codeFocus.requestFocus();
    }
  }

  void _requestOtp() {
    setState(() => _localMessage = null);
    unawaited(
      ref
          .read(familyJoinControllerProvider.notifier)
          .requestEmailOtp(_email.text),
    );
  }

  void _verifyOtp() {
    setState(() => _localMessage = null);
    unawaited(
      ref
          .read(familyJoinControllerProvider.notifier)
          .verifyEmailOtp(email: _email.text, token: _otp.text),
    );
  }

  void _requestJoin() {
    final state = ref.read(familyJoinControllerProvider);
    final memberId = state.proposedMemberId;
    final publicKey = state.proposedJoiningPublicKey;
    final avatar = _avatar ?? state.proposedAvatar;
    if (_name.text.trim().isEmpty ||
        memberId == null ||
        publicKey == null ||
        avatar == null) {
      setState(() => _localMessage = 'Add your name before requesting access.');
      _nameFocus.requestFocus();
      return;
    }
    setState(() => _localMessage = null);
    unawaited(
      ref
          .read(familyJoinControllerProvider.notifier)
          .requestJoin(
            FamilyJoinProfileDraft(
              memberId: memberId,
              displayName: _name.text.trim(),
              demographicRole: FamilyDemographicRole.adult,
              colorToken: 'ochre',
              avatar: avatar,
              joiningPublicKey: publicKey,
            ),
          ),
    );
  }

  void _recoverFocus(FamilyJoinState state) {
    if (state.isBusy) return;
    if (state.failure != null &&
        state.retryPoint != null &&
        _terminalMessage(state) == null) {
      _retryFocus.requestFocus();
      return;
    }
    switch (state.phase) {
      case FamilyJoinPhase.enteringCode:
        _codeFocus.requestFocus();
      case FamilyJoinPhase.needsAuthentication:
        _emailFocus.requestFocus();
      case FamilyJoinPhase.awaitingOtp:
        _otpFocus.requestFocus();
      case FamilyJoinPhase.preview:
        _nameFocus.requestFocus();
      case FamilyJoinPhase.pending ||
          FamilyJoinPhase.declined ||
          FamilyJoinPhase.cancelled ||
          FamilyJoinPhase.expired ||
          FamilyJoinPhase.invitationChanged ||
          FamilyJoinPhase.failed:
        _actionFocus.requestFocus();
      case FamilyJoinPhase.checking ||
          FamilyJoinPhase.requesting ||
          FamilyJoinPhase.installing ||
          FamilyJoinPhase.complete:
        break;
    }
  }

  void _abandon() {
    final callback = widget.onAbandoned;
    if (callback != null) {
      callback();
    } else {
      Navigator.of(context).maybePop();
    }
  }
}

final class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => KeepersText(
    text,
    style: KeepersType.heading.copyWith(color: KeepersColors.ink),
  );
}

final class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.busy,
    required this.focusNode,
    required this.onPressed,
  });
  final String label;
  final bool busy;
  final FocusNode focusNode;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    focusNode: focusNode,
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    onPressed: onPressed,
    child: SizedBox(
      height: 24,
      child: Center(
        child: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : KeepersText(label),
      ),
    ),
  );
}

final class _JoinAvatarPicker extends StatelessWidget {
  const _JoinAvatarPicker({
    required this.config,
    required this.category,
    required this.enabled,
    required this.onCategorySelected,
    required this.onSelected,
  });

  final AvatarConfig config;
  final AvatarCategory category;
  final bool enabled;
  final ValueChanged<AvatarCategory> onCategorySelected;
  final ValueChanged<AvatarOption> onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Customize your avatar',
    container: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KeepersAvatar(
              config: config,
              size: 88,
              crop: KeepersAvatarCrop.detail,
              semanticLabel: 'Your avatar preview',
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: KeepersText(
                'Choose the details that feel like you.',
                style: TextStyle(color: KeepersColors.inkMuted, height: 1.35),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in avatarCatalog.categories)
              OutlinedButton(
                key: Key('join-avatar-category-${item.name}'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(72, 48),
                  backgroundColor: item == category
                      ? KeepersColors.ink
                      : KeepersColors.auraIvory,
                  foregroundColor: item == category
                      ? KeepersColors.auraIvory
                      : KeepersColors.ink,
                  side: const BorderSide(color: KeepersColors.homeLine),
                ),
                onPressed: enabled ? () => onCategorySelected(item) : null,
                child: KeepersText(item.name),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in avatarCatalog.optionsFor(category))
              Semantics(
                label: option.label,
                button: true,
                selected: option.isSelected(config),
                child: ExcludeSemantics(
                  child: OutlinedButton(
                    key: Key('join-avatar-option-${option.id}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(72, 72),
                      padding: const EdgeInsets.all(4),
                      backgroundColor: option.isSelected(config)
                          ? KeepersColors.auraBlush
                          : KeepersColors.auraIvory,
                      side: BorderSide(
                        width: option.isSelected(config) ? 2 : 1,
                        color: option.isSelected(config)
                            ? KeepersColors.ink
                            : KeepersColors.homeLine,
                      ),
                    ),
                    onPressed: enabled ? () => onSelected(option) : null,
                    child: KeepersAvatar(
                      config: avatarCatalog.sanitize(
                        option.apply(config),
                        fallbackSeed: config.seed,
                      ),
                      size: 58,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

String? _terminalMessage(FamilyJoinState state) => switch (state.phase) {
  FamilyJoinPhase.declined => "Your request wasn't accepted",
  FamilyJoinPhase.cancelled => 'Your request was cancelled',
  FamilyJoinPhase.expired => 'Your request has expired',
  FamilyJoinPhase.invitationChanged =>
    'This family invitation has changed. Ask for the new code.',
  FamilyJoinPhase.failed => switch (state.failure?.code) {
    FamilyJoinFailureCode.alreadyMember => 'You already belong to a family',
    FamilyJoinFailureCode.familyNotFound => 'Family not found',
    FamilyJoinFailureCode.invitationChanged ||
    FamilyJoinFailureCode.codeVersionChanged =>
      'This family invitation has changed. Ask for the new code.',
    _ => null,
  },
  _ => null,
};

bool _isResolvedTerminal(FamilyJoinPhase phase) => switch (phase) {
  FamilyJoinPhase.complete ||
  FamilyJoinPhase.declined ||
  FamilyJoinPhase.cancelled ||
  FamilyJoinPhase.expired ||
  FamilyJoinPhase.invitationChanged => true,
  _ => false,
};

bool _hasUnresolvedJoin(FamilyJoinState state) =>
    switch (state.phase) {
      FamilyJoinPhase.requesting ||
      FamilyJoinPhase.pending ||
      FamilyJoinPhase.installing ||
      FamilyJoinPhase.complete => true,
      _ => false,
    } ||
    switch (state.request?.state) {
      FamilyJoinRequestState.pending ||
      FamilyJoinRequestState.approved ||
      FamilyJoinRequestState.installed => true,
      _ => false,
    } ||
    (state.failure != null &&
        state.retryPoint == FamilyJoinRetryPoint.requestJoin);

String? _recoverableMessage(FamilyJoinFailureCode? code) => switch (code) {
  null => null,
  FamilyJoinFailureCode.networkUnavailable =>
    'Keepers could not connect. Try again.',
  FamilyJoinFailureCode.notConfigured =>
    'Family joining is not available on this device.',
  FamilyJoinFailureCode.rateLimited =>
    'Please wait a moment before trying again.',
  FamilyJoinFailureCode.invalidJoinKey ||
  FamilyJoinFailureCode.envelopeRejected =>
    'This approval could not be verified.',
  FamilyJoinFailureCode.localPersistenceFailed =>
    'Keepers could not finish saving this family.',
  FamilyJoinFailureCode.signedOut => 'Sign in again to continue.',
  _ => 'Keepers could not continue. Try again.',
};
