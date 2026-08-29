import 'package:flutter/material.dart';
import 'package:keepers/theme/keepers_theme.dart';

enum AccountConflictKind { profileAccountMismatch, accountAlreadyHasFamily }

final class AccountConflictScreen extends StatefulWidget {
  const AccountConflictScreen({
    required this.kind,
    required this.onUseAnotherAccount,
    super.key,
  });

  final AccountConflictKind kind;
  final Future<void> Function() onUseAnotherAccount;

  @override
  State<AccountConflictScreen> createState() => _AccountConflictScreenState();
}

final class _AccountConflictScreenState extends State<AccountConflictScreen> {
  var _isSwitching = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = switch (widget.kind) {
      AccountConflictKind.profileAccountMismatch =>
        'THIS KEEPERS PROFILE IS CONNECTED TO A DIFFERENT ACCOUNT.',
      AccountConflictKind.accountAlreadyHasFamily =>
        'THIS ACCOUNT IS ALREADY CONNECTED TO ANOTHER FAMILY.',
    };
    final explanation = switch (widget.kind) {
      AccountConflictKind.profileAccountMismatch => "This phone's private family space was not changed. Sign in with the account that belongs to this profile.",
      AccountConflictKind.accountAlreadyHasFamily => "This phone's private family space was not changed. Choose another account to connect it to the family on this phone.",
    };

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
                    title,
                    key: const Key('account-conflict-title'),
                    style: KeepersType.heading.copyWith(
                      color: colors.onSurface,
                      fontSize: 28,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 14),
                  KeepersText(
                    explanation,
                    style: textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  SizedBox(
                    height: 54,
                    child: _errorMessage == null
                        ? null
                        : Center(
                            child: Semantics(
                              liveRegion: true,
                              label: _errorMessage,
                              child: ExcludeSemantics(
                                child: KeepersText(
                                  _errorMessage!,
                                  key: const Key('account-conflict-error'),
                                  textAlign: TextAlign.center,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colors.error,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                  FilledButton(
                    key: const Key('use-another-account'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _isSwitching ? null : _useAnotherAccount,
                    child: _isSwitching
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const KeepersText('Use another account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _useAnotherAccount() async {
    if (_isSwitching) return;
    setState(() {
      _isSwitching = true;
      _errorMessage = null;
    });
    try {
      await widget.onUseAnotherAccount();
    } on Object {
      if (!mounted) return;
      setState(() {
        _isSwitching = false;
        _errorMessage =
            "We couldn't switch accounts. Check your connection and try again.";
      });
    }
  }
}
