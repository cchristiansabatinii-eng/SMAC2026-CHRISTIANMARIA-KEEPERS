import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';

void main() {
  test('approval envelope round-trips only its exact wire shape', () {
    const requestId = '11111111-1111-4111-8111-111111111111';
    const validEnvelopeJson = <String, Object?>{
      'version': 1,
      'requestId': requestId,
      'familyId': '22222222-2222-4222-8222-222222222222',
      'requesterAccountId': '33333333-3333-4333-8333-333333333333',
      'codeVersion': 1,
      'ephemeralPublicKey': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      'nonce': 'ICEiIyQlJicoKSor',
      'ciphertext': 'QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8',
      'mac': 'YGFiY2RlZmdoaWprbG1ubw',
    };

    final envelope = FamilyJoinApprovalEnvelope.fromJson(validEnvelopeJson);

    expect(envelope.context.requestId, requestId);
    expect(envelope.toJson().keys, {
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
    expect(envelope.toString(), 'FamilyJoinApprovalEnvelope(<redacted>)');
  });

  test(
    'validated profile rejects noncanonical identity and avatar material',
    () {
      expect(
        () => FamilyJoinProfileDraft.validated(
          memberId: 'not-a-uuid',
          displayName: 'Noura',
          demographicRole: FamilyDemographicRole.adult,
          colorToken: 'coral',
          avatar: const AvatarConfig.defaults(seed: 'noura'),
          joiningPublicKey: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
        ),
        throwsArgumentError,
      );
      expect(
        () => FamilyJoinProfileDraft.validated(
          memberId: '11111111-1111-4111-8111-111111111111',
          displayName: 'Noura',
          demographicRole: FamilyDemographicRole.adult,
          colorToken: 'coral',
          avatar: AvatarConfig(
            schemaVersion: 99,
            styleId: AvatarConfig.currentStyleId,
            styleRevision: AvatarConfig.currentStyleRevision,
            seed: 'noura',
            selections: const {},
            colors: const {},
          ),
          joiningPublicKey: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
        ),
        throwsArgumentError,
      );
    },
  );

  test('validating factories protect every join-request model invariant', () {
    const requestId = '11111111-1111-4111-8111-111111111111';
    const familyId = '22222222-2222-4222-8222-222222222222';
    const accountId = '33333333-3333-4333-8333-333333333333';
    const memberId = '44444444-4444-4444-8444-444444444444';
    const publicKey = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
    const nonce = 'ICEiIyQlJicoKSor';
    const mac = 'YGFiY2RlZmdoaWprbG1ubw';
    const avatar = AvatarConfig.defaults(seed: 'noura');
    final now = DateTime.utc(2026, 9, 7);
    final member = FamilyMember(
      id: memberId,
      familyId: familyId,
      name: 'Noura',
      role: 'adult',
      colorToken: 'coral',
      avatar: avatar,
      joinedAt: now,
    );
    final profile = FamilyJoinProfileDraft.validated(
      memberId: memberId,
      displayName: 'Noura',
      demographicRole: FamilyDemographicRole.adult,
      colorToken: 'coral',
      avatar: avatar,
      joiningPublicKey: publicKey,
    );
    final context = JoinEnvelopeContext.validated(
      requestId: requestId,
      familyId: familyId,
      requesterAccountId: accountId,
      codeVersion: 1,
    );
    final envelope = FamilyJoinApprovalEnvelope.validated(
      version: 1,
      context: context,
      ephemeralPublicKey: publicKey,
      nonce: nonce,
      ciphertext: publicKey,
      mac: mac,
    );

    expect(
      FamilyJoinPreview.validated(
        familyId: familyId,
        familyName: 'The Keepers',
        codeVersion: 1,
        members: <FamilyMember>[member],
      ).members,
      <FamilyMember>[member],
    );
    expect(
      FamilyJoinRequestDraft.validated(
        code: FamilyCode.parse('K7M4-P2Q8'),
        profile: profile,
      ).profile,
      profile,
    );
    expect(
      PendingFamilyJoinRequest.validated(
        requestId: requestId,
        familyId: familyId,
        requesterAccountId: accountId,
        memberId: memberId,
        displayName: 'Noura',
        demographicRole: FamilyDemographicRole.adult,
        colorToken: 'coral',
        avatar: avatar,
        joiningPublicKey: publicKey,
        codeVersion: 1,
        state: FamilyJoinRequestState.pending,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 7)),
      ).requestId,
      requestId,
    );
    expect(
      OwnFamilyJoinRequest.validated(
        requestId: requestId,
        familyId: familyId,
        familyName: 'The Keepers',
        requesterAccountId: accountId,
        memberId: memberId,
        displayName: 'Noura',
        demographicRole: FamilyDemographicRole.adult,
        colorToken: 'coral',
        avatar: avatar,
        joiningPublicKey: publicKey,
        codeVersion: 1,
        state: FamilyJoinRequestState.approved,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 7)),
        approvalEnvelope: envelope,
        roster: <FamilyMember>[member],
      ).approvalEnvelope,
      envelope,
    );
    expect(
      FamilyJoinDecision.validated(
        requestId: requestId,
        familyId: familyId,
        state: FamilyJoinRequestState.approved,
        updatedAt: now,
      ).state,
      FamilyJoinRequestState.approved,
    );
    expect(
      ApprovedFamilyJoin.validated(
        requestId: requestId,
        familyId: familyId,
        familyName: 'The Keepers',
        localMemberId: memberId,
        joiningPublicKey: publicKey,
        approvalEnvelope: envelope,
        roster: <FamilyMember>[member],
      ).roster,
      <FamilyMember>[member],
    );
    expect(
      () => PendingFamilyJoinRequest.validated(
        requestId: requestId,
        familyId: familyId,
        requesterAccountId: accountId,
        memberId: memberId,
        displayName: 'Noura',
        demographicRole: FamilyDemographicRole.adult,
        colorToken: 'coral',
        avatar: avatar,
        joiningPublicKey: publicKey,
        codeVersion: 0,
        state: FamilyJoinRequestState.pending,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 7)),
      ),
      throwsArgumentError,
    );
  });

  test('strict approval envelopes reject malformed canonical fields', () {
    const valid = <String, Object?>{
      'version': 1,
      'requestId': '11111111-1111-4111-8111-111111111111',
      'familyId': '22222222-2222-4222-8222-222222222222',
      'requesterAccountId': '33333333-3333-4333-8333-333333333333',
      'codeVersion': 1,
      'ephemeralPublicKey': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      'nonce': 'ICEiIyQlJicoKSor',
      'ciphertext': 'QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8',
      'mac': 'YGFiY2RlZmdoaWprbG1ubw',
    };
    for (final json in <Map<String, Object?>>[
      <String, Object?>{...valid, 'codeVersion': 0},
      <String, Object?>{
        ...valid,
        'familyId': 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',
      },
      <String, Object?>{...valid, 'ephemeralPublicKey': 'short'},
      <String, Object?>{...valid}..['extra'] = true,
    ]) {
      expect(
        () => FamilyJoinApprovalEnvelope.fromJson(json),
        throwsFormatException,
      );
    }
  });
}
