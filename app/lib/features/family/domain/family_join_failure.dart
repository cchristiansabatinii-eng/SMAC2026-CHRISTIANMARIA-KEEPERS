enum FamilyJoinFailureCode {
  notConfigured,
  signedOut,
  networkUnavailable,
  familyNotFound,
  alreadyMember,
  requestAlreadyPending,
  requestExpired,
  requestDeclined,
  requestCancelled,
  invitationChanged,
  codeCollision,
  codeVersionChanged,
  rateLimited,
  invalidJoinKey,
  notCreator,
  forbidden,
  envelopeRejected,
  localPersistenceFailed,
  unknown,
}

final class FamilyJoinFailure implements Exception {
  const FamilyJoinFailure(this.code);

  final FamilyJoinFailureCode code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyJoinFailure && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'FamilyJoinFailure(${code.name})';
}
