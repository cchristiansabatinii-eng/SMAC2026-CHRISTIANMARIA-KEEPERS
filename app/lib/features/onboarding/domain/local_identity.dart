final class SetupInput {
  const SetupInput({required this.familyName, required this.memberName});

  final String familyName;
  final String memberName;

  bool get isValid =>
      familyName.trim().isNotEmpty && memberName.trim().isNotEmpty;
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
  });

  final String familyId;
  final String familyName;
  final String familyKeyRef;
  final String memberId;
  final String memberName;
  final String memberKeyRef;
  final String colorToken;

  @override
  bool operator ==(Object other) =>
      other is LocalIdentity &&
      other.familyId == familyId &&
      other.familyName == familyName &&
      other.familyKeyRef == familyKeyRef &&
      other.memberId == memberId &&
      other.memberName == memberName &&
      other.memberKeyRef == memberKeyRef &&
      other.colorToken == colorToken;

  @override
  int get hashCode => Object.hash(
    familyId,
    familyName,
    familyKeyRef,
    memberId,
    memberName,
    memberKeyRef,
    colorToken,
  );
}
