import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/onboarding/application/account_auth_controller.dart';

void main() {
  test('starts idle when the gateway has no authenticated session', () {
    final gateway = _AuthGateway();
    final container = _container(gateway);

    expect(
      container.read(accountAuthControllerProvider),
      const AccountAuthState(),
    );
  });

  test('starts authenticated when the gateway restored a session', () {
    final gateway = _AuthGateway()..authenticatedAccountId = 'account-1';
    final container = _container(gateway);

    expect(
      container.read(accountAuthControllerProvider).phase,
      AccountAuthPhase.authenticated,
    );
  });

  test('rejects an invalid email before calling the gateway', () async {
    final gateway = _AuthGateway();
    final container = _container(gateway);

    await container
        .read(accountAuthControllerProvider.notifier)
        .requestEmailCode('not-an-email');

    expect(gateway.requestedEmails, isEmpty);
    expect(
      container.read(accountAuthControllerProvider),
      const AccountAuthState(
        phase: AccountAuthPhase.error,
        errorMessage: 'Enter a valid email address',
      ),
    );
  });

  test('normalizes email before requesting a code', () async {
    final gateway = _AuthGateway();
    final container = _container(gateway);

    await container
        .read(accountAuthControllerProvider.notifier)
        .requestEmailCode('  Keeper@Example.COM  ');

    expect(gateway.requestedEmails, ['keeper@example.com']);
    expect(
      container.read(accountAuthControllerProvider),
      const AccountAuthState(
        phase: AccountAuthPhase.awaitingCode,
        email: 'keeper@example.com',
      ),
    );
  });

  test('guards duplicate email-code requests while one is pending', () async {
    final gateway = _AuthGateway()..requestCompleter = Completer<void>();
    final container = _container(gateway);
    final controller = container.read(accountAuthControllerProvider.notifier);

    final first = controller.requestEmailCode('first@example.com');
    final duplicate = controller.requestEmailCode('second@example.com');
    await Future<void>.delayed(Duration.zero);

    expect(gateway.requestedEmails, ['first@example.com']);
    expect(
      container.read(accountAuthControllerProvider),
      const AccountAuthState(
        phase: AccountAuthPhase.busy,
        email: 'first@example.com',
      ),
    );

    gateway.requestCompleter!.complete();
    await Future.wait([first, duplicate]);
    expect(
      container.read(accountAuthControllerProvider).phase,
      AccountAuthPhase.awaitingCode,
    );
  });

  test('maps email request failures to generic inline-safe copy', () async {
    final gateway = _AuthGateway()
      ..requestError = StateError('backend details must stay private');
    final container = _container(gateway);

    await container
        .read(accountAuthControllerProvider.notifier)
        .requestEmailCode('keeper@example.com');

    final state = container.read(accountAuthControllerProvider);
    expect(state.phase, AccountAuthPhase.error);
    expect(state.email, 'keeper@example.com');
    expect(state.errorMessage, "We couldn't create your account. Try again.");
    expect(state.errorMessage, isNot(contains('backend details')));
  });

  test('changeEmail returns from code entry to a clean idle state', () async {
    final gateway = _AuthGateway();
    final container = _container(gateway);
    final controller = container.read(accountAuthControllerProvider.notifier);
    await controller.requestEmailCode('keeper@example.com');

    controller.changeEmail();

    expect(
      container.read(accountAuthControllerProvider),
      const AccountAuthState(),
    );
  });

  test('rejects a code that is not exactly six digits', () async {
    final gateway = _AuthGateway();
    final container = _container(gateway);
    final controller = container.read(accountAuthControllerProvider.notifier);
    await controller.requestEmailCode('keeper@example.com');

    await controller.verifyEmailCode('12a456');

    expect(gateway.verifiedCodes, isEmpty);
    expect(
      container.read(accountAuthControllerProvider),
      const AccountAuthState(
        phase: AccountAuthPhase.error,
        email: 'keeper@example.com',
        errorMessage: 'Enter the six-digit code',
      ),
    );
  });

  test(
    'verifies a normalized six-digit code and confirms the session',
    () async {
      final gateway = _AuthGateway()..authenticateOnVerify = true;
      final container = _container(gateway);
      final controller = container.read(accountAuthControllerProvider.notifier);
      await controller.requestEmailCode('keeper@example.com');

      await controller.verifyEmailCode(' 123456 ');

      expect(gateway.verifiedCodes, [
        (email: 'keeper@example.com', token: '123456'),
      ]);
      expect(
        container.read(accountAuthControllerProvider),
        const AccountAuthState(
          phase: AccountAuthPhase.authenticated,
          email: 'keeper@example.com',
        ),
      );
    },
  );

  test('does not report authentication without a confirmed session', () async {
    final gateway = _AuthGateway();
    final container = _container(gateway);
    final controller = container.read(accountAuthControllerProvider.notifier);
    await controller.requestEmailCode('keeper@example.com');

    await controller.verifyEmailCode('123456');

    expect(
      container.read(accountAuthControllerProvider),
      const AccountAuthState(
        phase: AccountAuthPhase.error,
        email: 'keeper@example.com',
        errorMessage: "We couldn't create your account. Try again.",
      ),
    );
  });

  test('promotes a confirmed external sign-in event to authenticated', () {
    final gateway = _AuthGateway();
    final container = _container(gateway);
    container.read(accountAuthControllerProvider);

    gateway.completeSignIn();

    expect(
      container.read(accountAuthControllerProvider).phase,
      AccountAuthPhase.authenticated,
    );
  });

  test('pending email request cannot overwrite a sign-in event', () async {
    final gateway = _AuthGateway()..requestCompleter = Completer<void>();
    final container = _container(gateway);
    final controller = container.read(accountAuthControllerProvider.notifier);
    final request = controller.requestEmailCode('keeper@example.com');
    await Future<void>.delayed(Duration.zero);

    gateway.completeSignIn();
    gateway.requestCompleter!.complete();
    await request;

    expect(
      container.read(accountAuthControllerProvider).phase,
      AccountAuthPhase.authenticated,
    );
  });

  for (final provider in SocialAuthProvider.values) {
    test(
      'starts ${provider.name} auth and stays pending for browser confirmation',
      () async {
        final gateway = _SocialAuthGateway();
        final container = _container(gateway);

        await container
            .read(accountAuthControllerProvider.notifier)
            .startSocialAuth(provider);

        expect(gateway.socialProviders, [provider]);
        expect(
          container.read(accountAuthControllerProvider).phase,
          AccountAuthPhase.awaitingProvider,
        );
      },
    );
  }

  test(
    'pending provider auth blocks another provider and an email launch',
    () async {
      final gateway = _SocialAuthGateway();
      final container = _container(gateway);
      final controller = container.read(accountAuthControllerProvider.notifier);

      await controller.startSocialAuth(SocialAuthProvider.google);
      await controller.startSocialAuth(SocialAuthProvider.apple);
      await controller.requestEmailCode('keeper@example.com');

      expect(gateway.socialProviders, [SocialAuthProvider.google]);
      expect(gateway.requestedEmails, isEmpty);
      expect(
        container.read(accountAuthControllerProvider).phase,
        AccountAuthPhase.awaitingProvider,
      );
    },
  );

  test('only chooseAnotherWay abandons pending provider auth', () async {
    final gateway = _SocialAuthGateway();
    final container = _container(gateway);
    final controller = container.read(accountAuthControllerProvider.notifier);

    await controller.startSocialAuth(SocialAuthProvider.apple);
    controller.changeEmail();

    expect(
      container.read(accountAuthControllerProvider).phase,
      AccountAuthPhase.awaitingProvider,
    );

    await controller.chooseAnotherWay();

    expect(
      container.read(accountAuthControllerProvider),
      const AccountAuthState(),
    );
    expect(gateway.cancelledProviderSignIns, 1);
  });

  test('a provider callback already exchanging cannot be replaced', () async {
    final gateway = _SocialAuthGateway()..canCancelProviderSignIn = false;
    final container = _container(gateway);
    final controller = container.read(accountAuthControllerProvider.notifier);

    await controller.startSocialAuth(SocialAuthProvider.google);
    await controller.chooseAnotherWay();
    await controller.startSocialAuth(SocialAuthProvider.apple);

    expect(gateway.socialProviders, [SocialAuthProvider.google]);
    expect(
      container.read(accountAuthControllerProvider).phase,
      AccountAuthPhase.awaitingProvider,
    );
  });

  test(
    'provider callback completes while browser confirmation is pending',
    () async {
      final gateway = _SocialAuthGateway();
      final container = _container(gateway);
      final controller = container.read(accountAuthControllerProvider.notifier);

      await controller.startSocialAuth(SocialAuthProvider.microsoft);
      expect(
        container.read(accountAuthControllerProvider).phase,
        AccountAuthPhase.awaitingProvider,
      );

      gateway.completeSignIn();

      expect(
        container.read(accountAuthControllerProvider).phase,
        AccountAuthPhase.authenticated,
      );
    },
  );

  test(
    'provider callback failure clears PKCE state and allows retry',
    () async {
      final gateway = _SocialAuthGateway();
      final container = _container(gateway);
      final controller = container.read(accountAuthControllerProvider.notifier);

      await controller.startSocialAuth(SocialAuthProvider.google);
      gateway.failSignIn();
      await Future<void>.delayed(Duration.zero);

      expect(gateway.clearedFailedProviderSignIns, 1);
      expect(
        container.read(accountAuthControllerProvider),
        const AccountAuthState(
          phase: AccountAuthPhase.error,
          errorMessage: "We couldn't create your account. Try again.",
        ),
      );

      await controller.startSocialAuth(SocialAuthProvider.apple);
      expect(gateway.socialProviders, [
        SocialAuthProvider.google,
        SocialAuthProvider.apple,
      ]);
    },
  );

  test(
    'cold-start callback failure releases PKCE state and allows retry',
    () async {
      final gateway = _SocialAuthGateway();
      final container = _container(gateway);
      final controller = container.read(accountAuthControllerProvider.notifier);

      expect(
        container.read(accountAuthControllerProvider).phase,
        AccountAuthPhase.idle,
      );
      gateway.failSignIn();
      await Future<void>.delayed(Duration.zero);

      expect(gateway.clearedFailedProviderSignIns, 1);
      expect(
        container.read(accountAuthControllerProvider),
        const AccountAuthState(
          phase: AccountAuthPhase.error,
          errorMessage: "We couldn't create your account. Try again.",
        ),
      );

      await controller.startSocialAuth(SocialAuthProvider.google);
      expect(gateway.socialProviders, [SocialAuthProvider.google]);
      expect(
        container.read(accountAuthControllerProvider).phase,
        AccountAuthPhase.awaitingProvider,
      );
    },
  );

  test(
    'stale callback failure cannot release the current provider attempt',
    () async {
      final gateway = _SocialAuthGateway();
      final container = _container(gateway);
      final controller = container.read(accountAuthControllerProvider.notifier);

      await controller.startSocialAuth(SocialAuthProvider.google);
      await controller.chooseAnotherWay();
      await controller.startSocialAuth(SocialAuthProvider.apple);
      gateway.canClearFailedProviderSignIn = false;
      gateway.failSignIn();
      await Future<void>.delayed(Duration.zero);

      expect(gateway.clearedFailedProviderSignIns, 1);
      expect(
        container.read(accountAuthControllerProvider).phase,
        AccountAuthPhase.awaitingProvider,
      );

      gateway.completeSignIn();
      expect(
        container.read(accountAuthControllerProvider).phase,
        AccountAuthPhase.authenticated,
      );
    },
  );

  test('failed email-link callback preserves six-digit code entry', () async {
    final gateway = _SocialAuthGateway();
    final container = _container(gateway);
    final controller = container.read(accountAuthControllerProvider.notifier);
    await controller.requestEmailCode('keeper@example.com');

    gateway.failSignIn();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.clearedFailedProviderSignIns, 1);
    expect(
      container.read(accountAuthControllerProvider),
      const AccountAuthState(
        phase: AccountAuthPhase.error,
        email: 'keeper@example.com',
        errorMessage: "We couldn't create your account. Try again.",
      ),
    );
  });

  test('guards duplicate social auth launches', () async {
    final gateway = _SocialAuthGateway()..socialCompleter = Completer<void>();
    final container = _container(gateway);
    final controller = container.read(accountAuthControllerProvider.notifier);

    final first = controller.startSocialAuth(SocialAuthProvider.google);
    final duplicate = controller.startSocialAuth(SocialAuthProvider.apple);
    await Future<void>.delayed(Duration.zero);

    expect(gateway.socialProviders, [SocialAuthProvider.google]);
    expect(
      container.read(accountAuthControllerProvider).phase,
      AccountAuthPhase.busy,
    );

    gateway.socialCompleter!.complete();
    await Future.wait([first, duplicate]);
    expect(
      container.read(accountAuthControllerProvider).phase,
      AccountAuthPhase.awaitingProvider,
    );
  });

  test('handles gateways without optional social auth safely', () async {
    final gateway = _AuthGateway();
    final container = _container(gateway);

    await container
        .read(accountAuthControllerProvider.notifier)
        .startSocialAuth(SocialAuthProvider.microsoft);

    expect(
      container.read(accountAuthControllerProvider).errorMessage,
      "We couldn't create your account. Try again.",
    );
  });
}

ProviderContainer _container(_AuthGateway gateway) {
  final container = ProviderContainer(
    overrides: [cloudFamilyGatewayProvider.overrideWithValue(gateway)],
  );
  final subscription = container.listen<AccountAuthState>(
    accountAuthControllerProvider,
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(() async {
    subscription.close();
    container.dispose();
    await gateway.close();
  });
  return container;
}

class _AuthGateway implements CloudFamilyGateway, CloudFamilyAuthEvents {
  final signedInController = StreamController<void>.broadcast(sync: true);
  final requestedEmails = <String>[];
  final verifiedCodes = <({String email, String token})>[];
  Completer<void>? requestCompleter;
  Completer<void>? verifyCompleter;
  Object? requestError;
  Object? verifyError;
  bool authenticateOnVerify = false;

  @override
  bool get isConfigured => true;

  @override
  String? authenticatedAccountId;

  @override
  String? get authenticatedEmail => null;

  @override
  Stream<void> get signedInEvents => signedInController.stream;

  @override
  Future<void> requestEmailOtp(String email) async {
    requestedEmails.add(email);
    if (requestError case final error?) throw error;
    await requestCompleter?.future;
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    verifiedCodes.add((email: email, token: token));
    if (verifyError case final error?) throw error;
    await verifyCompleter?.future;
    if (authenticateOnVerify) completeSignIn();
  }

  void completeSignIn() {
    authenticatedAccountId = 'account-1';
    signedInController.add(null);
  }

  void failSignIn() {
    signedInController.addError(StateError('redacted auth callback failure'));
  }

  Future<void> close() => signedInController.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _SocialAuthGateway extends _AuthGateway
    implements CloudFamilySocialAuth {
  final socialProviders = <SocialAuthProvider>[];
  var cancelledProviderSignIns = 0;
  var clearedFailedProviderSignIns = 0;
  bool canCancelProviderSignIn = true;
  bool canClearFailedProviderSignIn = true;
  Completer<void>? socialCompleter;
  Object? socialError;

  @override
  Future<bool> cancelPendingProviderSignIn() async {
    cancelledProviderSignIns += 1;
    return canCancelProviderSignIn;
  }

  @override
  Future<bool> clearFailedProviderSignIn() async {
    clearedFailedProviderSignIns += 1;
    return canClearFailedProviderSignIn;
  }

  @override
  Future<void> signInWithProvider(SocialAuthProvider provider) async {
    socialProviders.add(provider);
    if (socialError case final error?) throw error;
    await socialCompleter?.future;
  }
}
