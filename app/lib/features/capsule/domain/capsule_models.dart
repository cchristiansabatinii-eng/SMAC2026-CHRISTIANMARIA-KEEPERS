final class CapsuleAssignment {
  const CapsuleAssignment({
    required this.id,
    required this.familyId,
    required this.authorId,
    required this.targetId,
    required this.contentEntryId,
    required this.unlockTask,
    required this.state,
    required this.createdAt,
    required this.openedAt,
  });

  final String id;
  final String familyId;
  final String authorId;
  final String targetId;
  final String contentEntryId;
  final String? unlockTask;
  final CapsuleAssignmentState state;
  final DateTime createdAt;
  final DateTime? openedAt;

  @override
  bool operator ==(Object other) =>
      other is CapsuleAssignment &&
      other.id == id &&
      other.familyId == familyId &&
      other.authorId == authorId &&
      other.targetId == targetId &&
      other.contentEntryId == contentEntryId &&
      other.unlockTask == unlockTask &&
      other.state == state &&
      other.createdAt == createdAt &&
      other.openedAt == openedAt;

  @override
  int get hashCode => Object.hash(
    id,
    familyId,
    authorId,
    targetId,
    contentEntryId,
    unlockTask,
    state,
    createdAt,
    openedAt,
  );
}

enum CapsuleAssignmentState { locked, ready, opened }
