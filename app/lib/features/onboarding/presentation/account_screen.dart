import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/onboarding/application/account_auth_controller.dart';
import 'package:keepers/theme/keepers_theme.dart';

final class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({required this.onAuthenticated, this.onRetry, super.key});

  final VoidCallback onAuthenticated;
  final VoidCallback? onRetry;

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

final class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _emailFocus = FocusNode(debugLabel: 'account email');
  final _codeFocus = FocusNode(debugLabel: 'account email code');
  ProviderSubscription<AccountAuthState>? _authSubscription;
  var _showCode = false;
  var _completionScheduled = false;

  @override
  void initState() {
    super.initState();
    _authSubscription = ref.listenManual(
      accountAuthControllerProvider,
      _onAuthStateChanged,
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _email.dispose();
    _code.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gateway = ref.watch(cloudFamilyGatewayProvider);
    final auth = ref.watch(accountAuthControllerProvider);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final awaitingCode =
        _showCode || auth.phase == AccountAuthPhase.awaitingCode;
    final awaitingProvider = auth.phase == AccountAuthPhase.awaitingProvider;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_rounded, color: colors.primary),
                      const SizedBox(width: 10),
                      KeepersText(
                        'KEEPERS',
                        style: textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 44),
                  KeepersText(
                    gateway.isConfigured
                        ? (awaitingProvider
                              ? 'Finish in your browser'
                              : awaitingCode
                              ? 'Check your email'
                              : 'Create your Keepers account')
                        : 'Account setup is unavailable right now.',
                    style: KeepersType.heading.copyWith(
                      color: colors.onSurface,
                      fontSize: 28,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 14),
                  KeepersText(
                    gateway.isConfigured
                        ? (awaitingProvider
                              ? 'Complete sign-in in the browser, then return to Keepers. We’ll continue automatically.'
                              : awaitingCode
                              ? 'Open the sign-in link or enter the six-digit code we sent to ${auth.email}.'
                              : 'Your account connects you to your family. Your memories and keys stay private on this device.')
                        : 'Check your connection and try again. New family spaces need a Keepers account.',
                    style: textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 30),
                  if (!gateway.isConfigured)
                    _UnavailableAction(onRetry: widget.onRetry)
                  else if (awaitingProvider)
                    _providerPending(auth)
                  else if (awaitingCode)
                    _codeForm(auth)
                  else
                    _accountChoices(auth),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountChoices(AccountAuthState auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProviderButton(
          provider: SocialAuthProvider.google,
          label: 'Continue with Google',
          onPressed: auth.isBusy
              ? null
              : () => _startSocialAuth(SocialAuthProvider.google),
        ),
        const SizedBox(height: 12),
        _ProviderButton(
          provider: SocialAuthProvider.microsoft,
          label: 'Continue with Microsoft',
          onPressed: auth.isBusy
              ? null
              : () => _startSocialAuth(SocialAuthProvider.microsoft),
        ),
        const SizedBox(height: 12),
        _ProviderButton(
          provider: SocialAuthProvider.apple,
          label: 'Continue with Apple',
          onPressed: auth.isBusy
              ? null
              : () => _startSocialAuth(SocialAuthProvider.apple),
        ),
        const SizedBox(height: 24),
        const _DividerLabel(),
        const SizedBox(height: 24),
        TextField(
          key: const Key('account-email'),
          controller: _email,
          focusNode: _emailFocus,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          enabled: !auth.isBusy,
          onSubmitted: (_) => _requestEmailCode(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            label: const KeepersText('Email address'),
          ),
        ),
        _FeedbackSlot(
          message: auth.phase == AccountAuthPhase.error
              ? auth.errorMessage
              : null,
        ),
        FilledButton(
          key: const Key('continue-with-email'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: auth.isBusy ? null : _requestEmailCode,
          child: const KeepersText('Continue with email'),
        ),
        _ProgressSlot(isBusy: auth.isBusy),
        KeepersText(
          'Already have an account? Use the same options to continue.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _codeForm(AccountAuthState auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('account-email-code'),
          controller: _code,
          focusNode: _codeFocus,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          enabled: !auth.isBusy,
          onSubmitted: (_) => _verifyEmailCode(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            label: const KeepersText('Email code'),
            counterText: '',
          ),
        ),
        _FeedbackSlot(
          message: auth.phase == AccountAuthPhase.error
              ? auth.errorMessage
              : null,
        ),
        FilledButton(
          key: const Key('verify-account-code'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: auth.isBusy ? null : _verifyEmailCode,
          child: const KeepersText('Verify code'),
        ),
        _ProgressSlot(isBusy: auth.isBusy),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: auth.isBusy ? null : _changeEmail,
          child: const KeepersText('Use a different email'),
        ),
      ],
    );
  }

  Widget _providerPending(AccountAuthState auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          liveRegion: true,
          label: 'Waiting for browser sign-in',
          child: ExcludeSemantics(
            child: KeepersText(
              'Waiting for browser sign-in…',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (auth.errorMessage != null)
          _FeedbackSlot(message: auth.errorMessage),
        OutlinedButton(
          key: const Key('choose-another-account-auth'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: _chooseAnotherWay,
          child: const KeepersText('Choose another way'),
        ),
      ],
    );
  }

  Future<void> _requestEmailCode() async {
    await ref
        .read(accountAuthControllerProvider.notifier)
        .requestEmailCode(_email.text);
    if (!mounted) return;
    final state = ref.read(accountAuthControllerProvider);
    if (state.phase == AccountAuthPhase.awaitingCode) {
      setState(() => _showCode = true);
      _codeFocus.requestFocus();
    } else if (state.phase == AccountAuthPhase.error) {
      _emailFocus.requestFocus();
    }
  }

  Future<void> _verifyEmailCode() async {
    await ref
        .read(accountAuthControllerProvider.notifier)
        .verifyEmailCode(_code.text);
    if (!mounted) return;
    if (ref.read(accountAuthControllerProvider).phase ==
        AccountAuthPhase.error) {
      _codeFocus.requestFocus();
    }
  }

  Future<void> _startSocialAuth(SocialAuthProvider provider) => ref
      .read(accountAuthControllerProvider.notifier)
      .startSocialAuth(provider);

  Future<void> _chooseAnotherWay() async {
    await ref.read(accountAuthControllerProvider.notifier).chooseAnotherWay();
    if (!mounted ||
        ref.read(accountAuthControllerProvider).phase !=
            AccountAuthPhase.idle) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emailFocus.requestFocus();
    });
  }

  void _changeEmail() {
    ref.read(accountAuthControllerProvider.notifier).changeEmail();
    _code.clear();
    setState(() => _showCode = false);
    _emailFocus.requestFocus();
  }

  void _onAuthStateChanged(AccountAuthState? previous, AccountAuthState next) {
    if (next.phase != AccountAuthPhase.authenticated || _completionScheduled) {
      return;
    }
    _completionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onAuthenticated();
    });
  }
}

final class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.provider,
    required this.label,
    required this.onPressed,
  });

  final SocialAuthProvider provider;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 18),
      ),
      onPressed: onPressed,
      icon: ExcludeSemantics(
        child: SizedBox(
          width: 24,
          child: Center(child: _ProviderMark(provider)),
        ),
      ),
      label: Center(child: KeepersText(label)),
    );
  }
}

final class _ProviderMark extends StatelessWidget {
  const _ProviderMark(this.provider);

  final SocialAuthProvider provider;

  @override
  Widget build(BuildContext context) {
    return switch (provider) {
      SocialAuthProvider.google => const Text(
        'G',
        semanticsLabel: 'Google',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
      SocialAuthProvider.microsoft => Semantics(
        label: 'Microsoft',
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: 17,
            child: Wrap(
              spacing: 2,
              runSpacing: 2,
              children: const [
                _MicrosoftSquare(Color(0xFFF25022)),
                _MicrosoftSquare(Color(0xFF7FBA00)),
                _MicrosoftSquare(Color(0xFF00A4EF)),
                _MicrosoftSquare(Color(0xFFFFB900)),
              ],
            ),
          ),
        ),
      ),
      SocialAuthProvider.apple => const Icon(
        Icons.apple,
        size: 21,
        semanticLabel: 'Apple',
      ),
    };
  }
}

final class _MicrosoftSquare extends StatelessWidget {
  const _MicrosoftSquare(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: color, child: const SizedBox.square(dimension: 7.5));
}

final class _DividerLabel extends StatelessWidget {
  const _DividerLabel();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return Row(
      children: [
        Expanded(child: Divider(color: color)),
        const Flexible(
          flex: 4,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: KeepersText(
              'or continue with email',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        Expanded(child: Divider(color: color)),
      ],
    );
  }
}

final class _FeedbackSlot extends StatelessWidget {
  const _FeedbackSlot({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final value = message;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 42),
      child: value == null
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Semantics(
                  label: value,
                  liveRegion: true,
                  child: ExcludeSemantics(
                    child: KeepersText(
                      value,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

final class _ProgressSlot extends StatelessWidget {
  const _ProgressSlot({required this.isBusy});

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: isBusy
          ? const Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : null,
    );
  }
}

final class _UnavailableAction extends StatelessWidget {
  const _UnavailableAction({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: onRetry,
      child: const KeepersText('Try again'),
    );
  }
}
