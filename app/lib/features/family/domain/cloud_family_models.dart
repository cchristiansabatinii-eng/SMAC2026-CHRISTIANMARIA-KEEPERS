import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';

enum FamilyDemographicRole { adult, child }

enum CloudInvitationState { pending, claimed, accepted, revoked }

final class LocalOwnerFamily {
  const LocalOwnerFamily({
    required this.familyId,
    required this.familyName,
    required this.memberId,
    required this.displayName,
    required this.demographicRole,
    required this.colorToken,
    required this.avatar,
  });

  final String familyId;
  final String familyName;
  final String memberId;
  final String displayName;
  final FamilyDemographicRole demographicRole;
  final String colorToken;
  final AvatarConfig avatar;
}

final class CloudInvitationDraft {
  const CloudInvitationDraft({
    required this.inviteId,
    required this.familyId,
    required this.recipientEmail,
    required this.tokenHash,
    required this.envelope,
  });

  final String inviteId;
  final String familyId;
  final String recipientEmail;
  final String tokenHash;
  final InvitationEnvelope envelope;
}

final class CreatedInvitation {
  CreatedInvitation({
    required this.inviteId,
    required this.familyId,
    required this.state,
    required DateTime createdAt,
    required DateTime expiresAt,
  }) : createdAt = createdAt.toUtc(),
       expiresAt = expiresAt.toUtc();

  final String inviteId;
  final String familyId;
  final CloudInvitationState state;
  final DateTime createdAt;
  final DateTime expiresAt;
}

final class InvitePreview {
  InvitePreview({
    required this.inviteId,
    required this.familyId,
    required this.familyName,
    required this.ownerName,
    required DateTime expiresAt,
    required this.state,
  }) : expiresAt = expiresAt.toUtc();

  final String inviteId;
  final String familyId;
  final String familyName;
  final String ownerName;
  final DateTime expiresAt;
  final CloudInvitationState state;
}

final class JoinRequest {
  const JoinRequest({
    required this.link,
    required this.memberId,
    required this.displayName,
    required this.demographicRole,
    required this.colorToken,
    required this.avatar,
  });

  final FamilyInviteLink link;
  final String memberId;
  final String displayName;
  final FamilyDemographicRole demographicRole;
  final String colorToken;
  final AvatarConfig avatar;
}
