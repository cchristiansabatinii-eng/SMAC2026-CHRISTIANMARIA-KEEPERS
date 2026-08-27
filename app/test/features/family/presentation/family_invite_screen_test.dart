import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/family_invite_controller.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/presentation/family_invite_screen.dart';
import 'package:keepers/theme/keepers_theme.dart';

void main() {
  testWidgets('screen-reader actions expose semantic activation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final cases = <(FamilyInviteState, String)>[
      (
        const FamilyInviteState(phase: FamilyInvitePhase.needsAuthentication),
        'SEND CODE',
      ),
      (
        const FamilyInviteState(phase: FamilyInvitePhase.awaitingOtp),
        'VERIFY CODE',
      ),
      (
        const FamilyInviteState(phase: FamilyInvitePhase.ready),
        'CREATE INVITATION',
      ),
      (
        const FamilyInviteState(
          phase: FamilyInvitePhase.failed,
          failure: InvitationFailure(InvitationFailureCode.notConfigured),
          retryPoint: FamilyInviteRetryPoint.initialize,
        ),
        'TRY AGAIN',
      ),
      (
        FamilyInviteState(
          phase: FamilyInvitePhase.created,
          recipientEmail: 'mariam@example.com',
          createdInvitation: _createdInvitation(),
        ),
        'SHARE AGAIN',
      ),
    ];

    for (final (state, label) in cases) {
      await _pump(tester, _ScreenInviteController(state));

      final data = tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue, reason: label);
      expect(data.hasAction(SemanticsAction.tap), isTrue, reason: label);
    }
    semantics.dispose();
  });

  testWidgets('revoking cancellation keeps an announced busy label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      _ScreenInviteController(
        FamilyInviteState(
          phase: FamilyInvitePhase.revoking,
          recipientEmail: 'mariam@example.com',
          createdInvitation: _createdInvitation(),
        ),
      ),
    );

    final data = tester
        .getSemantics(find.bySemanticsLabel('CANCELLING INVITATION'))
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isLiveRegion, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  testWidgets('unconfigured invitation screen is honest and recoverable', (
    tester,
  ) async {
    final controller = _ScreenInviteController(
      const FamilyInviteState(
        phase: FamilyInvitePhase.failed,
        failure: InvitationFailure(InvitationFailureCode.notConfigured),
        retryPoint: FamilyInviteRetryPoint.initialize,
      ),
    );
    await _pump(tester, controller);

    expect(
      find.textContaining('CLOUD INVITATIONS ARE NOT CONFIGURED'),
      findsOneWidget,
    );
    expect(find.text('INVITATION READY'), findsNothing);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets('joined member sees owner-only state without invite actions', (
    tester,
  ) async {
    await _pump(
      tester,
      _ScreenInviteController(
        const FamilyInviteState(
          phase: FamilyInvitePhase.failed,
          failure: InvitationFailure(InvitationFailureCode.notOwner),
          retryPoint: FamilyInviteRetryPoint.bootstrap,
        ),
      ),
    );

    expect(
      find.textContaining('ONLY THE FAMILY OWNER CAN CREATE'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('invite-recipient-email')), findsNothing);
    expect(find.text('CREATE INVITATION'), findsNothing);
    expect(find.text('TRY AGAIN'), findsNothing);
  });

  testWidgets('signed-out create and revoke failures require owner sign-in', (
    tester,
  ) async {
    for (final state in [
      const FamilyInviteState(
        phase: FamilyInvitePhase.failed,
        recipientEmail: 'mariam@example.com',
        failure: InvitationFailure(InvitationFailureCode.signedOut),
        retryPoint: FamilyInviteRetryPoint.create,
      ),
      FamilyInviteState(
        phase: FamilyInvitePhase.failed,
        recipientEmail: 'mariam@example.com',
        createdInvitation: _createdInvitation(),
        failure: const InvitationFailure(InvitationFailureCode.signedOut),
        retryPoint: FamilyInviteRetryPoint.revoke,
      ),
    ]) {
      final controller = _ScreenInviteController(state);
      await _pump(tester, controller);

      expect(find.byKey(const Key('invite-owner-email')), findsOneWidget);
      expect(find.textContaining('SESSION CHANGED'), findsOneWidget);
      expect(find.byKey(const Key('invite-recipient-email')), findsNothing);
      expect(find.text('INVITATION READY'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('invite-owner-email')),
        'owner@example.com',
      );
      await tester.tap(find.text('SEND CODE'));
      await tester.pump();
      expect(controller.requestedEmails, ['owner@example.com']);
    }
  });

  testWidgets('ambiguous create retry stays bound to its original recipient', (
    tester,
  ) async {
    final controller = _ScreenInviteController(
      const FamilyInviteState(
        phase: FamilyInvitePhase.failed,
        recipientEmail: ' Mariam@Example.com ',
        isRecipientLocked: true,
        failure: InvitationFailure(InvitationFailureCode.networkUnavailable),
        retryPoint: FamilyInviteRetryPoint.create,
      ),
    );
    await _pump(tester, controller);

    final field = tester.widget<TextField>(
      find.byKey(const Key('invite-recipient-email')),
    );
    expect(field.enabled, isFalse);
    expect(field.controller!.text, ' Mariam@Example.com ');
    expect(find.text('RETRY INVITATION'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Recipient locked for this retry'),
      findsOneWidget,
    );

    await tester.tap(find.text('RETRY INVITATION'));
    await tester.pump();
    expect(controller.createdRecipients, [' Mariam@Example.com ']);
  });

  testWidgets('invite route remains usable at phone size and scaled text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _ScreenInviteController(
      const FamilyInviteState(phase: FamilyInvitePhase.ready),
    );

    await _pump(
      tester,
      controller,
      mediaQuery: const MediaQueryData(
        size: Size(390, 844),
        textScaler: TextScaler.linear(1.4),
        viewInsets: EdgeInsets.only(bottom: 280),
        disableAnimations: true,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('family-invite-scroll')), findsOneWidget);
    expect(find.byKey(const Key('invite-recipient-email')), findsOneWidget);
    final button = find.ancestor(
      of: find.text('CREATE INVITATION'),
      matching: find.byType(FilledButton),
    );
    expect(tester.getSize(button).height, 48);
  });

  testWidgets('pending recipient detail stays whole at phone large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(
      tester,
      _ScreenInviteController(
        FamilyInviteState(
          phase: FamilyInvitePhase.created,
          recipientEmail: 'mariam@example.com',
          createdInvitation: _createdInvitation(),
        ),
      ),
      mediaQuery: const MediaQueryData(
        size: Size(390, 844),
        textScaler: TextScaler.linear(1.4),
        disableAnimations: true,
      ),
    );

    final label = find.text('Recipient');
    final labelParagraphFinder = _renderedParagraph(label);
    final labelParagraph = tester.renderObject<RenderParagraph>(
      labelParagraphFinder,
    );
    final value = find.text('mariam@example.com');

    expect(labelParagraph.didExceedMaxLines, isFalse);
    expect(
      labelParagraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 9),
      ),
      hasLength(1),
      reason: 'RECIPIENT must not split across lines.',
    );
    expect(
      tester.getRect(labelParagraphFinder).right,
      lessThanOrEqualTo(tester.getRect(value).left - 8),
      reason: 'The detail label and value need a readable visual gap.',
    );

    final share = find.bySemanticsLabel('SHARE AGAIN');
    await tester.ensureVisible(share);
    await tester.pump();
    expect(share.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authentication work preserves its form and control geometry', (
    tester,
  ) async {
    for (final state in [
      const FamilyInviteState(
        phase: FamilyInvitePhase.checking,
        authenticationEmail: 'owner@example.com',
        retryPoint: FamilyInviteRetryPoint.requestOtp,
      ),
      const FamilyInviteState(
        phase: FamilyInvitePhase.checking,
        authenticationEmail: 'owner@example.com',
        retryPoint: FamilyInviteRetryPoint.verifyOtp,
      ),
    ]) {
      await _pump(tester, _ScreenInviteController(state));

      final fieldKey = state.retryPoint == FamilyInviteRetryPoint.requestOtp
          ? const Key('invite-owner-email')
          : const Key('invite-owner-otp');
      final busyLabel = state.retryPoint == FamilyInviteRetryPoint.requestOtp
          ? 'SENDING CODE'
          : 'VERIFYING CODE';
      expect(find.byKey(fieldKey), findsOneWidget);
      expect(find.bySemanticsLabel(busyLabel), findsOneWidget);
      expect(tester.getSize(find.byType(FilledButton)).height, 48);
    }
  });

  testWidgets('recipient retry action keeps one rectangle across feedback', (
    tester,
  ) async {
    final rectangles = <Rect>[];
    for (final state in [
      const FamilyInviteState(
        phase: FamilyInvitePhase.ready,
        recipientEmail: 'mariam@example.com',
        retryPoint: FamilyInviteRetryPoint.create,
        isRecipientLocked: true,
      ),
      const FamilyInviteState(
        phase: FamilyInvitePhase.creating,
        recipientEmail: 'mariam@example.com',
        retryPoint: FamilyInviteRetryPoint.create,
        isRecipientLocked: true,
      ),
      const FamilyInviteState(
        phase: FamilyInvitePhase.failed,
        recipientEmail: 'mariam@example.com',
        failure: InvitationFailure(InvitationFailureCode.networkUnavailable),
        retryPoint: FamilyInviteRetryPoint.create,
        isRecipientLocked: true,
      ),
    ]) {
      await _pump(tester, _ScreenInviteController(state));
      rectangles.add(
        tester.getRect(find.byKey(const Key('create-family-invitation'))),
      );
    }

    expect(rectangles[1], rectangles[0]);
    expect(rectangles[2], rectangles[0]);
  });

  testWidgets(
    'real ambiguous failure keeps long-recipient geometry at phone scale',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const recipient =
          'avery.long.family.recipient.with.tags+keepers@example-family-domain.com';
      final controller = _ScreenInviteController(
        const FamilyInviteState(phase: FamilyInvitePhase.ready),
        createFailure: const InvitationFailure(
          InvitationFailureCode.networkUnavailable,
        ),
      );
      await _pump(
        tester,
        controller,
        mediaQuery: const MediaQueryData(
          size: Size(390, 844),
          textScaler: TextScaler.linear(1.4),
          disableAnimations: true,
        ),
      );
      await tester.enterText(
        find.byKey(const Key('invite-recipient-email')),
        recipient,
      );
      await tester.pump();
      final fieldBefore = tester.getRect(
        find.byKey(const Key('invite-recipient-email')),
      );
      final actionBefore = tester.getRect(
        find.byKey(const Key('create-family-invitation')),
      );

      await tester.tap(find.text('CREATE INVITATION'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final lockedField = tester.widget<TextField>(
        find.byKey(const Key('invite-recipient-email')),
      );
      expect(lockedField.enabled, isFalse);
      expect(lockedField.controller!.text, recipient);
      expect(
        find.bySemanticsLabel('Recipient locked for this retry'),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(const Key('invite-recipient-email'))),
        fieldBefore,
      );
      expect(
        tester.getRect(find.byKey(const Key('create-family-invitation'))),
        actionBefore,
      );
    },
  );

  testWidgets('pending actions keep their rectangles across feedback', (
    tester,
  ) async {
    final rectangles = <(Rect, Rect)>[];
    for (final state in [
      FamilyInviteState(
        phase: FamilyInvitePhase.created,
        recipientEmail: 'mariam@example.com',
        createdInvitation: _createdInvitation(),
      ),
      FamilyInviteState(
        phase: FamilyInvitePhase.created,
        recipientEmail: 'mariam@example.com',
        createdInvitation: _createdInvitation(),
        isSharing: true,
      ),
      FamilyInviteState(
        phase: FamilyInvitePhase.created,
        recipientEmail: 'mariam@example.com',
        createdInvitation: _createdInvitation(),
        shareFailure: const InvitationFailure(InvitationFailureCode.unknown),
      ),
      FamilyInviteState(
        phase: FamilyInvitePhase.failed,
        recipientEmail: 'mariam@example.com',
        createdInvitation: _createdInvitation(),
        failure: const InvitationFailure(
          InvitationFailureCode.networkUnavailable,
        ),
        retryPoint: FamilyInviteRetryPoint.revoke,
      ),
    ]) {
      await _pump(tester, _ScreenInviteController(state));
      rectangles.add((
        tester.getRect(find.byKey(const Key('share-family-invitation'))),
        tester.getRect(find.byKey(const Key('cancel-family-invitation'))),
      ));
    }

    for (final rectangle in rectangles.skip(1)) {
      expect(rectangle.$1, rectangles.first.$1);
      expect(rectangle.$2, rectangles.first.$2);
    }
  });

  testWidgets('owner authenticates, creates, shares, and can cancel', (
    tester,
  ) async {
    final controller = _ScreenInviteController(
      const FamilyInviteState(phase: FamilyInvitePhase.needsAuthentication),
    );
    await _pump(tester, controller);

    await tester.enterText(
      find.byKey(const Key('invite-owner-email')),
      'Owner@Example.com',
    );
    await tester.tap(find.text('SEND CODE'));
    await tester.pump();
    expect(controller.requestedEmails, ['Owner@Example.com']);
    expect(find.textContaining('Open the sign-in link'), findsOneWidget);
    expect(find.byKey(const Key('invite-owner-otp')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('invite-owner-otp')), '12a');
    await tester.tap(find.text('VERIFY CODE'));
    await tester.pump();
    expect(controller.verifiedTokens, isEmpty);
    expect(find.text('ENTER THE SIX-DIGIT CODE.'), findsOneWidget);
    expect(tester.testTextInput.editingState!['text'], '12');

    await tester.enterText(find.byKey(const Key('invite-owner-otp')), '123456');
    await tester.tap(find.text('VERIFY CODE'));
    await tester.pump();
    expect(controller.verifiedTokens, ['123456']);

    await tester.enterText(
      find.byKey(const Key('invite-recipient-email')),
      'Mariam@Example.com',
    );
    await tester.tap(find.text('CREATE INVITATION'));
    await tester.pump();
    await tester.pump();

    expect(controller.createdRecipients, ['Mariam@Example.com']);
    expect(controller.shareCount, 1);
    expect(find.text('INVITATION READY'), findsOneWidget);
    expect(find.text('SHARE AGAIN'), findsOneWidget);
    expect(find.text('CANCEL INVITATION'), findsOneWidget);
    expect(find.textContaining('keepers://join'), findsNothing);

    await tester.tap(find.text('CANCEL INVITATION'));
    await tester.pump();
    expect(controller.revokeCount, 1);
    expect(find.byKey(const Key('invite-recipient-email')), findsOneWidget);
  });

  testWidgets('authentication-only mode never exposes recipient controls', (
    tester,
  ) async {
    final controller = _ScreenInviteController(
      const FamilyInviteState(phase: FamilyInvitePhase.needsAuthentication),
    );
    await _pump(tester, controller, authenticationOnly: true);

    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.byKey(const Key('invite-owner-email')), findsOneWidget);
    expect(find.byKey(const Key('invite-recipient-email')), findsNothing);

    controller.emit(const FamilyInviteState(phase: FamilyInvitePhase.ready));
    await tester.pump();

    expect(find.byKey(const Key('invite-recipient-email')), findsNothing);
  });

  testWidgets('share and revoke failures keep the pending invitation visible', (
    tester,
  ) async {
    final created = CreatedInvitation(
      inviteId: '44444444-4444-4444-8444-444444444444',
      familyId: '11111111-1111-4111-8111-111111111111',
      state: CloudInvitationState.pending,
      createdAt: DateTime.utc(2026, 9, 5, 8),
      expiresAt: DateTime.utc(2026, 9, 6, 8),
    );
    final controller = _ScreenInviteController(
      FamilyInviteState(
        phase: FamilyInvitePhase.failed,
        recipientEmail: 'mariam@example.com',
        createdInvitation: created,
        failure: const InvitationFailure(
          InvitationFailureCode.networkUnavailable,
        ),
        retryPoint: FamilyInviteRetryPoint.revoke,
        shareFailure: const InvitationFailure(InvitationFailureCode.unknown),
      ),
    );
    await _pump(tester, controller);

    expect(find.text('INVITATION READY'), findsOneWidget);
    expect(find.text('SHARE AGAIN'), findsOneWidget);
    expect(find.text('CANCEL INVITATION'), findsOneWidget);
    expect(find.textContaining('keepers://join'), findsNothing);
  });

  testWidgets('create and revoke phases block route disposal', (tester) async {
    for (final phase in [
      FamilyInvitePhase.creating,
      FamilyInvitePhase.revoking,
    ]) {
      final created = phase == FamilyInvitePhase.revoking
          ? CreatedInvitation(
              inviteId: '44444444-4444-4444-8444-444444444444',
              familyId: '11111111-1111-4111-8111-111111111111',
              state: CloudInvitationState.pending,
              createdAt: DateTime.utc(2026, 9, 5, 8),
              expiresAt: DateTime.utc(2026, 9, 6, 8),
            )
          : null;
      await _pump(
        tester,
        _ScreenInviteController(
          FamilyInviteState(
            phase: phase,
            recipientEmail: 'mariam@example.com',
            createdInvitation: created,
          ),
        ),
      );

      expect(
        tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
        isFalse,
      );
    }
  });
}

CreatedInvitation _createdInvitation() => CreatedInvitation(
  inviteId: '44444444-4444-4444-8444-444444444444',
  familyId: '11111111-1111-4111-8111-111111111111',
  state: CloudInvitationState.pending,
  createdAt: DateTime.utc(2026, 9, 5, 8),
  expiresAt: DateTime.utc(2026, 9, 6, 8),
);

Future<void> _pump(
  WidgetTester tester,
  _ScreenInviteController controller, {
  MediaQueryData mediaQuery = const MediaQueryData(disableAnimations: true),
  bool authenticationOnly = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        familyInviteControllerProvider.overrideWith(() => controller),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: KeepersType.primary),
        home: MediaQuery(
          data: mediaQuery,
          child: FamilyInviteScreen(
            initializeOnMount: false,
            authenticationOnly: authenticationOnly,
          ),
        ),
      ),
    ),
  );
}

Finder _renderedParagraph(Finder sourceText) =>
    find.descendant(of: sourceText, matching: find.byType(RichText));

final class _ScreenInviteController extends FamilyInviteController {
  _ScreenInviteController(this.initialState, {this.createFailure});

  final FamilyInviteState initialState;
  final InvitationFailure? createFailure;
  final requestedEmails = <String>[];
  final verifiedTokens = <String>[];
  final createdRecipients = <String>[];
  var shareCount = 0;
  var revokeCount = 0;

  @override
  FamilyInviteState build() => initialState;

  void emit(FamilyInviteState value) => state = value;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestEmailOtp(String email) async {
    requestedEmails.add(email);
    state = FamilyInviteState(
      phase: FamilyInvitePhase.awaitingOtp,
      authenticationEmail: email,
    );
  }

  @override
  Future<void> verifyEmailOtp(String token) async {
    verifiedTokens.add(token);
    state = FamilyInviteState(
      phase: FamilyInvitePhase.ready,
      authenticationEmail: state.authenticationEmail,
    );
  }

  @override
  Future<void> createInvite(
    String recipientEmail, {
    Rect? sharePositionOrigin,
  }) async {
    createdRecipients.add(recipientEmail);
    if (createFailure case final failure?) {
      state = FamilyInviteState(
        phase: FamilyInvitePhase.failed,
        authenticationEmail: state.authenticationEmail,
        recipientEmail: recipientEmail,
        failure: failure,
        retryPoint: FamilyInviteRetryPoint.create,
        isRecipientLocked: true,
      );
      return;
    }
    final created = CreatedInvitation(
      inviteId: '44444444-4444-4444-8444-444444444444',
      familyId: '11111111-1111-4111-8111-111111111111',
      state: CloudInvitationState.pending,
      createdAt: DateTime.utc(2026, 9, 5, 8),
      expiresAt: DateTime.utc(2026, 9, 6, 8),
    );
    state = FamilyInviteState(
      phase: FamilyInvitePhase.created,
      recipientEmail: recipientEmail,
      createdInvitation: created,
      isSharing: true,
    );
    shareCount += 1;
    state = FamilyInviteState(
      phase: FamilyInvitePhase.created,
      recipientEmail: recipientEmail,
      createdInvitation: created,
    );
  }

  @override
  Future<void> shareAgain({Rect? sharePositionOrigin}) async {
    shareCount += 1;
  }

  @override
  Future<void> revokeInvite() async {
    revokeCount += 1;
    state = FamilyInviteState(
      phase: FamilyInvitePhase.ready,
      recipientEmail: state.recipientEmail,
    );
  }
}
