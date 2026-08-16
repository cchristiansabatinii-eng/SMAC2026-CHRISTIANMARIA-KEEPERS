import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_join_crypto_providers.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';

final class FamilyJoinRequestsState {
  const FamilyJoinRequestsState({
    this.requests = const [],
    this.isRefreshing = false,
    this.resolvingRequestId,
    this.failure,
  });

  final List<PendingFamilyJoinRequest> requests;
  final bool isRefreshing;
  final String? resolvingRequestId;
  final FamilyJoinFailure? failure;
}

final familyJoinRequestsControllerProvider = NotifierProvider.autoDispose
    .family<FamilyJoinRequestsController, FamilyJoinRequestsState, String>(
      FamilyJoinRequestsController.new,
    );

base class FamilyJoinRequestsController
    extends Notifier<FamilyJoinRequestsState> {
  FamilyJoinRequestsController(this._familyId);

  final String _familyId;
  final Map<String, Future<void>> _decisions = {};
  final LinkedHashSet<String> _resolvingRequestIds = LinkedHashSet();
  final Set<List<int>> _activeFamilyKeyBuffers = HashSet.identity();
  StreamSubscription<void>? _invalidationSubscription;
  Future<void>? _refreshInFlight;
  var _refreshQueued = false;
  var _refreshRevision = 0;
  var _lifecycleGeneration = 0;
  var _disposed = false;

  @override
  FamilyJoinRequestsState build() {
    final gateway = ref.read(familyCodeJoinGatewayProvider);
    _invalidationSubscription = gateway
        .watchPendingJoinRequests(_familyId)
        .listen(
          (_) {
            if (!_disposed) unawaited(refresh());
          },
          onError: (Object _, StackTrace _) {
            // Realtime is only an invalidation hint. RPC refresh and resume
            // remain the authoritative recovery paths.
          },
        );
    ref.onDispose(() {
      _disposed = true;
      _lifecycleGeneration += 1;
      unawaited(_invalidationSubscription?.cancel());
      _zeroActiveFamilyKeys();
    });
    unawaited(Future<void>.microtask(refresh));
    return const FamilyJoinRequestsState();
  }

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    _refreshQueued = true;
    _refreshRevision += 1;

    final running = _refreshInFlight;
    if (running != null) return running;
    final operation = _drainRefreshQueue();
    _refreshInFlight = operation;
    return operation;
  }

  Future<void> approve(String requestId) =>
      _serializeDecision(requestId, approve: true);

  Future<void> decline(String requestId) =>
      _serializeDecision(requestId, approve: false);

  Future<void> _drainRefreshQueue() async {
    try {
      while (!_disposed && _refreshQueued) {
        _refreshQueued = false;
        final revision = _refreshRevision;
        state = FamilyJoinRequestsState(
          requests: state.requests,
          isRefreshing: true,
          resolvingRequestId: _visibleResolvingRequestId,
        );
        await _refresh(revision);
      }
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<void> _refresh(int revision) async {
    final generation = _lifecycleGeneration;
    try {
      final authority = await _readAuthority(generation);
      final requests = await authority.gateway.listPendingJoinRequests(
        _familyId,
      );
      await _revalidateAuthority(authority, generation);
      _validatePendingProjection(requests);
      if (!_isCurrentRefresh(generation, revision)) return;
      state = FamilyJoinRequestsState(
        requests: List<PendingFamilyJoinRequest>.unmodifiable(requests),
        resolvingRequestId: _visibleResolvingRequestId,
      );
    } on _AbortedOperation {
      return;
    } on FamilyJoinFailure catch (failure) {
      if (_isCurrentRefresh(generation, revision)) {
        _publishRefreshFailure(failure, generation);
      }
    } on Object catch (error) {
      if (_isCurrentRefresh(generation, revision)) {
        _publishRefreshFailure(_mapFailure(error), generation);
      }
    }
  }

  Future<void> _serializeDecision(String requestId, {required bool approve}) {
    final running = _decisions[requestId];
    if (running != null) return running;
    if (_disposed) return Future<void>.value();

    late final Future<void> decision;
    decision = _decide(requestId, approve: approve).whenComplete(() {
      if (identical(_decisions[requestId], decision)) {
        _decisions.remove(requestId);
      }
    });
    _decisions[requestId] = decision;
    return decision;
  }

  Future<void> _decide(String requestId, {required bool approve}) async {
    var request = _requestById(requestId);
    if (request == null) {
      await refresh();
      request = _requestById(requestId);
      if (request == null) return;
    }

    final generation = _lifecycleGeneration;
    _resolvingRequestIds.add(requestId);
    _publishResolving();
    List<int>? familyKeyBuffer;
    try {
      final authority = await _readAuthority(generation);
      final currentRequest = _exactCurrentRequest(request);
      if (currentRequest == null) {
        await refresh();
        return;
      }

      FamilyJoinDecision decision;
      if (approve) {
        final resolved = await ref
            .read(identityKeyServiceProvider)
            .resolve(authority.identity.familyKeyRef);
        await _revalidateAuthority(authority, generation);
        familyKeyBuffer = List<int>.from(resolved, growable: false);
        _activeFamilyKeyBuffers.add(familyKeyBuffer);
        await _revalidateAuthority(authority, generation);

        final envelope = await ref
            .read(familyJoinEnvelopeCodecProvider)
            .seal(
              context: JoinEnvelopeContext.validated(
                requestId: currentRequest.requestId,
                familyId: currentRequest.familyId,
                requesterAccountId: currentRequest.requesterAccountId,
                codeVersion: currentRequest.codeVersion,
              ),
              requesterPublicKey: currentRequest.joiningPublicKey,
              familyKey: familyKeyBuffer,
            );
        await _revalidateAuthority(authority, generation);
        if (_exactCurrentRequest(currentRequest) == null) {
          await refresh();
          return;
        }
        decision = await _submitWithReconciliation(
          authority: authority,
          request: currentRequest,
          submit: () => authority.gateway.approveJoinRequest(
            currentRequest.requestId,
            envelope,
          ),
          generation: generation,
        );
      } else {
        decision = await _submitWithReconciliation(
          authority: authority,
          request: currentRequest,
          submit: () =>
              authority.gateway.declineJoinRequest(currentRequest.requestId),
          generation: generation,
        );
      }

      await _revalidateAuthority(authority, generation);
      _validateDecision(decision, currentRequest);
      if (!_isAlive(generation)) return;
      _removeResolvedRequest(currentRequest.requestId);
      if (decision.state == FamilyJoinRequestState.approved ||
          decision.state == FamilyJoinRequestState.installed) {
        ref.invalidate(familyRosterProvider(_familyId));
      }
      await refresh();
    } on _AuthoritativeResolution {
      if (_isAlive(generation)) {
        _removeResolvedRequest(requestId);
      }
    } on _AbortedOperation {
      return;
    } on FamilyJoinFailure catch (failure) {
      _publishDecisionFailure(failure, generation);
    } on Object catch (error) {
      _publishDecisionFailure(_mapFailure(error), generation);
    } finally {
      if (familyKeyBuffer != null) {
        _zero(familyKeyBuffer);
        _activeFamilyKeyBuffers.remove(familyKeyBuffer);
      }
      _resolvingRequestIds.remove(requestId);
      if (_isAlive(generation)) {
        state = FamilyJoinRequestsState(
          requests: state.requests,
          isRefreshing: state.isRefreshing,
          resolvingRequestId: _visibleResolvingRequestId,
          failure: state.failure,
        );
      }
    }
  }

  Future<FamilyJoinDecision> _submitWithReconciliation({
    required _FamilyJoinAuthority authority,
    required PendingFamilyJoinRequest request,
    required Future<FamilyJoinDecision> Function() submit,
    required int generation,
  }) async {
    try {
      final decision = await submit();
      await _revalidateAuthority(authority, generation);
      return decision;
    } on _AbortedOperation {
      rethrow;
    } on Object catch (error) {
      final failure = _mapFailure(error);
      await refresh();
      if (!_isAlive(generation)) throw const _AbortedOperation();
      if (_requestById(request.requestId) == null && state.failure == null) {
        throw const _AuthoritativeResolution();
      }
      throw failure;
    }
  }

  Future<_FamilyJoinAuthority> _readAuthority(int generation) async {
    _ensureAlive(generation);
    final gateway = ref.read(familyCodeJoinGatewayProvider);
    if (!gateway.isConfigured) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.notConfigured);
    }
    final accountId = gateway.authenticatedAccountId;
    if (accountId == null) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut);
    }
    final identity = await ref.read(localIdentityProvider.future);
    _ensureAlive(generation);
    if (gateway.authenticatedAccountId != accountId) {
      _zeroActiveFamilyKeys();
      throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut);
    }
    _validateIdentity(identity, accountId: accountId);
    return _FamilyJoinAuthority(
      gateway: gateway,
      accountId: accountId,
      identity: identity!,
    );
  }

  Future<void> _revalidateAuthority(
    _FamilyJoinAuthority authority,
    int generation,
  ) async {
    _ensureAlive(generation);
    if (authority.gateway.authenticatedAccountId != authority.accountId ||
        ref.read(familyCodeJoinGatewayProvider).authenticatedAccountId !=
            authority.accountId) {
      _zeroActiveFamilyKeys();
      throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut);
    }
    final identity = await ref.read(localIdentityProvider.future);
    _ensureAlive(generation);
    if (authority.gateway.authenticatedAccountId != authority.accountId) {
      _zeroActiveFamilyKeys();
      throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut);
    }
    _validateIdentity(
      identity,
      accountId: authority.accountId,
      baseline: authority.identity,
    );
  }

  void _validateIdentity(
    LocalIdentity? identity, {
    required String accountId,
    LocalIdentity? baseline,
  }) {
    final invalid =
        identity == null ||
        identity.familyId != _familyId ||
        identity.accountId != accountId ||
        identity.memberId.isEmpty ||
        identity.familyKeyRef.isEmpty ||
        (baseline != null &&
            (identity.memberId != baseline.memberId ||
                identity.familyKeyRef != baseline.familyKeyRef ||
                identity.memberKeyRef != baseline.memberKeyRef));
    if (invalid) {
      _zeroActiveFamilyKeys();
      throw const FamilyJoinFailure(FamilyJoinFailureCode.forbidden);
    }
  }

  void _validatePendingProjection(List<PendingFamilyJoinRequest> requests) {
    final ids = <String>{};
    for (final request in requests) {
      if (request.familyId != _familyId ||
          request.state != FamilyJoinRequestState.pending ||
          !ids.add(request.requestId)) {
        throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
      }
    }
  }

  void _validateDecision(
    FamilyJoinDecision decision,
    PendingFamilyJoinRequest request,
  ) {
    if (decision.requestId != request.requestId ||
        decision.familyId != _familyId ||
        decision.state == FamilyJoinRequestState.pending) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
    }
  }

  PendingFamilyJoinRequest? _requestById(String requestId) {
    for (final request in state.requests) {
      if (request.requestId == requestId) return request;
    }
    return null;
  }

  PendingFamilyJoinRequest? _exactCurrentRequest(
    PendingFamilyJoinRequest expected,
  ) {
    final current = _requestById(expected.requestId);
    if (current == null) return null;
    if (current.familyId != expected.familyId ||
        current.requesterAccountId != expected.requesterAccountId ||
        current.memberId != expected.memberId ||
        current.displayName != expected.displayName ||
        current.demographicRole != expected.demographicRole ||
        current.colorToken != expected.colorToken ||
        current.avatar != expected.avatar ||
        current.joiningPublicKey != expected.joiningPublicKey ||
        current.codeVersion != expected.codeVersion ||
        current.state != FamilyJoinRequestState.pending) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
    }
    return current;
  }

  void _removeResolvedRequest(String requestId) {
    state = FamilyJoinRequestsState(
      requests: List<PendingFamilyJoinRequest>.unmodifiable(
        state.requests.where((request) => request.requestId != requestId),
      ),
      isRefreshing: state.isRefreshing,
      resolvingRequestId: _visibleResolvingRequestId,
    );
  }

  void _publishResolving() {
    state = FamilyJoinRequestsState(
      requests: state.requests,
      isRefreshing: state.isRefreshing,
      resolvingRequestId: _visibleResolvingRequestId,
    );
  }

  void _publishRefreshFailure(FamilyJoinFailure failure, int generation) {
    if (!_isAlive(generation)) return;
    final hidesPriorAccountData =
        failure.code == FamilyJoinFailureCode.signedOut ||
        failure.code == FamilyJoinFailureCode.forbidden;
    state = FamilyJoinRequestsState(
      requests: hidesPriorAccountData ? const [] : state.requests,
      resolvingRequestId: _visibleResolvingRequestId,
      failure: failure,
    );
  }

  void _publishDecisionFailure(FamilyJoinFailure failure, int generation) {
    if (!_isAlive(generation)) return;
    final hidesPriorAccountData =
        failure.code == FamilyJoinFailureCode.signedOut ||
        failure.code == FamilyJoinFailureCode.forbidden;
    state = FamilyJoinRequestsState(
      requests: hidesPriorAccountData ? const [] : state.requests,
      isRefreshing: state.isRefreshing,
      resolvingRequestId: _visibleResolvingRequestId,
      failure: failure,
    );
  }

  String? get _visibleResolvingRequestId =>
      _resolvingRequestIds.isEmpty ? null : _resolvingRequestIds.first;

  bool _isAlive(int generation) =>
      !_disposed && generation == _lifecycleGeneration && ref.mounted;

  bool _isCurrentRefresh(int generation, int revision) =>
      _isAlive(generation) && revision == _refreshRevision;

  void _ensureAlive(int generation) {
    if (!_isAlive(generation)) throw const _AbortedOperation();
  }

  void _zeroActiveFamilyKeys() {
    for (final buffer in _activeFamilyKeyBuffers) {
      _zero(buffer);
    }
  }
}

final class _FamilyJoinAuthority {
  const _FamilyJoinAuthority({
    required this.gateway,
    required this.accountId,
    required this.identity,
  });

  final FamilyCodeJoinGateway gateway;
  final String accountId;
  final LocalIdentity identity;
}

final class _AbortedOperation implements Exception {
  const _AbortedOperation();
}

final class _AuthoritativeResolution implements Exception {
  const _AuthoritativeResolution();
}

FamilyJoinFailure _mapFailure(Object error) => switch (error) {
  FamilyJoinFailure failure => failure,
  StateError() => const FamilyJoinFailure(
    FamilyJoinFailureCode.localPersistenceFailed,
  ),
  FormatException() || ArgumentError() => const FamilyJoinFailure(
    FamilyJoinFailureCode.envelopeRejected,
  ),
  _ => const FamilyJoinFailure(FamilyJoinFailureCode.unknown),
};

void _zero(List<int> bytes) {
  for (var index = 0; index < bytes.length; index += 1) {
    bytes[index] = 0;
  }
}
