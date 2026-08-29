import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/onboarding/presentation/account_screen.dart';

void main() {
  testWidgets('offers email, Google, Microsoft, and Apple on first launch', (
    tester,
  ) async {
    final gateway = _AccountGateway();
    addTearDown(gateway.dispose);
    await _pumpAccountScreen(tester, gateway: gateway);

    expect(find.text('Create your Keepers account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Microsoft'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.byKey(const Key('account-email')), findsOneWidget);
    expect(find.text('Continue with email'), findsOneWidget);
    expect(
      find.textContaining('memories and keys stay private on this device'),
      findsOneWidget,
    );
  });

  testWidgets('validates email inline before requesting a code', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final gateway = _AccountGateway();
    addTearDown(gateway.dispose);
    await _pumpAccountScreen(tester, gateway: gateway);

    await tester.enterText(
      find.byKey(const Key('account-email')),
      'not-an-email',
    );
    await tester.ensureVisible(find.text('Continue with email'));
    await tester.tap(find.text('Continue with email'));
    await tester.pump();

    final error = find.bySemanticsLabel('Enter a valid email address');
    expect(error, findsOneWidget);
    expect(
      tester
          .getSemantics(error)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(gateway.requestedEmails, isEmpty);
    semantics.dispose();
  });

  testWidgets('email code creates the account and resumes startup', (
    tester,
  ) async {
    final gateway = _AccountGateway();
    addTearDown(gateway.dispose);
    var authenticated = 0;
    await _pumpAccountScreen(
      tester,
      gateway: gateway,
      onAuthenticated: () => authenticated += 1,
    );

    await tester.enterText(
      find.byKey(const Key('account-email')),
      '  Chris@Example.com  ',
    );
    await tester.ensureVisible(find.text('Continue with email'));
    await tester.tap(find.text('Continue with email'));
    await tester.pumpAndSettle();

    expect(gateway.requestedEmails, ['chris@example.com']);
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.byKey(const Key('account-email-code')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('account-email-code')),
      '123456',
    );
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();

    expect(gateway.verifiedCodes, [
      (email: 'chris@example.com', token: '123456'),
    ]);
    expect(authenticated, 1);
  });

  for (final entry in <String, SocialAuthProvider>{
    'Google': SocialAuthProvider.google,
    'Microsoft': SocialAuthProvider.microsoft,
    'Apple': SocialAuthProvider.apple,
  }.entries) {
    testWidgets('${entry.key} launches provider auth and resumes on callback', (
      tester,
    ) async {
      final gateway = _AccountGateway();
      addTearDown(gateway.dispose);
      var authenticated = 0;
      await _pumpAccountScreen(
        tester,
        gateway: gateway,
        onAuthenticated: () => authenticated += 1,
      );

      await tester.tap(find.text('Continue with ${entry.key}'));
      await tester.pump();

      expect(gateway.socialProviders, [entry.value]);
      expect(authenticated, 0);

      gateway.completeSignIn();
      await tester.pumpAndSettle();
      expect(authenticated, 1);
    });
  }

  testWidgets(
    'provider auth waits for the browser until another way is chosen',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final gateway = _AccountGateway();
      addTearDown(gateway.dispose);
      await _pumpAccountScreen(tester, gateway: gateway);

      await tester.tap(find.text('Continue with Google'));
      await tester.pump();

      expect(find.text('Finish in your browser'), findsOneWidget);
      final waiting = find.bySemanticsLabel('Waiting for browser sign-in');
      expect(waiting, findsOneWidget);
      expect(
        tester
            .getSemantics(waiting)
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(find.text('Choose another way'), findsOneWidget);
      expect(find.text('Continue with Microsoft'), findsNothing);
      expect(find.byKey(const Key('account-email')), findsNothing);

      await tester.tap(find.text('Choose another way'));
      await tester.pump();

      expect(find.text('Create your Keepers account'), findsOneWidget);
      expect(find.text('Continue with Microsoft'), findsOneWidget);
      expect(find.byKey(const Key('account-email')), findsOneWidget);

      await tester.tap(find.text('Continue with Microsoft'));
      await tester.pump();
      expect(gateway.socialProviders, [
        SocialAuthProvider.google,
        SocialAuthProvider.microsoft,
      ]);
      semantics.dispose();
    },
  );

  testWidgets('unconfigured account service blocks setup with retry', (
    tester,
  ) async {
    final gateway = _AccountGateway(isConfigured: false);
    addTearDown(gateway.dispose);
    var retries = 0;
    await _pumpAccountScreen(
      tester,
      gateway: gateway,
      onRetry: () => retries += 1,
    );

    expect(
      find.text('Account setup is unavailable right now.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('account-email')), findsNothing);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });

  testWidgets('account actions stay reachable at 1.4x text on a small phone', (
    tester,
  ) async {
    final gateway = _AccountGateway();
    addTearDown(gateway.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAccountScreen(
      tester,
      gateway: gateway,
      textScaler: const TextScaler.linear(1.4),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.widgetWithText(OutlinedButton, 'Continue with Google'))
          .height,
      greaterThanOrEqualTo(48),
    );
    await tester.ensureVisible(find.text('Continue with email'));
    expect(find.text('Continue with email').hitTestable(), findsOneWidget);
  });

  testWidgets('long account errors remain readable at 1.4x text', (
    tester,
  ) async {
    final gateway = _AccountGateway(requestError: true);
    addTearDown(gateway.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAccountScreen(
      tester,
      gateway: gateway,
      textScaler: const TextScaler.linear(1.4),
    );
    await tester.enterText(
      find.byKey(const Key('account-email')),
      'chris@example.com',
    );
    await tester.ensureVisible(find.text('Continue with email'));
    await tester.tap(find.text('Continue with email'));
    await tester.pump();

    expect(
      find.text("We couldn't create your account. Try again."),
      findsOneWidget,
    );
    final error = find.text("We couldn't create your account. Try again.");
    final feedback = find.ancestor(of: error, matching: find.byType(Align));
    final feedbackRect = tester.getRect(feedback);
    final errorRect = tester.getRect(error);
    final continueButtonRect = tester.getRect(
      find.byKey(const Key('continue-with-email')),
    );

    expect(feedbackRect.height, greaterThan(42));
    expect(feedbackRect.top, lessThanOrEqualTo(errorRect.top));
    expect(feedbackRect.bottom, greaterThanOrEqualTo(errorRect.bottom));
    expect(continueButtonRect.top, greaterThanOrEqualTo(feedbackRect.bottom));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAccountScreen(
  WidgetTester tester, {
  required _AccountGateway gateway,
  VoidCallback? onAuthenticated,
  VoidCallback? onRetry,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [cloudFamilyGatewayProvider.overrideWithValue(gateway)],
      child: MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: AccountScreen(
            onAuthenticated: onAuthenticated ?? () {},
            onRetry: onRetry,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _AccountGateway
    implements
        CloudFamilyGateway,
        CloudFamilyAuthEvents,
        CloudFamilySocialAuth {
  _AccountGateway({this.isConfigured = true, this.requestError = false});

  @override
  final bool isConfigured;
  final bool requestError;
  final signedInController = StreamController<void>.broadcast(sync: true);
  final requestedEmails = <String>[];
  final verifiedCodes = <({String email, String token})>[];
  final socialProviders = <SocialAuthProvider>[];

  @override
  String? authenticatedAccountId;

  @override
  String? get authenticatedEmail => null;

  @override
  Stream<void> get signedInEvents => signedInController.stream;

  @override
  Future<void> requestEmailOtp(String email) async {
    if (requestError) throw StateError('network failed');
    requestedEmails.add(email);
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    verifiedCodes.add((email: email, token: token));
    completeSignIn();
  }

  @override
  Future<void> signInWithProvider(SocialAuthProvider provider) async {
    socialProviders.add(provider);
  }

  @override
  Future<bool> cancelPendingProviderSignIn() async => true;

  @override
  Future<bool> clearFailedProviderSignIn() async => true;

  void completeSignIn() {
    authenticatedAccountId = 'account-1';
    signedInController.add(null);
  }

  Future<void> dispose() => signedInController.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
