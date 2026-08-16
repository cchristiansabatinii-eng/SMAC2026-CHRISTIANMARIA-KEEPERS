import 'package:keepers/features/members/domain/avatar_config.dart';

const setupNameMaxLength = 100;

final class SetupInput {
  const SetupInput({required this.familyName, required this.memberName});

  final String familyName;
  final String memberName;

  String? get validationMessage {
    final normalizedFamilyName = familyName.trim();
    final normalizedMemberName = memberName.trim();
    if (normalizedFamilyName.isEmpty || normalizedMemberName.isEmpty) {
      return 'Enter both names';
    }
    if (normalizedFamilyName.length > setupNameMaxLength ||
        normalizedMemberName.length > setupNameMaxLength) {
      return 'Names can be up to $setupNameMaxLength characters';
    }
    return null;
  }

  bool get isValid => validationMessage == null;
}

final class CreatedIdentityKeys {
  const CreatedIdentityKeys({
    required this.familyKeyRef,
    required this.memberKeyRef,
  });

  final String familyKeyRef;
  final String memberKeyRef;
}

final class LocalIdentity {
  const LocalIdentity({
    required this.familyId,
    required this.familyName,
    required this.familyKeyRef,
    required this.memberId,
    required this.memberName,
    required this.memberKeyRef,
    required this.colorToken,
    required this.avatar,
    this.accountId,
  });

  final String familyId;
  final String familyName;
  final String familyKeyRef;
  final String memberId;
  final String memberName;
  final String memberKeyRef;
  final String colorToken;
  final AvatarConfig avatar;
  final String? accountId;

  @override
  bool operator ==(Object other) =>
      other is LocalIdentity &&
      other.familyId == familyId &&
      other.familyName == familyName &&
      other.familyKeyRef == familyKeyRef &&
      other.memberId == memberId &&
      other.memberName == memberName &&
      other.memberKeyRef == memberKeyRef &&
      other.colorToken == colorToken &&
      other.avatar == avatar &&
      other.accountId == accountId;

  @override
  int get hashCode => Object.hash(
    familyId,
    familyName,
    familyKeyRef,
    memberId,
    memberName,
    memberKeyRef,
    colorToken,
    avatar,
    accountId,
  );
}
