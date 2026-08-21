import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keepers/features/family/application/family_code_controller.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/pending_join_completion_controller.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';

import 'support/family_invitation_flow_harness.dart';

const _captureScreenshots = bool.fromEnvironment(
  'CAPTURE_FAMILY_INVITATION_SCREENSHOT',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'isolated owner, approver, and requester complete a permanent-code join',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = await FamilyInvitationFlowHarness.create();
      addTearDown(harness.dispose);

      expect(
        FamilyInvitationFlowHarness.developmentOnlyDeterministicFixtures,
        isTrue,
      );
      expect(harness.installationsAreIsolated, isTrue);

      final codeState = await harness.bootstrapOwnerAndShareCode();
      expect(codeState.phase, FamilyCodePhase.ready);
      expect(codeState.displayCode, 'K7M4-P2Q8');
      expect(codeState.isCreator, isTrue);
      expect(harness.recordedShareCount, 1);

      final sharedLink = harness.takeSharedJoinLink();
      expect(sharedLink.code, harness.sharedCode);
      expect(
        sharedLink.code.joinUri,
        Uri.parse('https://join.keepers.app/f/K7M4-P2Q8'),
      );

      await tester.pumpWidget(harness.buildRequesterManualEntryApp());
      await _pumpUntilFound(tester, find.byKey(const Key('family-code-field')));
      await tester.enterText(
        find.byKey(const Key('family-code-field')),
        'k7m4 p2q8',
      );
      await tester.tap(find.byKey(const Key('continue-family-code')));
      await _pumpUntilFound(tester, find.text('Rahman family'));
      expect(find.text('Private owner name'), findsNothing);
      expect(find.text('Amina'), findsNothing);
      expect(find.text('Omar'), findsNothing);
      expect(privateJoinMaterialAppearsInPaintOrSemantics(tester), isFalse);

      final pending = await harness.requestAccess();
      await tester.pump();
      expect(pending.phase, FamilyJoinPhase.pending);
      expect(harness.cloudRequestState, FamilyJoinRequestState.pending);

      harness.setRequesterOnline(false);
      final approverState = await harness.loadApproverRequests();
      expect(approverState.requests, hasLength(1));
      expect(approverState.requests.single.displayName, 'Mariam');
      await harness.approveFirstRequest();
      expect(harness.cloudRequestState, FamilyJoinRequestState.approved);

      harness.loseNextCompletionResponse();
      harness.setRequesterOnline(true);
      final interrupted = await harness.refreshRequester();
      expect(interrupted.phase, FamilyJoinPhase.failed);
      expect(interrupted.retryPoint, FamilyJoinRetryPoint.complete);
      expect(await harness.requesterIdentityIsInstalled(), isTrue);
      expect(await harness.hasPendingCompletion(), isTrue);
      expect(
        harness.activeMembershipCount(
          FamilyInvitationFlowHarness.requesterMemberId,
        ),
        1,
      );

      final recovered = await harness.restartRequesterAndRecoverCompletion();
      expect(recovered.phase, PendingJoinCompletionPhase.complete);
      expect(await harness.hasPendingCompletion(), isFalse);
      expect(harness.cloudRequestState, FamilyJoinRequestState.installed);
      expect(
        harness.activeMembershipCount(
          FamilyInvitationFlowHarness.requesterMemberId,
        ),
        1,
      );

      final roster = await harness.requesterLocalRoster();
      expect(roster.map((member) => member.name), ['Amina', 'Omar', 'Mariam']);
      await tester.pumpWidget(await harness.buildInstalledRosterApp());
      await _pumpUntilFound(
        tester,
        find.bySemanticsLabel('You, Mariam, 0% sealed'),
      );
      expect(privateJoinMaterialAppearsInPaintOrSemantics(tester), isFalse);

      if (_captureScreenshots) {
        expect(
          Platform.isAndroid,
          isTrue,
          reason: 'The integration screenshot target is Android-only.',
        );
        await binding.convertFlutterSurfaceToImage();
        await tester.pump(const Duration(milliseconds: 300));
        await binding.takeScreenshot(
          FamilyInvitationFlowHarness.safeScreenshotName,
        );
      }
      semantics.dispose();
    },
  );

  test('pending request survives process death and regeneration invalidates its code', () async {
    final harness = await FamilyInvitationFlowHarness.create();
    addTearDown(harness.dispose);
    await harness.bootstrapOwnerAndShareCode();
    final staleCode = harness.sharedCode;
    await harness.loadRequesterCode();
    await harness.requestAccess();

    final restored = await harness.restartRequesterAndRestorePending();
    expect(restored.phase, FamilyJoinPhase.pending);
    expect(
      restored.request?.memberId,
      FamilyInvitationFlowHarness.requesterMemberId,
    );

    final regenerated = await harness.regenerateOwnerCode();
    expect(regenerated.phase, FamilyCodePhase.ready);
    expect(regenerated.codeVersion, 2);
    expect(harness.sharedCode, isNot(staleCode));

    final invalidated = await harness.refreshRequester();
    expect(invalidated.phase, FamilyJoinPhase.invitationChanged);
    expect(harness.cloudRequestState, FamilyJoinRequestState.cancelled);
  });

  test(
    'existing approver can decline without exposing family contents',
    () async {
      final harness = await FamilyInvitationFlowHarness.create();
      addTearDown(harness.dispose);
      await harness.bootstrapOwnerAndShareCode();
      final preview = await harness.loadRequesterCode();
      expect(preview.preview?.familyName, 'Rahman family');
      await harness.requestAccess();
      await harness.loadApproverRequests();
      await harness.declineFirstRequest();

      final declined = await harness.refreshRequester();
      expect(declined.phase, FamilyJoinPhase.declined);
      expect(harness.cloudRequestState, FamilyJoinRequestState.declined);
    },
  );

  testWidgets(
    'visual QA manifest covers both mobile sizes and every family-code state',
    (tester) async {
      final harness = await FamilyInvitationFlowHarness.create();
      addTearDown(harness.dispose);
      final captured = await captureFamilyInvitationVisualQa(
        binding: binding,
        tester: tester,
        harness: harness,
      );
      expect(captured, familyInvitationQaScreenshotNames);
    },
    skip: !_captureScreenshots,
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
