import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_join_crypto_providers.dart';
import 'package:keepers/features/family/application/pending_join_completion_controller.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/joining_key_store.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/storage/database_providers.dart';

enum FamilyJoinPhase {
  enteringCode,
  checking,
  needsAuthentication,
  awaitingOtp,
  preview,
  requesting,
  pending,
  installing,
  complete,
  declined,
  cancelled,
  expired,
  invitationChanged,
  failed,
}

enum FamilyJoinRetryPoint {
  loadCode,
  requestOtp,
  verifyOtp,
  requestJoin,
  refreshStatus,
  cancel,
  install,
  complete,
}

final class FamilyJoinState {
  const FamilyJoinState({
    this.phase = FamilyJoinPhase.enteringCode,
    this.authenticationEmail = '',
    this.preview,
    this.request,
    this.proposedMemberId,
    this.proposedAvatar,
    this.proposedJoiningPublicKey,
    this.failure,
    this.retryPoint,
    this.isRefreshing = false,
  });

  final FamilyJoinPhase phase;
  final String authenticationEmail;
  final FamilyJoinPreview? preview;
  final OwnFamilyJoinRequest? request;
  final String? proposedMemberId;
  final AvatarConfig? proposedAvatar;
  final String? proposedJoiningPublicKey;
  final FamilyJoinFailure? failure;
  final FamilyJoinRetryPoint? retryPoint;
  final bool isRefreshing;

  bool get isBusy =>
      phase == FamilyJoinPhase.checking ||
      phase == FamilyJoinPhase.requesting ||
      phase == FamilyJoinPhase.installing ||
      isRefreshing;

  @override
  String toString() => 'FamilyJoinState(${phase.name})';
}

typedef FamilyJoinCompletionRecovery =
    Future<PendingJoinCompletionState> Function();

/// Keeps Task 3's auto-dispose recovery controller alive while a join screen
/// is using it and gives callers the authoritative result after recovery.
final familyJoinCompletionRecoveryProvider =
    Provider<FamilyJoinCompletionRecovery>((ref) {
      final controller = ref.watch(
        pendingJoinCompletionControllerProvider.notifier,
      );
      return () async {
        await controller.recover();
        return ref.read(pendingJoinCompletionControllerProvider);
      };
    });

final familyJoinControllerProvider =
    NotifierProvider.autoDispose<FamilyJoinController, FamilyJoinState>(
      FamilyJoinController.new,
    );

final class FamilyJoinController extends Notifier<FamilyJoinState> {
  Future<void>? _inFlight;
  StreamSubscription<void>? _ownRequestSubscription;
  FamilyCode? _code;
  FamilyJoinPreview? _preview;
  OwnFamilyJoinRequest? _request;
  FamilyJoinProfileDraft? _lastProfile;
  StoredJoiningKey? _joiningKey;
  String? _accountId;
  String? _authenticationEmailNormalized;
  String? _proposedMemberId;
  AvatarConfig? _proposedAvatar;
  String? _proposedJoiningPublicKey;
  bool _cancelInitiated = false;
  bool _installedLocally = false;

  @override
  FamilyJoinState build() {
    // Watching this provider owns the lifetime of Task 3 recovery.
    ref.watch(familyJoinCompletionRecoveryProvider);
    final gateway = ref.read(cloudFamilyGatewayProvider);
    if (gateway case CloudFamilyAuthEvents(:final signedInEvents)) {
      final subscription = signedInEvents.listen(
        (_) => unawaited(_resumeAfterExternalSignIn()),
        onError: (Object _, StackTrace _) {},
      );
      ref.onDispose(subscription.cancel);
    }
    ref.onDispose(() {
      unawaited(_ownRequestSubscription?.cancel());
      _joiningKey = null;
      _proposedJoiningPublicKey = null;
      _authenticationEmailNormalized = null;
    });
    return const FamilyJoinState();
  }

  Future<void> loadCode(FamilyCode code) => _deduplicate(() async {
    final retainedPhase = state.phase;
    final changedCode = _code != code;
    _code = code;
    if (changedCode) {
      _preview = null;
      _request = null;
      _lastProfile = null;
      _cancelInitiated = false;
      _installedLocally = false;
    }
    state = _next(phase: FamilyJoinPhase.checking, clearFailure: true);

    final gateway = ref.read(familyCodeJoinGatewayProvider);
    if (!gateway.isConfigured) {
      _fail(FamilyJoinFailureCode.notConfigured, FamilyJoinRetryPoint.loadCode);
      return;
    }
    final accountId = gateway.authenticatedAccountId;
    if (accountId == null) {
      state = _next(
        phase: FamilyJoinPhase.needsAuthentication,
        clearFailure: true,
      );
      return;
    }
    if (await ref.read(localIdentityProvider.future) != null) {
      _fail(FamilyJoinFailureCode.alreadyMember, FamilyJoinRetryPoint.loadCode);
      return;
    }
    if (!_accountStillCurrent(accountId)) return;
    _accountId = accountId;
    _subscribeToInvalidations(gateway);

    try {
      final own = await gateway.getOwnJoinRequest();
      if (!_accountStillCurrent(accountId)) return;
      if (own != null) {
        await _restoreProposalForRequest(own);
        await _applyAuthoritative(own);
        return;
      }
      final preview = await gateway.previewFamilyByCode(code);
      if (!_accountStillCurrent(accountId)) return;
      _preview = preview;
      await _ensureProposal(accountId);
      if (!_accountStillCurrent(accountId)) return;
      state = _next(phase: FamilyJoinPhase.preview, clearFailure: true);
    } on FamilyJoinFailure catch (failure) {
      _setFailure(
        failure,
        FamilyJoinRetryPoint.loadCode,
        retainedPhase: failure.code == FamilyJoinFailureCode.networkUnavailable
            ? retainedPhase
            : null,
      );
    } on Object {
      _fail(FamilyJoinFailureCode.unknown, FamilyJoinRetryPoint.loadCode);
    }
  });

  Future<void> requestEmailOtp(String email) => _deduplicate(() async {
    final normalized = _normalizeJoinEmail(email);
    if (normalized == null) {
      state = _next(
        phase: FamilyJoinPhase.failed,
        authenticationEmail: email,
        failure: const FamilyJoinFailure(FamilyJoinFailureCode.unknown),
        retryPoint: FamilyJoinRetryPoint.requestOtp,
      );
      return;
    }
    state = _next(
      phase: FamilyJoinPhase.checking,
      authenticationEmail: email,
      clearFailure: true,
    );
    try {
      await ref.read(cloudFamilyGatewayProvider).requestEmailOtp(normalized);
      _authenticationEmailNormalized = normalized;
      state = _next(
        phase: FamilyJoinPhase.awaitingOtp,
        authenticationEmail: email,
        clearFailure: true,
      );
    } on FamilyJoinFailure catch (failure) {
      _setFailure(
        failure,
        FamilyJoinRetryPoint.requestOtp,
        retainedPhase: failure.code == FamilyJoinFailureCode.networkUnavailable
            ? FamilyJoinPhase.needsAuthentication
            : null,
      );
    } on Object {
      _fail(FamilyJoinFailureCode.unknown, FamilyJoinRetryPoint.requestOtp);
    }
  });

  Future<void> verifyEmailOtp({required String email, required String token}) =>
      _deduplicate(() async {
        final normalized =
            _authenticationEmailNormalized ?? _normalizeJoinEmail(email);
        if (normalized == null) {
          _fail(FamilyJoinFailureCode.unknown, FamilyJoinRetryPoint.verifyOtp);
          return;
        }
        state = _next(phase: FamilyJoinPhase.checking, clearFailure: true);
        try {
          await ref
              .read(cloudFamilyGatewayProvider)
              .verifyEmailOtp(email: normalized, token: token);
          final code = _code;
          if (code == null) {
            _fail(
              FamilyJoinFailureCode.familyNotFound,
              FamilyJoinRetryPoint.loadCode,
            );
            return;
          }
          // OTPs are single use. Resume the authenticated code path, never the
          // token submission, after successful verification.
          await _loadCodeAfterInFlight(code);
        } on FamilyJoinFailure catch (failure) {
          _setFailure(
            failure,
            FamilyJoinRetryPoint.verifyOtp,
            retainedPhase:
                failure.code == FamilyJoinFailureCode.networkUnavailable
                ? FamilyJoinPhase.awaitingOtp
                : null,
          );
        } on Object {
          _fail(FamilyJoinFailureCode.unknown, FamilyJoinRetryPoint.verifyOtp);
        }
      });

  void changeAuthenticationEmail() {
    _authenticationEmailNormalized = null;
    state = _next(
      phase: FamilyJoinPhase.needsAuthentication,
      authenticationEmail: '',
      clearFailure: true,
    );
  }

  Future<void> requestJoin(
    FamilyJoinProfileDraft profile,
  ) => _deduplicate(() async {
    final code = _code;
    final preview = _preview;
    final accountId = _accountId;
    if (code == null || preview == null || accountId == null) {
      _fail(FamilyJoinFailureCode.signedOut, FamilyJoinRetryPoint.requestJoin);
      return;
    }
    if (!_profileMatchesProposal(profile)) {
      _fail(
        FamilyJoinFailureCode.invalidJoinKey,
        FamilyJoinRetryPoint.requestJoin,
      );
      return;
    }
    try {
      final validated = FamilyJoinProfileDraft.validated(
        memberId: profile.memberId,
        displayName: profile.displayName.trim(),
        demographicRole: profile.demographicRole,
        colorToken: profile.colorToken,
        avatar: profile.avatar,
        joiningPublicKey: profile.joiningPublicKey,
      );
      _lastProfile = validated;
      state = _next(phase: FamilyJoinPhase.requesting, clearFailure: true);
      final own = await ref
          .read(familyCodeJoinGatewayProvider)
          .createFamilyJoinRequest(
            FamilyJoinRequestDraft.validated(code: code, profile: validated),
          );
      if (!_accountStillCurrent(accountId)) return;
      _validateRequestIdentity(own, accountId: accountId);
      await _applyAuthoritative(own);
    } on FamilyJoinFailure catch (failure) {
      if (failure.code == FamilyJoinFailureCode.requestAlreadyPending) {
        await _refreshStatusUncoalesced();
        return;
      }
      _setFailure(
        failure,
        FamilyJoinRetryPoint.requestJoin,
        retainedPhase: failure.code == FamilyJoinFailureCode.networkUnavailable
            ? FamilyJoinPhase.preview
            : null,
      );
    } on ArgumentError {
      _fail(FamilyJoinFailureCode.unknown, FamilyJoinRetryPoint.requestJoin);
    } on Object {
      _fail(FamilyJoinFailureCode.unknown, FamilyJoinRetryPoint.requestJoin);
    }
  });

  Future<void> refreshStatus() => _deduplicate(_refreshStatusUncoalesced);

  Future<void> _refreshStatusUncoalesced() async {
    final gateway = ref.read(familyCodeJoinGatewayProvider);
    final accountId = _accountId ?? gateway.authenticatedAccountId;
    if (accountId == null) {
      _fail(
        FamilyJoinFailureCode.signedOut,
        FamilyJoinRetryPoint.refreshStatus,
      );
      return;
    }
    _accountId = accountId;
    _subscribeToInvalidations(gateway);
    if (_installedLocally) {
      await _completeInstalledJoin();
      return;
    }
    final retainedPhase = state.phase;
    state = _next(phase: retainedPhase, isRefreshing: true, clearFailure: true);
    try {
      final own = await gateway.getOwnJoinRequest();
      if (!_accountStillCurrent(accountId)) return;
      if (own == null) {
        _fail(
          FamilyJoinFailureCode.familyNotFound,
          FamilyJoinRetryPoint.refreshStatus,
          retainedPhase: retainedPhase,
        );
        return;
      }
      await _restoreProposalForRequest(own);
      await _applyAuthoritative(own);
    } on FamilyJoinFailure catch (failure) {
      _setFailure(
        failure,
        FamilyJoinRetryPoint.refreshStatus,
        retainedPhase: retainedPhase,
      );
    } on Object {
      _fail(
        FamilyJoinFailureCode.unknown,
        FamilyJoinRetryPoint.refreshStatus,
        retainedPhase: retainedPhase,
      );
    }
  }

  Future<void> cancel() => _deduplicate(() async {
    final request = _request;
    final accountId = _accountId;
    if (request == null || accountId == null) return;
    _cancelInitiated = true;
    final retainedPhase = state.phase;
    state = _next(phase: retainedPhase, isRefreshing: true, clearFailure: true);
    try {
      await ref
          .read(familyCodeJoinGatewayProvider)
          .cancelJoinRequest(request.requestId);
      if (!_accountStillCurrent(accountId)) return;
      // Decisions and Realtime payloads are never display authority.
      final own = await ref
          .read(familyCodeJoinGatewayProvider)
          .getOwnJoinRequest();
      if (own == null) {
        throw const FamilyJoinFailure(FamilyJoinFailureCode.unknown);
      }
      await _applyAuthoritative(own);
    } on FamilyJoinFailure catch (failure) {
      _setFailure(
        failure,
        FamilyJoinRetryPoint.cancel,
        retainedPhase: retainedPhase,
      );
    } on Object {
      _fail(
        FamilyJoinFailureCode.unknown,
        FamilyJoinRetryPoint.cancel,
        retainedPhase: retainedPhase,
      );
    }
  });

  Future<void> onResumed() {
    if (_code == null &&
        _request == null &&
        _accountId == null &&
        state.phase == FamilyJoinPhase.enteringCode) {
      return Future<void>.value();
    }
    return refreshStatus();
  }

  Future<void> retry() async {
    switch (state.retryPoint) {
      case FamilyJoinRetryPoint.loadCode:
        final code = _code;
        if (code != null) await loadCode(code);
      case FamilyJoinRetryPoint.requestOtp:
        await requestEmailOtp(state.authenticationEmail);
      case FamilyJoinRetryPoint.verifyOtp:
        state = _next(phase: FamilyJoinPhase.awaitingOtp, clearFailure: true);
      case FamilyJoinRetryPoint.requestJoin:
        final profile = _lastProfile;
        if (profile != null) await requestJoin(profile);
      case FamilyJoinRetryPoint.refreshStatus:
      case FamilyJoinRetryPoint.cancel:
        await refreshStatus();
      case FamilyJoinRetryPoint.install:
        final request = _request;
        if (request != null) await _installApproved(request);
      case FamilyJoinRetryPoint.complete:
        await _completeInstalledJoin();
      case null:
        break;
    }
  }

  Future<void> _resumeAfterExternalSignIn() async {
    final running = _inFlight;
    if (running != null) await running;
    if (!ref.mounted || _code == null) return;
    final canResume =
        state.phase == FamilyJoinPhase.needsAuthentication ||
        state.phase == FamilyJoinPhase.awaitingOtp ||
        (state.failure != null &&
            (state.retryPoint == FamilyJoinRetryPoint.requestOtp ||
                state.retryPoint == FamilyJoinRetryPoint.verifyOtp));
    if (canResume &&
        ref.read(familyCodeJoinGatewayProvider).authenticatedAccountId !=
            null) {
      await loadCode(_code!);
    }
  }

  Future<void> _loadCodeAfterInFlight(FamilyCode code) async {
    // This method runs inside the OTP operation, so calling the public
    // deduplicator would return the OTP future recursively.
    _inFlight = null;
    await loadCode(code);
  }

  void _subscribeToInvalidations(FamilyCodeJoinGateway gateway) {
    if (_ownRequestSubscription != null) return;
    _ownRequestSubscription = gateway.watchOwnJoinRequest().listen(
      (_) => unawaited(_refreshAfterCurrentOperation()),
      onError: (Object _, StackTrace _) {},
    );
  }

  Future<void> _refreshAfterCurrentOperation() async {
    final running = _inFlight;
    if (running != null) await running;
    if (ref.mounted && _accountId != null) await refreshStatus();
  }

  Future<void> _ensureProposal(String accountId) async {
    final values = ref.read(secureValueStoreProvider);
    final reference = _proposalReference(accountId);
    var memberId = await values.read(reference);
    if (memberId == null || !isCanonicalFamilyJoinUuid(memberId)) {
      memberId = ref.read(idFactoryProvider)();
      if (!isCanonicalFamilyJoinUuid(memberId)) {
        throw const FamilyJoinFailure(
          FamilyJoinFailureCode.localPersistenceFailed,
        );
      }
      // Persist the UUID before key creation so a crash cannot mint a second
      // request identity with a different key reference.
      await values.write(reference, memberId);
    }
    final joiningKey = await ref
        .read(joiningKeyStoreProvider)
        .getOrCreate(accountId: accountId, memberId: memberId);
    _proposedMemberId = memberId;
    _proposedAvatar ??= AvatarConfig.defaults(seed: memberId);
    _joiningKey = joiningKey;
    _proposedJoiningPublicKey = joiningKey.publicKey;
  }

  Future<void> _restoreProposalForRequest(OwnFamilyJoinRequest request) async {
    final accountId = ref
        .read(familyCodeJoinGatewayProvider)
        .authenticatedAccountId;
    if (accountId == null) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut);
    }
    _validateRequestIdentity(request, accountId: accountId);
    await ref
        .read(secureValueStoreProvider)
        .write(_proposalReference(accountId), request.memberId);
    final key = await ref
        .read(joiningKeyStoreProvider)
        .find(accountId: accountId, memberId: request.memberId);
    if (key == null || key.publicKey != request.joiningPublicKey) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.invalidJoinKey);
    }
    _accountId = accountId;
    _proposedMemberId = request.memberId;
    _proposedAvatar = request.avatar;
    _proposedJoiningPublicKey = request.joiningPublicKey;
    _joiningKey = key;
    _preview ??= FamilyJoinPreview(
      familyId: request.familyId,
      familyName: request.familyName,
      codeVersion: request.codeVersion,
      members: request.roster,
    );
  }

  Future<void> _applyAuthoritative(OwnFamilyJoinRequest request) async {
    final accountId = _accountId;
    if (accountId == null) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut);
    }
    _validateRequestIdentity(request, accountId: accountId);
    _request = request;
    _preview = FamilyJoinPreview(
      familyId: request.familyId,
      familyName: request.familyName,
      codeVersion: request.codeVersion,
      members: request.roster,
    );
    switch (request.state) {
      case FamilyJoinRequestState.pending:
        state = _next(phase: FamilyJoinPhase.pending, clearFailure: true);
      case FamilyJoinRequestState.approved:
        await _installApproved(request);
      case FamilyJoinRequestState.installed:
        _installedLocally = true;
        await _completeInstalledJoin();
      case FamilyJoinRequestState.declined:
        state = _next(phase: FamilyJoinPhase.declined, clearFailure: true);
      case FamilyJoinRequestState.cancelled:
        state = _next(
          phase: _cancelInitiated
              ? FamilyJoinPhase.cancelled
              : FamilyJoinPhase.invitationChanged,
          clearFailure: true,
        );
      case FamilyJoinRequestState.expired:
        state = _next(phase: FamilyJoinPhase.expired, clearFailure: true);
    }
  }

  Future<void> _installApproved(OwnFamilyJoinRequest request) async {
    final accountId = _accountId;
    final key = _joiningKey;
    final envelope = request.approvalEnvelope;
    if (accountId == null || key == null || envelope == null) {
      _fail(
        FamilyJoinFailureCode.envelopeRejected,
        FamilyJoinRetryPoint.install,
      );
      return;
    }
    final context = envelope.context;
    final validContext =
        envelope.version == FamilyJoinApprovalEnvelope.currentVersion &&
        context.requestId == request.requestId &&
        context.familyId == request.familyId &&
        context.requesterAccountId == request.requesterAccountId &&
        context.requesterAccountId == accountId &&
        context.codeVersion == request.codeVersion &&
        request.memberId == _proposedMemberId &&
        request.joiningPublicKey == key.publicKey &&
        request.roster.any(
          (member) =>
              member.id == request.memberId &&
              member.familyId == request.familyId,
        );
    if (!validContext) {
      _fail(
        FamilyJoinFailureCode.envelopeRejected,
        FamilyJoinRetryPoint.install,
      );
      return;
    }

    state = _next(phase: FamilyJoinPhase.installing, clearFailure: true);
    List<int>? opened;
    List<int>? familyKey;
    try {
      opened = await ref
          .read(familyJoinEnvelopeCodecProvider)
          .open(
            envelope: envelope,
            expectedRequesterPublicKey: request.joiningPublicKey,
            joiningKey: key,
          );
      familyKey = List<int>.of(opened);
      final approval = ApprovedFamilyJoin(
        requestId: request.requestId,
        familyId: request.familyId,
        familyName: request.familyName,
        localMemberId: request.memberId,
        joiningPublicKey: request.joiningPublicKey,
        approvalEnvelope: envelope,
        roster: request.roster,
      );
      await ref
          .read(approvedFamilyJoinInstallerProvider)
          .install(
            approval: approval,
            familyKey: familyKey,
            accountId: accountId,
          );
      _installedLocally = true;
    } on FamilyJoinFailure catch (failure) {
      _setFailure(failure, FamilyJoinRetryPoint.install);
      return;
    } on Object {
      _fail(
        FamilyJoinFailureCode.envelopeRejected,
        FamilyJoinRetryPoint.install,
      );
      return;
    } finally {
      _zero(familyKey);
      _zero(opened);
    }
    await _completeInstalledJoin();
  }

  Future<void> _completeInstalledJoin() async {
    try {
      final result = await ref.read(familyJoinCompletionRecoveryProvider)();
      if (result.phase == PendingJoinCompletionPhase.complete) {
        _joiningKey = null;
        _proposedJoiningPublicKey = null;
        state = _next(phase: FamilyJoinPhase.complete, clearFailure: true);
        return;
      }
      final failure =
          result.failure ??
          const FamilyJoinFailure(FamilyJoinFailureCode.localPersistenceFailed);
      _setFailure(failure, FamilyJoinRetryPoint.complete);
    } on FamilyJoinFailure catch (failure) {
      _setFailure(failure, FamilyJoinRetryPoint.complete);
    } on Object {
      _fail(FamilyJoinFailureCode.unknown, FamilyJoinRetryPoint.complete);
    }
  }

  void _validateRequestIdentity(
    OwnFamilyJoinRequest request, {
    required String accountId,
  }) {
    if (request.requesterAccountId != accountId ||
        !isCanonicalFamilyJoinUuid(request.requestId) ||
        !isCanonicalFamilyJoinUuid(request.familyId) ||
        !isCanonicalFamilyJoinUuid(request.memberId) ||
        request.codeVersion <= 0) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.forbidden);
    }
    final preview = _preview;
    if (preview != null &&
        (preview.familyId != request.familyId ||
            preview.codeVersion != request.codeVersion)) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.invitationChanged);
    }
  }

  bool _profileMatchesProposal(FamilyJoinProfileDraft profile) =>
      profile.memberId == _proposedMemberId &&
      profile.joiningPublicKey == _proposedJoiningPublicKey;

  FamilyJoinState _next({
    required FamilyJoinPhase phase,
    String? authenticationEmail,
    FamilyJoinFailure? failure,
    FamilyJoinRetryPoint? retryPoint,
    bool isRefreshing = false,
    bool clearFailure = false,
  }) => FamilyJoinState(
    phase: phase,
    authenticationEmail: authenticationEmail ?? state.authenticationEmail,
    preview: _preview,
    request: _request,
    proposedMemberId: _proposedMemberId,
    proposedAvatar: _proposedAvatar,
    proposedJoiningPublicKey: _proposedJoiningPublicKey,
    failure: clearFailure ? null : failure,
    retryPoint: clearFailure ? null : retryPoint,
    isRefreshing: isRefreshing,
  );

  void _setFailure(
    FamilyJoinFailure failure,
    FamilyJoinRetryPoint retryPoint, {
    FamilyJoinPhase? retainedPhase,
  }) {
    if (!ref.mounted) return;
    state = _next(
      phase:
          retainedPhase ??
          _terminalPhaseFor(failure.code) ??
          FamilyJoinPhase.failed,
      failure: failure,
      retryPoint: retryPoint,
    );
  }

  void _fail(
    FamilyJoinFailureCode code,
    FamilyJoinRetryPoint retryPoint, {
    FamilyJoinPhase? retainedPhase,
  }) => _setFailure(
    FamilyJoinFailure(code),
    retryPoint,
    retainedPhase: retainedPhase,
  );

  FamilyJoinPhase? _terminalPhaseFor(FamilyJoinFailureCode code) =>
      switch (code) {
        FamilyJoinFailureCode.alreadyMember => FamilyJoinPhase.failed,
        FamilyJoinFailureCode.familyNotFound => FamilyJoinPhase.failed,
        FamilyJoinFailureCode.requestDeclined => FamilyJoinPhase.declined,
        FamilyJoinFailureCode.requestExpired => FamilyJoinPhase.expired,
        FamilyJoinFailureCode.requestCancelled => FamilyJoinPhase.cancelled,
        FamilyJoinFailureCode.invitationChanged ||
        FamilyJoinFailureCode.codeVersionChanged =>
          FamilyJoinPhase.invitationChanged,
        _ => null,
      };

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

  bool _accountStillCurrent(String accountId) {
    if (!ref.mounted) return false;
    final current = ref
        .read(familyCodeJoinGatewayProvider)
        .authenticatedAccountId;
    if (current == accountId) return true;
    _fail(FamilyJoinFailureCode.signedOut, FamilyJoinRetryPoint.refreshStatus);
    return false;
  }

  static String _proposalReference(String accountId) =>
      'keepers.join.$accountId.proposed-member-id.v1';
}

String? _normalizeJoinEmail(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.length > 254 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

void _zero(List<int>? bytes) {
  if (bytes == null) return;
  try {
    for (var index = 0; index < bytes.length; index += 1) {
      bytes[index] = 0;
    }
  } on UnsupportedError {
    // Codec output can be immutable; the controller-owned mutable copy is not.
  }
}
