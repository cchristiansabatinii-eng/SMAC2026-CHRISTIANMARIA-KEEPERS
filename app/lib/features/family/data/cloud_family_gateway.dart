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

/// Optional capability for gateways that report changes to the active account.
///
/// Unlike [CloudFamilyAuthEvents], this includes session loss and switching
/// from one authenticated account to another.
abstract interface class CloudFamilyAccountSessionEvents {
  Stream<String?> get accountSessionChangedEvents;
}

/// Optional capability for gateways that can end the current account session.
abstract interface class CloudFamilyAccountSession {
  Future<void> signOut();
}

enum SocialAuthProvider { google, microsoft, apple }

/// Optional account-authentication capability for gateways that support
/// browser-based identity providers.
abstract interface class CloudFamilySocialAuth {
  Future<void> signInWithProvider(SocialAuthProvider provider);

  /// Abandons the outstanding browser flow before another PKCE method starts.
  /// Returns false when its callback has already checked out the verifier and
  /// therefore must finish as the sole in-flight authentication attempt.
  Future<bool> cancelPendingProviderSignIn();

  /// Clears PKCE state after the SDK reports that callback processing ended
  /// in failure. Returns false when the error did not belong to the current
  /// attempt, so a stale callback cannot release a newer PKCE verifier.
  Future<bool> clearFailedProviderSignIn();
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
