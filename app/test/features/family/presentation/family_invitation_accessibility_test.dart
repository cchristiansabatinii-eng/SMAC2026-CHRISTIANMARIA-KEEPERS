import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/family_code_controller.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/family_join_requests_controller.dart';
import 'package:keepers/features/family/domain/family_join_failure.dart';
import 'package:keepers/features/family/presentation/family_invite_sheet.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';

import 'family_invitation_test_harness.dart';

void main() {
  for (final size in const [
    familyInvitationPhone,
    familyInvitationLargePhone,
  ]) {
    final sizeName = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets(
      '$sizeName family-code sharing is readable, operable, and creator-safe',
      (tester) async {
        await configureFamilyInvitationViewport(tester, size: size);
        final semantics = tester.ensureSemantics();
        final controller = InvitationTestFamilyCodeController(
          const FamilyCodeState(
            phase: FamilyCodePhase.ready,
            displayCode: 'K7M4-P2Q8',
            codeVersion: 1,
            isCreator: true,
          ),
        );
        await pumpFamilyCodeSheet(tester, controller, size: size);

        expect(
          find.bySemanticsLabel('Family code K 7 M 4 P 2 Q 8'),
          findsOneWidget,
        );
        for (final key in const [
          'share-family-link',
          'copy-family-code',
          'copy-family-link',
          'regenerate-family-code',
        ]) {
          expectMinimumFamilyTarget(tester, find.byKey(Key(key)));
        }
        final media = MediaQuery.of(
          tester.element(find.byType(FamilyInviteSheet)),
        );
        expect(media.size, size);
        expect(media.textScaler.scale(10), 14);
        expect(media.disableAnimations, isTrue);

        await tester.tap(find.byKey(const Key('regenerate-family-code')));
        await tester.pumpAndSettle();
        expect(find.text('Regenerate family code?'), findsOneWidget);
        expect(
          find.textContaining('previous code and pending requests'),
          findsOneWidget,
        );
        expectMinimumFamilyTarget(
          tester,
          find.widgetWithText(FilledButton, 'Regenerate'),
        );
        expectNoPrivateFamilyJoinMaterial();
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );

    testWidgets(
      '$sizeName cached and noncreator family-code states stay explicit',
      (tester) async {
        await configureFamilyInvitationViewport(tester, size: size);
        final semantics = tester.ensureSemantics();
        final states = <FamilyCodeState>[
          const FamilyCodeState(
            phase: FamilyCodePhase.ready,
            displayCode: 'K7M4-P2Q8',
            codeVersion: 1,
            isOffline: true,
          ),
          const FamilyCodeState(
            phase: FamilyCodePhase.regenerating,
            displayCode: 'K7M4-P2Q8',
            codeVersion: 1,
            isCreator: true,
          ),
          const FamilyCodeState(
            phase: FamilyCodePhase.failed,
            displayCode: 'K7M4-P2Q8',
            codeVersion: 1,
            failure: FamilyJoinFailure(
              FamilyJoinFailureCode.networkUnavailable,
            ),
          ),
        ];

        for (final state in states) {
          await pumpFamilyCodeSheet(
            tester,
            InvitationTestFamilyCodeController(state),
            size: size,
          );
          expect(find.byKey(const Key('family-code-display')), findsOneWidget);
          if (state.isOffline) {
            expect(
              find.text('Showing the code saved on this device'),
              findsOneWidget,
            );
          }
          if (!state.isCreator) {
            expect(
              find.byKey(const Key('regenerate-family-code')),
              findsNothing,
            );
          }
          if (state.phase == FamilyCodePhase.regenerating) {
            expectFamilyLiveRegion(tester, 'Regenerating family code');
            final share = tester.widget<TextButton>(
              find.byKey(const Key('share-family-link')),
            );
            expect(share.onPressed, isNull);
          }
          if (state.phase == FamilyCodePhase.failed) {
            expect(find.text('Keepers is offline.'), findsOneWidget);
            expectMinimumFamilyTarget(
              tester,
              find.widgetWithText(TextButton, 'Retry'),
            );
          }
          expectNoPrivateFamilyJoinMaterial();
          expect(tester.takeException(), isNull, reason: state.toString());
        }
        semantics.dispose();
      },
    );

    testWidgets(
      '$sizeName manual, preview, and pending requester states remain stable',
      (tester) async {
        await configureFamilyInvitationViewport(tester, size: size);
        final semantics = tester.ensureSemantics();

        await pumpFamilyJoinSnapshot(
          tester,
          const FamilyJoinState(),
          size: size,
          keyboardInset: 300,
        );
        expectMinimumFamilyTarget(
          tester,
          find.byKey(const Key('continue-family-code')),
        );
        await tester.tap(find.byKey(const Key('continue-family-code')));
        await tester.pump();
        expectFamilyLiveRegion(
          tester,
          'Enter a valid eight-character family code.',
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('family-code-field')))
              .focusNode
              ?.hasFocus,
          isTrue,
        );

        await pumpFamilyJoinSnapshot(
          tester,
          FamilyJoinState(
            phase: FamilyJoinPhase.preview,
            preview: familyInvitationPreview,
            proposedMemberId: familyInvitationRequesterMemberId,
            proposedAvatar: const AvatarConfig.defaults(
              seed: familyInvitationRequesterMemberId,
            ),
            proposedJoiningPublicKey: familyInvitationJoiningPublicKey,
          ),
          size: size,
        );
        expect(find.text('Rahman family'), findsOneWidget);
        expect(
          find.byKey(const Key('family-preview-avatar-0')),
          findsOneWidget,
        );
        expectMinimumFamilyTarget(
          tester,
          find.byKey(const Key('join-family-submit')),
        );
        expectNoPrivateFamilyJoinMaterial();

        await pumpFamilyJoinSnapshot(
          tester,
          FamilyJoinState(
            phase: FamilyJoinPhase.pending,
            preview: familyInvitationPreview,
            request: familyInvitationPendingRequest,
            failure: const FamilyJoinFailure(
              FamilyJoinFailureCode.networkUnavailable,
            ),
            retryPoint: FamilyJoinRetryPoint.refreshStatus,
          ),
          size: size,
        );
        expectFamilyLiveRegion(tester, 'Keepers could not connect. Try again.');
        expectMinimumFamilyTarget(
          tester,
          find.byKey(const Key('cancel-join-request')),
        );
        expectMinimumFamilyTarget(
          tester,
          find.widgetWithText(TextButton, 'Retry'),
        );
        expectNoPrivateFamilyJoinMaterial();
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets('approver sheet exposes only requester identity and decisions', (
    tester,
  ) async {
    await configureFamilyInvitationViewport(tester);
    final semantics = tester.ensureSemantics();
    final controller = InvitationTestJoinRequestsController(
      FamilyJoinRequestsState(requests: [familyInvitationApproverRequest]),
    );
    await pumpFamilyJoinRequestSheet(tester, controller);

    expect(find.text('Mariam wants to join'), findsOneWidget);
    expect(find.bySemanticsLabel('Mariam profile'), findsOneWidget);
    expect(find.textContaining('Rahman'), findsNothing);
    for (final key in const [
      'approve-join-request',
      'decline-join-request',
      'close-join-request-sheet',
    ]) {
      expectMinimumFamilyTarget(tester, find.byKey(Key(key)));
    }
    expectNoPrivateFamilyJoinMaterial();

    await tester.tap(find.byKey(const Key('decline-join-request')));
    await tester.pumpAndSettle();
    expect(find.text("Decline Mariam's request?"), findsOneWidget);
    await tester.tap(find.text('Decline').last);
    await tester.pumpAndSettle();
    expect(controller.declineCalls, 1);
    semantics.dispose();
  });

  testWidgets('resolving approval disables every sheet exit and decision', (
    tester,
  ) async {
    await configureFamilyInvitationViewport(tester);
    final controller = InvitationTestJoinRequestsController(
      FamilyJoinRequestsState(
        requests: [familyInvitationApproverRequest],
        resolvingRequestId: familyInvitationRequestId,
      ),
    );
    await pumpFamilyJoinRequestSheet(tester, controller);

    for (final key in const [
      'approve-join-request',
      'decline-join-request',
      'close-join-request-sheet',
    ]) {
      final button = tester.widget<ButtonStyleButton>(find.byKey(Key(key)));
      expect(button.onPressed, isNull, reason: key);
      expectMinimumFamilyTarget(tester, find.byKey(Key(key)));
    }
    expect(
      tester
          .getSemantics(find.byKey(const Key('join-request-status')))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expectNoPrivateFamilyJoinMaterial();
  });

  testWidgets('request feedback and actions remain separated at 200% text', (
    tester,
  ) async {
    await configureFamilyInvitationViewport(tester);
    await pumpFamilyJoinSnapshot(
      tester,
      FamilyJoinState(
        phase: FamilyJoinPhase.pending,
        preview: familyInvitationPreview,
        request: familyInvitationPendingRequest,
        failure: const FamilyJoinFailure(
          FamilyJoinFailureCode.networkUnavailable,
        ),
        retryPoint: FamilyJoinRetryPoint.refreshStatus,
      ),
      textScale: 2,
    );

    final error = find.text('Keepers could not connect. Try again.');
    final retry = find.widgetWithText(TextButton, 'Retry');
    final cancel = find.byKey(const Key('cancel-join-request'));
    expect(error, findsOneWidget);
    expect(retry, findsOneWidget);
    expect(tester.getRect(error).bottom, lessThan(tester.getRect(retry).top));
    expect(
      tester.getRect(retry).bottom,
      lessThanOrEqualTo(tester.getRect(cancel).top),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('terminal requester outcomes remain distinct and announced', (
    tester,
  ) async {
    await configureFamilyInvitationViewport(tester);
    final semantics = tester.ensureSemantics();
    const cases = <FamilyJoinState, String>{
      FamilyJoinState(phase: FamilyJoinPhase.declined):
          "Your request wasn't accepted",
      FamilyJoinState(phase: FamilyJoinPhase.expired):
          'Your request has expired',
      FamilyJoinState(phase: FamilyJoinPhase.invitationChanged):
          'This family invitation has changed. Ask for the new code.',
    };
    for (final entry in cases.entries) {
      await pumpFamilyJoinSnapshot(tester, entry.key);
      expectFamilyLiveRegion(tester, entry.value);
      expectMinimumFamilyTarget(
        tester,
        find.widgetWithText(OutlinedButton, 'Back'),
      );
      expectNoPrivateFamilyJoinMaterial();
    }
    semantics.dispose();
  });
}
