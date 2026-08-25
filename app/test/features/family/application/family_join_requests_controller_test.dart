import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_join_crypto_providers.dart';
import 'package:keepers/features/family/application/family_join_requests_controller.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/family_join_envelope_codec.dart';
import 'package:keepers/features/family/data/joining_key_store.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/database_key_store.dart';

void main() {
  test(
    'any active member seals the exact approval and zeroes its key copy',
    () async {
      final gateway = _JoinRequestsGateway([_request]);
      final codec = _RecordingEnvelopeCodec();
      final fixture = _Fixture(gateway: gateway, codec: codec);
      addTearDown(fixture.dispose);
      await fixture.settleInitialRefresh();

      await fixture.controller.approve(_requestId);

      expect(codec.lastContext, _requestContext);
      expect(codec.lastRequesterPublicKey, _joiningPublicKey);
      expect(gateway.approvals, hasLength(1));
      expect(gateway.approvals.single.$1, _requestId);
      expect(fixture.state.requests, isEmpty);
      expect(fixture.state.failure, isNull);
      expect(fixture.state.activationCandidateMemberIds, {_request.memberId});
      expect(
        () => fixture.state.activationCandidateMemberIds.add('other-member'),
        throwsUnsupportedError,
      );
      expect(codec.lastFamilyKey!.every((byte) => byte == 0), isTrue);
    },
  );

  test(
    'concurrent decline resolved elsewhere is authoritative success',
    () async {
      final gateway = _JoinRequestsGateway([_request])
        ..nextDeclineDecision = _decision(FamilyJoinRequestState.approved);
      final fixture = _Fixture(gateway: gateway);
      addTearDown(fixture.dispose);
      await fixture.settleInitialRefresh();

      await fixture.controller.decline(_requestId);

      expect(fixture.state.failure, isNull);
      expect(fixture.state.requests, isEmpty);
      expect(fixture.state.activationCandidateMemberIds, {_request.memberId});
    },
  );

  test(
    'authoritative decline never publishes an activation candidate',
    () async {
      final gateway = _JoinRequestsGateway([_request]);
      final fixture = _Fixture(gateway: gateway);
      addTearDown(fixture.dispose);
      await fixture.settleInitialRefresh();

      await fixture.controller.decline(_requestId);

      expect(fixture.state.requests, isEmpty);
      expect(fixture.state.activationCandidateMemberIds, isEmpty);
    },
  );

  test(
    'authoritative installed decision publishes an activation candidate',
    () async {
      final gateway = _JoinRequestsGateway([_request])
        ..nextApproveDecision = _decision(FamilyJoinRequestState.installed);
      final fixture = _Fixture(gateway: gateway);
      addTearDown(fixture.dispose);
      await fixture.settleInitialRefresh();

      await fixture.controller.approve(_requestId);

      expect(fixture.state.activationCandidateMemberIds, {_request.memberId});
    },
  );

  test('serializes approve and decline for the same request', () async {
    final sealGate = Completer<void>();
    final codec = _RecordingEnvelopeCodec(sealGate: sealGate);
    final gateway = _JoinRequestsGateway([_request]);
    final fixture = _Fixture(gateway: gateway, codec: codec);
    addTearDown(fixture.dispose);
    await fixture.settleInitialRefresh();

    final approve = fixture.controller.approve(_requestId);
    await _waitUntil(() => codec.lastFamilyKey != null);
    final decline = fixture.controller.decline(_requestId);
    sealGate.complete();
    await Future.wait([approve, decline]);

    expect(gateway.approvals, hasLength(1));
    expect(gateway.declines, isEmpty);
  });

  test(
    'Realtime is only an invalidation before an authoritative RPC read',
    () async {
      final gateway = _JoinRequestsGateway([_request]);
      final fixture = _Fixture(gateway: gateway);
      addTearDown(fixture.dispose);
      await fixture.settleInitialRefresh();
      final initialReads = gateway.listCalls;
      gateway.pending = [_secondRequest];

      gateway.invalidate();
      await _waitUntil(() => gateway.listCalls > initialReads);
      await _waitUntil(
        () => fixture.state.requests.single.requestId == _secondRequestId,
      );

      expect(fixture.state.requests.single.requestId, _secondRequestId);
    },
  );

  test('queues invalidation while a stale pending read is in flight', () async {
    final oldReadGate = Completer<void>();
    final oldReadStarted = Completer<void>();
    final gateway = _JoinRequestsGateway([_request]);
    final fixture = _Fixture(gateway: gateway);
    addTearDown(fixture.dispose);
    await fixture.settleInitialRefresh();
    fixture.requestSnapshots.clear();
    gateway
      ..nextListGate = oldReadGate
      ..nextListStarted = oldReadStarted;

    gateway.invalidate();
    await oldReadStarted.future;
    final approval = fixture.controller.approve(_requestId);
    await _waitUntil(() => gateway.approvals.isNotEmpty);
    await _waitUntil(() => fixture.state.requests.isEmpty);
    gateway.invalidate();
    oldReadGate.complete();
    await approval;
    await _waitUntil(() => gateway.listCalls >= 3);

    expect(fixture.state.requests, isEmpty);
    expect(fixture.state.failure, isNull);
    final resolutionIndex = fixture.requestSnapshots.indexWhere(
      (requests) => requests.isEmpty,
    );
    expect(resolutionIndex, isNonNegative);
    expect(
      fixture.requestSnapshots
          .skip(resolutionIndex)
          .every((requests) => requests.isEmpty),
      isTrue,
    );
  });

  test(
    'account change during sealing zeroes the key and blocks submission',
    () async {
      final sealGate = Completer<void>();
      final codec = _RecordingEnvelopeCodec(sealGate: sealGate);
      final gateway = _JoinRequestsGateway([_request]);
      final fixture = _Fixture(gateway: gateway, codec: codec);
      addTearDown(fixture.dispose);
      await fixture.settleInitialRefresh();

      final approval = fixture.controller.approve(_requestId);
      await _waitUntil(() => codec.lastFamilyKey != null);
      gateway.accountId = _otherAccountId;
      sealGate.complete();
      await approval;

      expect(gateway.approvals, isEmpty);
      expect(codec.lastFamilyKey!.every((byte) => byte == 0), isTrue);
      expect(
        fixture.state.failure,
        const FamilyJoinFailure(FamilyJoinFailureCode.signedOut),
      );
      expect(fixture.state.requests, isEmpty);
    },
  );

  test(
    'disposing during sealing zeroes the key before sealing returns',
    () async {
      final sealGate = Completer<void>();
      final codec = _RecordingEnvelopeCodec(sealGate: sealGate);
      final gateway = _JoinRequestsGateway([_request]);
      final fixture = _Fixture(gateway: gateway, codec: codec);
      await fixture.settleInitialRefresh();

      final approval = fixture.controller.approve(_requestId);
      await _waitUntil(() => codec.lastFamilyKey != null);
      fixture.dispose();

      expect(codec.lastFamilyKey!.every((byte) => byte == 0), isTrue);
      sealGate.complete();
      await approval;
      expect(gateway.approvals, isEmpty);
    },
  );

  test(
    'rejects a local identity bound to another family before listing',
    () async {
      final gateway = _JoinRequestsGateway([_request]);
      final fixture = _Fixture(
        gateway: gateway,
        identity: _identity(familyId: _otherFamilyId),
      );
      addTearDown(fixture.dispose);
      await fixture.settleInitialRefresh();

      expect(gateway.listCalls, 0);
      expect(
        fixture.state.failure,
        const FamilyJoinFailure(FamilyJoinFailureCode.forbidden),
      );
      expect(fixture.state.requests, isEmpty);
    },
  );
}

final class _Fixture {
  _Fixture({
    required this.gateway,
    _RecordingEnvelopeCodec? codec,
    LocalIdentity? identity,
  }) : codec = codec ?? _RecordingEnvelopeCodec(),
       identity = identity ?? _identity() {
    final store = _MemorySecureValueStore({
      _familyKeyRef: base64UrlEncode(_familyKey),
    });
    container = ProviderContainer(
      overrides: [
        familyCodeJoinGatewayProvider.overrideWithValue(gateway),
        familyJoinEnvelopeCodecProvider.overrideWithValue(this.codec),
        identityKeyServiceProvider.overrideWithValue(IdentityKeyService(store)),
        localIdentityProvider.overrideWith((ref) async => this.identity),
      ],
    );
    subscription = container.listen(
      familyJoinRequestsControllerProvider(_familyId),
      (_, next) => requestSnapshots.add(
        next.requests.map((request) => request.requestId).toList(),
      ),
    );
  }

  final _JoinRequestsGateway gateway;
  final _RecordingEnvelopeCodec codec;
  final LocalIdentity identity;
  late final ProviderContainer container;
  late final ProviderSubscription<FamilyJoinRequestsState> subscription;
  final requestSnapshots = <List<String>>[];
  var _disposed = false;

  FamilyJoinRequestsController get controller =>
      container.read(familyJoinRequestsControllerProvider(_familyId).notifier);

  FamilyJoinRequestsState get state =>
      container.read(familyJoinRequestsControllerProvider(_familyId));

  Future<void> settleInitialRefresh() async {
    await _waitUntil(() => gateway.listCalls > 0 || state.failure != null);
    await _waitUntil(() => !state.isRefreshing);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    subscription.close();
    container.dispose();
  }
}

final class _RecordingEnvelopeCodec implements FamilyJoinEnvelopeCodec {
  _RecordingEnvelopeCodec({this.sealGate});

  final Completer<void>? sealGate;
  JoinEnvelopeContext? lastContext;
  String? lastRequesterPublicKey;
  List<int>? lastFamilyKey;

  @override
  Future<FamilyJoinApprovalEnvelope> seal({
    required JoinEnvelopeContext context,
    required String requesterPublicKey,
    required List<int> familyKey,
  }) async {
    lastContext = context;
    lastRequesterPublicKey = requesterPublicKey;
    lastFamilyKey = familyKey;
    await sealGate?.future;
    return FamilyJoinApprovalEnvelope(
      version: FamilyJoinApprovalEnvelope.currentVersion,
      context: context,
      ephemeralPublicKey: _joiningPublicKey,
      nonce: 'AAAAAAAAAAAAAAAA',
      ciphertext: _joiningPublicKey,
      mac: 'AAAAAAAAAAAAAAAAAAAAAA',
    );
  }

  @override
  Future<List<int>> open({
    required FamilyJoinApprovalEnvelope envelope,
    required String expectedRequesterPublicKey,
    required StoredJoiningKey joiningKey,
  }) => throw UnimplementedError();
}

final class _JoinRequestsGateway implements FamilyCodeJoinGateway {
  _JoinRequestsGateway(List<PendingFamilyJoinRequest> pending)
    : pending = List.of(pending);

  final invalidations = StreamController<void>.broadcast();
  List<PendingFamilyJoinRequest> pending;
  String? accountId = _accountId;
  FamilyJoinDecision? nextApproveDecision;
  FamilyJoinDecision? nextDeclineDecision;
  Completer<void>? nextListGate;
  Completer<void>? nextListStarted;
  final approvals = <(String, FamilyJoinApprovalEnvelope)>[];
  final declines = <String>[];
  var listCalls = 0;

  void invalidate() => invalidations.add(null);

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => accountId;

  @override
  Future<List<PendingFamilyJoinRequest>> listPendingJoinRequests(
    String familyId,
  ) async {
    listCalls += 1;
    final result = List<PendingFamilyJoinRequest>.of(pending);
    final gate = nextListGate;
    if (gate != null) {
      nextListGate = null;
      nextListStarted?.complete();
      nextListStarted = null;
      await gate.future;
    }
    return result;
  }

  @override
  Future<FamilyJoinDecision> approveJoinRequest(
    String requestId,
    FamilyJoinApprovalEnvelope envelope,
  ) async {
    approvals.add((requestId, envelope));
    pending.removeWhere((request) => request.requestId == requestId);
    return nextApproveDecision ?? _decision(FamilyJoinRequestState.approved);
  }

  @override
  Future<FamilyJoinDecision> declineJoinRequest(String requestId) async {
    declines.add(requestId);
    pending.removeWhere((request) => request.requestId == requestId);
    return nextDeclineDecision ?? _decision(FamilyJoinRequestState.declined);
  }

  @override
  Stream<void> watchPendingJoinRequests(String familyId) =>
      invalidations.stream;

  @override
  Future<EncryptedFamilyCodeRecord> bootstrapOwnerWithFamilyCode(
    LocalOwnerFamily owner,
    FamilyCodeDraft code,
  ) => throw UnimplementedError();

  @override
  Future<FamilyJoinDecision> cancelJoinRequest(String requestId) =>
      throw UnimplementedError();

  @override
  Future<FamilyJoinDecision> completeJoinRequest(String requestId) =>
      throw UnimplementedError();

  @override
  Future<OwnFamilyJoinRequest> createFamilyJoinRequest(
    FamilyJoinRequestDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<EncryptedFamilyCodeRecord> getFamilyCode(String familyId) =>
      throw UnimplementedError();

  @override
  Future<OwnFamilyJoinRequest?> getOwnJoinRequest() =>
      throw UnimplementedError();

  @override
  Future<FamilyJoinPreview> previewFamilyByCode(FamilyCode code) =>
      throw UnimplementedError();

  @override
  Future<EncryptedFamilyCodeRecord> regenerateFamilyCode({
    required String familyId,
    required int expectedVersion,
    required FamilyCodeDraft replacement,
  }) => throw UnimplementedError();

  @override
  Stream<void> watchOwnJoinRequest() => const Stream.empty();
}

final class _MemorySecureValueStore implements SecureValueStore {
  _MemorySecureValueStore(this.values);

  final Map<String, String> values;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

LocalIdentity _identity({String familyId = _familyId}) => LocalIdentity(
  familyId: familyId,
  familyName: 'Rahman',
  familyKeyRef: _familyKeyRef,
  memberId: _localMemberId,
  memberName: 'Omar',
  memberKeyRef: 'member-key',
  colorToken: 'sage',
  avatar: const AvatarConfig.defaults(seed: _localMemberId),
  accountId: _accountId,
);

PendingFamilyJoinRequest _pendingRequest({
  required String requestId,
  required String memberId,
  required String displayName,
}) => PendingFamilyJoinRequest.validated(
  requestId: requestId,
  familyId: _familyId,
  requesterAccountId: _requesterAccountId,
  memberId: memberId,
  displayName: displayName,
  demographicRole: FamilyDemographicRole.adult,
  colorToken: 'clay',
  avatar: AvatarConfig.defaults(seed: memberId),
  joiningPublicKey: _joiningPublicKey,
  codeVersion: 3,
  state: FamilyJoinRequestState.pending,
  createdAt: DateTime.utc(2026, 9, 7),
  expiresAt: DateTime.utc(2026, 9, 14),
);

FamilyJoinDecision _decision(FamilyJoinRequestState state) =>
    FamilyJoinDecision.validated(
      requestId: _requestId,
      familyId: _familyId,
      state: state,
      updatedAt: DateTime.utc(2026, 9, 7, 12),
    );

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition was not reached');
}

const _familyId = '11111111-1111-4111-8111-111111111111';
const _otherFamilyId = '99999999-9999-4999-8999-999999999999';
const _localMemberId = '22222222-2222-4222-8222-222222222222';
const _accountId = '33333333-3333-4333-8333-333333333333';
const _otherAccountId = '44444444-4444-4444-8444-444444444444';
const _requesterAccountId = '55555555-5555-4555-8555-555555555555';
const _requestId = '66666666-6666-4666-8666-666666666666';
const _secondRequestId = '77777777-7777-4777-8777-777777777777';
const _joiningPublicKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _familyKeyRef = 'keepers.family.$_familyId.entry-key.v1';
final _familyKey = List<int>.generate(32, (index) => index + 1);
final _request = _pendingRequest(
  requestId: _requestId,
  memberId: '88888888-8888-4888-8888-888888888888',
  displayName: 'Mariam',
);
final _secondRequest = _pendingRequest(
  requestId: _secondRequestId,
  memberId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  displayName: 'Noura',
);
final _requestContext = JoinEnvelopeContext.validated(
  requestId: _requestId,
  familyId: _familyId,
  requesterAccountId: _requesterAccountId,
  codeVersion: 3,
);
