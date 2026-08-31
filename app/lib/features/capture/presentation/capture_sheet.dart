// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/design_system/observatory/motion_policy.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/capture/application/capture_controller.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:keepers/ui/keepers_app_background.dart';

const _privacyCopy = <PrivacyTier, ({String title, String consequence})>{
  PrivacyTier.journal: (
    title: 'Private Journal',
    consequence: 'Only you can open this memory on this device.',
  ),
  PrivacyTier.reveal: (
    title: 'Weekly Reveal',
    consequence: 'Kept for your family’s next reveal.',
  ),
  PrivacyTier.capsule: (
    title: 'Capsule',
    consequence: 'Shared through Memory Key when each family member is ready.',
  ),
};

final class CaptureSheet extends ConsumerStatefulWidget {
  const CaptureSheet({super.key});

  static Future<EntryMetadata?> show(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final result = await showModalBottomSheet<EntryMetadata>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          Theme(data: KeepersTheme.daylight(), child: const CaptureSheet()),
    );
    final controller = container.read(captureControllerProvider.notifier);
    if (result == null) {
      await controller.finalizeDismissal();
    } else {
      controller.resetAfterCompletion();
    }
    return result;
  }

  @override
  ConsumerState<CaptureSheet> createState() => _CaptureSheetState();
}

final class _CaptureSheetState extends ConsumerState<CaptureSheet> {
  final _captionFocus = FocusNode();
  final _captionController = TextEditingController();
  final _textController = TextEditingController();
  final _capsuleTaskController = TextEditingController();
  Timer? _recordingClock;
  Duration _elapsedRecording = Duration.zero;
  int _stepIndex = 0;
  bool _dialogOpen = false;
  bool _allowPop = false;
  bool _didReturnEntry = false;

  @override
  void dispose() {
    _recordingClock?.cancel();
    _captionFocus.dispose();
    _captionController.dispose();
    _textController.dispose();
    _capsuleTaskController.dispose();
    super.dispose();
  }

  void _syncRecordingClock(CaptureDraft? previous, CaptureDraft next) {
    if (next.isRecording && previous?.isRecording != true) {
      _elapsedRecording = Duration.zero;
      _recordingClock?.cancel();
      _recordingClock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _elapsedRecording += const Duration(seconds: 1));
          final seconds = _elapsedRecording.inSeconds;
          if (seconds == 30 || (seconds > 0 && seconds % 60 == 0)) {
            unawaited(_announce(_elapsedAnnouncement(_elapsedRecording)));
          }
        }
      });
    } else if (!next.isRecording && previous?.isRecording == true) {
      _recordingClock?.cancel();
      _recordingClock = null;
    }
  }

  Future<void> _returnSavedEntry(EntryMetadata entry) async {
    if (_didReturnEntry || !mounted) return;
    final current = ref.read(captureControllerProvider);
    if (current.phase != CapturePhase.saved || current.savedEntry != entry) {
      return;
    }
    _didReturnEntry = true;
    await _announce('Memory kept');
    if (!mounted) return;
    _closeWith(entry);
  }

  Future<void> _announce(String message) => SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    Directionality.of(context),
  );

  void _closeWith(EntryMetadata? result) {
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<void> _requestClose() async {
    final draft = ref.read(captureControllerProvider);
    if (!draft.hasDraft) {
      if (_hasInFlightCapture(draft.phase) ||
          draft.retryRequiresCleanup ||
          draft.cleanupRequired) {
        await ref.read(captureControllerProvider.notifier).discard();
        if (!mounted) return;
        final after = ref.read(captureControllerProvider);
        if (!after.hasDraft &&
            !after.cleanupRequired &&
            after.phase == CapturePhase.editing) {
          _closeWith(null);
        }
        return;
      }
      _closeWith(null);
      return;
    }
    if (_dialogOpen || draft.phase == CapturePhase.saving) return;
    _dialogOpen = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: KeepersText(
          'Discard this memory?',
          style: KeepersType.heading.copyWith(color: KeepersColors.ink),
        ),
        content: const KeepersText(
          'The unfinished memory and any temporary media will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const KeepersText('Keep editing'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const KeepersText('Discard'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (discard != true || !mounted) return;
    await ref.read(captureControllerProvider.notifier).discard();
    if (!mounted) return;
    final after = ref.read(captureControllerProvider);
    if (!after.hasDraft &&
        !after.cleanupRequired &&
        after.phase == CapturePhase.editing) {
      _closeWith(null);
    }
  }

  void _continueToPrivacy(CaptureDraft draft) {
    if (!_canContinueToAccess(draft)) return;
    FocusScope.of(context).unfocus();
    setState(() => _stepIndex = 1);
    unawaited(_announce('Step 2 of 2. Choose who can open this memory.'));
  }

  bool _canContinueToAccess(CaptureDraft draft) =>
      draft.hasPrimary &&
      !draft.isRecording &&
      (draft.phase == CapturePhase.editing ||
          (draft.phase == CapturePhase.failed &&
              draft.retryIntent == CaptureRetryIntent.save));

  void _backToFormat() {
    if (_stepIndex == 0) return;
    setState(() => _stepIndex = 0);
    unawaited(_announce('Step 1 of 2. Choose a memory format.'));
  }

  void _handleSystemBack(CaptureDraft draft) {
    if (_stepIndex == 1 && !_isLocked(draft)) {
      _backToFormat();
    } else {
      unawaited(_requestClose());
    }
  }

  void _syncEditingControllers(CaptureDraft draft) {
    if (_captionController.text != draft.caption) {
      _captionController.value = TextEditingValue(
        text: draft.caption,
        selection: TextSelection.collapsed(offset: draft.caption.length),
      );
    }
    if (_textController.text != draft.text) {
      _textController.value = TextEditingValue(
        text: draft.text,
        selection: TextSelection.collapsed(offset: draft.text.length),
      );
    }
    if (_capsuleTaskController.text != draft.capsuleTask) {
      _capsuleTaskController.value = TextEditingValue(
        text: draft.capsuleTask,
        selection: TextSelection.collapsed(offset: draft.capsuleTask.length),
      );
    }
  }

  Future<void> _toggleRecording() async {
    final wasRecording = ref.read(captureControllerProvider).isRecording;
    await ref.read(captureControllerProvider.notifier).toggleRecording();
    if (!mounted) return;
    final isRecording = ref.read(captureControllerProvider).isRecording;
    if (!wasRecording && isRecording) {
      await _announce('Recording started');
    } else if (wasRecording && !isRecording) {
      await _announce('Recording stopped');
    }
  }

  Future<void> _retry(CaptureDraft draft) async {
    final controller = ref.read(captureControllerProvider.notifier);
    switch (draft.retryIntent) {
      case CaptureRetryIntent.save:
        await controller.save();
      case CaptureRetryIntent.discard:
        await controller.discard();
        if (!mounted) return;
        final after = ref.read(captureControllerProvider);
        if (!after.hasDraft &&
            !after.cleanupRequired &&
            after.phase == CapturePhase.editing) {
          _closeWith(null);
        }
      case CaptureRetryIntent.camera:
        await controller.pickPhoto(PhotoSource.camera);
      case CaptureRetryIntent.library:
        await controller.pickPhoto(PhotoSource.library);
      case CaptureRetryIntent.recording:
        await _toggleRecording();
      case CaptureRetryIntent.replacePrimary:
        await controller.replacePrimary();
      case CaptureRetryIntent.recoverLostPhoto:
        await controller.recoverLostPhoto();
      case CaptureRetryIntent.selectPhoto:
        await controller.selectFormat(MemoryFormat.photo);
      case CaptureRetryIntent.selectVoice:
        await controller.selectFormat(MemoryFormat.voice);
      case CaptureRetryIntent.selectText:
        await controller.selectFormat(MemoryFormat.text);
      case CaptureRetryIntent.pendingCleanup:
        await controller.retryPendingCleanup();
      case CaptureRetryIntent.committedCleanup:
        await controller.retryCleanup();
      case null:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(captureControllerProvider);
    final controller = ref.read(captureControllerProvider.notifier);
    ref.listen<CaptureDraft>(captureControllerProvider, (previous, next) {
      _syncRecordingClock(previous, next);
      if (next.phase == CapturePhase.saved && next.savedEntry != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_returnSavedEntry(next.savedEntry!));
        });
      }
    });
    _syncEditingControllers(draft);
    final theme = KeepersTheme.daylight();
    final tokens = theme.extension<ObservatoryTokens>()!;
    final identity = ref.watch(localIdentityProvider).asData?.value;
    final memberColor = tokens.memberColor(identity?.colorToken ?? 'ochre');
    final viewport = MediaQuery.sizeOf(context);
    final height = math.min(760.0, viewport.height * .94);
    final locked = _isLocked(draft);

    final canDismiss =
        !draft.hasDraft &&
        !draft.retryRequiresCleanup &&
        !draft.cleanupRequired &&
        !_hasInFlightCapture(draft.phase);

    return Theme(
      data: theme,
      child: PopScope<EntryMetadata>(
        canPop: _allowPop || (_stepIndex == 0 && canDismiss),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleSystemBack(draft);
        },
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            height: height,
            child: KeepersAppBackground(
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    24 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            child: Container(
                              width: 44,
                              height: 4,
                              decoration: BoxDecoration(
                                color: KeepersColors.ink.withValues(alpha: .24),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: KeepersColors.ink,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: memberColor.withValues(alpha: .72),
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.add_rounded,
                                  color: KeepersColors.auraIvory,
                                  size: 25,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    KeepersText(
                                      _stepIndex == 0
                                          ? 'Keep a memory'
                                          : 'Who can open it?',
                                      style: KeepersType.heading.copyWith(
                                        color: KeepersColors.ink,
                                      ),
                                    ),
                                    KeepersText(
                                      _stepIndex == 0
                                          ? '1 of 2 · Choose a format'
                                          : '2 of 2 · Choose access',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: KeepersColors.inkMuted,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Semantics(
                                label: 'Close capture',
                                button: true,
                                enabled:
                                    !locked ||
                                    draft.phase == CapturePhase.recovering,
                                onTap:
                                    locked &&
                                        draft.phase != CapturePhase.recovering
                                    ? null
                                    : _requestClose,
                                child: ExcludeSemantics(
                                  child: IconButton(
                                    tooltip: 'Close Capture',
                                    onPressed:
                                        locked &&
                                            draft.phase !=
                                                CapturePhase.recovering
                                        ? null
                                        : _requestClose,
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          AnimatedSwitcher(
                            duration: keepersReduceMotion(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeOutCubic,
                            child: _stepIndex == 0
                                ? KeyedSubtree(
                                    key: const ValueKey('capture-step-format'),
                                    child: _formatStep(
                                      draft: draft,
                                      controller: controller,
                                      memberColor: memberColor,
                                      locked: locked,
                                    ),
                                  )
                                : KeyedSubtree(
                                    key: const ValueKey('capture-step-access'),
                                    child: _accessStep(
                                      draft: draft,
                                      controller: controller,
                                      memberColor: memberColor,
                                      locked: locked,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.security_rounded,
                                size: 16,
                                color: KeepersColors.inkMuted,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: KeepersText(
                                  'Temporary plaintext is removed after save or discard.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: KeepersColors.inkMuted,
                                  ),
                                ),
                              ),
                            ],
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
      ),
    );
  }

  Widget _formatStep({
    required CaptureDraft draft,
    required CaptureController controller,
    required Color memberColor,
    required bool locked,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<MemoryFormat>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: MemoryFormat.photo,
            icon: Icon(Icons.photo_camera_rounded),
            label: KeepersText('Photo'),
          ),
          ButtonSegment(
            value: MemoryFormat.voice,
            icon: Icon(Icons.mic_rounded),
            label: KeepersText('Voice'),
          ),
          ButtonSegment(
            value: MemoryFormat.text,
            icon: Icon(Icons.notes_rounded),
            label: KeepersText('Text'),
          ),
        ],
        selected: {draft.format},
        onSelectionChanged: locked || draft.isRecording
            ? null
            : (formats) => unawaited(controller.selectFormat(formats.single)),
      ),
      const SizedBox(height: 20),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: KeyedSubtree(
          key: ValueKey(draft.format),
          child: _primaryEditor(
            draft: draft,
            controller: controller,
            memberColor: memberColor,
            locked: locked,
          ),
        ),
      ),
      const SizedBox(height: 20),
      TextField(
        key: const Key('memory-caption'),
        controller: _captionController,
        focusNode: _captionFocus,
        enabled: !locked,
        maxLength: 280,
        minLines: 1,
        maxLines: 3,
        onChanged: controller.updateCaption,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          label: KeepersText('Caption (optional)'),
          hint: KeepersText('Add a small detail or date'),
        ),
      ),
      _errorPanel(draft: draft, locked: locked),
      const SizedBox(height: 12),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: KeepersColors.ink,
          foregroundColor: KeepersColors.auraIvory,
        ),
        onPressed: _canContinueToAccess(draft)
            ? () => _continueToPrivacy(draft)
            : null,
        icon: const Icon(Icons.arrow_forward_rounded),
        label: const KeepersText('Continue'),
      ),
    ],
  );

  Widget _accessStep({
    required CaptureDraft draft,
    required CaptureController controller,
    required Color memberColor,
    required bool locked,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      KeepersText(
        'Choose where this memory belongs.',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: KeepersColors.inkMuted),
      ),
      const SizedBox(height: 14),
      ...PrivacyTier.values.map((tier) {
        final copy = _privacyCopy[tier]!;
        final selected = tier == draft.privacy;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RadioListTile<PrivacyTier>(
            key: Key('privacy-${tier.name}'),
            value: tier,
            groupValue: draft.privacy,
            onChanged: locked
                ? null
                : (value) {
                    if (value != null) controller.setPrivacy(value);
                  },
            title: KeepersText(copy.title),
            subtitle: KeepersText(copy.consequence),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 4,
            ),
            tileColor: selected
                ? memberColor.withValues(alpha: .12)
                : KeepersColors.auraIvory.withValues(alpha: .7),
            activeColor: KeepersColors.ink,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: selected
                    ? KeepersColors.ink
                    : KeepersColors.ink.withValues(alpha: .14),
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        );
      }),
      if (draft.privacy == PrivacyTier.capsule) ...[
        const SizedBox(height: 2),
        Material(
          color: KeepersColors.auraIvory.withValues(alpha: .78),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: KeepersColors.ink.withValues(alpha: .14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile.adaptive(
                key: const Key('capsule-task-toggle'),
                value: draft.capsuleTaskEnabled,
                onChanged: locked ? null : controller.setCapsuleTaskEnabled,
                activeColor: KeepersColors.ink,
                title: const KeepersText('Set specific task to unlock'),
                subtitle: const KeepersText(
                  'Optional · each family member confirms the task for themselves.',
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
              ),
              if (draft.capsuleTaskEnabled) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: TextField(
                    key: const Key('capsule-task-field'),
                    controller: _capsuleTaskController,
                    enabled: !locked,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 180,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: controller.updateCapsuleTask,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      label: const KeepersText('Task to unlock'),
                      hint: const KeepersText(
                        'For example, cook our family recipe together',
                      ),
                      helperText: draft.capsuleTask.trim().isEmpty
                          ? 'Add a task. Each member confirms completion on '
                                'their own device.'
                          : 'Each family member confirms completion on their '
                                'own device.',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
      _errorPanel(draft: draft, locked: locked),
      const SizedBox(height: 12),
      Row(
        children: [
          OutlinedButton.icon(
            key: const Key('capture-back'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(108, 52),
              foregroundColor: KeepersColors.ink,
            ),
            onPressed: locked ? null : _backToFormat,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const KeepersText('Back'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              label: draft.phase == CapturePhase.saving
                  ? 'Keeping memory'
                  : 'Keep memory',
              button: true,
              enabled: draft.canSave,
              liveRegion: draft.phase == CapturePhase.saving,
              onTap: draft.canSave ? controller.save : null,
              child: ExcludeSemantics(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: KeepersColors.ink,
                    foregroundColor: KeepersColors.auraIvory,
                  ),
                  onPressed: draft.canSave ? controller.save : null,
                  icon: draft.phase == CapturePhase.saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: KeepersColors.auraIvory,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: KeepersText(
                    draft.phase == CapturePhase.saving
                        ? 'Keeping…'
                        : 'Keep memory',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _errorPanel({required CaptureDraft draft, required bool locked}) {
    final message = draft.errorMessage;
    if (message == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              label: message,
              liveRegion: true,
              child: ExcludeSemantics(
                child: KeepersText(
                  message,
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed:
                draft.retryIntent != null &&
                    (!locked ||
                        draft.phase == CapturePhase.failed ||
                        draft.phase == CapturePhase.committedCleanup)
                ? () => _retry(draft)
                : null,
            child: const KeepersText('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _primaryEditor({
    required CaptureDraft draft,
    required CaptureController controller,
    required Color memberColor,
    required bool locked,
  }) => switch (draft.format) {
    MemoryFormat.photo => _PhotoEditor(
      path: draft.photoPath,
      busy: draft.phase == CapturePhase.picking,
      enabled: !locked,
      onCamera: () => controller.pickPhoto(PhotoSource.camera),
      onLibrary: () => controller.pickPhoto(PhotoSource.library),
      onReplace: controller.replacePrimary,
      onContinue: () => _captionFocus.requestFocus(),
    ),
    MemoryFormat.voice => _VoiceEditor(
      isRecording: draft.isRecording,
      isStarting: draft.phase == CapturePhase.starting,
      duration: draft.isRecording ? _elapsedRecording : draft.voiceDuration,
      hasRecording: draft.voicePath != null,
      amplitudes: controller.amplitudes,
      memberColor: memberColor,
      enabled: !locked,
      onToggle: _toggleRecording,
      onPlay: controller.playVoice,
      onRerecord: controller.replacePrimary,
    ),
    MemoryFormat.text => TextField(
      key: const Key('memory-text'),
      controller: _textController,
      minLines: 5,
      maxLines: 10,
      autofocus: true,
      enabled: !locked,
      onChanged: controller.updateText,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        label: KeepersText('Memory'),
        hint: KeepersText('Write what you want to remember…'),
        alignLabelWithHint: true,
      ),
    ),
  };
}

bool _isLocked(CaptureDraft draft) =>
    draft.retryRequiresCleanup ||
    switch (draft.phase) {
      CapturePhase.recovering ||
      CapturePhase.picking ||
      CapturePhase.starting ||
      CapturePhase.stopping ||
      CapturePhase.cleaning ||
      CapturePhase.saving ||
      CapturePhase.saved ||
      CapturePhase.committedCleanup => true,
      _ => false,
    };

bool _hasInFlightCapture(CapturePhase phase) => switch (phase) {
  CapturePhase.recovering ||
  CapturePhase.picking ||
  CapturePhase.starting ||
  CapturePhase.stopping ||
  CapturePhase.cleaning ||
  CapturePhase.saving => true,
  _ => false,
};

final class _PhotoEditor extends StatelessWidget {
  const _PhotoEditor({
    required this.path,
    required this.busy,
    required this.enabled,
    required this.onCamera,
    required this.onLibrary,
    required this.onReplace,
    required this.onContinue,
  });

  final String? path;
  final bool busy;
  final bool enabled;
  final Future<void> Function() onCamera;
  final Future<void> Function() onLibrary;
  final Future<void> Function() onReplace;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    if (path == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeepersText(
            'Choose a photo',
            style: KeepersType.heading.copyWith(color: KeepersColors.ink),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(150, 48),
                ),
                onPressed: enabled ? onCamera : null,
                icon: const Icon(Icons.photo_camera_rounded),
                label: const KeepersText('Camera'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(170, 48),
                ),
                onPressed: enabled ? onLibrary : null,
                icon: const Icon(Icons.photo_library_rounded),
                label: const KeepersText('Photo Library'),
              ),
            ],
          ),
          if (busy) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            const KeepersText('Opening photo picker…'),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 230,
            child: Image.file(
              File(path!),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Center(
                child: KeepersText('Photo preview unavailable.'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
              onPressed: enabled ? onReplace : null,
              icon: const Icon(Icons.refresh_rounded),
              label: const KeepersText('Replace'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
              onPressed: enabled ? onContinue : null,
              icon: const Icon(Icons.arrow_downward_rounded),
              label: const KeepersText('Add caption'),
            ),
          ],
        ),
      ],
    );
  }
}

final class _VoiceEditor extends StatelessWidget {
  const _VoiceEditor({
    required this.isRecording,
    required this.isStarting,
    required this.duration,
    required this.hasRecording,
    required this.amplitudes,
    required this.memberColor,
    required this.enabled,
    required this.onToggle,
    required this.onPlay,
    required this.onRerecord,
  });

  final bool isRecording;
  final bool isStarting;
  final Duration duration;
  final bool hasRecording;
  final Stream<double> amplitudes;
  final Color memberColor;
  final bool enabled;
  final Future<void> Function() onToggle;
  final Future<void> Function() onPlay;
  final Future<void> Function() onRerecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (!hasRecording) ...[
          Semantics(
            key: const Key('record-toggle'),
            label: isRecording
                ? 'Stop voice recording'
                : 'Start voice recording',
            button: true,
            enabled: enabled,
            onTap: enabled ? onToggle : null,
            child: ExcludeSemantics(
              child: SizedBox.square(
                dimension: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                    backgroundColor: isRecording
                        ? theme.colorScheme.error
                        : memberColor,
                  ),
                  onPressed: enabled ? onToggle : null,
                  child: isStarting
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          KeepersText(isRecording ? 'Tap to stop' : 'Tap to record'),
        ],
        const SizedBox(height: 12),
        KeepersText(
          _formatDuration(duration),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<double>(
          stream: amplitudes,
          initialData: -60,
          builder: (context, snapshot) => SizedBox(
            key: const Key('voice-waveform'),
            height: 52,
            width: double.infinity,
            child: CustomPaint(
              painter: _WaveformPainter(
                amplitude: snapshot.data ?? -60,
                color: memberColor,
              ),
            ),
          ),
        ),
        if (hasRecording) ...[
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
                onPressed: enabled ? onPlay : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const KeepersText('Play recording'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(130, 48),
                ),
                onPressed: enabled ? onRerecord : null,
                icon: const Icon(Icons.refresh_rounded),
                label: const KeepersText('Re-record'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _elapsedAnnouncement(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes > 0) {
    return 'Recording $minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  }
  return 'Recording ${duration.inSeconds} seconds';
}

final class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.amplitude, required this.color});

  final double amplitude;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final normalized = ((amplitude.clamp(-60.0, 0.0) + 60) / 60).toDouble();
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const bars = 18;
    final spacing = size.width / bars;
    for (var index = 0; index < bars; index += 1) {
      final cadence = .35 + .65 * math.sin((index + 1) * 1.7).abs();
      final height = 8 + (size.height - 12) * normalized * cadence;
      final x = spacing * (index + .5);
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.amplitude != amplitude || oldDelegate.color != color;
}
