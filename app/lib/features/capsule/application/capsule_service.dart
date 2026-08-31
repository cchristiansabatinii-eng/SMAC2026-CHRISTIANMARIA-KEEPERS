import 'package:keepers/features/capsule/data/capsule_repository.dart';
import 'package:keepers/features/capsule/domain/capsule_models.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/application/vault_controller.dart';
import 'package:keepers/features/vault/data/vault_repository.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

typedef CapsuleMemoryOpener = Future<MemoryOpenResult> Function(
  VaultEntryMetadata metadata,
);

final class CapsuleService {
  const CapsuleService({
    required this.database,
    required this.identity,
    required this.capsuleRepository,
    required this.vaultRepository,
    required this.openMemory,
    required this.utcNow,
  });

  final DatabaseExecutor database;
  final LocalIdentity identity;
  final CapsuleRepository capsuleRepository;
  final VaultRepository vaultRepository;
  final CapsuleMemoryOpener openMemory;
  final DateTime Function() utcNow;

  Future<bool> completeTask(String assignmentId) async {
    final assignment = await capsuleRepository.findForMember(
      database,
      assignmentId: assignmentId,
      familyId: identity.familyId,
      memberId: identity.memberId,
    );
    if (!_belongsToCurrentMember(assignment) ||
        assignment!.unlockTask == null ||
        assignment.state == CapsuleAssignmentState.opened) {
      return assignment?.state == CapsuleAssignmentState.opened &&
          assignment?.unlockTask != null;
    }
    return capsuleRepository.completeTask(
      database,
      assignmentId: assignmentId,
      familyId: identity.familyId,
      memberId: identity.memberId,
    );
  }

  Future<MemoryOpenResult> openForCurrentMember(String assignmentId) async {
    OpenedMemory? opened;
    try {
      final assignment = await capsuleRepository.findForMember(
        database,
        assignmentId: assignmentId,
        familyId: identity.familyId,
        memberId: identity.memberId,
      );
      if (!_belongsToCurrentMember(assignment) ||
          !_canOpen(assignment!.state)) {
        return _unavailable;
      }
      final entry = await vaultRepository.findByIdForFamily(
        database,
        entryId: assignment.contentEntryId,
        familyId: identity.familyId,
      );
      if (!_matchesAssignment(entry, assignment) || _isExpired(entry!)) {
        return _unavailable;
      }
      final result = await openMemory(entry);
      if (result is! OpenedMemory) return _unavailable;
      opened = result;
      if (!_matchesCanonicalEntry(opened.metadata, entry)) {
        _clearPrimary(opened);
        return _unavailable;
      }
      final marked = await capsuleRepository.markOpened(
        database,
        assignmentId: assignment.id,
        familyId: identity.familyId,
        memberId: identity.memberId,
        openedAt: utcNow().toUtc(),
      );
      if (!marked) {
        _clearPrimary(opened);
        return _unavailable;
      }
      return opened;
    } on Object {
      if (opened != null) _clearPrimary(opened);
      return _unavailable;
    }
  }

  bool _belongsToCurrentMember(CapsuleAssignment? assignment) =>
      assignment != null &&
      assignment.familyId == identity.familyId &&
      assignment.targetId == identity.memberId;

  bool _matchesAssignment(
    VaultEntryMetadata? entry,
    CapsuleAssignment assignment,
  ) =>
      entry != null &&
      entry.id == assignment.contentEntryId &&
      entry.familyId == identity.familyId &&
      entry.authorId == assignment.authorId &&
      entry.privacy == PrivacyTier.capsule;

  bool _isExpired(VaultEntryMetadata entry) {
    if (entry.state == 'expired') return true;
    final expiresAt = entry.expiresAt;
    return expiresAt != null && !expiresAt.toUtc().isAfter(utcNow().toUtc());
  }

  static bool _canOpen(CapsuleAssignmentState state) =>
      state == CapsuleAssignmentState.ready ||
      state == CapsuleAssignmentState.opened;

  static bool _matchesCanonicalEntry(
    VaultEntryMetadata opened,
    VaultEntryMetadata canonical,
  ) =>
      opened.id == canonical.id &&
      opened.familyId == canonical.familyId &&
      opened.authorId == canonical.authorId &&
      opened.createdAt.isAtSameMomentAs(canonical.createdAt) &&
      opened.format == canonical.format &&
      opened.privacy == canonical.privacy &&
      opened.blobRef == canonical.blobRef &&
      opened.state == canonical.state &&
      _sameInstant(opened.expiresAt, canonical.expiresAt);

  static bool _sameInstant(DateTime? left, DateTime? right) => left == null
      ? right == null
      : right != null && left.isAtSameMomentAs(right);

  static void _clearPrimary(OpenedMemory memory) {
    final primary = memory.payload.primaryBytes;
    primary?.fillRange(0, primary.length, 0);
  }

  static const _unavailable = UnavailableMemory(
    VaultController.unavailableMessage,
  );
}
