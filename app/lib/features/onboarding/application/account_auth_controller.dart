import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';

enum AccountAuthPhase {
  idle,
  awaitingCode,
  awaitingProvider,
  busy,
  authenticated,
  error,
}

final class AccountAuthState {
  const AccountAuthState({
    this.phase = AccountAuthPhase.idle,
    this.email = '',
    this.errorMessage,
  });

  final AccountAuthPhase phase;
  final String email;
  final String? errorMessage;

  bool get isBusy => phase == AccountAuthPhase.busy;

  @override
  bool operator ==(Object other) =>
      other is AccountAuthState &&
      other.phase == phase &&
      other.email == email &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(phase, email, errorMessage);
}

final accountAuthControllerProvider =
    NotifierProvider.autoDispose<AccountAuthController, AccountAuthState>(
      AccountAuthController.new,
    );

final class AccountAuthController extends Notifier<AccountAuthState> {
  Future<void>? _inFlight;

  @override
  AccountAuthState build() {
    final gateway = ref.read(cloudFamilyGatewayProvider);
    if (gateway case CloudFamilyAuthEvents(:final signedInEvents)) {
      final subscription = signedInEvents.listen(
        (_) => _confirmGatewaySession(),
        onError: (Object _, StackTrace _) {
          unawaited(_handleExternalSignInFailure());
        },
      );
      ref.onDispose(subscription.cancel);
    }
    return gateway.authenticatedAccountId == null
        ? const AccountAuthState()
        : const AccountAuthState(phase: AccountAuthPhase.authenticated);
  }

  Future<void> requestEmailCode(String email) => _deduplicate(() async {
    if (!_canStartAuthentication) return;
    final normalized = _normalizeEmail(email);
    if (normalized == null) {
      state = const AccountAuthState(
        phase: AccountAuthPhase.error,
        errorMessage: 'Enter a valid email address',
      );
      return;
    }

    final gateway = ref.read(cloudFamilyGatewayProvider);
    state = AccountAuthState(phase: AccountAuthPhase.busy, email: normalized);
    try {
      await gateway.requestEmailOtp(normalized);
      if (!ref.mounted) return;
      if (gateway.authenticatedAccountId != null) {
        _confirmGatewaySession();
        return;
      }
      state = AccountAuthState(
        phase: AccountAuthPhase.awaitingCode,
        email: normalized,
      );
    } on Object {
      _setGenericError(email: normalized);
    }
  });

  Future<void> verifyEmailCode(String code) => _deduplicate(() async {
    if (!_canStartAuthentication) return;
    final token = code.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(token)) {
      state = AccountAuthState(
        phase: AccountAuthPhase.error,
        email: state.email,
        errorMessage: 'Enter the six-digit code',
      );
      return;
    }

    final email = _normalizeEmail(state.email);
    if (email == null) {
      _setGenericError();
      return;
    }

    final gateway = ref.read(cloudFamilyGatewayProvider);
    state = AccountAuthState(phase: AccountAuthPhase.busy, email: email);
    try {
      await gateway.verifyEmailOtp(email: email, token: token);
      if (!ref.mounted) return;
      if (gateway.authenticatedAccountId == null) {
        _setGenericError(email: email);
        return;
      }
      _confirmGatewaySession();
    } on Object {
      _setGenericError(email: email);
    }
  });

  Future<void> startSocialAuth(SocialAuthProvider provider) =>
      _deduplicate(() async {
        if (!_canStartAuthentication) return;
        final gateway = ref.read(cloudFamilyGatewayProvider);
        final socialGateway = switch (gateway) {
          CloudFamilySocialAuth capability => capability,
          _ => null,
        };
        if (socialGateway == null) {
          _setGenericError();
          return;
        }

        state = const AccountAuthState(phase: AccountAuthPhase.busy);
        try {
          await socialGateway.signInWithProvider(provider);
          if (!ref.mounted) return;
          if (gateway.authenticatedAccountId != null) {
            _confirmGatewaySession();
            return;
          }
          state = const AccountAuthState(
            phase: AccountAuthPhase.awaitingProvider,
          );
        } on Object {
          _setGenericError();
        }
      });

  bool get _canStartAuthentication =>
      state.phase != AccountAuthPhase.awaitingProvider &&
      state.phase != AccountAuthPhase.authenticated;

  void changeEmail() {
    if (state.isBusy ||
        state.phase == AccountAuthPhase.awaitingProvider ||
        state.phase == AccountAuthPhase.authenticated) {
      return;
    }
    state = const AccountAuthState();
  }

  Future<void> chooseAnotherWay() => _deduplicate(() async {
    if (state.phase != AccountAuthPhase.awaitingProvider) return;
    final gateway = ref.read(cloudFamilyGatewayProvider);
    final socialGateway = switch (gateway) {
      CloudFamilySocialAuth capability => capability,
      _ => null,
    };
    if (socialGateway == null) {
      _setProviderCancellationError();
      return;
    }
    try {
      final cancelled = await socialGateway.cancelPendingProviderSignIn();
      if (!ref.mounted) return;
      if (gateway.authenticatedAccountId != null) {
        _confirmGatewaySession();
        return;
      }
      if (!cancelled) {
        state = AccountAuthState(
          phase: AccountAuthPhase.awaitingProvider,
          email: state.email,
        );
        return;
      }
      state = const AccountAuthState();
    } on Object {
      _setProviderCancellationError();
    }
  });

  Future<void> _handleExternalSignInFailure() async {
    final failedPhase = state.phase;
    final gateway = ref.read(cloudFamilyGatewayProvider);
    final socialGateway = switch (gateway) {
      CloudFamilySocialAuth capability => capability,
      _ => null,
    };
    if (socialGateway == null) return;
    try {
      final cleared = await socialGateway.clearFailedProviderSignIn();
      if (!cleared) return;
    } on Object {
      return;
    }
    if (!ref.mounted || state.phase != failedPhase) return;
    if (gateway.authenticatedAccountId != null) {
      _confirmGatewaySession();
      return;
    }
    if (failedPhase == AccountAuthPhase.busy ||
        failedPhase == AccountAuthPhase.authenticated) {
      return;
    }
    _setGenericError(
      email: failedPhase == AccountAuthPhase.awaitingCode ? state.email : null,
    );
  }

  Future<void> _deduplicate(Future<void> Function() operation) {
    final running = _inFlight;
    if (running != null) return running;
    late final Future<void> future;
    future = operation().whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  void _confirmGatewaySession() {
    if (!ref.mounted ||
        ref.read(cloudFamilyGatewayProvider).authenticatedAccountId == null) {
      return;
    }
    state = AccountAuthState(
      phase: AccountAuthPhase.authenticated,
      email: state.email,
    );
  }

  void _setGenericError({String? email}) {
    if (!ref.mounted) return;
    state = AccountAuthState(
      phase: AccountAuthPhase.error,
      email: email ?? state.email,
      errorMessage: "We couldn't create your account. Try again.",
    );
  }

  void _setProviderCancellationError() {
    if (!ref.mounted) return;
    state = AccountAuthState(
      phase: AccountAuthPhase.awaitingProvider,
      email: state.email,
      errorMessage: "We couldn't cancel browser sign-in. Try again.",
    );
  }
}

String? _normalizeEmail(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty ||
      normalized.length > 254 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
    return null;
  }
  return normalized;
}
