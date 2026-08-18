import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/supabase_cloud_family_gateway.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late _FakeSupabaseCloudClient client;
  late SupabaseCloudFamilyGateway gateway;

  setUp(() {
    client = _FakeSupabaseCloudClient();
    gateway = SupabaseCloudFamilyGateway(
      client,
      emailRedirectTo:
          'https://family-project.supabase.co/functions/v1/'
          'keepers-auth-bridge',
    );
  });

  test('exposes configured authentication state without session contents', () {
    client
      ..accountId = _ownerAccountId
      ..email = 'owner@example.com';

    expect(gateway.isConfigured, isTrue);
    expect(gateway.authenticatedAccountId, _ownerAccountId);
    expect(gateway.authenticatedEmail, 'owner@example.com');
  });

  group('email OTP', () {
    test(
      'normalizes a valid email before requesting or verifying OTP',
      () async {
        await gateway.requestEmailOtp('  Person@Example.COM ');
        await gateway.verifyEmailOtp(
          email: ' Person@Example.COM ',
          token: ' 123456 ',
        );

        expect(client.requestedEmails, ['person@example.com']);
        expect(client.requestedRedirects, [
          'https://family-project.supabase.co/functions/v1/'
              'keepers-auth-bridge',
        ]);
        expect(client.verifiedOtps, [
          const _VerifiedOtp('person@example.com', '123456'),
        ]);
      },
    );

    test('rejects invalid email before auth is called', () async {
      await expectLater(
        gateway.requestEmailOtp('not-an-email'),
        throwsInvitation(InvitationFailureCode.invalidEmail),
      );

      expect(client.requestedEmails, isEmpty);
    });

    test(
      'maps exact invalid-email auth code for OTP request and verification',
      () async {
        const rawDetail = 'person@example.com must not escape';
        client.requestError = const AuthApiException(
          rawDetail,
          code: 'email_address_invalid',
        );
        await expectLater(
          gateway.requestEmailOtp('person@example.com'),
          throwsA(
            isA<InvitationFailure>()
                .having(
                  (failure) => failure.code,
                  'code',
                  InvitationFailureCode.invalidEmail,
                )
                .having(
                  (failure) => failure.toString(),
                  'redacted string',
                  isNot(contains(rawDetail)),
                ),
          ),
        );

        client
          ..requestError = null
          ..verifyError = const AuthApiException(
            rawDetail,
            code: 'email_address_invalid',
          );
        await expectLater(
          gateway.verifyEmailOtp(email: 'person@example.com', token: '123456'),
          throwsA(
            isA<InvitationFailure>()
                .having(
                  (failure) => failure.code,
                  'code',
                  InvitationFailureCode.invalidEmail,
                )
                .having(
                  (failure) => failure.toString(),
                  'redacted string',
                  isNot(contains(rawDetail)),
                ),
          ),
        );
      },
    );

    test('does not infer invalid email from nearby auth codes', () async {
      for (final code in const [
        'email_address_invalidated',
        'invalid_email',
        'EMAIL_ADDRESS_INVALID',
      ]) {
        client.requestError = AuthApiException(
          'raw invalid email detail',
          code: code,
        );

        await expectLater(
          gateway.requestEmailOtp('person@example.com'),
          throwsInvitation(InvitationFailureCode.unknown),
          reason: code,
        );
      }
    });

    test('maps exact invalid OTP auth codes without raw details', () async {
      client.verifyError = const AuthApiException(
        'token 123456 was rejected',
        code: 'otp_expired',
        statusCode: '403',
      );

      await expectLater(
        gateway.verifyEmailOtp(email: 'person@example.com', token: '123456'),
        throwsInvitation(InvitationFailureCode.invalidOtp),
      );
    });

    test('maps socket failures but redacts other auth failures', () async {
      client.requestError = const SocketException('host with secret path');
      await expectLater(
        gateway.requestEmailOtp('person@example.com'),
        throwsInvitation(InvitationFailureCode.networkUnavailable),
      );

      client.requestError = const AuthApiException(
        'server leaked a token',
        code: 'unexpected_failure',
      );
      await expectLater(
        gateway.requestEmailOtp('person@example.com'),
        throwsInvitation(InvitationFailureCode.unknown),
      );
    });
  });

  group('RPC payloads', () {
    test(
      'bootstraps owner with explicit demographic role and validates ack',
      () async {
        client.completeValue({
          'familyId': _familyId,
          'memberId': _ownerMemberId,
          'membershipRole': 'owner',
          'state': 'active',
        });

        await gateway.bootstrapOwner(_owner);

        expect(client.rpcInvocations, [
          _RpcInvocation('bootstrap_owner_family', {
            'p_family_id': _familyId,
            'p_family_name': 'Sabati',
            'p_member_id': _ownerMemberId,
            'p_display_name': 'Chris',
            'p_demographic_role': 'adult',
            'p_color_token': 'ochre',
            'p_avatar_json': _ownerAvatar.toJson(),
          }),
        ]);
      },
    );

    test('creates invitation with ciphertext-only request fields', () async {
      client.completeValue(_createdResponse());

      await gateway.createInvitation(_draft);

      expect(client.rpcInvocations, [
        _RpcInvocation('create_family_invite', {
          'p_invite_id': _inviteId,
          'p_family_id': _familyId,
          'p_recipient_email': 'recipient@example.com',
          'p_token_hash': _tokenHash,
          'p_envelope': _envelope.toJson(),
        }),
      ]);
      final serialized = client.rpcInvocations.single.params.toString();
      expect(serialized, isNot(contains(_token)));
      expect(serialized, isNot(contains(_wrappingSecret)));
      expect(serialized, isNot(contains('expiresAt')));
      expect(serialized, isNot(contains('familyKey')));
      expect(serialized, isNot(contains('memberKey')));
    });

    test('preview sends only the token', () async {
      client.completeValue(_previewResponse());

      await gateway.previewInvitation(_link);

      expect(client.rpcInvocations, [
        _RpcInvocation('preview_family_invite', {'p_token': _token}),
      ]);
      expect(
        client.rpcInvocations.single.params.toString(),
        isNot(contains(_wrappingSecret)),
      );
      expect(
        client.rpcInvocations.single.params.toString(),
        isNot(contains(_inviteId)),
      );
    });

    test(
      'claim sends token and profile but no link secret or invite ID',
      () async {
        client.completeValue(_claimResponse());

        await gateway.claimInvitation(_joinRequest);

        expect(client.rpcInvocations, [
          _RpcInvocation('claim_family_invite', {
            'p_token': _token,
            'p_member_id': _joiningMemberId,
            'p_display_name': 'Mariam',
            'p_demographic_role': 'child',
            'p_color_token': 'teal',
            'p_avatar_json': _joiningAvatar.toJson(),
          }),
        ]);
        final serialized = client.rpcInvocations.single.params.toString();
        expect(serialized, isNot(contains(_wrappingSecret)));
        expect(serialized, isNot(contains(_inviteId)));
      },
    );

    test(
      'complete, revoke, and list use exact names and identifier keys',
      () async {
        client.completeValue({
          'inviteId': _inviteId,
          'familyId': _familyId,
          'state': 'accepted',
        });
        await gateway.completeInvitation(_inviteId);

        client.completeValue({
          'inviteId': _inviteId,
          'familyId': _familyId,
          'state': 'revoked',
        });
        await gateway.revokeInvitation(_inviteId);

        client.completeValue([_memberResponse()]);
        await gateway.listActiveMembers(_familyId);

        expect(client.rpcInvocations, [
          _RpcInvocation('complete_family_invite', {'p_invite_id': _inviteId}),
          _RpcInvocation('revoke_family_invite', {'p_invite_id': _inviteId}),
          _RpcInvocation('list_active_family_members', {
            'p_family_id': _familyId,
          }),
        ]);
      },
    );
  });

  group('authoritative decoding', () {
    test(
      'maps all invitation creation metadata and converts dates to UTC',
      () async {
        client.completeValue(
          _createdResponse(
            createdAt: '2026-09-05T12:00:00+04:00',
            expiresAt: '2026-09-06T12:00:00+04:00',
          ),
        );

        final created = await gateway.createInvitation(_draft);

        expect(created.inviteId, _inviteId);
        expect(created.familyId, _familyId);
        expect(created.state, CloudInvitationState.pending);
        expect(created.createdAt, DateTime.utc(2026, 9, 5, 8));
        expect(created.expiresAt, DateTime.utc(2026, 9, 6, 8));
      },
    );

    test('maps a preview only when its invite ID matches the link', () async {
      client.completeValue(
        _previewResponse(expiresAt: '2026-09-06T12:00:00+04:00'),
      );

      final preview = await gateway.previewInvitation(_link);

      expect(preview.inviteId, _inviteId);
      expect(preview.familyId, _familyId);
      expect(preview.familyName, 'Sabati');
      expect(preview.ownerName, 'Chris');
      expect(preview.expiresAt, DateTime.utc(2026, 9, 6, 8));
      expect(preview.state, CloudInvitationState.pending);
    });

    test('claim validates IDs and maps the complete roster', () async {
      client.completeValue(_claimResponse());

      final claim = await gateway.claimInvitation(_joinRequest);

      expect(claim.familyId, _familyId);
      expect(claim.familyName, 'Sabati');
      expect(claim.localMemberId, _joiningMemberId);
      expect(claim.envelope, _envelope);
      expect(claim.members, hasLength(2));
      expect(claim.members.last.id, _joiningMemberId);
      expect(claim.members.last.familyId, _familyId);
      expect(claim.members.last.name, 'Mariam');
      expect(claim.members.last.role, 'child');
      expect(claim.members.last.colorToken, 'teal');
      expect(claim.members.last.avatar, _joiningAvatar);
      expect(claim.members.last.joinedAt, DateTime.utc(2026, 9, 5, 8));
    });

    test(
      'list response is a root array and demographicRole becomes member role',
      () async {
        client.completeValue([_memberResponse()]);

        final members = await gateway.listActiveMembers(_familyId);

        expect(members, hasLength(1));
        expect(members.single.role, 'adult');
        expect(members.single.avatar, _ownerAvatar);
        expect(members.single.joinedAt, DateTime.utc(2026, 9, 5, 8));
        expect(() => members.add(members.single), throwsUnsupportedError);
      },
    );
  });

  group('strict validation', () {
    test('rejects invalid local UUIDs before issuing an RPC', () async {
      await expectLater(
        gateway.listActiveMembers('NOT-A-UUID'),
        throwsInvitation(InvitationFailureCode.malformedLink),
      );
      await expectLater(
        gateway.bootstrapOwner(
          LocalOwnerFamily(
            familyId: _familyId,
            familyName: 'Sabati',
            memberId: 'AAAAAAAA-2222-4222-8222-222222222222',
            displayName: 'Chris',
            demographicRole: FamilyDemographicRole.adult,
            colorToken: 'ochre',
            avatar: _ownerAvatar,
          ),
        ),
        throwsInvitation(InvitationFailureCode.malformedLink),
      );

      expect(client.rpcInvocations, isEmpty);
    });

    test('rejects a malformed link before preview or claim', () async {
      const malformed = FamilyInviteLink(
        inviteId: _inviteId,
        token: 'too-short',
        wrappingSecret: _wrappingSecret,
      );

      await expectLater(
        gateway.previewInvitation(malformed),
        throwsInvitation(InvitationFailureCode.malformedLink),
      );
      await expectLater(
        gateway.claimInvitation(
          JoinRequest(
            link: malformed,
            memberId: _joiningMemberId,
            displayName: 'Mariam',
            demographicRole: FamilyDemographicRole.child,
            colorToken: 'teal',
            avatar: _joiningAvatar,
          ),
        ),
        throwsInvitation(InvitationFailureCode.malformedLink),
      );

      expect(client.rpcInvocations, isEmpty);
    });

    test(
      'rejects a create envelope whose identifiers disagree with draft',
      () async {
        final mismatchedDraft = CloudInvitationDraft(
          inviteId: _inviteId,
          familyId: _familyId,
          recipientEmail: 'recipient@example.com',
          tokenHash: _tokenHash,
          envelope: const InvitationEnvelope(
            version: 1,
            inviteId: _differentInviteId,
            familyId: _familyId,
            nonce: _nonce,
            ciphertext: _ciphertext,
            mac: _mac,
          ),
        );

        await expectLater(
          gateway.createInvitation(mismatchedDraft),
          throwsInvitation(InvitationFailureCode.envelopeRejected),
        );
        expect(client.rpcInvocations, isEmpty);
      },
    );

    test('rejects an alternate noncanonical token-hash encoding', () async {
      final alternateHash = '$_tokenHash=';
      expect(alternateHash, isNot(_tokenHash));
      expect(
        base64Url.decode(alternateHash),
        orderedEquals(base64Url.decode(base64Url.normalize(_tokenHash))),
      );
      final draft = CloudInvitationDraft(
        inviteId: _inviteId,
        familyId: _familyId,
        recipientEmail: 'recipient@example.com',
        tokenHash: alternateHash,
        envelope: _envelope,
      );

      await expectLater(
        gateway.createInvitation(draft),
        throwsInvitation(InvitationFailureCode.envelopeRejected),
      );

      expect(client.rpcInvocations, isEmpty);
    });

    test(
      'rejects extra, missing, mistyped, mismatched, and invalid create fields',
      () async {
        final malformed = <Object?>[
          {..._createdResponse(), 'extra': true},
          Map<String, Object?>.from(_createdResponse())..remove('state'),
          {..._createdResponse(), 'createdAt': 1},
          {..._createdResponse(), 'createdAt': 'not-a-timestamp'},
          {..._createdResponse(), 'createdAt': '2026-02-31T08:00:00Z'},
          {..._createdResponse(), 'state': 'new'},
          {..._createdResponse(), 'inviteId': _differentInviteId},
          {..._createdResponse(), 'familyId': 'not-a-uuid'},
          [_createdResponse()],
        ];

        for (final response in malformed) {
          client.completeValue(response);
          await expectLater(
            gateway.createInvitation(_draft),
            throwsInvitation(InvitationFailureCode.unknown),
            reason: '$response',
          );
        }
      },
    );

    test(
      'rejects preview response with a different invitation identifier',
      () async {
        client.completeValue(_previewResponse(inviteId: _differentInviteId));

        await expectLater(
          gateway.previewInvitation(_link),
          throwsInvitation(InvitationFailureCode.unknown),
        );
      },
    );

    test(
      'rejects claim IDs that disagree with link, envelope, or roster',
      () async {
        final malformedClaims = <Map<String, Object?>>[
          _claimResponse(inviteId: _differentInviteId),
          _claimResponse(
            envelope: {..._envelope.toJson(), 'familyId': _differentFamilyId},
          ),
          _claimResponse(
            members: [
              _memberResponse(familyId: _differentFamilyId),
              _memberResponse(
                memberId: _joiningMemberId,
                name: 'Mariam',
                role: 'child',
                avatar: _joiningAvatar,
              ),
            ],
          ),
          _claimResponse(members: [_memberResponse()]),
        ];

        for (final response in malformedClaims) {
          client.completeValue(response);
          await expectLater(
            gateway.claimInvitation(_joinRequest),
            throwsA(isA<InvitationFailure>()),
            reason: '$response',
          );
        }
      },
    );

    test(
      'rejects malformed remote roles, avatars, member fields, and list roots',
      () async {
        final malformed = <Object?>[
          {
            'members': [_memberResponse()],
          },
          [_memberResponse(role: 'owner')],
          [_memberResponse(avatarJson: 'not-an-object')],
          [
            _memberResponse(
              avatarJson: {..._ownerAvatar.toJson(), 'unexpected': true},
            ),
          ],
          [
            _memberResponse(
              avatarJson: {
                ..._ownerAvatar.toJson(),
                'selections': {'head': 'unknown-cloud-part'},
              },
            ),
          ],
          [_memberResponse()..remove('joinedAt')],
          [_memberResponse()..['joinedAt'] = 'yesterday'],
          [_memberResponse(familyId: _differentFamilyId)],
        ];

        for (final response in malformed) {
          client.completeValue(response);
          await expectLater(
            gateway.listActiveMembers(_familyId),
            throwsInvitation(InvitationFailureCode.unknown),
            reason: '$response',
          );
        }
      },
    );

    test('validates complete and revoke acknowledgement bodies', () async {
      for (final response in <Object?>[
        {'inviteId': _inviteId, 'familyId': _familyId, 'state': 'claimed'},
        {
          'inviteId': _differentInviteId,
          'familyId': _familyId,
          'state': 'accepted',
        },
        {
          'inviteId': _inviteId,
          'familyId': _familyId,
          'state': 'accepted',
          'extra': true,
        },
      ]) {
        client.completeValue(response);
        await expectLater(
          gateway.completeInvitation(_inviteId),
          throwsInvitation(InvitationFailureCode.unknown),
        );
      }

      client.completeValue({
        'inviteId': _inviteId,
        'familyId': _familyId,
        'state': 'accepted',
      });
      await expectLater(
        gateway.revokeInvitation(_inviteId),
        throwsInvitation(InvitationFailureCode.unknown),
      );
    });

    test(
      'validates bootstrap acknowledgement despite its void return type',
      () async {
        for (final response in <Object?>[
          {
            'familyId': _familyId,
            'memberId': _ownerMemberId,
            'membershipRole': 'member',
            'state': 'active',
          },
          {
            'familyId': _familyId,
            'memberId': _ownerMemberId,
            'membershipRole': 'owner',
            'state': 'pending_key',
          },
          {
            'familyId': _familyId,
            'memberId': _ownerMemberId,
            'membershipRole': 'owner',
            'state': 'active',
            'extra': true,
          },
        ]) {
          client.completeValue(response);
          await expectLater(
            gateway.bootstrapOwner(_owner),
            throwsInvitation(InvitationFailureCode.unknown),
          );
        }
      },
    );
  });

  group('remote failure mapping', () {
    test('maps every exact P0001 business identifier', () async {
      const cases = <String, InvitationFailureCode>{
        'SIGNED_OUT': InvitationFailureCode.signedOut,
        'INVALID_EMAIL': InvitationFailureCode.invalidEmail,
        'NOT_OWNER': InvitationFailureCode.notOwner,
        'FORBIDDEN': InvitationFailureCode.forbidden,
        'INVALID_TOKEN': InvitationFailureCode.malformedLink,
        'INVITE_NOT_FOUND': InvitationFailureCode.malformedLink,
        'INVITE_EXPIRED': InvitationFailureCode.expired,
        'INVITE_REVOKED': InvitationFailureCode.revoked,
        'ALREADY_CLAIMED': InvitationFailureCode.alreadyClaimed,
        'EMAIL_MISMATCH': InvitationFailureCode.emailMismatch,
        'DIFFERENT_FAMILY': InvitationFailureCode.differentFamily,
        'INVALID_ENVELOPE': InvitationFailureCode.envelopeRejected,
      };

      for (final entry in cases.entries) {
        client.completeError(
          PostgrestException(code: 'P0001', message: entry.key),
        );
        await expectLater(
          gateway.previewInvitation(_link),
          throwsInvitation(entry.value),
          reason: entry.key,
        );
      }
    });

    test('rejects every non-exact RPC error tuple', () async {
      final errors = <PostgrestException>[
        const PostgrestException(
          code: 'INVITE_EXPIRED',
          message: 'INVITE_EXPIRED',
        ),
        const PostgrestException(code: 'P0001', message: 'raw INVITE_EXPIRED'),
        const PostgrestException(code: 'P0001', message: 'invite_expired'),
        const PostgrestException(code: 'P0001', message: 'FAMILY_NOT_FOUND'),
        const PostgrestException(code: 'P0001', message: 'FAMILY_UNAVAILABLE'),
        const PostgrestException(
          code: 'P0001',
          message: 'INVITE_EXPIRED',
          details: 'raw detail',
        ),
        const PostgrestException(
          code: 'P0001',
          message: 'INVITE_EXPIRED',
          hint: 'raw hint',
        ),
      ];

      for (final error in errors) {
        client.completeError(error);
        await expectLater(
          gateway.previewInvitation(_link),
          throwsInvitation(InvitationFailureCode.unknown),
        );
      }
    });

    test('maps RPC socket failures without leaking their message', () async {
      client.completeError(
        const SocketException('https://secret.invalid/token'),
      );

      try {
        await gateway.previewInvitation(_link);
        fail('preview should fail');
      } on InvitationFailure catch (failure) {
        expect(failure.code, InvitationFailureCode.networkUnavailable);
        expect(failure.toString(), 'InvitationFailure(networkUnavailable)');
        expect(failure.toString(), isNot(contains('secret')));
        expect(failure.toString(), isNot(contains(_token)));
      }
    });
  });
}

Matcher throwsInvitation(InvitationFailureCode code) => throwsA(
  isA<InvitationFailure>().having((failure) => failure.code, 'code', code),
);

const _familyId = '11111111-1111-4111-8111-111111111111';
const _differentFamilyId = '99999999-9999-4999-8999-999999999999';
const _ownerMemberId = '22222222-2222-4222-8222-222222222222';
const _joiningMemberId = '33333333-3333-4333-8333-333333333333';
const _inviteId = '44444444-4444-4444-8444-444444444444';
const _differentInviteId = '88888888-8888-4888-8888-888888888888';
const _ownerAccountId = '55555555-5555-4555-8555-555555555555';
const _token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _wrappingSecret = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE';
const _tokenHash = 'BQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQU';
const _nonce = 'AgICAgICAgICAgIC';
const _ciphertext = 'AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM';
const _mac = 'BAQEBAQEBAQEBAQEBAQEBA';
const _ownerAvatar = AvatarConfig.defaults(seed: _ownerMemberId);
const _joiningAvatar = AvatarConfig.defaults(seed: _joiningMemberId);

const _link = FamilyInviteLink(
  inviteId: _inviteId,
  token: _token,
  wrappingSecret: _wrappingSecret,
);

const _envelope = InvitationEnvelope(
  version: 1,
  inviteId: _inviteId,
  familyId: _familyId,
  nonce: _nonce,
  ciphertext: _ciphertext,
  mac: _mac,
);

const _owner = LocalOwnerFamily(
  familyId: _familyId,
  familyName: 'Sabati',
  memberId: _ownerMemberId,
  displayName: 'Chris',
  demographicRole: FamilyDemographicRole.adult,
  colorToken: 'ochre',
  avatar: _ownerAvatar,
);

const _draft = CloudInvitationDraft(
  inviteId: _inviteId,
  familyId: _familyId,
  recipientEmail: 'Recipient@Example.com',
  tokenHash: _tokenHash,
  envelope: _envelope,
);

const _joinRequest = JoinRequest(
  link: _link,
  memberId: _joiningMemberId,
  displayName: 'Mariam',
  demographicRole: FamilyDemographicRole.child,
  colorToken: 'teal',
  avatar: _joiningAvatar,
);

Map<String, Object?> _createdResponse({
  String createdAt = '2026-09-05T08:00:00Z',
  String expiresAt = '2026-09-06T08:00:00Z',
}) => {
  'inviteId': _inviteId,
  'familyId': _familyId,
  'state': 'pending',
  'createdAt': createdAt,
  'expiresAt': expiresAt,
};

Map<String, Object?> _previewResponse({
  String inviteId = _inviteId,
  String expiresAt = '2026-09-06T08:00:00Z',
}) => {
  'inviteId': inviteId,
  'familyId': _familyId,
  'familyName': 'Sabati',
  'ownerName': 'Chris',
  'expiresAt': expiresAt,
  'state': 'pending',
};

Map<String, Object?> _memberResponse({
  String memberId = _ownerMemberId,
  String familyId = _familyId,
  String name = 'Chris',
  String role = 'adult',
  AvatarConfig avatar = _ownerAvatar,
  Object? avatarJson,
}) => {
  'memberId': memberId,
  'familyId': familyId,
  'displayName': name,
  'demographicRole': role,
  'colorToken': memberId == _joiningMemberId ? 'teal' : 'ochre',
  'avatarJson': avatarJson ?? avatar.toJson(),
  'joinedAt': '2026-09-05T12:00:00+04:00',
};

Map<String, Object?> _claimResponse({
  String inviteId = _inviteId,
  Object? envelope,
  List<Object?>? members,
}) => {
  'inviteId': inviteId,
  'familyId': _familyId,
  'familyName': 'Sabati',
  'localMemberId': _joiningMemberId,
  'envelope': envelope ?? _envelope.toJson(),
  'members':
      members ??
      [
        _memberResponse(),
        _memberResponse(
          memberId: _joiningMemberId,
          name: 'Mariam',
          role: 'child',
          avatar: _joiningAvatar,
        ),
      ],
};

final class _FakeSupabaseCloudClient implements SupabaseCloudClient {
  String? accountId;
  String? email;
  Object? requestError;
  Object? verifyError;
  Object? _rpcValue;
  Object? _rpcError;
  final requestedEmails = <String>[];
  final requestedRedirects = <String>[];
  final verifiedOtps = <_VerifiedOtp>[];
  final rpcInvocations = <_RpcInvocation>[];

  @override
  String? get authenticatedAccountId => accountId;

  @override
  String? get authenticatedEmail => email;

  @override
  Future<void> requestEmailOtp(
    String email, {
    required String emailRedirectTo,
  }) async {
    requestedEmails.add(email);
    requestedRedirects.add(emailRedirectTo);
    if (requestError case final error?) throw error;
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    verifiedOtps.add(_VerifiedOtp(email, token));
    if (verifyError case final error?) throw error;
  }

  void completeValue(Object? value) {
    _rpcValue = value;
    _rpcError = null;
  }

  void completeError(Object error) {
    _rpcValue = null;
    _rpcError = error;
  }

  @override
  Future<Object?> rpc(
    String function, {
    required Map<String, Object?> params,
  }) async {
    rpcInvocations.add(_RpcInvocation(function, params));
    if (_rpcError case final error?) throw error;
    return _rpcValue;
  }
}

final class _RpcInvocation {
  const _RpcInvocation(this.function, this.params);

  final String function;
  final Map<String, Object?> params;

  @override
  bool operator ==(Object other) =>
      other is _RpcInvocation &&
      other.function == function &&
      _mapsEqual(other.params, params);

  @override
  int get hashCode => Object.hash(function, Object.hashAll(params.entries));
}

final class _VerifiedOtp {
  const _VerifiedOtp(this.email, this.token);

  final String email;
  final String token;

  @override
  bool operator ==(Object other) =>
      other is _VerifiedOtp && other.email == email && other.token == token;

  @override
  int get hashCode => Object.hash(email, token);
}

bool _mapsEqual(Map<String, Object?> left, Map<String, Object?> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    final rightValue = right[entry.key];
    if (entry.value is Map<String, Object?> &&
        rightValue is Map<String, Object?>) {
      if (!_mapsEqual(entry.value! as Map<String, Object?>, rightValue)) {
        return false;
      }
    } else if (rightValue != entry.value) {
      return false;
    }
  }
  return true;
}
