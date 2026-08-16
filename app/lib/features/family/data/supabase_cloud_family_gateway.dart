import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/members/domain/avatar_catalog.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The narrow external boundary used by [SupabaseCloudFamilyGateway].
///
/// Keeping the SDK behind this interface lets adapter tests exercise real
/// payload and decoding behavior without constructing a network client.
abstract interface class SupabaseCloudClient {
  String? get authenticatedAccountId;

  String? get authenticatedEmail;

  Future<void> requestEmailOtp(String email);

  Future<void> verifyEmailOtp({required String email, required String token});

  Future<Object?> rpc(String function, {required Map<String, Object?> params});
}

/// Optional narrow Realtime capability. Events only invalidate RPC-backed
/// reads; no row payload crosses this boundary.
abstract interface class SupabaseCloudRealtimeClient {
  Stream<void> watchOwnJoinRequest(String requesterAccountId);

  Stream<void> watchPendingJoinRequests(String familyId);
}

final class SupabaseCloudClientAdapter
    implements SupabaseCloudClient, SupabaseCloudRealtimeClient {
  const SupabaseCloudClientAdapter(this._client);

  final SupabaseClient _client;

  @override
  String? get authenticatedAccountId => _client.auth.currentSession?.user.id;

  @override
  String? get authenticatedEmail => _client.auth.currentUser?.email;

  @override
  Future<void> requestEmailOtp(String email) =>
      _client.auth.signInWithOtp(email: email, shouldCreateUser: true);

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    await _client.auth.verifyOTP(
      email: email,
      token: token,
      type: OtpType.email,
    );
  }

  @override
  Future<Object?> rpc(
    String function, {
    required Map<String, Object?> params,
  }) async => await _client.rpc<Object?>(function, params: Map.from(params));

  @override
  Stream<void> watchOwnJoinRequest(String requesterAccountId) => _client
      .schema('public')
      .from('family_join_requests')
      .stream(primaryKey: const ['id'])
      .eq('requester_account_id', requesterAccountId)
      .map<void>((_) {});

  @override
  Stream<void> watchPendingJoinRequests(String familyId) => _client
      .schema('public')
      .from('family_join_requests')
      .stream(primaryKey: const ['id'])
      .eq('family_id', familyId)
      .map<void>((_) {});
}

final class SupabaseCloudFamilyGateway
    implements CloudFamilyGateway, FamilyCodeJoinGateway {
  const SupabaseCloudFamilyGateway(this._client);

  final SupabaseCloudClient _client;

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => _client.authenticatedAccountId;

  @override
  String? get authenticatedEmail => _client.authenticatedEmail;

  @override
  Future<void> requestEmailOtp(String email) async {
    final normalizedEmail = _normalizeEmail(email);
    await _guard(() => _client.requestEmailOtp(normalizedEmail));
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    final normalizedToken = token.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(normalizedToken)) {
      throw const InvitationFailure(InvitationFailureCode.invalidOtp);
    }
    await _guard(
      () => _client.verifyEmailOtp(
        email: normalizedEmail,
        token: normalizedToken,
      ),
      mapInvalidOtp: true,
    );
  }

  @override
  Future<void> bootstrapOwner(LocalOwnerFamily owner) async {
    _requireCanonicalUuid(owner.familyId);
    _requireCanonicalUuid(owner.memberId);
    final familyName = _validateText(owner.familyName, maximumLength: 100);
    final displayName = _validateText(owner.displayName, maximumLength: 100);
    final colorToken = _validateText(owner.colorToken, maximumLength: 64);
    final avatar = _validatedOutgoingAvatar(owner.avatar);

    await _guard(() async {
      final response = await _client.rpc(
        'bootstrap_owner_family',
        params: {
          'p_family_id': owner.familyId,
          'p_family_name': familyName,
          'p_member_id': owner.memberId,
          'p_display_name': displayName,
          'p_demographic_role': owner.demographicRole.name,
          'p_color_token': colorToken,
          'p_avatar_json': avatar,
        },
      );
      final acknowledgement = _strictObject(response, const {
        'familyId',
        'memberId',
        'membershipRole',
        'state',
      });
      if (_uuidField(acknowledgement, 'familyId') != owner.familyId ||
          _uuidField(acknowledgement, 'memberId') != owner.memberId ||
          _stringField(acknowledgement, 'membershipRole') != 'owner' ||
          _stringField(acknowledgement, 'state') != 'active') {
        throw const FormatException('Invalid bootstrap acknowledgement');
      }
    });
  }

  @override
  Future<CreatedInvitation> createInvitation(CloudInvitationDraft draft) async {
    _requireCanonicalUuid(draft.inviteId);
    _requireCanonicalUuid(draft.familyId);
    final recipientEmail = _normalizeEmail(draft.recipientEmail);
    _validateCanonicalBytes(draft.tokenHash, expectedLength: 32);
    final envelope = _validatedEnvelope(draft.envelope);
    if (envelope.inviteId != draft.inviteId ||
        envelope.familyId != draft.familyId) {
      throw const InvitationFailure(InvitationFailureCode.envelopeRejected);
    }

    return _guard(() async {
      final response = await _client.rpc(
        'create_family_invite',
        params: {
          'p_invite_id': draft.inviteId,
          'p_family_id': draft.familyId,
          'p_recipient_email': recipientEmail,
          'p_token_hash': draft.tokenHash,
          'p_envelope': envelope.toJson(),
        },
      );
      final object = _strictObject(response, const {
        'inviteId',
        'familyId',
        'state',
        'createdAt',
        'expiresAt',
      });
      final inviteId = _uuidField(object, 'inviteId');
      final familyId = _uuidField(object, 'familyId');
      if (inviteId != draft.inviteId || familyId != draft.familyId) {
        throw const FormatException('Invitation creation identifiers differ');
      }
      return CreatedInvitation(
        inviteId: inviteId,
        familyId: familyId,
        state: _invitationState(object['state']),
        createdAt: _timestampField(object, 'createdAt'),
        expiresAt: _timestampField(object, 'expiresAt'),
      );
    });
  }

  @override
  Future<InvitePreview> previewInvitation(FamilyInviteLink link) async {
    final validatedLink = _validatedLink(link);
    return _guard(() async {
      final response = await _client.rpc(
        'preview_family_invite',
        params: {'p_token': validatedLink.token},
      );
      final object = _strictObject(response, const {
        'inviteId',
        'familyId',
        'familyName',
        'ownerName',
        'expiresAt',
        'state',
      });
      final inviteId = _uuidField(object, 'inviteId');
      if (inviteId != validatedLink.inviteId) {
        throw const FormatException('Invitation preview identifier differs');
      }
      return InvitePreview(
        inviteId: inviteId,
        familyId: _uuidField(object, 'familyId'),
        familyName: _strictRemoteText(object, 'familyName', maximumLength: 100),
        ownerName: _strictRemoteText(object, 'ownerName', maximumLength: 100),
        expiresAt: _timestampField(object, 'expiresAt'),
        state: _invitationState(object['state']),
      );
    });
  }

  @override
  Future<ClaimedFamily> claimInvitation(JoinRequest request) async {
    final link = _validatedLink(request.link);
    _requireCanonicalUuid(request.memberId);
    final displayName = _validateText(request.displayName, maximumLength: 100);
    final colorToken = _validateText(request.colorToken, maximumLength: 64);
    final avatar = _validatedOutgoingAvatar(request.avatar);

    return _guard(() async {
      final response = await _client.rpc(
        'claim_family_invite',
        params: {
          'p_token': link.token,
          'p_member_id': request.memberId,
          'p_display_name': displayName,
          'p_demographic_role': request.demographicRole.name,
          'p_color_token': colorToken,
          'p_avatar_json': avatar,
        },
      );
      final object = _strictObject(response, const {
        'inviteId',
        'familyId',
        'familyName',
        'localMemberId',
        'envelope',
        'members',
      });
      final inviteId = _uuidField(object, 'inviteId');
      final familyId = _uuidField(object, 'familyId');
      final localMemberId = _uuidField(object, 'localMemberId');
      if (inviteId != link.inviteId) {
        throw const FormatException('Claimed invitation identifier differs');
      }

      final envelope = _decodeRemoteEnvelope(object['envelope']);
      if (envelope.inviteId != inviteId || envelope.familyId != familyId) {
        throw const InvitationFailure(InvitationFailureCode.envelopeRejected);
      }

      final members = _decodeRoster(object['members'], familyId: familyId);
      if (!members.any((member) => member.id == localMemberId)) {
        throw const FormatException('Claimed local member is absent');
      }
      return ClaimedFamily(
        familyId: familyId,
        familyName: _strictRemoteText(object, 'familyName', maximumLength: 100),
        localMemberId: localMemberId,
        envelope: envelope,
        members: members,
      );
    });
  }

  @override
  Future<void> completeInvitation(String inviteId) async {
    _requireCanonicalUuid(inviteId);
    await _guard(() async {
      final response = await _client.rpc(
        'complete_family_invite',
        params: {'p_invite_id': inviteId},
      );
      _validateTransitionAcknowledgement(
        response,
        inviteId: inviteId,
        expectedState: 'accepted',
      );
    });
  }

  @override
  Future<void> revokeInvitation(String inviteId) async {
    _requireCanonicalUuid(inviteId);
    await _guard(() async {
      final response = await _client.rpc(
        'revoke_family_invite',
        params: {'p_invite_id': inviteId},
      );
      _validateTransitionAcknowledgement(
        response,
        inviteId: inviteId,
        expectedState: 'revoked',
      );
    });
  }

  @override
  Future<List<FamilyMember>> listActiveMembers(String familyId) async {
    _requireCanonicalUuid(familyId);
    return _guard(() async {
      final response = await _client.rpc(
        'list_active_family_members',
        params: {'p_family_id': familyId},
      );
      return _decodeRoster(response, familyId: familyId);
    });
  }

  @override
  Future<EncryptedFamilyCodeRecord> bootstrapOwnerWithFamilyCode(
    LocalOwnerFamily owner,
    FamilyCodeDraft code,
  ) => _familyGuard(() async {
    _requireFamilyUuid(owner.familyId);
    _requireFamilyUuid(owner.memberId);
    final familyName = _familyText(owner.familyName, maximumLength: 100);
    final displayName = _familyText(owner.displayName, maximumLength: 100);
    final colorToken = _familyText(owner.colorToken, maximumLength: 64);
    final avatar = _familyOutgoingAvatar(owner.avatar);
    final material = _validatedFamilyCodeMaterial(
      code.material,
      familyId: owner.familyId,
      codeVersion: 1,
    );
    final response = await _client.rpc(
      'bootstrap_owner_family_with_code',
      params: {
        'p_family_id': owner.familyId,
        'p_family_name': familyName,
        'p_member_id': owner.memberId,
        'p_display_name': displayName,
        'p_demographic_role': owner.demographicRole.name,
        'p_color_token': colorToken,
        'p_avatar_json': avatar,
        'p_code': code.code.normalized,
        'p_code_envelope': material.toJson(),
      },
    );
    return _decodeFamilyCodeRecord(response, expectedFamilyId: owner.familyId);
  });

  @override
  Future<EncryptedFamilyCodeRecord> getFamilyCode(String familyId) =>
      _familyGuard(() async {
        _requireFamilyUuid(familyId);
        final response = await _client.rpc(
          'get_family_join_code',
          params: {'p_family_id': familyId},
        );
        return _decodeFamilyCodeRecord(response, expectedFamilyId: familyId);
      });

  @override
  Future<FamilyJoinPreview> previewFamilyByCode(FamilyCode code) =>
      _familyGuard(() async {
        final response = await _client.rpc(
          'preview_family_by_code',
          params: {'p_code': code.normalized},
        );
        _throwIfFamilyNotFoundProjection(response);
        return _decodeFamilyJoinPreview(response);
      });

  @override
  Future<OwnFamilyJoinRequest> createFamilyJoinRequest(
    FamilyJoinRequestDraft draft,
  ) => _familyGuard(() async {
    final profile = _validatedJoinProfile(draft.profile);
    final requesterAccountId = _validatedAuthenticatedAccountId(
      authenticatedAccountId,
    );
    final previewResponse = await _client.rpc(
      'preview_family_by_code',
      params: {'p_code': draft.code.normalized},
    );
    _throwIfFamilyNotFoundProjection(previewResponse);
    final preview = _decodeFamilyJoinPreview(previewResponse);
    final response = await _client.rpc(
      'create_family_join_request',
      params: {
        'p_family_id': preview.familyId,
        'p_code': draft.code.normalized,
        'p_member_id': profile.memberId,
        'p_display_name': profile.displayName,
        'p_demographic_role': profile.demographicRole.name,
        'p_color_token': profile.colorToken,
        'p_avatar_json': profile.avatar.toJson(),
        'p_joining_public_key': profile.joiningPublicKey,
      },
    );
    _throwIfFamilyNotFoundProjection(response);
    final request = _decodeOwnFamilyJoinRequest(response);
    if (request.familyId != preview.familyId ||
        request.requesterAccountId != requesterAccountId ||
        request.memberId != profile.memberId ||
        request.displayName != profile.displayName ||
        request.demographicRole != profile.demographicRole ||
        request.colorToken != profile.colorToken ||
        request.avatar != profile.avatar ||
        request.joiningPublicKey != profile.joiningPublicKey ||
        request.codeVersion != preview.codeVersion) {
      throw const FormatException('Join request acknowledgement differs');
    }
    if (request.state != FamilyJoinRequestState.pending &&
        request.state != FamilyJoinRequestState.approved) {
      throw const FormatException('Join request creation state is invalid');
    }
    return request;
  });

  @override
  Future<List<PendingFamilyJoinRequest>> listPendingJoinRequests(
    String familyId,
  ) => _familyGuard(() async {
    _requireFamilyUuid(familyId);
    final response = await _client.rpc(
      'list_pending_family_join_requests',
      params: {'p_family_id': familyId},
    );
    if (response is! List<Object?>) {
      throw const FormatException('Pending join requests must be an array');
    }
    final seen = <String>{};
    final requests = <PendingFamilyJoinRequest>[];
    for (final value in response) {
      final request = _decodePendingFamilyJoinRequest(value);
      if (request.familyId != familyId ||
          request.state != FamilyJoinRequestState.pending ||
          !seen.add(request.requestId)) {
        throw const FormatException('Invalid pending join request list');
      }
      requests.add(request);
    }
    return List<PendingFamilyJoinRequest>.unmodifiable(requests);
  });

  @override
  Future<OwnFamilyJoinRequest?> getOwnJoinRequest() => _familyGuard(() async {
    final response = await _client.rpc(
      'get_own_family_join_request',
      params: const {},
    );
    return response == null ? null : _decodeOwnFamilyJoinRequest(response);
  });

  @override
  Future<FamilyJoinDecision> approveJoinRequest(
    String requestId,
    FamilyJoinApprovalEnvelope envelope,
  ) => _familyGuard(() async {
    _requireFamilyUuid(requestId);
    final validatedEnvelope = _validatedApprovalEnvelope(envelope);
    if (validatedEnvelope.context.requestId != requestId) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
    }
    final response = await _client.rpc(
      'approve_family_join_request',
      params: {
        'p_request_id': requestId,
        'p_approval_envelope': validatedEnvelope.toJson(),
      },
    );
    final decision = _decodeDecision(response, expectedRequestId: requestId);
    if (decision.state == FamilyJoinRequestState.pending) {
      throw const FormatException('Join approval state is invalid');
    }
    return decision;
  });

  @override
  Future<FamilyJoinDecision> declineJoinRequest(String requestId) =>
      _transitionJoinRequest(
        'decline_family_join_request',
        requestId,
        disallowPending: true,
      );

  @override
  Future<FamilyJoinDecision> cancelJoinRequest(String requestId) =>
      _transitionJoinRequest(
        'cancel_family_join_request',
        requestId,
        disallowPending: true,
      );

  @override
  Future<FamilyJoinDecision> completeJoinRequest(String requestId) =>
      _transitionJoinRequest(
        'complete_family_join_request',
        requestId,
        requiredState: FamilyJoinRequestState.installed,
      );

  Future<FamilyJoinDecision> _transitionJoinRequest(
    String function,
    String requestId, {
    bool disallowPending = false,
    FamilyJoinRequestState? requiredState,
  }) => _familyGuard(() async {
    _requireFamilyUuid(requestId);
    final response = await _client.rpc(
      function,
      params: {'p_request_id': requestId},
    );
    final decision = _decodeDecision(response, expectedRequestId: requestId);
    if ((disallowPending && decision.state == FamilyJoinRequestState.pending) ||
        (requiredState != null && decision.state != requiredState)) {
      throw const FormatException('Join transition state is invalid');
    }
    return decision;
  });

  @override
  Future<EncryptedFamilyCodeRecord> regenerateFamilyCode({
    required String familyId,
    required int expectedVersion,
    required FamilyCodeDraft replacement,
  }) => _familyGuard(() async {
    _requireFamilyUuid(familyId);
    if (expectedVersion <= 0) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.codeVersionChanged);
    }
    final material = _validatedFamilyCodeMaterial(
      replacement.material,
      familyId: familyId,
      codeVersion: expectedVersion + 1,
    );
    final response = await _client.rpc(
      'regenerate_family_join_code',
      params: {
        'p_family_id': familyId,
        'p_expected_version': expectedVersion,
        'p_code': replacement.code.normalized,
        'p_code_envelope': material.toJson(),
      },
    );
    final record = _decodeFamilyCodeRecord(
      response,
      expectedFamilyId: familyId,
    );
    if (record.material.codeVersion != expectedVersion + 1) {
      throw const FormatException('Regenerated code version differs');
    }
    return record;
  });

  @override
  Stream<void> watchOwnJoinRequest() {
    final accountId = authenticatedAccountId;
    return switch ((_client, accountId)) {
      (SupabaseCloudRealtimeClient realtime, String accountId)
          when isCanonicalFamilyJoinUuid(accountId) =>
        realtime.watchOwnJoinRequest(accountId),
      _ => const Stream<void>.empty(),
    };
  }

  @override
  Stream<void> watchPendingJoinRequests(String familyId) {
    if (!isCanonicalFamilyJoinUuid(familyId)) {
      return Stream<void>.error(
        const FamilyJoinFailure(FamilyJoinFailureCode.unknown),
      );
    }
    return switch (_client) {
      SupabaseCloudRealtimeClient realtime => realtime.watchPendingJoinRequests(
        familyId,
      ),
      _ => const Stream<void>.empty(),
    };
  }
}

Future<T> _familyGuard<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on FamilyJoinFailure {
    rethrow;
  } on SocketException {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable);
  } on TimeoutException {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable);
  } on AuthRetryableFetchException {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable);
  } on AuthUnknownException catch (error) {
    if (error.originalError is SocketException ||
        error.originalError is TimeoutException) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable);
    }
    throw const FamilyJoinFailure(FamilyJoinFailureCode.unknown);
  } on AuthSessionMissingException {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut);
  } on AuthException {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.unknown);
  } on PostgrestException catch (error) {
    throw _mapFamilyPostgrestFailure(error);
  } on Object {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.unknown);
  }
}

FamilyJoinFailure _mapFamilyPostgrestFailure(PostgrestException error) {
  if (error.code != 'P0001' || error.details != null || error.hint != null) {
    return const FamilyJoinFailure(FamilyJoinFailureCode.unknown);
  }
  final code = switch (error.message) {
    'SIGNED_OUT' => FamilyJoinFailureCode.signedOut,
    'FAMILY_NOT_FOUND' => FamilyJoinFailureCode.familyNotFound,
    'ALREADY_MEMBER' => FamilyJoinFailureCode.alreadyMember,
    'REQUEST_ALREADY_PENDING' => FamilyJoinFailureCode.requestAlreadyPending,
    'REQUEST_EXPIRED' => FamilyJoinFailureCode.requestExpired,
    'REQUEST_DECLINED' => FamilyJoinFailureCode.requestDeclined,
    'REQUEST_CANCELLED' => FamilyJoinFailureCode.requestCancelled,
    'INVITATION_CHANGED' => FamilyJoinFailureCode.invitationChanged,
    'CODE_COLLISION' => FamilyJoinFailureCode.codeCollision,
    'CODE_VERSION_CHANGED' => FamilyJoinFailureCode.codeVersionChanged,
    'RATE_LIMITED' => FamilyJoinFailureCode.rateLimited,
    'INVALID_JOIN_KEY' => FamilyJoinFailureCode.invalidJoinKey,
    'NOT_CREATOR' => FamilyJoinFailureCode.notCreator,
    'FORBIDDEN' => FamilyJoinFailureCode.forbidden,
    'ENVELOPE_REJECTED' => FamilyJoinFailureCode.envelopeRejected,
    _ => FamilyJoinFailureCode.unknown,
  };
  return FamilyJoinFailure(code);
}

void _throwIfFamilyNotFoundProjection(Object? response) {
  if (response is Map &&
      response.length == 1 &&
      response.containsKey('errorCode') &&
      response['errorCode'] == 'FAMILY_NOT_FOUND') {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.familyNotFound);
  }
}

EncryptedFamilyCodeMaterial _validatedFamilyCodeMaterial(
  EncryptedFamilyCodeMaterial material, {
  required String familyId,
  required int codeVersion,
}) {
  try {
    final validated = EncryptedFamilyCodeMaterial.fromJson(material.toJson());
    if (validated.familyId != familyId ||
        validated.codeVersion != codeVersion) {
      throw const FormatException('Family code envelope context differs');
    }
    return validated;
  } on Object {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
  }
}

EncryptedFamilyCodeRecord _decodeFamilyCodeRecord(
  Object? response, {
  required String expectedFamilyId,
}) {
  final object = _strictObject(response, const {
    'codecVersion',
    'familyId',
    'codeVersion',
    'nonce',
    'ciphertext',
    'mac',
    'creatorAccountId',
    'createdAt',
    'updatedAt',
  });
  final material = EncryptedFamilyCodeMaterial.fromJson({
    'codecVersion': object['codecVersion'],
    'familyId': object['familyId'],
    'codeVersion': object['codeVersion'],
    'nonce': object['nonce'],
    'ciphertext': object['ciphertext'],
    'mac': object['mac'],
  });
  if (material.familyId != expectedFamilyId) {
    throw const FormatException('Family code response family differs');
  }
  final createdAt = _timestampField(object, 'createdAt');
  final updatedAt = _timestampField(object, 'updatedAt');
  if (updatedAt.isBefore(createdAt)) {
    throw const FormatException('Family code timestamps are invalid');
  }
  return EncryptedFamilyCodeRecord(
    material: material,
    creatorAccountId: _uuidField(object, 'creatorAccountId'),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

FamilyJoinPreview _decodeFamilyJoinPreview(Object? response) {
  final object = _strictObject(response, const {
    'familyId',
    'familyName',
    'codeVersion',
    'members',
  });
  final familyId = _uuidField(object, 'familyId');
  return FamilyJoinPreview.validated(
    familyId: familyId,
    familyName: _strictRemoteText(object, 'familyName', maximumLength: 100),
    codeVersion: _positiveIntField(object, 'codeVersion'),
    members: _decodeRoster(object['members'], familyId: familyId),
  );
}

FamilyJoinProfileDraft _validatedJoinProfile(FamilyJoinProfileDraft profile) {
  try {
    return FamilyJoinProfileDraft.validated(
      memberId: profile.memberId,
      displayName: _familyText(profile.displayName, maximumLength: 100),
      demographicRole: profile.demographicRole,
      colorToken: _familyText(profile.colorToken, maximumLength: 64),
      avatar: _decodeAvatar(profile.avatar.toJson()),
      joiningPublicKey: profile.joiningPublicKey,
    );
  } on Object {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.invalidJoinKey);
  }
}

PendingFamilyJoinRequest _decodePendingFamilyJoinRequest(Object? response) {
  final object = _strictObject(response, const {
    'requestId',
    'familyId',
    'requesterAccountId',
    'memberId',
    'displayName',
    'demographicRole',
    'colorToken',
    'avatarJson',
    'joiningPublicKey',
    'codeVersion',
    'state',
    'createdAt',
    'expiresAt',
  });
  return PendingFamilyJoinRequest.validated(
    requestId: _uuidField(object, 'requestId'),
    familyId: _uuidField(object, 'familyId'),
    requesterAccountId: _uuidField(object, 'requesterAccountId'),
    memberId: _uuidField(object, 'memberId'),
    displayName: _strictRemoteText(object, 'displayName', maximumLength: 100),
    demographicRole: _familyDemographicRole(object['demographicRole']),
    colorToken: _strictRemoteText(object, 'colorToken', maximumLength: 64),
    avatar: _decodeAvatar(object['avatarJson']),
    joiningPublicKey: _canonicalBytesField(
      object,
      'joiningPublicKey',
      expectedLength: 32,
    ),
    codeVersion: _positiveIntField(object, 'codeVersion'),
    state: _familyJoinRequestState(object['state']),
    createdAt: _timestampField(object, 'createdAt'),
    expiresAt: _timestampField(object, 'expiresAt'),
  );
}

OwnFamilyJoinRequest _decodeOwnFamilyJoinRequest(Object? response) {
  final object = _strictObject(response, const {
    'requestId',
    'familyId',
    'requesterAccountId',
    'memberId',
    'displayName',
    'demographicRole',
    'colorToken',
    'avatarJson',
    'joiningPublicKey',
    'codeVersion',
    'state',
    'createdAt',
    'expiresAt',
    'familyName',
    'cancelReason',
    'approvalEnvelope',
    'roster',
  });
  final requestId = _uuidField(object, 'requestId');
  final familyId = _uuidField(object, 'familyId');
  final requesterAccountId = _uuidField(object, 'requesterAccountId');
  final memberId = _uuidField(object, 'memberId');
  final codeVersion = _positiveIntField(object, 'codeVersion');
  final state = _familyJoinRequestState(object['state']);
  final cancelReason = _familyJoinRequestCancelReason(object['cancelReason']);
  final envelope = object['approvalEnvelope'] == null
      ? null
      : _decodeFamilyApprovalEnvelope(object['approvalEnvelope']);
  final roster = _decodeRoster(object['roster'], familyId: familyId);
  final carriesApproval =
      state == FamilyJoinRequestState.approved ||
      state == FamilyJoinRequestState.installed;
  if (carriesApproval != (envelope != null) ||
      (!carriesApproval && roster.isNotEmpty) ||
      (carriesApproval &&
          (roster.isEmpty || !roster.any((member) => member.id == memberId)))) {
    throw const FormatException('Join request approval projection differs');
  }
  if (envelope != null &&
      (envelope.context.requestId != requestId ||
          envelope.context.familyId != familyId ||
          envelope.context.requesterAccountId != requesterAccountId ||
          envelope.context.codeVersion != codeVersion)) {
    throw const FormatException('Join request envelope context differs');
  }
  return OwnFamilyJoinRequest.validated(
    requestId: requestId,
    familyId: familyId,
    familyName: _strictRemoteText(object, 'familyName', maximumLength: 100),
    requesterAccountId: requesterAccountId,
    memberId: memberId,
    displayName: _strictRemoteText(object, 'displayName', maximumLength: 100),
    demographicRole: _familyDemographicRole(object['demographicRole']),
    colorToken: _strictRemoteText(object, 'colorToken', maximumLength: 64),
    avatar: _decodeAvatar(object['avatarJson']),
    joiningPublicKey: _canonicalBytesField(
      object,
      'joiningPublicKey',
      expectedLength: 32,
    ),
    codeVersion: codeVersion,
    state: state,
    createdAt: _timestampField(object, 'createdAt'),
    expiresAt: _timestampField(object, 'expiresAt'),
    cancelReason: cancelReason,
    approvalEnvelope: envelope,
    roster: roster,
  );
}

FamilyJoinApprovalEnvelope _validatedApprovalEnvelope(
  FamilyJoinApprovalEnvelope envelope,
) {
  try {
    return FamilyJoinApprovalEnvelope.fromJson(envelope.toJson());
  } on Object {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
  }
}

FamilyJoinApprovalEnvelope _decodeFamilyApprovalEnvelope(Object? value) {
  final object = _strictObject(value, const {
    'version',
    'requestId',
    'familyId',
    'requesterAccountId',
    'codeVersion',
    'ephemeralPublicKey',
    'nonce',
    'ciphertext',
    'mac',
  });
  return FamilyJoinApprovalEnvelope.fromJson(object);
}

FamilyJoinDecision _decodeDecision(
  Object? response, {
  required String expectedRequestId,
}) {
  final object = _strictObject(response, const {
    'requestId',
    'familyId',
    'state',
    'updatedAt',
  });
  final requestId = _uuidField(object, 'requestId');
  if (requestId != expectedRequestId) {
    throw const FormatException('Join decision request differs');
  }
  return FamilyJoinDecision.validated(
    requestId: requestId,
    familyId: _uuidField(object, 'familyId'),
    state: _familyJoinRequestState(object['state']),
    updatedAt: _timestampField(object, 'updatedAt'),
  );
}

FamilyDemographicRole _familyDemographicRole(Object? value) => switch (value) {
  'adult' => FamilyDemographicRole.adult,
  'child' => FamilyDemographicRole.child,
  _ => throw const FormatException('Invalid family demographic role'),
};

FamilyJoinRequestState _familyJoinRequestState(Object? value) =>
    switch (value) {
      'pending' => FamilyJoinRequestState.pending,
      'approved' => FamilyJoinRequestState.approved,
      'installed' => FamilyJoinRequestState.installed,
      'declined' => FamilyJoinRequestState.declined,
      'cancelled' => FamilyJoinRequestState.cancelled,
      'expired' => FamilyJoinRequestState.expired,
      _ => throw const FormatException('Invalid family join request state'),
    };

FamilyJoinRequestCancelReason? _familyJoinRequestCancelReason(Object? value) =>
    switch (value) {
      null => null,
      'requester' => FamilyJoinRequestCancelReason.requester,
      'code_regenerated' => FamilyJoinRequestCancelReason.codeRegenerated,
      _ => throw const FormatException('Invalid family join cancel reason'),
    };

int _positiveIntField(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is! int || value <= 0) {
    throw const FormatException('Cloud response integer is invalid');
  }
  return value;
}

String _canonicalBytesField(
  Map<String, Object?> object,
  String field, {
  required int expectedLength,
}) {
  final value = _stringField(object, field);
  final decoded = decodeCanonicalFamilyJoinBase64Url(
    value,
    expectedLength: expectedLength,
    field: field,
  );
  if (unpaddedFamilyJoinBase64Url(decoded) != value) {
    throw const FormatException('Cloud response bytes are invalid');
  }
  return value;
}

void _requireFamilyUuid(String value) {
  if (!isCanonicalFamilyJoinUuid(value)) {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.unknown);
  }
}

String _validatedAuthenticatedAccountId(String? value) {
  if (value == null) {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut);
  }
  _requireFamilyUuid(value);
  return value;
}

String _familyText(String value, {required int maximumLength}) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > maximumLength) {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.unknown);
  }
  return normalized;
}

Map<String, Object> _familyOutgoingAvatar(AvatarConfig avatar) {
  try {
    return _decodeAvatar(avatar.toJson()).toJson();
  } on Object {
    throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
  }
}

Future<T> _guard<T>(
  Future<T> Function() operation, {
  bool mapInvalidOtp = false,
}) async {
  try {
    return await operation();
  } on InvitationFailure {
    rethrow;
  } on SocketException {
    throw const InvitationFailure(InvitationFailureCode.networkUnavailable);
  } on TimeoutException {
    throw const InvitationFailure(InvitationFailureCode.networkUnavailable);
  } on AuthRetryableFetchException {
    throw const InvitationFailure(InvitationFailureCode.networkUnavailable);
  } on AuthUnknownException catch (error) {
    if (error.originalError is SocketException ||
        error.originalError is TimeoutException) {
      throw const InvitationFailure(InvitationFailureCode.networkUnavailable);
    }
    throw const InvitationFailure(InvitationFailureCode.unknown);
  } on AuthSessionMissingException {
    throw const InvitationFailure(InvitationFailureCode.signedOut);
  } on AuthException catch (error) {
    if (error.code == 'email_address_invalid') {
      throw const InvitationFailure(InvitationFailureCode.invalidEmail);
    }
    if (mapInvalidOtp &&
        (error.code == 'otp_expired' || error.code == 'invalid_otp')) {
      throw const InvitationFailure(InvitationFailureCode.invalidOtp);
    }
    throw const InvitationFailure(InvitationFailureCode.unknown);
  } on PostgrestException catch (error) {
    throw _mapPostgrestFailure(error);
  } on Object {
    throw const InvitationFailure(InvitationFailureCode.unknown);
  }
}

InvitationFailure _mapPostgrestFailure(PostgrestException error) {
  if (error.code != 'P0001' || error.details != null || error.hint != null) {
    return const InvitationFailure(InvitationFailureCode.unknown);
  }
  final code = switch (error.message) {
    'SIGNED_OUT' => InvitationFailureCode.signedOut,
    'INVALID_EMAIL' => InvitationFailureCode.invalidEmail,
    'NOT_OWNER' => InvitationFailureCode.notOwner,
    'FORBIDDEN' => InvitationFailureCode.forbidden,
    'INVALID_TOKEN' => InvitationFailureCode.malformedLink,
    'INVITE_NOT_FOUND' => InvitationFailureCode.malformedLink,
    'INVITE_EXPIRED' => InvitationFailureCode.expired,
    'INVITE_REVOKED' => InvitationFailureCode.revoked,
    'ALREADY_CLAIMED' => InvitationFailureCode.alreadyClaimed,
    'EMAIL_MISMATCH' => InvitationFailureCode.emailMismatch,
    'DIFFERENT_FAMILY' => InvitationFailureCode.differentFamily,
    'INVALID_ENVELOPE' => InvitationFailureCode.envelopeRejected,
    _ => InvitationFailureCode.unknown,
  };
  return InvitationFailure(code);
}

String _normalizeEmail(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.length > 254 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
    throw const InvitationFailure(InvitationFailureCode.invalidEmail);
  }
  return normalized;
}

String _validateText(String value, {required int maximumLength}) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > maximumLength) {
    throw const InvitationFailure(InvitationFailureCode.unknown);
  }
  return normalized;
}

void _requireCanonicalUuid(String value) {
  if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      .hasMatch(value)) {
    throw const InvitationFailure(InvitationFailureCode.malformedLink);
  }
}

void _validateCanonicalBytes(String value, {required int expectedLength}) {
  try {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const FormatException('Invalid encoded bytes');
    }
    final decoded = base64Url.decode(base64Url.normalize(value));
    if (decoded.length != expectedLength ||
        base64UrlEncode(decoded).replaceAll('=', '') != value) {
      throw const FormatException('Invalid encoded bytes');
    }
  } on Object {
    throw const InvitationFailure(InvitationFailureCode.envelopeRejected);
  }
}

FamilyInviteLink _validatedLink(FamilyInviteLink link) {
  try {
    return FamilyInviteLink.parse(link.toUri());
  } on FormatException {
    throw const InvitationFailure(InvitationFailureCode.malformedLink);
  }
}

InvitationEnvelope _validatedEnvelope(InvitationEnvelope envelope) {
  try {
    return InvitationEnvelope.fromJson(envelope.toJson());
  } on FormatException {
    throw const InvitationFailure(InvitationFailureCode.envelopeRejected);
  }
}

InvitationEnvelope _decodeRemoteEnvelope(Object? value) {
  try {
    final object = _strictObject(value, const {
      'version',
      'inviteId',
      'familyId',
      'nonce',
      'ciphertext',
      'mac',
    });
    return InvitationEnvelope.fromJson(object);
  } on FormatException {
    throw const InvitationFailure(InvitationFailureCode.envelopeRejected);
  }
}

Map<String, Object> _validatedOutgoingAvatar(AvatarConfig avatar) {
  try {
    return _decodeAvatar(avatar.toJson()).toJson();
  } on FormatException {
    throw const InvitationFailure(InvitationFailureCode.envelopeRejected);
  }
}

List<FamilyMember> _decodeRoster(Object? value, {required String familyId}) {
  if (value is! List<Object?>) {
    throw const FormatException('Family roster must be an array');
  }
  final seenMemberIds = <String>{};
  final members = <FamilyMember>[];
  for (final entry in value) {
    final member = _decodeMember(entry);
    if (member.familyId != familyId || !seenMemberIds.add(member.id)) {
      throw const FormatException('Invalid family roster identifiers');
    }
    members.add(member);
  }
  return List<FamilyMember>.unmodifiable(members);
}

FamilyMember _decodeMember(Object? value) {
  final object = _strictObject(value, const {
    'memberId',
    'familyId',
    'displayName',
    'demographicRole',
    'colorToken',
    'avatarJson',
    'joinedAt',
  });
  final role = switch (_stringField(object, 'demographicRole')) {
    'adult' => FamilyDemographicRole.adult,
    'child' => FamilyDemographicRole.child,
    _ => throw const FormatException('Invalid demographic role'),
  };
  return FamilyMember(
    id: _uuidField(object, 'memberId'),
    familyId: _uuidField(object, 'familyId'),
    name: _strictRemoteText(object, 'displayName', maximumLength: 100),
    role: role.name,
    colorToken: _strictRemoteText(object, 'colorToken', maximumLength: 64),
    avatar: _decodeAvatar(object['avatarJson']),
    joinedAt: _timestampField(object, 'joinedAt'),
  );
}

AvatarConfig _decodeAvatar(Object? value) {
  final object = _strictObject(value, const {
    'schemaVersion',
    'styleId',
    'styleRevision',
    'seed',
    'selections',
    'colors',
  });
  if (object['schemaVersion'] != AvatarConfig.currentSchemaVersion ||
      object['styleId'] != AvatarConfig.currentStyleId ||
      object['styleRevision'] != AvatarConfig.currentStyleRevision) {
    throw const FormatException('Unsupported cloud avatar contract');
  }
  final seed = object['seed'];
  if (seed is! String || seed.isEmpty || seed.trim() != seed) {
    throw const FormatException('Invalid cloud avatar seed');
  }
  final avatar = AvatarConfig(
    schemaVersion: AvatarConfig.currentSchemaVersion,
    styleId: AvatarConfig.currentStyleId,
    styleRevision: AvatarConfig.currentStyleRevision,
    seed: seed,
    selections: _strictStringMap(object['selections']),
    colors: _strictStringMap(object['colors'], colors: true),
  );
  if (!avatarCatalog.isAllowed(avatar)) {
    throw const FormatException('Cloud avatar contains unknown values');
  }
  return avatar;
}

Map<String, String> _strictStringMap(Object? value, {bool colors = false}) {
  if (value is! Map) {
    throw const FormatException('Invalid cloud avatar values');
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! String) {
      throw const FormatException('Invalid cloud avatar value type');
    }
    final key = (entry.key as String).trim().toLowerCase();
    final rawValue = entry.value as String;
    final normalizedValue = colors
        ? AvatarConfig.normalizeHex(rawValue)
        : rawValue.trim();
    if (key.isEmpty ||
        key != entry.key ||
        normalizedValue == null ||
        normalizedValue.isEmpty ||
        normalizedValue != rawValue ||
        result.containsKey(key)) {
      throw const FormatException('Invalid cloud avatar value');
    }
    result[key] = normalizedValue;
  }
  return result;
}

void _validateTransitionAcknowledgement(
  Object? value, {
  required String inviteId,
  required String expectedState,
}) {
  final object = _strictObject(value, const {'inviteId', 'familyId', 'state'});
  if (_uuidField(object, 'inviteId') != inviteId ||
      _stringField(object, 'state') != expectedState) {
    throw const FormatException('Invalid invitation acknowledgement');
  }
  _uuidField(object, 'familyId');
}

Map<String, Object?> _strictObject(Object? value, Set<String> expectedFields) {
  if (value is! Map) {
    throw const FormatException('Cloud response must be an object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('Cloud response has a non-string key');
    }
    result[entry.key as String] = entry.value;
  }
  if (result.length != expectedFields.length ||
      !expectedFields.every(result.containsKey)) {
    throw const FormatException('Cloud response fields differ');
  }
  return result;
}

String _stringField(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is! String) {
    throw const FormatException('Cloud response field must be a string');
  }
  return value;
}

String _strictRemoteText(
  Map<String, Object?> object,
  String field, {
  required int maximumLength,
}) {
  final value = _stringField(object, field);
  if (value.isEmpty || value.length > maximumLength || value.trim() != value) {
    throw const FormatException('Cloud response text is invalid');
  }
  return value;
}

String _uuidField(Map<String, Object?> object, String field) {
  final value = _stringField(object, field);
  if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      .hasMatch(value)) {
    throw const FormatException('Cloud response UUID is invalid');
  }
  return value;
}

DateTime _timestampField(Map<String, Object?> object, String field) {
  final value = _stringField(object, field);
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
    r'(?:\.\d{1,6})?(?:Z|([+-])(\d{2}):(\d{2}))$',
  ).firstMatch(value);
  if (match == null) {
    throw const FormatException('Cloud response timestamp is invalid');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final offsetHour = int.tryParse(match.group(8) ?? '0') ?? -1;
  final offsetMinute = int.tryParse(match.group(9) ?? '0') ?? -1;
  if (year < 1 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > DateTime.utc(year, month + 1, 0).day ||
      hour > 23 ||
      minute > 59 ||
      second > 59 ||
      offsetHour > 23 ||
      offsetMinute > 59) {
    throw const FormatException('Cloud response timestamp is invalid');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('Cloud response timestamp is invalid');
  }
  return parsed.toUtc();
}

CloudInvitationState _invitationState(Object? value) => switch (value) {
  'pending' => CloudInvitationState.pending,
  'claimed' => CloudInvitationState.claimed,
  'accepted' => CloudInvitationState.accepted,
  'revoked' => CloudInvitationState.revoked,
  _ => throw const FormatException('Cloud invitation state is invalid'),
};
