import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/family_join_crypto_providers.dart';
import 'package:keepers/features/family/application/pending_join_completion_controller.dart';
import 'package:keepers/features/family/data/approved_family_join_installer.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/family_join_envelope_codec.dart';
import 'package:keepers/features/family/data/joining_key_store.dart';
import 'package:keepers/features/family/data/pending_join_completion_repository.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/database_providers.dart';

void main() {
  test('approval installs locally before Task 3 cloud activation', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    await fixture.controller.loadCode(_code);
    await fixture.controller.requestJoin(fixture.profile());
    fixture.gateway.ownRequest = fixture.approvedRequest;
    await fixture.controller.refreshStatus();

    expect(fixture.events, ['install', 'complete', 'deleteJoiningKey']);
    expect(fixture.installer.familyKey, everyElement(0));
    expect(fixture.state.phase, FamilyJoinPhase.complete);
  });

  test('missed realtime approval is recovered on resume', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.controller.loadCode(_code);
    await fixture.controller.requestJoin(fixture.profile());

    fixture.gateway.ownRequest = fixture.approvedRequest;
    await fixture.controller.onResumed();

    expect(fixture.installer.installCalls, 1);
  });

  test(
    'realtime is invalidation and refreshes the authoritative row',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.controller.loadCode(_code);
      await fixture.controller.requestJoin(fixture.profile());
      final readsBefore = fixture.gateway.ownRequestReads;

      fixture.gateway.ownRequest = fixture.declinedRequest;
      fixture.gateway.invalidateOwnRequest();
      await fixture.waitFor((state) => state.phase == FamilyJoinPhase.declined);

      expect(fixture.gateway.ownRequestReads, greaterThan(readsBefore));
      expect(fixture.state.phase, FamilyJoinPhase.declined);
    },
  );

  test(
    'network failure preserves pending request and exposes refresh retry',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.controller.loadCode(_code);
      await fixture.controller.requestJoin(fixture.profile());
      fixture.gateway.getOwnFailures.add(
        const FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable),
      );

      await fixture.controller.refreshStatus();

      expect(fixture.state.phase, FamilyJoinPhase.pending);
      expect(
        fixture.state.failure?.code,
        FamilyJoinFailureCode.networkUnavailable,
      );
      expect(fixture.state.retryPoint, FamilyJoinRetryPoint.refreshStatus);
    },
  );

  test('cancel waits for an authoritative cancelled row', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.controller.loadCode(_code);
    await fixture.controller.requestJoin(fixture.profile());
    fixture.gateway.cancelResult = fixture.cancelledRequest;

    await fixture.controller.cancel();

    expect(fixture.gateway.cancelledIds, [_requestId]);
    expect(fixture.state.phase, FamilyJoinPhase.cancelled);
    expect(fixture.gateway.ownRequestReads, greaterThan(0));
  });

  test(
    'signed-in event resumes the same code after external email auth',
    () async {
      final fixture = _Fixture(authenticated: false);
      addTearDown(fixture.dispose);
      await fixture.controller.loadCode(_code);
      await fixture.controller.requestEmailOtp('Mariam@example.com');

      fixture.gateway
        ..accountId = _accountId
        ..emitSignedIn();
      await fixture.waitFor((state) => state.phase == FamilyJoinPhase.preview);

      expect(fixture.gateway.previewedCodes, [_code]);
      expect(fixture.state.phase, FamilyJoinPhase.preview);
    },
  );

  test('proposed UUID and joining key survive controller restart', () async {
    final values = _MemorySecureValueStore();
    final first = _Fixture(values: values, generatedId: _memberId);
    await first.controller.loadCode(_code);
    final firstMemberId = first.state.proposedMemberId;
    final firstPublicKey = first.state.proposedJoiningPublicKey;
    first.dispose();

    final second = _Fixture(values: values, generatedId: _otherMemberId);
    addTearDown(second.dispose);
    await second.controller.loadCode(_code);

    expect(second.state.proposedMemberId, firstMemberId);
    expect(second.state.proposedJoiningPublicKey, firstPublicKey);
  });

  test(
    'request retry reuses the exact proposed UUID and joining key',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.controller.loadCode(_code);
      fixture.gateway.createFailures.add(
        const FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable),
      );

      await fixture.controller.requestJoin(fixture.profile());
      await fixture.controller.retry();

      expect(fixture.gateway.createdDrafts, hasLength(2));
      expect(
        fixture.gateway.createdDrafts
            .map((draft) => draft.profile.memberId)
            .toSet(),
        {_memberId},
      );
      expect(
        fixture.gateway.createdDrafts
            .map((draft) => draft.profile.joiningPublicKey)
            .toSet(),
        {fixture.state.request!.joiningPublicKey},
      );
    },
  );

  test(
    'approval envelope context mismatch fails before decrypt or install',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.controller.loadCode(_code);
      await fixture.controller.requestJoin(fixture.profile());
      fixture.gateway.ownRequest = fixture.approvedRequestWith(
        envelope: _envelope(requestId: _otherRequestId),
      );

      await fixture.controller.refreshStatus();

      expect(fixture.codec.openCalls, 0);
      expect(fixture.installer.installCalls, 0);
      expect(
        fixture.state.failure?.code,
        FamilyJoinFailureCode.envelopeRejected,
      );
    },
  );

  test('state diagnostics redact family code and joining material', () {
    const state = FamilyJoinState(
      proposedMemberId: _memberId,
      proposedJoiningPublicKey: _publicKey,
    );
    expect(state.toString(), 'FamilyJoinState(enteringCode)');
    expect(state.toString(), isNot(contains(_memberId)));
    expect(state.toString(), isNot(contains(_publicKey)));
  });
}

final class _Fixture {
  _Fixture({
    bool authenticated = true,
    _MemorySecureValueStore? values,
    String generatedId = _memberId,
  }) : values = values ?? _MemorySecureValueStore(),
       gateway = _Gateway(accountId: authenticated ? _accountId : null),
       events = <String>[],
       installer = _Installer(<String>[]),
       codec = _Codec() {
    installer.events = events;
    container = ProviderContainer(
      overrides: [
        cloudFamilyGatewayProvider.overrideWithValue(gateway),
        familyCodeJoinGatewayProvider.overrideWithValue(gateway),
        secureValueStoreProvider.overrideWithValue(this.values),
        joiningKeyStoreProvider.overrideWithValue(
          SecureJoiningKeyStore(
            this.values,
            seedFactory: (length) => List<int>.generate(length, (i) => i + 1),
          ),
        ),
        approvedFamilyJoinInstallerProvider.overrideWithValue(installer),
        familyJoinEnvelopeCodecProvider.overrideWithValue(codec),
        familyJoinCompletionRecoveryProvider.overrideWithValue(() async {
          events.add('complete');
          events.add('deleteJoiningKey');
          return const PendingJoinCompletionState(
            phase: PendingJoinCompletionPhase.complete,
          );
        }),
        idFactoryProvider.overrideWithValue(() => generatedId),
        localIdentityProvider.overrideWith((ref) async => null),
      ],
    );
    subscription = container.listen(
      familyJoinControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
  }

  final _MemorySecureValueStore values;
  final _Gateway gateway;
  final List<String> events;
  final _Installer installer;
  final _Codec codec;
  late final ProviderContainer container;
  late final ProviderSubscription<FamilyJoinState> subscription;

  FamilyJoinController get controller =>
      container.read(familyJoinControllerProvider.notifier);
  FamilyJoinState get state => container.read(familyJoinControllerProvider);

  FamilyJoinProfileDraft profile() => FamilyJoinProfileDraft(
    memberId: state.proposedMemberId!,
    displayName: 'Mariam',
    demographicRole: FamilyDemographicRole.adult,
    colorToken: 'ochre',
    avatar: state.proposedAvatar!,
    joiningPublicKey: state.proposedJoiningPublicKey!,
  );

  OwnFamilyJoinRequest get approvedRequest =>
      approvedRequestWith(envelope: _envelope());

  OwnFamilyJoinRequest approvedRequestWith({
    required FamilyJoinApprovalEnvelope envelope,
  }) => _request(
    state: FamilyJoinRequestState.approved,
    memberId: state.proposedMemberId!,
    publicKey: state.proposedJoiningPublicKey!,
    envelope: envelope,
  );

  OwnFamilyJoinRequest get declinedRequest => _request(
    state: FamilyJoinRequestState.declined,
    memberId: state.proposedMemberId!,
    publicKey: state.proposedJoiningPublicKey!,
  );

  OwnFamilyJoinRequest get cancelledRequest => _request(
    state: FamilyJoinRequestState.cancelled,
    memberId: state.proposedMemberId!,
    publicKey: state.proposedJoiningPublicKey!,
  );

  Future<void> waitFor(bool Function(FamilyJoinState state) predicate) async {
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (predicate(state)) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('Timed out waiting for join state; state was $state');
  }

  void dispose() {
    subscription.close();
    container.dispose();
    gateway.dispose();
  }
}

final class _Gateway
    implements
        CloudFamilyGateway,
        FamilyCodeJoinGateway,
        CloudFamilyAuthEvents {
  _Gateway({required this.accountId});

  String? accountId;
  OwnFamilyJoinRequest? ownRequest;
  OwnFamilyJoinRequest? cancelResult;
  final List<FamilyJoinFailure> getOwnFailures = [];
  final List<FamilyJoinFailure> createFailures = [];
  final List<FamilyCode> previewedCodes = [];
  final List<FamilyJoinRequestDraft> createdDrafts = [];
  final List<String> cancelledIds = [];
  final _auth = StreamController<void>.broadcast(sync: true);
  final _ownInvalidations = StreamController<void>.broadcast(sync: true);
  var ownRequestReads = 0;

  @override
  bool get isConfigured => true;
  @override
  String? get authenticatedAccountId => accountId;
  @override
  String? get authenticatedEmail => 'mariam@example.com';
  @override
  Stream<void> get signedInEvents => _auth.stream;

  void emitSignedIn() => _auth.add(null);
  void invalidateOwnRequest() => _ownInvalidations.add(null);
  void dispose() {
    _auth.close();
    _ownInvalidations.close();
  }

  @override
  Future<FamilyJoinPreview> previewFamilyByCode(FamilyCode code) async {
    previewedCodes.add(code);
    return _preview;
  }

  @override
  Future<OwnFamilyJoinRequest> createFamilyJoinRequest(
    FamilyJoinRequestDraft draft,
  ) async {
    createdDrafts.add(draft);
    if (createFailures.isNotEmpty) throw createFailures.removeAt(0);
    return ownRequest = _request(
      state: FamilyJoinRequestState.pending,
      memberId: draft.profile.memberId,
      publicKey: draft.profile.joiningPublicKey,
    );
  }

  @override
  Future<OwnFamilyJoinRequest?> getOwnJoinRequest() async {
    ownRequestReads += 1;
    if (getOwnFailures.isNotEmpty) throw getOwnFailures.removeAt(0);
    return ownRequest;
  }

  @override
  Future<FamilyJoinDecision> cancelJoinRequest(String requestId) async {
    cancelledIds.add(requestId);
    ownRequest = cancelResult ?? ownRequest;
    return FamilyJoinDecision(
      requestId: requestId,
      familyId: _familyId,
      state: FamilyJoinRequestState.cancelled,
      updatedAt: DateTime.utc(2026, 9, 7),
    );
  }

  @override
  Stream<void> watchOwnJoinRequest() => _ownInvalidations.stream;
  @override
  Future<void> requestEmailOtp(String email) async {}
  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    accountId = _accountId;
  }

  @override
  Future<FamilyJoinDecision> approveJoinRequest(
    String requestId,
    FamilyJoinApprovalEnvelope envelope,
  ) => throw UnimplementedError();
  @override
  Future<void> bootstrapOwner(LocalOwnerFamily owner) =>
      throw UnimplementedError();
  @override
  Future<EncryptedFamilyCodeRecord> bootstrapOwnerWithFamilyCode(
    LocalOwnerFamily owner,
    FamilyCodeDraft code,
  ) => throw UnimplementedError();
  @override
  Future<ClaimedFamily> claimInvitation(JoinRequest request) =>
      throw UnimplementedError();
  @override
  Future<FamilyJoinDecision> completeJoinRequest(String requestId) =>
      throw UnimplementedError();
  @override
  Future<void> completeInvitation(String inviteId) =>
      throw UnimplementedError();
  @override
  Future<CreatedInvitation> createInvitation(CloudInvitationDraft draft) =>
      throw UnimplementedError();
  @override
  Future<FamilyJoinDecision> declineJoinRequest(String requestId) =>
      throw UnimplementedError();
  @override
  Future<EncryptedFamilyCodeRecord> getFamilyCode(String familyId) =>
      throw UnimplementedError();
  @override
  Future<List<FamilyMember>> listActiveMembers(String familyId) =>
      throw UnimplementedError();
  @override
  Future<List<PendingFamilyJoinRequest>> listPendingJoinRequests(
    String familyId,
  ) => throw UnimplementedError();
  @override
  Future<InvitePreview> previewInvitation(FamilyInviteLink link) =>
      throw UnimplementedError();
  @override
  Future<EncryptedFamilyCodeRecord> regenerateFamilyCode({
    required String familyId,
    required int expectedVersion,
    required FamilyCodeDraft replacement,
  }) => throw UnimplementedError();
  @override
  Future<void> revokeInvitation(String inviteId) => throw UnimplementedError();
  @override
  Stream<void> watchPendingJoinRequests(String familyId) =>
      const Stream.empty();
}

final class _Installer implements ApprovedFamilyJoinInstaller {
  _Installer(this.events);
  List<String> events;
  var installCalls = 0;
  List<int> familyKey = const [];

  @override
  Future<PendingJoinCompletion> install({
    required ApprovedFamilyJoin approval,
    required List<int> familyKey,
    required String accountId,
  }) async {
    installCalls += 1;
    events.add('install');
    this.familyKey = familyKey;
    return PendingJoinCompletion(
      requestId: approval.requestId,
      familyId: approval.familyId,
      memberId: approval.localMemberId,
      accountId: accountId,
      installedAt: DateTime.utc(2026, 9, 7),
    );
  }
}

final class _Codec implements FamilyJoinEnvelopeCodec {
  var openCalls = 0;
  @override
  Future<List<int>> open({
    required FamilyJoinApprovalEnvelope envelope,
    required String expectedRequesterPublicKey,
    required StoredJoiningKey joiningKey,
  }) async {
    openCalls += 1;
    return List<int>.generate(32, (index) => index);
  }

  @override
  Future<FamilyJoinApprovalEnvelope> seal({
    required JoinEnvelopeContext context,
    required String requesterPublicKey,
    required List<int> familyKey,
  }) => throw UnimplementedError();
}

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

OwnFamilyJoinRequest _request({
  required FamilyJoinRequestState state,
  required String memberId,
  required String publicKey,
  FamilyJoinApprovalEnvelope? envelope,
}) => OwnFamilyJoinRequest(
  requestId: _requestId,
  familyId: _familyId,
  familyName: 'Rahman family',
  requesterAccountId: _accountId,
  memberId: memberId,
  displayName: 'Mariam',
  demographicRole: FamilyDemographicRole.adult,
  colorToken: 'ochre',
  avatar: AvatarConfig.defaults(seed: memberId),
  joiningPublicKey: publicKey,
  codeVersion: 1,
  state: state,
  createdAt: DateTime.utc(2026, 9, 7),
  expiresAt: DateTime.utc(2026, 9, 14),
  approvalEnvelope: envelope,
  roster: state == FamilyJoinRequestState.approved
      ? [_member(memberId)]
      : const [],
);

FamilyJoinApprovalEnvelope _envelope({String requestId = _requestId}) =>
    FamilyJoinApprovalEnvelope(
      version: 1,
      context: JoinEnvelopeContext(
        requestId: requestId,
        familyId: _familyId,
        requesterAccountId: _accountId,
        codeVersion: 1,
      ),
      ephemeralPublicKey: _publicKey,
      nonce: 'AAAAAAAAAAAAAAAA',
      ciphertext: _publicKey,
      mac: 'AAAAAAAAAAAAAAAAAAAAAA',
    );

FamilyMember _member(String memberId) => FamilyMember(
  id: memberId,
  familyId: _familyId,
  name: 'Mariam',
  role: 'adult',
  colorToken: 'ochre',
  avatar: AvatarConfig.defaults(seed: memberId),
  joinedAt: DateTime.utc(2026, 9, 7),
);

final _code = FamilyCode.parse('K7M4-P2Q8');
final _preview = FamilyJoinPreview(
  familyId: _familyId,
  familyName: 'Rahman family',
  codeVersion: 1,
  members: [_member(_existingMemberId)],
);

const _requestId = '11111111-1111-4111-8111-111111111111';
const _otherRequestId = '11111111-1111-4111-8111-111111111112';
const _familyId = '22222222-2222-4222-8222-222222222222';
const _accountId = '33333333-3333-4333-8333-333333333333';
const _memberId = '44444444-4444-4444-8444-444444444444';
const _otherMemberId = '55555555-5555-4555-8555-555555555555';
const _existingMemberId = '66666666-6666-4666-8666-666666666666';
const _publicKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
