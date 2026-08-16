import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/domain/family_member.dart';

final class UnavailableCloudFamilyGateway implements CloudFamilyGateway {
  const UnavailableCloudFamilyGateway();

  static const _failure = InvitationFailure(
    InvitationFailureCode.notConfigured,
  );

  @override
  bool get isConfigured => false;

  @override
  String? get authenticatedAccountId => null;

  @override
  String? get authenticatedEmail => null;

  @override
  Future<void> requestEmailOtp(String email) => Future<void>.error(_failure);

  @override
  Future<void> verifyEmailOtp({required String email, required String token}) =>
      Future<void>.error(_failure);

  @override
  Future<void> bootstrapOwner(LocalOwnerFamily owner) =>
      Future<void>.error(_failure);

  @override
  Future<CreatedInvitation> createInvitation(CloudInvitationDraft draft) =>
      Future<CreatedInvitation>.error(_failure);

  @override
  Future<InvitePreview> previewInvitation(FamilyInviteLink link) =>
      Future<InvitePreview>.error(_failure);

  @override
  Future<ClaimedFamily> claimInvitation(JoinRequest request) =>
      Future<ClaimedFamily>.error(_failure);

  @override
  Future<void> completeInvitation(String inviteId) =>
      Future<void>.error(_failure);

  @override
  Future<void> revokeInvitation(String inviteId) =>
      Future<void>.error(_failure);

  @override
  Future<List<FamilyMember>> listActiveMembers(String familyId) =>
      Future<List<FamilyMember>>.error(_failure);
}

final class UnavailableFamilyCodeJoinGateway implements FamilyCodeJoinGateway {
  const UnavailableFamilyCodeJoinGateway();

  static const _failure = FamilyJoinFailure(
    FamilyJoinFailureCode.notConfigured,
  );

  @override
  bool get isConfigured => false;

  @override
  String? get authenticatedAccountId => null;

  @override
  Future<EncryptedFamilyCodeRecord> bootstrapOwnerWithFamilyCode(
    LocalOwnerFamily owner,
    FamilyCodeDraft code,
  ) => Future<EncryptedFamilyCodeRecord>.error(_failure);

  @override
  Future<EncryptedFamilyCodeRecord> getFamilyCode(String familyId) =>
      Future<EncryptedFamilyCodeRecord>.error(_failure);

  @override
  Future<FamilyJoinPreview> previewFamilyByCode(FamilyCode code) =>
      Future<FamilyJoinPreview>.error(_failure);

  @override
  Future<OwnFamilyJoinRequest> createFamilyJoinRequest(
    FamilyJoinRequestDraft draft,
  ) => Future<OwnFamilyJoinRequest>.error(_failure);

  @override
  Future<List<PendingFamilyJoinRequest>> listPendingJoinRequests(
    String familyId,
  ) => Future<List<PendingFamilyJoinRequest>>.error(_failure);

  @override
  Future<OwnFamilyJoinRequest?> getOwnJoinRequest() =>
      Future<OwnFamilyJoinRequest?>.error(_failure);

  @override
  Future<FamilyJoinDecision> approveJoinRequest(
    String requestId,
    FamilyJoinApprovalEnvelope envelope,
  ) => Future<FamilyJoinDecision>.error(_failure);

  @override
  Future<FamilyJoinDecision> declineJoinRequest(String requestId) =>
      Future<FamilyJoinDecision>.error(_failure);

  @override
  Future<FamilyJoinDecision> cancelJoinRequest(String requestId) =>
      Future<FamilyJoinDecision>.error(_failure);

  @override
  Future<FamilyJoinDecision> completeJoinRequest(String requestId) =>
      Future<FamilyJoinDecision>.error(_failure);

  @override
  Future<EncryptedFamilyCodeRecord> regenerateFamilyCode({
    required String familyId,
    required int expectedVersion,
    required FamilyCodeDraft replacement,
  }) => Future<EncryptedFamilyCodeRecord>.error(_failure);

  @override
  Stream<void> watchOwnJoinRequest() => const Stream<void>.empty();

  @override
  Stream<void> watchPendingJoinRequests(String familyId) =>
      const Stream<void>.empty();
}
