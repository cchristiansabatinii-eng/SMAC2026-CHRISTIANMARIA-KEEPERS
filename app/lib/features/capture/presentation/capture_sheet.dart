// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/capture/application/capture_controller.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';

const _privacyCopy = <PrivacyTier, ({String title, String consequence})>{
  PrivacyTier.journal: (
    title: 'Private Journal',
    consequence: 'Only you can open this memory on this device.',
  ),
  PrivacyTier.reveal: (
    title: 'Weekly Reveal',
    consequence: 'Sealed for your family’s future reveal.',
  ),
  PrivacyTier.legacy: (
    title: 'Legacy Milestone',
    consequence: 'Sealed with the family key for a future milestone.',
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => const CaptureSheet(),
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
  Timer? _recordingClock;
  Duration _elapsedRecording = Duration.zero;
  bool _dialogOpen = false;
  bool _allowPop = false;
  bool _didReturnEntry = false;

  @override
  void dispose() {
    _recordingClock?.cancel();
    _captionFocus.dispose();
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
    await _announce('Memory sealed');
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
        title: const Text('Discard this memory?'),
        content: const Text(
          'The unfinished memory and any temporary media will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = theme.extension<ObservatoryTokens>()!;
    final identity = ref.watch(localIdentityProvider).asData?.value;
    final memberColor = tokens.memberColor(identity?.colorToken ?? 'ochre');
    final viewport = MediaQuery.sizeOf(context);
    final height = math.min(760.0, viewport.height * .94);
    final locked = _isLocked(draft);

    return PopScope<EntryMetadata>(
      canPop:
          _allowPop ||
          (!draft.hasDraft &&
              !draft.retryRequiresCleanup &&
              !draft.cleanupRequired &&
              !_hasInFlightCapture(draft.phase)),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: Material(
        color: tokens.ground,
        child: SizedBox(
          height: height,
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
                            color: colors.onSurfaceVariant.withValues(
                              alpha: .42,
                            ),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: memberColor.withValues(alpha: .15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: memberColor.withValues(alpha: .55),
                              ),
                            ),
                            child: Icon(
                              Icons.lock_rounded,
                              color: tokens.brass,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Seal a memory',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Choose one form for this moment.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close capture',
                            onPressed:
                                locked && draft.phase != CapturePhase.recovering
                                ? null
                                : _requestClose,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      SegmentedButton<MemoryFormat>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: MemoryFormat.photo,
                            icon: Icon(Icons.photo_camera_rounded),
                            label: Text('Photo'),
                          ),
                          ButtonSegment(
                            value: MemoryFormat.voice,
                            icon: Icon(Icons.mic_rounded),
                            label: Text('Voice'),
                          ),
                          ButtonSegment(
                            value: MemoryFormat.text,
                            icon: Icon(Icons.notes_rounded),
                            label: Text('Text'),
                          ),
                        ],
                        selected: {draft.format},
                        onSelectionChanged: locked || draft.isRecording
                            ? null
                            : (formats) => unawaited(
                                controller.selectFormat(formats.single),
                              ),
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
                        focusNode: _captionFocus,
                        enabled: !locked,
                        maxLength: 280,
                        minLines: 1,
                        maxLines: 3,
                        onChanged: controller.updateCaption,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Caption (optional)',
                          hintText: 'Add a small detail or date',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Who can open it?',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...PrivacyTier.values.map((tier) {
                        final copy = _privacyCopy[tier]!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: RadioListTile<PrivacyTier>(
                            key: Key('privacy-${tier.name}'),
                            value: tier,
                            groupValue: draft.privacy,
                            onChanged: locked
                                ? null
                                : (value) {
                                    if (value != null) {
                                      controller.setPrivacy(value);
                                    }
                                  },
                            title: Text(copy.title),
                            subtitle: Text(copy.consequence),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              side: BorderSide(
                                color: tier == draft.privacy
                                    ? memberColor
                                    : colors.outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        );
                      }),
                      if (draft.errorMessage case final message?) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: colors.onErrorContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Semantics(
                                  label: message,
                                  liveRegion: true,
                                  child: ExcludeSemantics(
                                    child: Text(
                                      message,
                                      style: TextStyle(
                                        color: colors.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed:
                                    draft.retryIntent != null &&
                                        (!locked ||
                                            draft.phase ==
                                                CapturePhase.failed ||
                                            draft.phase ==
                                                CapturePhase.committedCleanup)
                                    ? () => _retry(draft)
                                    : null,
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Semantics(
                        label: draft.phase == CapturePhase.saving
                            ? 'Sealing memory'
                            : 'Seal memory',
                        button: true,
                        enabled: draft.canSave,
                        liveRegion: draft.phase == CapturePhase.saving,
                        onTap: draft.canSave ? controller.save : null,
                        child: ExcludeSemantics(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: memberColor,
                              foregroundColor:
                                  ThemeData.estimateBrightnessForColor(
                                        memberColor,
                                      ) ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                            ),
                            onPressed: draft.canSave ? controller.save : null,
                            icon: draft.phase == CapturePhase.saving
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    Icons.verified_rounded,
                                    color: tokens.brass,
                                  ),
                            label: Text(
                              draft.phase == CapturePhase.saving
                                  ? 'Sealing…'
                                  : 'Seal memory',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.security_rounded,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Temporary plaintext is removed after save or discard.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
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
      minLines: 5,
      maxLines: 10,
      autofocus: true,
      enabled: !locked,
      onChanged: controller.updateText,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'Memory',
        hintText: 'Write what you want to remember…',
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
          Text(
            'Choose a photo',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
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
                label: const Text('Camera'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(170, 48),
                ),
                onPressed: enabled ? onLibrary : null,
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('Photo Library'),
              ),
            ],
          ),
          if (busy) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            const Text('Opening photo picker…'),
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
              errorBuilder: (_, _, _) =>
                  const Center(child: Text('Photo preview unavailable.')),
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
              label: const Text('Replace'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
              onPressed: enabled ? onContinue : null,
              icon: const Icon(Icons.arrow_downward_rounded),
              label: const Text('Continue'),
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
          Text(isRecording ? 'Tap to stop' : 'Tap to record'),
        ],
        const SizedBox(height: 12),
        Text(
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
                label: const Text('Play recording'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(130, 48),
                ),
                onPressed: enabled ? onRerecord : null,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Re-record'),
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
