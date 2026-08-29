import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/presentation/family_join_screen.dart';
import 'package:keepers/features/onboarding/application/setup_controller.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/theme/keepers_theme.dart';

final class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key, this.statusMessage, this.onReauthenticate});

  final String? statusMessage;
  final VoidCallback? onReauthenticate;

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

final class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _familyName = TextEditingController();
  final _memberName = TextEditingController();
  var _branch = _SetupBranch.choice;

  bool get _hasBothNames =>
      _familyName.text.trim().isNotEmpty && _memberName.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _familyName.addListener(_onTextChanged);
    _memberName.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _familyName
      ..removeListener(_onTextChanged)
      ..dispose();
    _memberName
      ..removeListener(_onTextChanged)
      ..dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  Future<void> _submit() {
    return ref
        .read(setupControllerProvider.notifier)
        .submit(
          SetupInput(
            familyName: _familyName.text.trim(),
            memberName: _memberName.text.trim(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(setupControllerProvider);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final canSubmit =
        _hasBothNames && !setup.isSubmitting && !setup.requiresAuthentication;

    return PopScope<void>(
      canPop: _branch == _SetupBranch.choice,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _branch != _SetupBranch.choice) {
          setState(() => _branch = _SetupBranch.choice);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
                    const SizedBox(height: 48),
                    if (widget.statusMessage case final message?) ...[
                      Semantics(
                        liveRegion: true,
                        label: message,
                        child: ExcludeSemantics(
                          child: KeepersText(
                            message,
                            key: const Key('setup-status'),
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (_branch == _SetupBranch.choice) ...[
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              key: const Key('create-family-choice'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                              onPressed: () =>
                                  setState(() => _branch = _SetupBranch.create),
                              child: const KeepersText('CREATE A FAMILY'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              key: const Key('join-family-choice'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                              onPressed: () async {
                                await Navigator.of(context).push<void>(
                                  MaterialPageRoute<void>(
                                    settings: const RouteSettings(
                                      name: '/family/join/manual',
                                    ),
                                    builder: (_) =>
                                        const FamilyJoinScreen.manual(),
                                  ),
                                );
                              },
                              child: const KeepersText('JOIN A FAMILY'),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const Key('setup-choice-back'),
                          onPressed: () =>
                              setState(() => _branch = _SetupBranch.choice),
                          child: const KeepersText('BACK'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      KeepersText(
                        'Name your family space',
                        style: KeepersType.heading.copyWith(
                          color: textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 12),
                      KeepersText(
                        'Create one private space and your local keeper profile.',
                        style: textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        key: const Key('family-name'),
                        controller: _familyName,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(setupNameMaxLength),
                        ],
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.organizationName],
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          label: KeepersText('Family name'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('member-name'),
                        controller: _memberName,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(setupNameMaxLength),
                        ],
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.name],
                        onSubmitted: canSubmit ? (_) => _submit() : null,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          label: KeepersText('Your name'),
                        ),
                      ),
                      if (setup.validationMessage case final message?) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          label: message,
                          liveRegion: true,
                          child: ExcludeSemantics(
                            child: KeepersText(
                              message,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colors.error,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (setup.errorMessage case final message?) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          label: message,
                          liveRegion: true,
                          child: ExcludeSemantics(
                            child: KeepersText(
                              message,
                              key: const Key('setup-error'),
                              style: textTheme.bodyMedium?.copyWith(
                                color: colors.error,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (setup.requiresAuthentication &&
                          widget.onReauthenticate != null) ...[
                        const SizedBox(height: 16),
                        OutlinedButton(
                          key: const Key('setup-reauthenticate'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: widget.onReauthenticate,
                          child: const KeepersText('Sign in again'),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Semantics(
                        label: setup.isSubmitting
                            ? 'Entering the Observatory'
                            : 'Enter the Observatory',
                        button: true,
                        enabled: canSubmit,
                        liveRegion: setup.isSubmitting,
                        onTap: canSubmit ? _submit : null,
                        child: ExcludeSemantics(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: canSubmit ? _submit : null,
                            child: setup.isSubmitting
                                ? const SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const KeepersText('Enter the Observatory'),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SetupBranch { choice, create }
