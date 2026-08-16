import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/members/application/avatar_editor_controller.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/widgets/avatar_draft_picker.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/theme/keepers_theme.dart';

final class AvatarEditorScreen extends ConsumerStatefulWidget {
  const AvatarEditorScreen({
    super.key,
    required this.identity,
    this.initialCategory = AvatarCategory.head,
  });

  final LocalIdentity identity;
  final AvatarCategory initialCategory;

  @override
  ConsumerState<AvatarEditorScreen> createState() => _AvatarEditorScreenState();
}

final class _AvatarEditorScreenState extends ConsumerState<AvatarEditorScreen> {
  var _hasPopped = false;

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(avatarEditorControllerProvider(widget.identity));
    final isSaving = editor.phase == AvatarSavePhase.saving;
    final accent =
        Theme.of(context)
            .extension<ObservatoryTokens>()
            ?.memberColor(widget.identity.colorToken) ??
        KeepersColors.homeGold;

    return PopScope<bool>(
      canPop: !editor.isDirty && !isSaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !isSaving) _requestDismiss(editor);
      },
      child: Scaffold(
        backgroundColor: KeepersColors.auraGround,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(
                        onBack: isSaving ? null : () => _requestDismiss(editor),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Column(
                          children: [
                            KeepersAvatarSurface(
                              key: const Key('avatar-editor-preview'),
                              size: 132,
                              accent: accent,
                              padding: 8,
                              child: KeepersAvatar(
                                key: const Key('avatar-editor-preview-artwork'),
                                config: editor.draft,
                                size: 116,
                                crop: KeepersAvatarCrop.detail,
                                semanticLabel: 'Your avatar preview',
                              ),
                            ),
                            const SizedBox(height: 10),
                            const KeepersText(
                              'Shown on your family wheel.',
                              style: TextStyle(
                                color: KeepersColors.inkMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      AvatarDraftPicker(
                        initialCategory: widget.initialCategory,
                        config: editor.draft,
                        enabled: !isSaving,
                        onSelected: (option) => ref
                            .read(
                              avatarEditorControllerProvider(widget.identity)
                                  .notifier,
                            )
                            .select(option),
                      ),
                    ],
                  ),
                ),
              ),
              _SaveFooter(
                canSave: editor.canSave,
                isSaving: isSaving,
                onSave: _save,
                errorMessage: editor.errorMessage,
                onRetry: isSaving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_hasPopped) return;
    final controller = ref.read(
      avatarEditorControllerProvider(widget.identity).notifier,
    );
    final saved = await controller.save();
    if (!mounted || !saved || _hasPopped) return;
    _hasPopped = true;
    Navigator.of(context).pop(true);
  }

  Future<void> _requestDismiss(AvatarEditorState editor) async {
    if (_hasPopped || editor.phase == AvatarSavePhase.saving) return;
    if (!editor.isDirty) {
      _hasPopped = true;
      Navigator.of(context).maybePop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        elevation: 0,
        backgroundColor: KeepersColors.auraIvory,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeepersText(
                'Discard avatar changes?',
                style: KeepersType.heading.copyWith(color: KeepersColors.ink),
              ),
              const SizedBox(height: 8),
              const KeepersText(
                'Your unsaved avatar choices will be lost.',
                style: TextStyle(color: KeepersColors.inkMuted, height: 1.35),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: KeepersColors.ink,
                        side: const BorderSide(color: KeepersColors.homeLine),
                      ),
                      child: const KeepersText('Keep editing'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: KeepersColors.ink,
                        foregroundColor: KeepersColors.auraIvory,
                        elevation: 0,
                      ),
                      child: const KeepersText('Discard changes'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || discard != true || _hasPopped) return;
    _hasPopped = true;
    Navigator.of(context).pop();
  }
}

final class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox.square(
        dimension: 48,
        child: Semantics(
          label: 'Back',
          button: true,
          onTap: onBack,
          child: ExcludeSemantics(
            child: IconButton(
              key: const Key('avatar-editor-back'),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'BACK',
              color: KeepersColors.ink,
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const KeepersText(
              'YOUR PROFILE',
              style: TextStyle(
                color: KeepersColors.inkMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 3),
            KeepersText(
              'Choose your avatar',
              style: KeepersType.heading.copyWith(color: KeepersColors.ink),
            ),
          ],
        ),
      ),
    ],
  );
}

final class _SaveError extends StatefulWidget {
  const _SaveError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  State<_SaveError> createState() => _SaveErrorState();
}

final class _SaveErrorState extends State<_SaveError> {
  late final FocusNode _retryFocusNode = FocusNode(
    debugLabel: 'avatar save retry',
  );

  @override
  void initState() {
    super.initState();
    _focusRetryAfterBuild();
  }

  @override
  void didUpdateWidget(covariant _SaveError oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        (oldWidget.onRetry == null && widget.onRetry != null)) {
      _focusRetryAfterBuild();
    }
  }

  void _focusRetryAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.onRetry != null) {
        _retryFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _retryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: KeepersColors.auraBlush,
      border: Border.all(color: KeepersColors.homeClay),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, color: KeepersColors.ink),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                key: const Key('avatar-save-error-live-region'),
                label: widget.message,
                liveRegion: true,
                child: ExcludeSemantics(
                  child: KeepersText(
                    widget.message,
                    style: const TextStyle(color: KeepersColors.ink),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                focusNode: _retryFocusNode,
                onPressed: widget.onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: KeepersColors.ink,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const KeepersText('Try again'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _SaveFooter extends StatelessWidget {
  const _SaveFooter({
    required this.canSave,
    required this.isSaving,
    required this.onSave,
    required this.errorMessage,
    required this.onRetry,
  });

  final bool canSave;
  final bool isSaving;
  final VoidCallback onSave;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: KeepersColors.auraGround,
        border: Border(top: BorderSide(color: KeepersColors.homeLine)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (errorMessage != null) ...[
            _SaveError(message: errorMessage!, onRetry: onRetry),
            const SizedBox(height: 10),
          ],
          FilledButton(
            onPressed: canSave ? onSave : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: KeepersColors.ink,
              foregroundColor: KeepersColors.auraIvory,
              disabledBackgroundColor: KeepersColors.homeLine,
              disabledForegroundColor: KeepersColors.inkMuted,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: SizedBox(
              height: 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const KeepersText('Save avatar'),
                  if (isSaving)
                    const Positioned(
                      right: 0,
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: KeepersColors.auraIvory,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
