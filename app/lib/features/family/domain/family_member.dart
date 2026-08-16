import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';

final class ClaimedFamily {
  ClaimedFamily({
    required this.familyId,
    required this.familyName,
    required this.localMemberId,
    required this.envelope,
    required List<FamilyMember> members,
  }) : members = List<FamilyMember>.unmodifiable(members);

  final String familyId;
  final String familyName;
  final String localMemberId;
  final InvitationEnvelope envelope;
  final List<FamilyMember> members;
}

final class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.familyId,
    required this.name,
    required this.role,
    required this.colorToken,
    required this.avatar,
    required this.joinedAt,
  });

  final String id;
  final String familyId;
  final String name;
  final String role;
  final String colorToken;
  final AvatarConfig avatar;
  final DateTime joinedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyMember &&
          other.id == id &&
          other.familyId == familyId &&
          other.name == name &&
          other.role == role &&
          other.colorToken == colorToken &&
          other.avatar == avatar &&
          other.joinedAt == joinedAt;

  @override
  int get hashCode =>
      Object.hash(id, familyId, name, role, colorToken, avatar, joinedAt);
}
