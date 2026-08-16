import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keepers/features/family/application/family_invite_controller.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/pending_invite_completion_controller.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/presentation/family_join_screen.dart';
import 'package:keepers/features/onboarding/presentation/setup_screen.dart';

import 'support/family_invitation_flow_harness.dart';

const _captureScreenshot = bool.fromEnvironment(
  'CAPTURE_FAMILY_INVITATION_SCREENSHOT',
);

const _qaScreenshotNames = <String>[
  'setup-choice-390x844-text-1_4',
  'setup-manual-join-390x844-text-1_4',
  'wheel-local-only-390x844-text-1_4',
  'invite-unconfigured-390x844-text-1_4',
  'invite-owner-email-390x844-text-1_4',
  'invite-owner-otp-390x844-text-1_4',
  'invite-owner-ready-recipient-entry-390x844-text-1_4',
  'invite-creating-390x844-text-1_4',
  'invite-pending-390x844-text-1_4',
  'invite-sharing-390x844-text-1_4',
  'invite-revoke-failure-390x844-text-1_4',
  'join-loading-390x844-text-1_4',
  'join-email-390x844-text-1_4',
  'join-otp-390x844-text-1_4',
  'join-preview-390x844-text-1_4',
  'join-joining-390x844-text-1_4',
  'join-keyboard-open-390x844-text-1_4',
  'join-recoverable-failure-390x844-text-1_4',
  'join-protected-failure-390x844-text-1_4',
  'join-long-content-reduced-motion-390x844-text-1_4',
  'wheel-post-acceptance-reduced-motion-390x844-text-1_4',
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'two isolated installations complete and recover a family invitation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = await FamilyInvitationFlowHarness.create();
      addTearDown(harness.dispose);
      expect(harness.installationsAreIsolated, isTrue);

      final ownerState = await harness.bootstrapOwnerAndShareInvitation();
      expect(ownerState.phase, FamilyInvitePhase.created);
      expect(ownerState.shareFailure, isNull);
      expect(harness.recordedShareCount, 1);

      final coldLink = await harness.takeRecipientColdStartLink();
      expect(coldLink.inviteId, FamilyInvitationFlowHarness.inviteId);

      await tester.pumpWidget(harness.buildRecipientColdStartApp());
      await _pumpUntilFound(tester, find.byKey(const Key('join-email')));
      final joinScreen = find.byType(FamilyJoinScreen);
      expect(joinScreen, findsOneWidget);
      final joinRoute = ModalRoute.of(tester.element(joinScreen));
      expect(joinRoute?.isCurrent, isTrue);
      expect(Navigator.of(tester.element(joinScreen)).canPop(), isFalse);
      expect(find.byType(SetupScreen), findsNothing);
      expect(
        capabilityAppearsInPaintOrSemantics(tester, coldLink),
        isFalse,
        reason: 'Bearer capability material reached visible or spoken UI.',
      );
      expect(
        await harness.recipientPersistenceContainsCapability(coldLink),
        isFalse,
        reason: 'Bearer capability material reached recipient persistence.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));

      final previewState = await harness.authenticateRecipientAndPreview(
        coldLink,
      );
      expect(previewState.phase, FamilyJoinPhase.preview);
      expect(previewState.preview?.familyName, 'Rahman');
      expect(previewState.preview?.ownerName, 'Amina');

      final interruptedState = await harness.claimInstallAndInterruptComplete();
      expect(interruptedState.phase, FamilyJoinPhase.failed);
      expect(interruptedState.retryPoint, FamilyJoinRetryPoint.complete);
      expect(await harness.recipientIdentityIsInstalled(), isTrue);
      expect(await harness.hasPendingCompletion(), isTrue);

      final recoveryState = await harness.restartRecipientAndRecover();
      expect(recoveryState.phase, PendingInviteCompletionPhase.complete);
      expect(await harness.hasPendingCompletion(), isFalse);

      final ownerRoster = await harness.refreshOwnerRoster();
      expect(ownerRoster.map((member) => member.name), ['Amina', 'Mariam']);

      await tester.pumpWidget(harness.buildSafePostSuccessApp());
      await _pumpUntilFound(
        tester,
        find.bySemanticsLabel('You, Mariam, 0% sealed'),
      );
      expect(find.textContaining('keepers://'), findsNothing);
      expect(find.textContaining('wrappingSecret'), findsNothing);
      expect(find.textContaining('token='), findsNothing);
      expect(
        capabilityAppearsInPaintOrSemantics(tester, coldLink),
        isFalse,
        reason: 'Bearer capability material reached visible or spoken UI.',
      );
      expect(
        await harness.recipientPersistenceContainsCapability(coldLink),
        isFalse,
        reason: 'Bearer capability material reached recipient persistence.',
      );

      if (_captureScreenshot) {
        expect(
          Platform.isAndroid,
          isTrue,
          reason: 'The invitation screenshot target is Android-only.',
        );
        await binding.convertFlutterSurfaceToImage();
        await tester.pump(const Duration(milliseconds: 500));
        await binding.takeScreenshot(
          FamilyInvitationFlowHarness.safeScreenshotName,
        );
      }
      semantics.dispose();
    },
  );

  group('stateful fake revocation contract', () {
    test('revokes a pending invitation', () async {
      final harness = await FamilyInvitationFlowHarness.create();
      addTearDown(harness.dispose);
      await harness.bootstrapOwnerAndShareInvitation();

      expect(harness.invitationState, CloudInvitationState.pending);
      await harness.revokeOwnerInvitation();
      expect(harness.invitationState, CloudInvitationState.revoked);
    });

    test('preserves and rejects a claimed invitation', () async {
      final harness = await FamilyInvitationFlowHarness.create();
      addTearDown(harness.dispose);
      await harness.bootstrapOwnerAndShareInvitation();
      final coldLink = await harness.takeRecipientColdStartLink();
      await harness.authenticateRecipientAndPreview(coldLink);
      await harness.claimInstallAndInterruptComplete();

      expect(harness.invitationState, CloudInvitationState.claimed);
      await expectLater(
        harness.revokeOwnerInvitation(),
        throwsA(
          isA<InvitationFailure>().having(
            (failure) => failure.code,
            'code',
            InvitationFailureCode.alreadyClaimed,
          ),
        ),
      );
      expect(harness.invitationState, CloudInvitationState.claimed);
    });

    test('preserves and rejects an accepted invitation', () async {
      final harness = await FamilyInvitationFlowHarness.create();
      addTearDown(harness.dispose);
      await harness.bootstrapOwnerAndShareInvitation();
      final coldLink = await harness.takeRecipientColdStartLink();
      await harness.authenticateRecipientAndPreview(coldLink);
      await harness.claimInstallAndInterruptComplete();
      await harness.restartRecipientAndRecover();

      expect(harness.invitationState, CloudInvitationState.accepted);
      await expectLater(
        harness.revokeOwnerInvitation(),
        throwsA(
          isA<InvitationFailure>().having(
            (failure) => failure.code,
            'code',
            InvitationFailureCode.unknown,
          ),
        ),
      );
      expect(harness.invitationState, CloudInvitationState.accepted);
    });
  });

  testWidgets(
    'QA screenshot manifest covers the invitation journey with safe product states',
    (tester) async {
      final harness = await FamilyInvitationFlowHarness.create();
      addTearDown(harness.dispose);
      final captured = await captureFamilyInvitationVisualQa(
        binding: binding,
        tester: tester,
        harness: harness,
      );
      expect(captured, _qaScreenshotNames);
    },
    skip: !_captureScreenshot,
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 100,
}) async {
  for (var pump = 0; pump < maxPumps; pump += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget);
}
