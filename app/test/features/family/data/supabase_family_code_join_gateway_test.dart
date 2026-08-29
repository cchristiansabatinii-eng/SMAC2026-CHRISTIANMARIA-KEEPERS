import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/data/supabase_cloud_family_gateway.dart';
import 'package:keepers/features/family/data/unavailable_cloud_family_gateway.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late _FakeClient client;
  late SupabaseCloudFamilyGateway gateway;

  setUp(() {
    client = _FakeClient()..accountId = _requesterAccountId;
    gateway = _makeGateway(client);
  });

  test(
    'request creation resolves family then sends only public material',
    () async {
      client.responses
        ..add(_previewResponse())
        ..add(_ownRequestResponse());

      final result = await gateway.createFamilyJoinRequest(_joinDraft);

      expect(result.requestId, _requestId);
      expect(
        client.calls.first,
        const _Call('preview_family_by_code', {'p_code': _codeValue}),
      );
      expect(
        client.calls.last,
        _Call('create_family_join_request', {
          'p_family_id': _familyId,
          'p_code': _codeValue,
          'p_member_id': _joiningMemberId,
          'p_display_name': 'Mariam',
          'p_demographic_role': 'child',
          'p_color_token': 'teal',
          'p_avatar_json': _joiningAvatar.toJson(),
          'p_joining_public_key': _joiningPublicKey,
        }),
      );
      expect(client.calls.last.params.keys, isNot(contains('familyKey')));
      expect(
        client.calls.last.params.keys,
        isNot(contains('joiningPrivateKey')),
      );
    },
  );

  test(
    'validates the complete join profile before previewing the code',
    () async {
      final invalidProfiles = <FamilyJoinProfileDraft>[
        const FamilyJoinProfileDraft(
          memberId: 'not-a-uuid',
          displayName: 'Mariam',
          demographicRole: FamilyDemographicRole.child,
          colorToken: 'teal',
          avatar: _joiningAvatar,
          joiningPublicKey: _joiningPublicKey,
        ),
        const FamilyJoinProfileDraft(
          memberId: _joiningMemberId,
          displayName: 'Mariam',
          demographicRole: FamilyDemographicRole.child,
          colorToken: 'teal',
          avatar: AvatarConfig.defaults(seed: ''),
          joiningPublicKey: _joiningPublicKey,
        ),
        const FamilyJoinProfileDraft(
          memberId: _joiningMemberId,
          displayName: 'Mariam',
          demographicRole: FamilyDemographicRole.child,
          colorToken: 'teal',
          avatar: _joiningAvatar,
          joiningPublicKey: 'not-a-public-key',
        ),
      ];

      for (final profile in invalidProfiles) {
        client.responses.add(_previewResponse());
        await expectLater(
          gateway.createFamilyJoinRequest(
            FamilyJoinRequestDraft(code: _code, profile: profile),
          ),
          throwsFamilyJoin(FamilyJoinFailureCode.invalidJoinKey),
        );
        expect(
          client.calls,
          isEmpty,
          reason: 'invalid profile must not hit RPC',
        );
        client.responses.clear();
      }
    },
  );

  test(
    'correlates every creation acknowledgement field to the request',
    () async {
      final mismatches = <Map<String, Object?>>[
        {'familyId': _differentFamilyId},
        {'requesterAccountId': _creatorAccountId},
        {'memberId': _ownerMemberId},
        {'displayName': 'Different'},
        {'demographicRole': 'adult'},
        {'colorToken': 'ochre'},
        {'avatarJson': _ownerAvatar.toJson()},
        {'joiningPublicKey': _ephemeralPublicKey},
        {'codeVersion': 2},
      ];

      for (final mismatch in mismatches) {
        client.responses
          ..add(_previewResponse())
          ..add({..._ownRequestResponse(), ...mismatch});
        await expectLater(
          gateway.createFamilyJoinRequest(_joinDraft),
          throwsFamilyJoin(FamilyJoinFailureCode.unknown),
          reason: mismatch.keys.single,
        );
      }
    },
  );

  test(
    'owner bootstrap passes the canonical code envelope unchanged',
    () async {
      client.responses.add(_codeRecordResponse());

      final record = await gateway.bootstrapOwnerWithFamilyCode(
        _owner,
        _codeDraft,
      );

      expect(record.material, _codeMaterial);
      expect(
        client.calls.single,
        _Call('bootstrap_owner_family_with_code', {
          'p_family_id': _familyId,
          'p_family_name': 'Sabati',
          'p_member_id': _ownerMemberId,
          'p_display_name': 'Chris',
          'p_demographic_role': 'adult',
          'p_color_token': 'ochre',
          'p_avatar_json': _ownerAvatar.toJson(),
          'p_code': _codeValue,
          'p_code_envelope': _codeMaterial.toJson(),
        }),
      );
      expect(
        (client.calls.single.params['p_code_envelope']! as Map)['codecVersion'],
        1,
      );
    },
  );

  test('code reads and regeneration use exact RPC contracts', () async {
    client.responses
      ..add(_codeRecordResponse())
      ..add(_codeRecordResponse(codeVersion: 2));

    await gateway.getFamilyCode(_familyId);
    await gateway.regenerateFamilyCode(
      familyId: _familyId,
      expectedVersion: 1,
      replacement: _replacementDraft,
    );

    expect(client.calls, [
      const _Call('get_family_join_code', {'p_family_id': _familyId}),
      _Call('regenerate_family_join_code', {
        'p_family_id': _familyId,
        'p_expected_version': 1,
        'p_code': _replacementCodeValue,
        'p_code_envelope': _replacementMaterial.toJson(),
      }),
    ]);
  });

  test('preview decodes exact result and exact not-found projection', () async {
    client.responses.add(_previewResponse());
    final preview = await gateway.previewFamilyByCode(_code);
    expect(preview.familyId, _familyId);
    expect(preview.members.single.familyId, _familyId);

    client.responses.add({'errorCode': 'FAMILY_NOT_FOUND'});
    await expectLater(
      gateway.previewFamilyByCode(_code),
      throwsFamilyJoin(FamilyJoinFailureCode.familyNotFound),
    );
  });

  test(
    'create recognizes only the exact neutral not-found projection',
    () async {
      client.responses
        ..add(_previewResponse())
        ..add({'errorCode': 'FAMILY_NOT_FOUND'});
      await expectLater(
        gateway.createFamilyJoinRequest(_joinDraft),
        throwsFamilyJoin(FamilyJoinFailureCode.familyNotFound),
      );

      client.responses
        ..add(_previewResponse())
        ..add({'errorCode': 'FAMILY_NOT_FOUND', 'extra': true});
      await expectLater(
        gateway.createFamilyJoinRequest(_joinDraft),
        throwsFamilyJoin(FamilyJoinFailureCode.unknown),
      );
    },
  );

  test('strictly decodes pending, own, and decision payloads', () async {
    client.responses
      ..add([_pendingRequestResponse()])
      ..add(_ownRequestResponse(state: 'approved', approved: true))
      ..add(_decisionResponse(state: 'approved'))
      ..add(_decisionResponse(state: 'declined'))
      ..add(_decisionResponse(state: 'cancelled'))
      ..add(_decisionResponse(state: 'installed'));

    expect(
      (await gateway.listPendingJoinRequests(_familyId)).single.state,
      FamilyJoinRequestState.pending,
    );
    expect((await gateway.getOwnJoinRequest())!.approvalEnvelope, isNotNull);
    expect(
      (await gateway.approveJoinRequest(_requestId, _approvalEnvelope)).state,
      FamilyJoinRequestState.approved,
    );
    expect(
      (await gateway.declineJoinRequest(_requestId)).state,
      FamilyJoinRequestState.declined,
    );
    expect(
      (await gateway.cancelJoinRequest(_requestId)).state,
      FamilyJoinRequestState.cancelled,
    );
    expect(
      (await gateway.completeJoinRequest(_requestId)).state,
      FamilyJoinRequestState.installed,
    );

    expect(client.calls.skip(2), [
      _Call('approve_family_join_request', {
        'p_request_id': _requestId,
        'p_approval_envelope': _approvalEnvelope.toJson(),
      }),
      const _Call('decline_family_join_request', {'p_request_id': _requestId}),
      const _Call('cancel_family_join_request', {'p_request_id': _requestId}),
      const _Call('complete_family_join_request', {'p_request_id': _requestId}),
    ]);
  });

  test('own request exposes the authoritative cancellation reason', () async {
    client.responses
      ..add(_ownRequestResponse(state: 'cancelled', cancelReason: 'requester'))
      ..add(
        _ownRequestResponse(
          state: 'cancelled',
          cancelReason: 'code_regenerated',
        ),
      );

    expect(
      (await gateway.getOwnJoinRequest())!.cancelReason,
      FamilyJoinRequestCancelReason.requester,
    );
    expect(
      (await gateway.getOwnJoinRequest())!.cancelReason,
      FamilyJoinRequestCancelReason.codeRegenerated,
    );
  });

  test(
    'own request rejects missing or impossible cancellation reasons',
    () async {
      final cancelled = _ownRequestResponse(state: 'cancelled');
      client.responses
        ..add({...cancelled}..remove('cancelReason'))
        ..add({..._ownRequestResponse(), 'cancelReason': 'requester'})
        ..add({...cancelled, 'cancelReason': 'unknown'});

      for (var index = 0; index < 3; index += 1) {
        await expectLater(
          gateway.getOwnJoinRequest(),
          throwsFamilyJoin(FamilyJoinFailureCode.unknown),
        );
      }
    },
  );

  test(
    'rejects impossible create and transition acknowledgement states',
    () async {
      client.responses
        ..add(_previewResponse())
        ..add(_ownRequestResponse(state: 'installed', approved: true));
      await expectLater(
        gateway.createFamilyJoinRequest(_joinDraft),
        throwsFamilyJoin(FamilyJoinFailureCode.unknown),
      );

      client.responses.add(_decisionResponse(state: 'pending'));
      await expectLater(
        gateway.approveJoinRequest(_requestId, _approvalEnvelope),
        throwsFamilyJoin(FamilyJoinFailureCode.unknown),
      );

      client.responses.add(_decisionResponse(state: 'approved'));
      await expectLater(
        gateway.completeJoinRequest(_requestId),
        throwsFamilyJoin(FamilyJoinFailureCode.unknown),
      );
    },
  );

  test(
    'null own request is valid but malformed payloads are unknown',
    () async {
      client.responses
        ..add(null)
        ..add({..._codeRecordResponse(), 'unexpected': true})
        ..add({..._previewResponse(), 'familyId': _differentFamilyId});
      expect(await gateway.getOwnJoinRequest(), isNull);
      await expectLater(
        gateway.getFamilyCode(_familyId),
        throwsFamilyJoin(FamilyJoinFailureCode.unknown),
      );
      await expectLater(
        gateway.previewFamilyByCode(_code),
        throwsFamilyJoin(FamilyJoinFailureCode.unknown),
      );
    },
  );

  test(
    'rejects noncanonical remote identifiers, bytes, and timestamps',
    () async {
      client.responses
        ..add({
          ..._codeRecordResponse(),
          'creatorAccountId': 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',
        })
        ..add({..._codeRecordResponse(), 'ciphertext': 'BAQEBAQEBAQ='})
        ..add({..._codeRecordResponse(), 'createdAt': '2026-09-05T08:00:00'});

      for (var index = 0; index < 3; index += 1) {
        await expectLater(
          gateway.getFamilyCode(_familyId),
          throwsFamilyJoin(FamilyJoinFailureCode.unknown),
        );
      }
    },
  );

  test(
    'rejects roster-family and approval-envelope context mismatches',
    () async {
      client.responses
        ..add([
          _pendingRequestResponse(),
          {
            ..._pendingRequestResponse(),
            'requestId': _differentRequestId,
            'familyId': _differentFamilyId,
          },
        ])
        ..add({
          ..._ownRequestResponse(state: 'approved', approved: true),
          'approvalEnvelope': {
            ..._approvalEnvelope.toJson(),
            'familyId': _differentFamilyId,
          },
        });

      await expectLater(
        gateway.listPendingJoinRequests(_familyId),
        throwsFamilyJoin(FamilyJoinFailureCode.unknown),
      );
      await expectLater(
        gateway.getOwnJoinRequest(),
        throwsFamilyJoin(FamilyJoinFailureCode.unknown),
      );
    },
  );

  test(
    'approved own requests require a non-empty roster containing the joiner',
    () async {
      client.responses
        ..add({
          ..._ownRequestResponse(state: 'approved', approved: true),
          'roster': <Object?>[],
        })
        ..add({
          ..._ownRequestResponse(state: 'installed', approved: true),
          'roster': [_memberResponse()],
        });

      for (var index = 0; index < 2; index += 1) {
        await expectLater(
          gateway.getOwnJoinRequest(),
          throwsFamilyJoin(FamilyJoinFailureCode.unknown),
        );
      }
    },
  );

  test(
    'maps exact clean P0001 join failures separately from legacy failures',
    () async {
      const mappings = {
        'SIGNED_OUT': FamilyJoinFailureCode.signedOut,
        'FAMILY_NOT_FOUND': FamilyJoinFailureCode.familyNotFound,
        'ALREADY_MEMBER': FamilyJoinFailureCode.alreadyMember,
        'REQUEST_ALREADY_PENDING': FamilyJoinFailureCode.requestAlreadyPending,
        'REQUEST_EXPIRED': FamilyJoinFailureCode.requestExpired,
        'REQUEST_DECLINED': FamilyJoinFailureCode.requestDeclined,
        'REQUEST_CANCELLED': FamilyJoinFailureCode.requestCancelled,
        'INVITATION_CHANGED': FamilyJoinFailureCode.invitationChanged,
        'CODE_COLLISION': FamilyJoinFailureCode.codeCollision,
        'CODE_VERSION_CHANGED': FamilyJoinFailureCode.codeVersionChanged,
        'RATE_LIMITED': FamilyJoinFailureCode.rateLimited,
        'INVALID_JOIN_KEY': FamilyJoinFailureCode.invalidJoinKey,
        'NOT_CREATOR': FamilyJoinFailureCode.notCreator,
        'FORBIDDEN': FamilyJoinFailureCode.forbidden,
        'ENVELOPE_REJECTED': FamilyJoinFailureCode.envelopeRejected,
      };
      for (final entry in mappings.entries) {
        client.errors.add(
          PostgrestException(code: 'P0001', message: entry.key),
        );
        await expectLater(
          gateway.getFamilyCode(_familyId),
          throwsFamilyJoin(entry.value),
          reason: entry.key,
        );
      }
      client.errors.add(
        const PostgrestException(
          code: 'P0001',
          message: 'FAMILY_NOT_FOUND',
          details: 'detail',
        ),
      );
      await expectLater(
        gateway.getFamilyCode(_familyId),
        throwsFamilyJoin(FamilyJoinFailureCode.unknown),
      );
    },
  );

  test('maps the live DIFFERENT_FAMILY PostgREST shape to an account-family conflict', () async {
    client.errors.add(
      const PostgrestException(
        code: 'P0001',
        message: 'DIFFERENT_FAMILY',
        details: 'Bad Request',
        hint: null,
      ),
    );

    await expectLater(
      gateway.getFamilyCode(_familyId),
      throwsFamilyJoin(FamilyJoinFailureCode.accountFamilyConflict),
    );
  });

  test('rejects DIFFERENT_FAMILY when PostgREST supplies a hint', () async {
    client.errors.add(
      const PostgrestException(
        code: 'P0001',
        message: 'DIFFERENT_FAMILY',
        details: 'Bad Request',
        hint: 'unexpected hint',
      ),
    );

    await expectLater(
      gateway.getFamilyCode(_familyId),
      throwsFamilyJoin(FamilyJoinFailureCode.unknown),
    );
  });

  test(
    'maps a clean P0001 failure when PostgREST supplies its HTTP reason',
    () async {
      client.errors.add(
        const PostgrestException(
          code: 'P0001',
          message: 'FAMILY_NOT_FOUND',
          details: 'Bad Request',
        ),
      );

      await expectLater(
        gateway.getFamilyCode(_familyId),
        throwsFamilyJoin(FamilyJoinFailureCode.familyNotFound),
      );
    },
  );

  test('maps a forbidden P0001 with the PostgREST HTTP reason', () async {
    client.errors.add(
      const PostgrestException(
        code: 'P0001',
        message: 'FORBIDDEN',
        details: 'Bad Request',
      ),
    );

    await expectLater(
      gateway.getFamilyCode(_familyId),
      throwsFamilyJoin(FamilyJoinFailureCode.forbidden),
    );
  });

  test('Realtime remains optional invalidation-only capability', () async {
    expect(await gateway.watchOwnJoinRequest().toList(), isEmpty);
    expect(await gateway.watchPendingJoinRequests(_familyId).toList(), isEmpty);

    final realtimeClient = _FakeRealtimeClient()
      ..accountId = _requesterAccountId;
    final realtimeGateway = _makeGateway(realtimeClient);
    expect(await realtimeGateway.watchOwnJoinRequest().toList(), [null]);
    expect(await realtimeGateway.watchPendingJoinRequests(_familyId).toList(), [
      null,
    ]);
    expect(realtimeClient.ownFilters, [_requesterAccountId]);
    expect(realtimeClient.pendingFilters, [_familyId]);
    expect(
      realtimeClient.calls,
      isEmpty,
      reason: 'Realtime does not read state',
    );
  });

  test('provider composes an independent unavailable capability', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final capability = container.read(familyCodeJoinGatewayProvider);
    expect(capability, isA<UnavailableFamilyCodeJoinGateway>());
    expect(capability.isConfigured, isFalse);
    await expectLater(
      capability.getOwnJoinRequest(),
      throwsFamilyJoin(FamilyJoinFailureCode.notConfigured),
    );
    expect(await capability.watchOwnJoinRequest().toList(), isEmpty);

    final configured = ProviderContainer(
      overrides: [cloudFamilyGatewayProvider.overrideWithValue(gateway)],
    );
    addTearDown(configured.dispose);
    expect(configured.read(familyCodeJoinGatewayProvider), same(gateway));
  });
}

Matcher throwsFamilyJoin(FamilyJoinFailureCode code) => throwsA(
  isA<FamilyJoinFailure>().having((failure) => failure.code, 'code', code),
);

const _familyId = '11111111-1111-4111-8111-111111111111';
const _differentFamilyId = '99999999-9999-4999-8999-999999999999';
const _ownerMemberId = '22222222-2222-4222-8222-222222222222';
const _joiningMemberId = '33333333-3333-4333-8333-333333333333';
const _requestId = '44444444-4444-4444-8444-444444444444';
const _differentRequestId = '77777777-7777-4777-8777-777777777777';
const _requesterAccountId = '55555555-5555-4555-8555-555555555555';
const _creatorAccountId = '66666666-6666-4666-8666-666666666666';
const _codeValue = 'K7M4P2Q8';
const _replacementCodeValue = 'ABCDEFGH';
const _joiningPublicKey = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE';
const _ephemeralPublicKey = 'AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI';
const _nonce = 'AwMDAwMDAwMDAwMD';
const _codeCiphertext = 'BAQEBAQEBAQ';
const _joinCiphertext = 'BQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQU';
const _mac = 'BgYGBgYGBgYGBgYGBgYGBg';
const _ownerAvatar = AvatarConfig.defaults(seed: _ownerMemberId);
const _joiningAvatar = AvatarConfig.defaults(seed: _joiningMemberId);
final _code = FamilyCode.parse(_codeValue);
final _replacementCode = FamilyCode.parse(_replacementCodeValue);

const _owner = LocalOwnerFamily(
  familyId: _familyId,
  familyName: 'Sabati',
  memberId: _ownerMemberId,
  displayName: 'Chris',
  demographicRole: FamilyDemographicRole.adult,
  colorToken: 'ochre',
  avatar: _ownerAvatar,
);
const _codeMaterial = EncryptedFamilyCodeMaterial(
  codecVersion: 1,
  familyId: _familyId,
  codeVersion: 1,
  nonce: _nonce,
  ciphertext: _codeCiphertext,
  mac: _mac,
);
const _replacementMaterial = EncryptedFamilyCodeMaterial(
  codecVersion: 1,
  familyId: _familyId,
  codeVersion: 2,
  nonce: _nonce,
  ciphertext: _codeCiphertext,
  mac: _mac,
);
final _codeDraft = FamilyCodeDraft(
  code: _code,
  lookupHash: 'unused-client-hash',
  material: _codeMaterial,
);
final _replacementDraft = FamilyCodeDraft(
  code: _replacementCode,
  lookupHash: 'unused-client-hash',
  material: _replacementMaterial,
);
const _joiningProfile = FamilyJoinProfileDraft(
  memberId: _joiningMemberId,
  displayName: 'Mariam',
  demographicRole: FamilyDemographicRole.child,
  colorToken: 'teal',
  avatar: _joiningAvatar,
  joiningPublicKey: _joiningPublicKey,
);
final _joinDraft = FamilyJoinRequestDraft(
  code: _code,
  profile: _joiningProfile,
);
const _approvalContext = JoinEnvelopeContext(
  requestId: _requestId,
  familyId: _familyId,
  requesterAccountId: _requesterAccountId,
  codeVersion: 1,
);
const _approvalEnvelope = FamilyJoinApprovalEnvelope(
  version: 1,
  context: _approvalContext,
  ephemeralPublicKey: _ephemeralPublicKey,
  nonce: _nonce,
  ciphertext: _joinCiphertext,
  mac: _mac,
);

Map<String, Object?> _memberResponse({
  String memberId = _ownerMemberId,
  String familyId = _familyId,
  String displayName = 'Chris',
  String role = 'adult',
  AvatarConfig avatar = _ownerAvatar,
}) => {
  'memberId': memberId,
  'familyId': familyId,
  'displayName': displayName,
  'demographicRole': role,
  'colorToken': memberId == _joiningMemberId ? 'teal' : 'ochre',
  'avatarJson': avatar.toJson(),
  'joinedAt': '2026-09-05T12:00:00+04:00',
};

Map<String, Object?> _codeRecordResponse({int codeVersion = 1}) => {
  'codecVersion': 1,
  'familyId': _familyId,
  'codeVersion': codeVersion,
  'nonce': _nonce,
  'ciphertext': _codeCiphertext,
  'mac': _mac,
  'creatorAccountId': _creatorAccountId,
  'createdAt': '2026-09-05T08:00:00Z',
  'updatedAt': '2026-09-05T08:01:00Z',
};

Map<String, Object?> _previewResponse() => {
  'familyId': _familyId,
  'familyName': 'Sabati',
  'codeVersion': 1,
  'members': [_memberResponse()],
};

Map<String, Object?> _pendingRequestResponse({String state = 'pending'}) => {
  'requestId': _requestId,
  'familyId': _familyId,
  'requesterAccountId': _requesterAccountId,
  'memberId': _joiningMemberId,
  'displayName': 'Mariam',
  'demographicRole': 'child',
  'colorToken': 'teal',
  'avatarJson': _joiningAvatar.toJson(),
  'joiningPublicKey': _joiningPublicKey,
  'codeVersion': 1,
  'state': state,
  'createdAt': '2026-09-05T08:00:00Z',
  'expiresAt': '2026-09-12T08:00:00Z',
};

Map<String, Object?> _ownRequestResponse({
  String state = 'pending',
  bool approved = false,
  String? cancelReason,
}) => {
  ..._pendingRequestResponse(state: state),
  'familyName': 'Sabati',
  'cancelReason': state == 'cancelled'
      ? (cancelReason ?? 'requester')
      : cancelReason,
  'approvalEnvelope': approved ? _approvalEnvelope.toJson() : null,
  'roster': approved
      ? [
          _memberResponse(),
          _memberResponse(
            memberId: _joiningMemberId,
            displayName: 'Mariam',
            role: 'child',
            avatar: _joiningAvatar,
          ),
        ]
      : <Object?>[],
};

Map<String, Object?> _decisionResponse({required String state}) => {
  'requestId': _requestId,
  'familyId': _familyId,
  'state': state,
  'updatedAt': '2026-09-05T08:05:00Z',
};

class _FakeClient implements SupabaseCloudClient {
  String? accountId;
  final responses = <Object?>[];
  final errors = <Object>[];
  final calls = <_Call>[];

  @override
  String? get authenticatedAccountId => accountId;
  @override
  String? get authenticatedEmail => null;
  @override
  Future<Object?> rpc(
    String function, {
    required Map<String, Object?> params,
  }) async {
    calls.add(_Call(function, params));
    if (errors.isNotEmpty) throw errors.removeAt(0);
    return responses.removeAt(0);
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected fake client call: $invocation');
}

final class _FakeRealtimeClient extends _FakeClient
    implements SupabaseCloudRealtimeClient {
  final ownFilters = <String>[];
  final pendingFilters = <String>[];

  @override
  Stream<void> watchOwnJoinRequest(String requesterAccountId) {
    ownFilters.add(requesterAccountId);
    return Stream<void>.value(null);
  }

  @override
  Stream<void> watchPendingJoinRequests(String familyId) {
    pendingFilters.add(familyId);
    return Stream<void>.value(null);
  }
}

final class _Call {
  const _Call(this.function, this.params);
  final String function;
  final Map<String, Object?> params;

  @override
  bool operator ==(Object other) =>
      other is _Call &&
      other.function == function &&
      _deepEqual(other.params, params);
  @override
  int get hashCode => Object.hash(function, params.length);
}

bool _deepEqual(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.entries.every(
          (entry) =>
              right.containsKey(entry.key) &&
              _deepEqual(entry.value, right[entry.key]),
        );
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        List.generate(
          left.length,
          (index) => index,
        ).every((index) => _deepEqual(left[index], right[index]));
  }
  return left == right;
}

SupabaseCloudFamilyGateway _makeGateway(SupabaseCloudClient client) {
  final constructor = SupabaseCloudFamilyGateway.new as dynamic;
  try {
    return Function.apply(constructor, [client]) as SupabaseCloudFamilyGateway;
  } on NoSuchMethodError {
    return Function.apply(
      constructor,
      [client],
      {#emailRedirectTo: 'https://example.test/auth'},
    ) as SupabaseCloudFamilyGateway;
  }
}
