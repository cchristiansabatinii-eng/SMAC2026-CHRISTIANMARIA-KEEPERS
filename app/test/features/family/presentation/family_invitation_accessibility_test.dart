import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/family_invite_controller.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/family/presentation/family_invite_screen.dart';
import 'package:keepers/features/family/presentation/family_join_screen.dart';

import 'family_invitation_test_harness.dart';

void main() {
  group('390x844, 1.4x, reduced-motion invitation coverage', () {
    testWidgets('invite route exposes every primary state without reflow', (
      tester,
    ) async {
      await configureFamilyInvitationViewport(tester);
      final semantics = tester.ensureSemantics();
      final states =
          <
            ({
              FamilyInviteState state,
              String? live,
              String? action,
              bool enabled,
              bool busy,
            })
          >[
            (
              state: const FamilyInviteState(),
              live: 'Checking cloud invitations',
              action: null,
              enabled: false,
              busy: true,
            ),
            (
              state: const FamilyInviteState(
                phase: FamilyInvitePhase.needsAuthentication,
              ),
              live: null,
              action: 'SEND CODE',
              enabled: true,
              busy: false,
            ),
            (
              state: const FamilyInviteState(
                phase: FamilyInvitePhase.checking,
                authenticationEmail: 'owner@example.com',
                retryPoint: FamilyInviteRetryPoint.requestOtp,
              ),
              live: null,
              action: 'SENDING CODE',
              enabled: false,
              busy: true,
            ),
            (
              state: const FamilyInviteState(
                phase: FamilyInvitePhase.awaitingOtp,
                authenticationEmail: 'owner@example.com',
              ),
              live: null,
              action: 'VERIFY CODE',
              enabled: true,
              busy: false,
            ),
            (
              state: const FamilyInviteState(
                phase: FamilyInvitePhase.checking,
                authenticationEmail: 'owner@example.com',
                retryPoint: FamilyInviteRetryPoint.verifyOtp,
              ),
              live: null,
              action: 'VERIFYING CODE',
              enabled: false,
              busy: true,
            ),
            (
              state: const FamilyInviteState(phase: FamilyInvitePhase.ready),
              live: null,
              action: 'CREATE INVITATION',
              enabled: true,
              busy: false,
            ),
            (
              state: const FamilyInviteState(
                phase: FamilyInvitePhase.creating,
                recipientEmail: 'relative@example.com',
              ),
              live: null,
              action: 'CREATING INVITATION',
              enabled: false,
              busy: true,
            ),
            (
              state: const FamilyInviteState(
                phase: FamilyInvitePhase.failed,
                failure: InvitationFailure(InvitationFailureCode.notConfigured),
                retryPoint: FamilyInviteRetryPoint.initialize,
              ),
              live: 'CLOUD INVITATIONS ARE NOT CONFIGURED FOR THIS BUILD.',
              action: 'TRY AGAIN',
              enabled: true,
              busy: false,
            ),
          ];

      for (final value in states) {
        await pumpInviteHarness(
          tester,
          InvitationTestInviteController(value.state),
        );
        expect(tester.takeException(), isNull, reason: '${value.state}');
        expect(find.byKey(const Key('family-invite-scroll')), findsOneWidget);
        expectMinimumTarget(
          tester,
          find.byKey(const Key('family-invite-back')),
        );
        final media = MediaQuery.of(
          tester.element(find.byType(FamilyInviteScreen)),
        );
        expect(media.size, familyInvitationViewport);
        expect(media.textScaler.scale(10), 14);
        expect(media.disableAnimations, isTrue);
        if (value.live case final label?) expectLiveRegion(tester, label);
        if (value.action case final label?) {
          expectOperableSemantics(
            tester,
            label,
            enabled: value.enabled,
            liveRegion: value.busy,
          );
        }
        expectNoInvitationSecrets();
      }
      semantics.dispose();
    });

    testWidgets(
      'pending invite actions remain stable, announced, and private',
      (tester) async {
        await configureFamilyInvitationViewport(tester);
        final semantics = tester.ensureSemantics();
        final created = invitationTestCreated();
        final controller = InvitationTestInviteController(
          FamilyInviteState(
            phase: FamilyInvitePhase.created,
            recipientEmail: 'relative@example.com',
            createdInvitation: created,
          ),
        );
        await pumpInviteHarness(tester, controller);

        expectLiveRegion(tester, 'INVITATION READY');
        expectOperableSemantics(tester, 'SHARE AGAIN');
        expectOperableSemantics(tester, 'CANCEL INVITATION');
        final shareRect = tester.getRect(
          find.byKey(const Key('share-family-invitation')),
        );
        final cancelRect = tester.getRect(
          find.byKey(const Key('cancel-family-invitation')),
        );
        expectNoInvitationSecrets();

        controller.show(
          FamilyInviteState(
            phase: FamilyInvitePhase.created,
            recipientEmail: 'relative@example.com',
            createdInvitation: created,
            isSharing: true,
          ),
        );
        await tester.pump();
        expectOperableSemantics(
          tester,
          'OPENING SHARE OPTIONS',
          enabled: false,
          liveRegion: true,
        );
        expectOperableSemantics(tester, 'CANCEL INVITATION', enabled: false);
        expect(
          tester.getRect(find.byKey(const Key('share-family-invitation'))),
          shareRect,
        );
        expect(
          tester.getRect(find.byKey(const Key('cancel-family-invitation'))),
          cancelRect,
        );

        controller.show(
          FamilyInviteState(
            phase: FamilyInvitePhase.revoking,
            recipientEmail: 'relative@example.com',
            createdInvitation: created,
          ),
        );
        await tester.pump();
        expectOperableSemantics(
          tester,
          'CANCELLING INVITATION',
          enabled: false,
          liveRegion: true,
        );
        expect(
          tester.getRect(find.byKey(const Key('share-family-invitation'))),
          shareRect,
        );
        expect(
          tester.getRect(find.byKey(const Key('cancel-family-invitation'))),
          cancelRect,
        );
        expectNoInvitationSecrets();
        semantics.dispose();
      },
    );

    testWidgets('join route covers loading, auth, OTP, preview, and joining', (
      tester,
    ) async {
      await configureFamilyInvitationViewport(tester);
      final semantics = tester.ensureSemantics();

      await pumpJoinHarness(
        tester,
        InvitationTestGateway(),
        identityLoading: true,
        settle: false,
      );
      expectLiveRegion(tester, 'CHECKING YOUR INVITATION');
      expect(find.byKey(const Key('family-join-scroll')), findsOneWidget);
      expectNoInvitationSecrets();

      final gateway = InvitationTestGateway();
      await pumpJoinHarness(tester, gateway);
      expectOperableSemantics(tester, 'SEND CODE');
      expectMinimumTarget(tester, find.byKey(const Key('join-email')));

      await tester.enterText(
        find.byKey(const Key('join-email')),
        'relative@example.com',
      );
      await tester.tap(find.text('SEND CODE'));
      await tester.pumpAndSettle();
      expectOperableSemantics(tester, 'VERIFY CODE');
      expectMinimumTarget(tester, find.byKey(const Key('join-email-otp')));
      expectMinimumTarget(
        tester,
        find.widgetWithText(OutlinedButton, 'CHANGE EMAIL'),
      );
      expectMinimumTarget(
        tester,
        find.widgetWithText(TextButton, 'RESEND CODE'),
      );

      await tester.enterText(find.byKey(const Key('join-email-otp')), '123456');
      await tester.tap(find.text('VERIFY CODE'));
      await tester.pumpAndSettle();
      expect(find.text('RAHMAN FAMILY'), findsOneWidget);
      expect(find.text('Created by Amina'), findsOneWidget);
      expectOperableSemantics(tester, 'JOIN FAMILY');
      expectMinimumTarget(tester, find.byKey(const Key('join-member-name')));
      final avatarOptions = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('avatar-option-') &&
            !key.value.startsWith('avatar-option-focus-');
      });
      expect(avatarOptions, findsWidgets);
      for (var index = 0; index < avatarOptions.evaluate().length; index += 1) {
        expectMinimumTarget(tester, avatarOptions.at(index));
      }
      expectNoInvitationSecrets();

      final joiningGateway = InvitationTestGateway(
        account: 'recipient',
        claimGate: Completer<ClaimedFamily>(),
      );
      await pumpJoinHarness(tester, joiningGateway);
      await tester.enterText(
        find.byKey(const Key('join-member-name')),
        'Mariam',
      );
      await tester.ensureVisible(find.byKey(const Key('join-family-submit')));
      final idleRect = tester.getRect(
        find.byKey(const Key('join-family-submit')),
      );
      await tester.tap(find.byKey(const Key('join-family-submit')));
      await tester.pump();
      expectOperableSemantics(
        tester,
        'WORKING',
        enabled: false,
        liveRegion: true,
      );
      expect(
        tester.getRect(find.byKey(const Key('join-family-submit'))),
        idleRect,
      );
      expect(
        tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
        isFalse,
      );
      expectNoInvitationSecrets();

      await pumpJoinSnapshotHarness(
        tester,
        const FamilyJoinState(phase: FamilyJoinPhase.complete),
      );
      expectLiveRegion(tester, 'OPENING YOUR FAMILY');
      expectNoInvitationSecrets();
      semantics.dispose();
    });
  });

  testWidgets('busy join actions keep their rectangle and announce progress', (
    tester,
  ) async {
    await configureFamilyInvitationViewport(tester);
    final semantics = tester.ensureSemantics();
    final gateway = InvitationTestGateway(requestGate: Completer<void>());
    await pumpJoinHarness(tester, gateway);
    await tester.enterText(
      find.byKey(const Key('join-email')),
      'relative@example.com',
    );
    final idleRect = tester.getRect(find.byType(FilledButton));
    await tester.tap(find.text('SEND CODE'));
    await tester.pump();
    expectOperableSemantics(
      tester,
      'WORKING',
      enabled: false,
      liveRegion: true,
    );
    expect(tester.getRect(find.byType(FilledButton)), idleRect);
    expectNoInvitationSecrets();
    semantics.dispose();
  });

  testWidgets('keyboard-open forms remain visible and submit their actions', (
    tester,
  ) async {
    await configureFamilyInvitationViewport(tester);
    final invite = InvitationTestInviteController(
      const FamilyInviteState(phase: FamilyInvitePhase.needsAuthentication),
    );
    await pumpInviteHarness(tester, invite, keyboardInset: 300);
    await tester.showKeyboard(find.byKey(const Key('invite-owner-email')));
    await tester.enterText(
      find.byKey(const Key('invite-owner-email')),
      'owner@example.com',
    );
    await tester.ensureVisible(find.bySemanticsLabel('SEND CODE'));
    expect(
      tester.getRect(find.bySemanticsLabel('SEND CODE')).bottom,
      lessThanOrEqualTo(544),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(invite.requestedEmails, ['owner@example.com']);

    final gateway = InvitationTestGateway();
    await pumpJoinHarness(tester, gateway, keyboardInset: 300);
    await tester.showKeyboard(find.byKey(const Key('join-email')));
    await tester.enterText(
      find.byKey(const Key('join-email')),
      'relative@example.com',
    );
    await tester.ensureVisible(find.bySemanticsLabel('SEND CODE'));
    expect(
      tester.getRect(find.bySemanticsLabel('SEND CODE')).bottom,
      lessThanOrEqualTo(544),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(gateway.requestedEmails, ['relative@example.com']);
    expect(find.byKey(const Key('join-email-otp')), findsOneWidget);
  });

  testWidgets('local validation announces errors and focuses invalid fields', (
    tester,
  ) async {
    await configureFamilyInvitationViewport(tester);
    final semantics = tester.ensureSemantics();
    await pumpInviteHarness(
      tester,
      InvitationTestInviteController(
        const FamilyInviteState(phase: FamilyInvitePhase.needsAuthentication),
      ),
    );
    await tester.tap(find.text('SEND CODE'));
    await tester.pump();
    expectLiveRegion(tester, 'ENTER A COMPLETE EMAIL ADDRESS.');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('invite-owner-email')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );

    await pumpJoinHarness(tester, InvitationTestGateway());
    await tester.tap(find.text('SEND CODE'));
    await tester.pump();
    expectLiveRegion(tester, 'ENTER A COMPLETE EMAIL ADDRESS.');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('join-email')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('recoverable failures are live, focused, and operable', (
    tester,
  ) async {
    await configureFamilyInvitationViewport(tester);
    final semantics = tester.ensureSemantics();
    final cases = <(InvitationTestGateway, String)>[
      (
        InvitationTestGateway(configured: false, account: 'recipient'),
        'CLOUD INVITATIONS ARE NOT CONFIGURED FOR THIS BUILD.',
      ),
      (
        InvitationTestGateway(
          account: 'recipient',
          previewFailure: const InvitationFailure(
            InvitationFailureCode.networkUnavailable,
          ),
        ),
        'KEEPERS COULD NOT REACH THE INVITATION SERVICE. TRY AGAIN.',
      ),
      (
        InvitationTestGateway(
          account: 'recipient',
          previewFailure: const InvitationFailure(
            InvitationFailureCode.localPersistenceFailed,
          ),
        ),
        'KEEPERS COULD NOT COMPLETE THIS SAFELY. TRY AGAIN.',
      ),
    ];
    for (final (gateway, message) in cases) {
      await pumpJoinHarness(tester, gateway);
      expectLiveRegion(tester, message);
      expectOperableSemantics(tester, 'TRY AGAIN');
      expect(
        tester
            .widget<FilledButton>(find.byType(FilledButton))
            .focusNode
            ?.hasFocus,
        isTrue,
      );
      expectMinimumTarget(
        tester,
        find.widgetWithText(OutlinedButton, 'CONTINUE TO KEEPERS'),
      );
      expectNoInvitationSecrets();
    }
    semantics.dispose();
  });

  testWidgets('email mismatch is protected, announced, and focuses email', (
    tester,
  ) async {
    await configureFamilyInvitationViewport(tester);
    final semantics = tester.ensureSemantics();
    const message =
        'SIGN IN WITH THE EMAIL ADDRESS THIS INVITATION WAS SENT TO.';
    await pumpJoinHarness(
      tester,
      InvitationTestGateway(
        account: 'wrong-account',
        previewFailure: const InvitationFailure(
          InvitationFailureCode.emailMismatch,
        ),
      ),
    );
    expectLiveRegion(tester, message);
    expect(find.byKey(const Key('join-family-submit')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('join-email')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    expectOperableSemantics(tester, 'SEND CODE');
    expectMinimumTarget(
      tester,
      find.widgetWithText(OutlinedButton, 'CONTINUE TO KEEPERS'),
    );
    expectNoInvitationSecrets();
    semantics.dispose();
  });

  testWidgets('terminal failures fail closed with a focused recovery action', (
    tester,
  ) async {
    await configureFamilyInvitationViewport(tester);
    final semantics = tester.ensureSemantics();
    final cases = <(InvitationFailureCode, String)>[
      (InvitationFailureCode.expired, 'THIS INVITATION HAS EXPIRED.'),
      (
        InvitationFailureCode.revoked,
        'THIS INVITATION IS NO LONGER AVAILABLE.',
      ),
      (
        InvitationFailureCode.alreadyClaimed,
        'THIS INVITATION HAS ALREADY BEEN CLAIMED.',
      ),
      (
        InvitationFailureCode.forbidden,
        'THIS INVITATION CANNOT BE USED WITH THIS PROFILE.',
      ),
      (
        InvitationFailureCode.differentFamily,
        'FAMILY SWITCHING IS NOT AVAILABLE ON THIS DEVICE.',
      ),
      (
        InvitationFailureCode.envelopeRejected,
        'THIS INVITATION LINK IS NOT VALID.',
      ),
      (
        InvitationFailureCode.malformedLink,
        'THIS INVITATION LINK IS NOT VALID.',
      ),
    ];
    for (final (code, message) in cases) {
      await pumpJoinHarness(
        tester,
        InvitationTestGateway(
          account: 'recipient',
          previewFailure: InvitationFailure(code),
        ),
      );
      expectLiveRegion(tester, message);
      expect(find.byKey(const Key('join-family-submit')), findsNothing);
      final recovery = find.widgetWithText(
        OutlinedButton,
        'CONTINUE TO KEEPERS',
      );
      expectMinimumTarget(tester, recovery);
      expect(
        tester.widget<OutlinedButton>(recovery).focusNode?.hasFocus,
        isTrue,
      );
      expectNoInvitationSecrets();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: invitationMediaQuery(),
          child: const FamilyJoinScreen.malformed(),
        ),
      ),
    );
    await tester.pump();
    expectLiveRegion(tester, 'THIS INVITATION LINK IS NOT VALID.');
    expect(find.byKey(const Key('join-family-submit')), findsNothing);
    expectMinimumTarget(
      tester,
      find.widgetWithText(OutlinedButton, 'CONTINUE TO KEEPERS'),
    );
    expectNoInvitationSecrets();
    semantics.dispose();
  });
}
