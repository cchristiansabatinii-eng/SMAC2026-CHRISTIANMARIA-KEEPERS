import 'dart:async';

import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/domain/family_member.dart';

abstract interface class CloudFamilyGateway {
  bool get isConfigured;

  String? get authenticatedAccountId;

  String? get authenticatedEmail;

  Future<void> requestEmailOtp(String email);

  Future<void> verifyEmailOtp({required String email, required String token});

  Future<void> bootstrapOwner(LocalOwnerFamily owner);

  Future<CreatedInvitation> createInvitation(CloudInvitationDraft draft);

  Future<InvitePreview> previewInvitation(FamilyInviteLink link);

  Future<ClaimedFamily> claimInvitation(JoinRequest request);

  Future<void> completeInvitation(String inviteId);

  Future<void> revokeInvitation(String inviteId);

  Future<List<FamilyMember>> listActiveMembers(String familyId);
}

/// Optional capability implemented by gateways whose authentication can
/// complete outside the app, such as a Supabase email sign-in link.
abstract interface class CloudFamilyAuthEvents {
  Stream<void> get signedInEvents;
}

/// Independent family-code join capability for gateways that support it.
abstract interface class FamilyCodeJoinGateway {
  bool get isConfigured;

  String? get authenticatedAccountId;

  Future<EncryptedFamilyCodeRecord> bootstrapOwnerWithFamilyCode(
    LocalOwnerFamily owner,
    FamilyCodeDraft code,
  );

  Future<EncryptedFamilyCodeRecord> getFamilyCode(String familyId);

  Future<FamilyJoinPreview> previewFamilyByCode(FamilyCode code);

  Future<OwnFamilyJoinRequest> createFamilyJoinRequest(
    FamilyJoinRequestDraft draft,
  );

  Future<List<PendingFamilyJoinRequest>> listPendingJoinRequests(
    String familyId,
  );

  Future<OwnFamilyJoinRequest?> getOwnJoinRequest();

  Future<FamilyJoinDecision> approveJoinRequest(
    String requestId,
    FamilyJoinApprovalEnvelope envelope,
  );

  Future<FamilyJoinDecision> declineJoinRequest(String requestId);

  Future<FamilyJoinDecision> cancelJoinRequest(String requestId);

  Future<FamilyJoinDecision> completeJoinRequest(String requestId);

  Future<EncryptedFamilyCodeRecord> regenerateFamilyCode({
    required String familyId,
    required int expectedVersion,
    required FamilyCodeDraft replacement,
  });

  Stream<void> watchOwnJoinRequest();

  Stream<void> watchPendingJoinRequests(String familyId);
}
