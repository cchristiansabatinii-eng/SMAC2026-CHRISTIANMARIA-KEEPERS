// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/application/capture_controller.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/theme/keepers_theme.dart';

import 'capture_test_harness.dart';

void main() {
  testWidgets('first page chooses a format before privacy', (tester) async {
    final harness = CaptureTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.sheet());
    await tester.pump();

    expect(find.text('Keep a memory'), findsOneWidget);
    expect(find.text('1 of 2 · Choose a format'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Private Journal'), findsNothing);
    expect(find.text('Weekly Reveal'), findsNothing);
    expect(find.text('Legacy Milestone'), findsNothing);
    expect(find.text('Capsule'), findsNothing);

    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(continueButton.onPressed, isNull);
  });

  testWidgets('photo offers labeled camera and library choices', (
    tester,
  ) async {
    final harness = CaptureTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.sheet());
    await tester.pump();

    expect(find.widgetWithText(OutlinedButton, 'Camera'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Photo Library'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.photo_camera_rounded), findsWidgets);
    expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);

    await tester.tap(find.text('Photo Library'));
    await tester.pump();
    expect(harness.photo.pickedSources, [PhotoSource.library]);
    expect(harness.container.read(captureControllerProvider).photoPath, isNull);
  });

  testWidgets('permission error stays inline while another format is usable', (
    tester,
  ) async {
    final harness = CaptureTestHarness(
      photo: FakePhotoCaptureAdapter(
        error: const CapturePermissionException(CapturePermissionSource.camera),
      ),
    );
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.sheet());
    await tester.pump();

    await tester.tap(find.text('Camera'));
    await tester.pump();
    expect(
      find.text('Camera access is needed to take a photo.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Text'));
    await tester.pump();
    expect(find.byKey(const Key('memory-text')), findsOneWidget);
  });

  testWidgets('text and caption continue to access selection', (tester) async {
    final harness = CaptureTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.sheet());
    await tester.pump();

    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('memory-text')),
      'The kitchen smelled like cardamom.',
    );
    await tester.enterText(
      find.byKey(const Key('memory-caption')),
      'Friday morning',
    );
    await tester.pump();

    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(continueButton.onPressed, isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('2 of 2 · Choose access'), findsOneWidget);
    expect(find.text('Private Journal'), findsOneWidget);
    expect(find.text('Weekly Reveal'), findsOneWidget);
    expect(find.text('Capsule'), findsOneWidget);
    expect(find.text('Legacy Milestone'), findsNothing);
    expect(find.text('Kept for your family’s next reveal.'), findsOneWidget);
    final reveal = tester.widget<RadioListTile<PrivacyTier>>(
      find.byKey(const Key('privacy-reveal')),
    );
    expect(reveal.groupValue, PrivacyTier.reveal);
    final keep = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Keep memory'),
    );
    expect(keep.onPressed, isNotNull);
    expect(
      harness.container.read(captureControllerProvider).caption,
      'Friday morning',
    );
  });

  testWidgets('Capsule reveals an optional task and validates it inline', (
    tester,
  ) async {
    final harness = CaptureTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.sheet());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('memory-text')),
      'A memory for the whole family',
    );
    tester.testTextInput.hide();
    await tester.pump();
    await _continueToAccess(tester);

    expect(find.byKey(const Key('capsule-task-toggle')), findsNothing);
    expect(find.byKey(const Key('capsule-task-field')), findsNothing);

    await tester.tap(find.text('Capsule'));
    await tester.pumpAndSettle();

    expect(
      find.text('Saved to this device’s Memory Key as a Capsule.'),
      findsOneWidget,
    );
    expect(find.text('Set specific task to unlock'), findsOneWidget);
    expect(
      find.text('Optional · task completion is stored only on this device.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('capsule-task-toggle')), findsOneWidget);
    expect(find.byKey(const Key('capsule-task-field')), findsNothing);
    expect(find.text('Legacy Milestone'), findsNothing);

    await tester.tap(find.byKey(const Key('capsule-task-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capsule-task-field')), findsOneWidget);
    expect(
      find.text(
        'Add a task. Capsule access and task completion stay on this device.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Keep memory'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('capsule-task-field')),
      'Call Grandma and ask about her first home',
    );
    await tester.pump();

    expect(
      find.text('Capsule access and task completion stay on this device.'),
      findsOneWidget,
    );
    expect(find.textContaining('their own device'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Keep memory'),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      harness.container.read(captureControllerProvider).capsuleTask,
      'Call Grandma and ask about her first home',
    );
  });

  testWidgets('Back never traps an unfinished Capsule task off-screen', (
    tester,
  ) async {
    final harness = CaptureTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.sheet());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('memory-text')),
      'Keep the unfinished task reachable',
    );
    tester.testTextInput.hide();
    await tester.pump();
    await _continueToAccess(tester);
    await tester.tap(find.text('Capsule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capsule-task-toggle')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Keep memory'),
          )
          .onPressed,
      isNull,
    );
    final backButton = find.byKey(const Key('capture-back'));
    await tester.ensureVisible(backButton);
    await tester.tap(backButton);
    await tester.pumpAndSettle();

    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(continueButton.onPressed, isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('capsule-task-field')), findsOneWidget);
    expect(
      harness.container.read(captureControllerProvider).capsuleTaskEnabled,
      isTrue,
    );
  });

  testWidgets('voice control is tap-to-start and tap-to-stop', (tester) async {
    final recorder = FakeVoiceCaptureAdapter();
    final harness = CaptureTestHarness(voice: recorder);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.sheet());
    await tester.pump();

    await tester.tap(find.text('Voice'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-toggle')));
    await tester.pump();
    expect(find.text('Tap to stop'), findsOneWidget);
    expect(recorder.starts, 1);

    recorder.amplitudesController.add(-18);
    await tester.pump();
    expect(find.byKey(const Key('voice-waveform')), findsOneWidget);

    await tester.tap(find.byKey(const Key('record-toggle')));
    await tester.pump();
    expect(find.text('Play recording'), findsOneWidget);
    expect(find.text('Re-record'), findsOneWidget);
    expect(find.text('00:07'), findsOneWidget);
    expect(recorder.stops, 1);

    await tester.tap(find.text('Play recording'));
    expect(harness.playback.playedFiles, ['/tmp/voice.m4a']);
  });

  testWidgets('saving shows progress and returns the persisted entry once', (
    tester,
  ) async {
    final persistence = Completer<EntryMetadata>();
    final harness = CaptureTestHarness(save: (_) => persistence.future);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.launcher());

    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('memory-text')),
      'Only after persistence',
    );
    tester.testTextInput.hide();
    await tester.pump();
    await _continueToAccess(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Keep memory'));
    await tester.pump();

    expect(find.text('Keeping…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Completions: 0'), findsOneWidget);

    persistence.complete(
      EntryMetadata(
        id: 'persisted-entry',
        familyId: captureIdentity.familyId,
        authorId: captureIdentity.memberId,
        createdAt: DateTime.utc(2026, 9, 1),
        format: MemoryFormat.text,
        privacy: PrivacyTier.reveal,
        blobRef: 'entries/blobs/persisted-entry.keeper',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved: persisted-entry'), findsOneWidget);
    expect(find.text('Completions: 1'), findsOneWidget);
    expect(
      harness.container.read(captureControllerProvider),
      const CaptureDraft(),
    );
  });

  testWidgets('committed cleanup stays open and retries before returning', (
    tester,
  ) async {
    final files = FakeCaptureFileAccess(releaseFailures: 1);
    final harness = CaptureTestHarness(files: files);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.launcher());
    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();

    await harness.container
        .read(captureControllerProvider.notifier)
        .acceptPhoto('/tmp/photo.jpg');
    await tester.pump();
    await _continueToAccess(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Keep memory'));
    await tester.pumpAndSettle();

    expect(find.text('Completions: 0'), findsOneWidget);
    expect(
      find.text('The memory is kept, but draft cleanup needs attention.'),
      findsOneWidget,
    );
    expect(
      harness.container.read(captureControllerProvider).phase,
      CapturePhase.committedCleanup,
    );

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Completions: 1'), findsOneWidget);
    expect(files.releaseFailures, 0);
  });

  testWidgets('failed save keeps the draft and Try again succeeds', (
    tester,
  ) async {
    var attempts = 0;
    final harness = CaptureTestHarness(
      save: (request) async {
        attempts += 1;
        if (attempts == 1) throw StateError('raw storage detail');
        return request.metadata.copyWith(
          blobRef: 'entries/blobs/entry-1.keeper',
        );
      },
    );
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.launcher());

    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('memory-text')), 'Keep this');
    tester.testTextInput.hide();
    await tester.pump();
    await _continueToAccess(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Keep memory'));
    await tester.pumpAndSettle();

    expect(
      find.text('This memory could not be kept. Your draft is still here.'),
      findsOneWidget,
    );
    expect(find.textContaining('raw storage detail'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(
      harness.container.read(captureControllerProvider).cleanupRequired,
      isFalse,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Back'));
    await tester.pumpAndSettle();
    expect(find.text('Keep this'), findsOneWidget);
    await _continueToAccess(tester);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Saved: entry-1'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('non-empty back action requires safe discard confirmation', (
    tester,
  ) async {
    final harness = CaptureTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.launcher());
    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('memory-text')), 'Keep me');
    tester.testTextInput.hide();
    await tester.pump();
    expect(harness.container.read(captureControllerProvider).hasDraft, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard this memory?'), findsOneWidget);
    final discardHeading = tester.widget<RichText>(
      find.descendant(
        of: find.text('Discard this memory?'),
        matching: find.byType(RichText),
      ),
    );
    final headingStyle = (discardHeading.text as TextSpan).style;
    expect(headingStyle?.fontSize, 20);
    expect(headingStyle?.fontWeight, FontWeight.w600);
    expect(headingStyle?.letterSpacing, KeepersType.heading.letterSpacing);
    expect(find.text('Keep editing'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Keep me'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Completions: 1'), findsOneWidget);
    expect(
      harness.container.read(captureControllerProvider),
      const CaptureDraft(),
    );
    expect(harness.playback.stops, greaterThanOrEqualTo(1));
  });

  testWidgets('back during photo picking waits for controller cleanup', (
    tester,
  ) async {
    final photo = BlockingPhotoCaptureAdapter();
    final harness = CaptureTestHarness(photo: photo);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.launcher());
    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Photo Library'));
    await tester.pump();
    expect(
      harness.container.read(captureControllerProvider).phase,
      CapturePhase.picking,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Completions: 0'), findsOneWidget);

    photo.pickResult.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Completions: 1'), findsOneWidget);
    expect(
      harness.container.read(captureControllerProvider),
      const CaptureDraft(),
    );
  });

  testWidgets('failed discard retries discard and never saves', (tester) async {
    var saves = 0;
    final files = FakeCaptureFileAccess(
      deleteError: StateError('delete failed'),
    );
    final harness = CaptureTestHarness(
      files: files,
      save: (request) async {
        saves += 1;
        return request.metadata;
      },
    );
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.launcher());
    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    await harness.container
        .read(captureControllerProvider.notifier)
        .acceptPhoto('/tmp/photo.jpg');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Some draft plaintext could not be removed. Try discard again.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed,
      isNull,
    );

    files.deleteError = null;
    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(saves, 0);
    expect(find.text('Completions: 1'), findsOneWidget);
    expect(find.textContaining('Saved:'), findsNothing);
    expect(
      harness.container.read(captureControllerProvider),
      const CaptureDraft(),
    );
  });

  for (final sourceCase
      in <
        ({PhotoSource source, CapturePermissionSource permission, String label})
      >[
        (
          source: PhotoSource.camera,
          permission: CapturePermissionSource.camera,
          label: 'Camera',
        ),
        (
          source: PhotoSource.library,
          permission: CapturePermissionSource.library,
          label: 'Photo Library',
        ),
      ]) {
    testWidgets('${sourceCase.label} permission retry repeats that source', (
      tester,
    ) async {
      final photo = FakePhotoCaptureAdapter(
        error: CapturePermissionException(sourceCase.permission),
      );
      final harness = CaptureTestHarness(photo: photo);
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.sheet());
      await tester.pumpAndSettle();

      await tester.tap(find.text(sourceCase.label));
      await tester.pump();
      photo
        ..error = null
        ..result = '/tmp/retried-photo.jpg';
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(photo.pickedSources, [sourceCase.source, sourceCase.source]);
      expect(
        harness.container.read(captureControllerProvider).photoPath,
        '/tmp/retried-photo.jpg',
      );
    });
  }

  testWidgets('microphone permission retry starts recording', (tester) async {
    final voice = FakeVoiceCaptureAdapter(permission: false);
    final harness = CaptureTestHarness(voice: voice);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.sheet());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('record-toggle')));
    await tester.pump();
    expect(
      find.text('Microphone access is needed to record a memory.'),
      findsOneWidget,
    );
    voice.permission = true;
    await tester.ensureVisible(find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(voice.starts, 1);
    expect(
      harness.container.read(captureControllerProvider).isRecording,
      isTrue,
    );
  });

  testWidgets('late snapshot release failure blocks result until retry', (
    tester,
  ) async {
    final releaseGate = Completer<void>();
    final files = FakeCaptureFileAccess(
      releaseGate: releaseGate,
      releaseFailures: 1,
    );
    final harness = CaptureTestHarness(files: files);
    addTearDown(harness.dispose);
    addTearDown(() {
      if (!releaseGate.isCompleted) releaseGate.complete();
    });
    await tester.pumpWidget(harness.launcher());
    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    await harness.container
        .read(captureControllerProvider.notifier)
        .acceptPhoto('/tmp/photo.jpg');
    await tester.pump();
    await _continueToAccess(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Keep memory'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Completions: 0'), findsOneWidget);
    expect(
      harness.container.read(captureControllerProvider).phase,
      CapturePhase.saving,
    );

    releaseGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Completions: 0'), findsOneWidget);
    expect(
      harness.container.read(captureControllerProvider).phase,
      CapturePhase.committedCleanup,
    );

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Completions: 1'), findsOneWidget);
  });

  testWidgets('retry Save drains a failed uncommitted snapshot first', (
    tester,
  ) async {
    final retryReleaseGate = Completer<void>();
    final files = FakeCaptureFileAccess(
      releaseFailures: 1,
      retryReleaseGate: retryReleaseGate,
    );
    var saveAttempts = 0;
    final harness = CaptureTestHarness(
      files: files,
      save: (request) async {
        saveAttempts += 1;
        if (saveAttempts == 1) throw StateError('not committed');
        return request.metadata.copyWith(blobRef: 'entries/blobs/retry.keeper');
      },
    );
    addTearDown(harness.dispose);
    addTearDown(() {
      if (!retryReleaseGate.isCompleted) retryReleaseGate.complete();
    });
    await tester.pumpWidget(harness.launcher());
    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    await harness.container
        .read(captureControllerProvider.notifier)
        .acceptPhoto('/tmp/photo.jpg');
    await tester.pump();
    await _continueToAccess(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Keep memory'));
    await tester.pumpAndSettle();

    expect(saveAttempts, 1);
    expect(files.releaseCalls, 1);
    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(saveAttempts, 1);
    expect(find.text('Completions: 0'), findsOneWidget);
    expect(
      harness.container.read(captureControllerProvider).phase,
      CapturePhase.saving,
    );

    retryReleaseGate.complete();
    await tester.pumpAndSettle();
    expect(files.retryPendingCalls, greaterThan(0));
    expect(files.successfulReleases, 2);
    expect(saveAttempts, 2);
    expect(find.text('Completions: 1'), findsOneWidget);
  });

  testWidgets('Discard drains a failed uncommitted snapshot before closing', (
    tester,
  ) async {
    final retryReleaseGate = Completer<void>();
    final files = FakeCaptureFileAccess(
      releaseFailures: 1,
      retryReleaseGate: retryReleaseGate,
    );
    var saveAttempts = 0;
    final harness = CaptureTestHarness(
      files: files,
      save: (_) async {
        saveAttempts += 1;
        throw StateError('not committed');
      },
    );
    addTearDown(harness.dispose);
    addTearDown(() {
      if (!retryReleaseGate.isCompleted) retryReleaseGate.complete();
    });
    await tester.pumpWidget(harness.launcher());
    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    await harness.container
        .read(captureControllerProvider.notifier)
        .acceptPhoto('/tmp/photo.jpg');
    await harness.container.read(captureControllerProvider.notifier).save();
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pump();

    expect(saveAttempts, 1);
    expect(find.text('Completions: 0'), findsOneWidget);
    expect(
      harness.container.read(captureControllerProvider).phase,
      CapturePhase.cleaning,
    );

    retryReleaseGate.complete();
    await tester.pumpAndSettle();
    expect(files.retryPendingCalls, greaterThan(0));
    expect(files.successfulReleases, 1);
    expect(find.text('Completions: 1'), findsOneWidget);
    expect(
      harness.container.read(captureControllerProvider),
      const CaptureDraft(),
    );
  });

  testWidgets(
    'read failure with retained cleanup survives Replace and dismissal',
    (tester) async {
      final files = FakeCaptureFileAccess(
        readFailuresWithPendingCleanup: 1,
        pendingCleanupFailures: 2,
      );
      final harness = CaptureTestHarness(files: files);
      addTearDown(harness.dispose);
      await tester.pumpWidget(harness.launcher());
      await tester.tap(find.text('Add a memory'));
      await tester.pumpAndSettle();
      await harness.container
          .read(captureControllerProvider.notifier)
          .acceptPhoto('/tmp/photo.jpg');
      await tester.pump();
      await _continueToAccess(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Keep memory'));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(captureControllerProvider).cleanupRequired,
        isTrue,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Back'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Replace'));
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(
        harness.container.read(captureControllerProvider).hasDraft,
        isFalse,
      );
      expect(
        harness.container.read(captureControllerProvider).cleanupRequired,
        isTrue,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Completions: 0'), findsOneWidget);
      expect(
        harness.container.read(captureControllerProvider).cleanupRequired,
        isTrue,
      );
      expect(
        find.text(
          'Some draft plaintext could not be removed. Try discard again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);

      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Completions: 1'), findsOneWidget);
      expect(
        harness.container.read(captureControllerProvider),
        const CaptureDraft(),
      );
    },
  );

  for (final dismissal
      in <
        ({
          bool editPrivacy,
          String label,
          Future<void> Function(WidgetTester tester) invoke,
          bool useReplace,
        })
      >[
        (
          editPrivacy: false,
          label: 'system back',
          invoke: (tester) => tester.binding.handlePopRoute(),
          useReplace: false,
        ),
        (
          editPrivacy: false,
          label: 'Close',
          invoke: (tester) async {
            await tester.ensureVisible(find.byTooltip('Close Capture'));
            await tester.tap(find.byTooltip('Close Capture'));
          },
          useReplace: true,
        ),
        (
          editPrivacy: true,
          label: 'modal barrier',
          invoke: (tester) => tester.tapAt(const Offset(8, 8)),
          useReplace: false,
        ),
      ]) {
    testWidgets(
      '${dismissal.label} keeps format-hidden cleanup visible until retry',
      (tester) async {
        final files = FakeCaptureFileAccess(releaseFailures: 2);
        var saveAttempts = 0;
        final harness = CaptureTestHarness(
          files: files,
          save: (_) async {
            saveAttempts += 1;
            throw StateError('not committed');
          },
        );
        addTearDown(harness.dispose);
        await tester.pumpWidget(harness.launcher());
        await tester.tap(find.text('Add a memory'));
        await tester.pumpAndSettle();
        await harness.container
            .read(captureControllerProvider.notifier)
            .acceptPhoto('/tmp/photo.jpg');
        await harness.container.read(captureControllerProvider.notifier).save();
        await tester.pumpAndSettle();

        final transition = dismissal.useReplace ? 'Replace' : 'Text';
        await tester.ensureVisible(find.text(transition));
        await tester.tap(find.text(transition));
        await tester.pumpAndSettle();
        if (dismissal.editPrivacy) {
          harness.container
              .read(captureControllerProvider.notifier)
              .setPrivacy(PrivacyTier.journal);
          await tester.pump();
        }
        expect(
          harness.container.read(captureControllerProvider).format,
          dismissal.useReplace ? MemoryFormat.photo : MemoryFormat.text,
        );
        expect(
          harness.container.read(captureControllerProvider).hasDraft,
          isFalse,
        );
        expect(
          harness.container.read(captureControllerProvider).cleanupRequired,
          isTrue,
        );
        if (dismissal.editPrivacy) {
          expect(
            harness.container.read(captureControllerProvider).privacy,
            PrivacyTier.journal,
          );
        }

        await dismissal.invoke(tester);
        await tester.pumpAndSettle();

        expect(saveAttempts, 1);
        expect(find.text('Completions: 0'), findsOneWidget);
        expect(
          find.text(
            'Some draft plaintext could not be removed. Try discard again.',
          ),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);

        await tester.ensureVisible(find.text('Try again'));
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Completions: 1'), findsOneWidget);
        expect(files.releaseFailures, 0);
        expect(
          harness.container.read(captureControllerProvider),
          const CaptureDraft(),
        );
      },
    );
  }

  testWidgets('null dismissal resets privacy before the next opening', (
    tester,
  ) async {
    final harness = CaptureTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.launcher());
    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    harness.container
        .read(captureControllerProvider.notifier)
        .setPrivacy(PrivacyTier.journal);
    await tester.tap(find.byTooltip('Close Capture'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('memory-text')), 'Check reset');
    tester.testTextInput.hide();
    await tester.pump();
    await _continueToAccess(tester);
    final reveal = tester.widget<RadioListTile<PrivacyTier>>(
      find.byKey(const Key('privacy-reveal')),
    );
    expect(reveal.groupValue, PrivacyTier.reveal);
  });

  testWidgets('null dismissal clears a permission error before reopening', (
    tester,
  ) async {
    final photo = FakePhotoCaptureAdapter(
      error: const CapturePermissionException(CapturePermissionSource.camera),
    );
    final harness = CaptureTestHarness(photo: photo);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.launcher());
    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera'));
    await tester.pump();
    expect(
      find.text('Camera access is needed to take a photo.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Close Capture'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    expect(find.text('Camera access is needed to take a photo.'), findsNothing);
    expect(
      harness.container.read(captureControllerProvider).privacy,
      PrivacyTier.reveal,
    );
  });

  testWidgets('dismissal waits for startup recovery and deletes its result', (
    tester,
  ) async {
    final photo = BlockingRecoveryPhotoCaptureAdapter();
    final files = FakeCaptureFileAccess();
    final harness = CaptureTestHarness(photo: photo, files: files);
    addTearDown(harness.dispose);
    addTearDown(() {
      if (!photo.recoveryResult.isCompleted) {
        photo.recoveryResult.complete(null);
      }
    });
    await tester.pumpWidget(harness.launcher());
    await tester.tap(find.text('Add a memory'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close Capture'));
    await tester.pump();

    expect(find.text('Completions: 0'), findsOneWidget);
    photo.recoveryResult.complete('/tmp/recovered.jpg');
    await tester.pumpAndSettle();

    expect(find.text('Completions: 1'), findsOneWidget);
    expect(files.deletedPaths, contains('/tmp/recovered.jpg'));
    expect(
      harness.container.read(captureControllerProvider),
      const CaptureDraft(),
    );
  });

  testWidgets(
    'failed startup cleanup keeps dismissal open through visible retry',
    (tester) async {
      final photo = BlockingRecoveryPhotoCaptureAdapter();
      final files = FakeCaptureFileAccess(deleteFailures: 2);
      final harness = CaptureTestHarness(photo: photo, files: files);
      addTearDown(harness.dispose);
      addTearDown(() {
        if (!photo.recoveryResult.isCompleted) {
          photo.recoveryResult.complete(null);
        }
      });
      await tester.pumpWidget(harness.launcher());
      await tester.tap(find.text('Add a memory'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close Capture'));
      await tester.pump();

      photo.recoveryResult.complete('/tmp/recovered-failure.jpg');
      await tester.pumpAndSettle();

      expect(find.text('Completions: 0'), findsOneWidget);
      expect(
        find.text(
          'Some draft plaintext could not be removed. Try discard again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);

      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Completions: 1'), findsOneWidget);
      expect(files.deleteFailures, 0);
      expect(
        harness.container.read(captureControllerProvider),
        const CaptureDraft(),
      );
    },
  );
}

Future<void> _continueToAccess(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Continue'));
  await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
  await tester.pumpAndSettle();
  expect(find.text('2 of 2 · Choose access'), findsOneWidget);
}
