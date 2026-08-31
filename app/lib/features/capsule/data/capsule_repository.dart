import 'package:keepers/features/capsule/domain/capsule_models.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class CapsuleRepository {
  const CapsuleRepository();

  Future<List<CapsuleAssignment>> insertAssignments(
    DatabaseExecutor db, {
    required EntryMetadata entry,
    required CapsuleSaveOptions options,
  }) async {
    if (entry.privacy != PrivacyTier.capsule) {
      throw ArgumentError.value(
        entry.privacy,
        'entry',
        'Capsule assignments require Capsule privacy',
      );
    }

    final entryRows = await db.query(
      'entries',
      columns: const ['family_id', 'author_id', 'privacy_tier'],
      where: 'id = ?',
      whereArgs: [entry.id],
      limit: 1,
    );
    if (entryRows.length != 1) {
      throw StateError('Capsule assignments require a persisted entry');
    }
    final persistedEntry = entryRows.single;
    if (persistedEntry['family_id'] != entry.familyId ||
        persistedEntry['author_id'] != entry.authorId ||
        persistedEntry['privacy_tier'] != PrivacyTier.capsule.storageValue) {
      throw StateError('Capsule entry metadata does not match persistence');
    }

    final memberRows = await db.query(
      'members',
      columns: const ['id'],
      where: 'family_id = ?',
      whereArgs: [entry.familyId],
      orderBy: 'created_at ASC, id ASC',
    );
    if (!memberRows.any((row) => row['id'] == entry.authorId)) {
      throw StateError('Capsule author is not in the persisted family roster');
    }

    final task = options.unlockTask;
    final triggerType = task == null ? 'shelf' : 'milestone';
    final state = task == null
        ? CapsuleAssignmentState.ready
        : CapsuleAssignmentState.locked;
    final createdAt = entry.createdAt.toUtc();
    final assignments = <CapsuleAssignment>[];
    for (final memberRow in memberRows) {
      final targetId = memberRow['id']! as String;
      final assignment = CapsuleAssignment(
        id: _assignmentId(entry.id, targetId),
        familyId: entry.familyId,
        authorId: entry.authorId,
        targetId: targetId,
        contentEntryId: entry.id,
        unlockTask: task,
        state: state,
        createdAt: createdAt,
        openedAt: null,
      );
      await db.insert('capsules', {
        'id': assignment.id,
        'family_id': assignment.familyId,
        'author_id': assignment.authorId,
        'target_id': assignment.targetId,
        'content_entry_id': assignment.contentEntryId,
        'trigger_type': triggerType,
        'trigger_value': assignment.unlockTask,
        'state': assignment.state.name,
        'created_at': assignment.createdAt.millisecondsSinceEpoch,
        'opened_at': null,
      });
      assignments.add(assignment);
    }
    return List<CapsuleAssignment>.unmodifiable(assignments);
  }

  Future<List<CapsuleAssignment>> listForMember(
    DatabaseExecutor db, {
    required String familyId,
    required String memberId,
  }) async {
    final rows = await db.query(
      'capsules',
      where:
          'family_id = ? AND target_id = ? '
          "AND trigger_type IN ('shelf', 'milestone')",
      whereArgs: [familyId, memberId],
      orderBy: 'created_at DESC, id ASC',
    );
    return List<CapsuleAssignment>.unmodifiable(rows.map(_decode));
  }

  Future<CapsuleAssignment?> findForMember(
    DatabaseExecutor db, {
    required String assignmentId,
    required String familyId,
    required String memberId,
  }) async {
    final rows = await db.query(
      'capsules',
      where:
          'id = ? AND family_id = ? AND target_id = ? '
          "AND trigger_type IN ('shelf', 'milestone')",
      whereArgs: [assignmentId, familyId, memberId],
      limit: 1,
    );
    return rows.isEmpty ? null : _decode(rows.single);
  }

  Future<bool> completeTask(
    DatabaseExecutor db, {
    required String assignmentId,
    required String familyId,
    required String memberId,
  }) async {
    final updated = await db.update(
      'capsules',
      {'state': CapsuleAssignmentState.ready.name},
      where:
          'id = ? AND family_id = ? AND target_id = ? '
          'AND trigger_type = ? AND state = ?',
      whereArgs: [
        assignmentId,
        familyId,
        memberId,
        'milestone',
        CapsuleAssignmentState.locked.name,
      ],
    );
    if (updated == 1) return true;
    if (updated != 0) {
      throw StateError('Expected at most one Capsule assignment update');
    }
    final current = await findForMember(
      db,
      assignmentId: assignmentId,
      familyId: familyId,
      memberId: memberId,
    );
    return current?.unlockTask != null &&
        (current!.state == CapsuleAssignmentState.ready ||
            current.state == CapsuleAssignmentState.opened);
  }

  Future<bool> markOpened(
    DatabaseExecutor db, {
    required String assignmentId,
    required String familyId,
    required String memberId,
    required DateTime openedAt,
  }) async {
    final updated = await db.update(
      'capsules',
      {
        'state': CapsuleAssignmentState.opened.name,
        'opened_at': openedAt.toUtc().millisecondsSinceEpoch,
      },
      where:
          'id = ? AND family_id = ? AND target_id = ? '
          'AND state = ?',
      whereArgs: [
        assignmentId,
        familyId,
        memberId,
        CapsuleAssignmentState.ready.name,
      ],
    );
    if (updated == 1) return true;
    if (updated != 0) {
      throw StateError('Expected at most one Capsule assignment update');
    }
    final current = await findForMember(
      db,
      assignmentId: assignmentId,
      familyId: familyId,
      memberId: memberId,
    );
    return current?.state == CapsuleAssignmentState.opened;
  }

  CapsuleAssignment _decode(Map<String, Object?> row) {
    final triggerType = row['trigger_type'];
    final triggerValue = row['trigger_value'];
    final unlockTask = switch (triggerType) {
      'shelf' when triggerValue == null => null,
      'milestone'
          when triggerValue is String &&
              triggerValue == triggerValue.trim() &&
              triggerValue.isNotEmpty &&
              triggerValue.length <= CapsuleSaveOptions.maxTaskCharacters =>
        triggerValue,
      _ => throw const FormatException('Invalid Capsule trigger'),
    };
    final state = switch (row['state']) {
      'locked' => CapsuleAssignmentState.locked,
      'ready' => CapsuleAssignmentState.ready,
      'opened' => CapsuleAssignmentState.opened,
      _ => throw const FormatException('Invalid Capsule assignment state'),
    };
    final createdAt = row['created_at'];
    final openedAt = row['opened_at'];
    if (createdAt is! int || (openedAt != null && openedAt is! int)) {
      throw const FormatException('Invalid Capsule assignment timestamp');
    }
    return CapsuleAssignment(
      id: row['id']! as String,
      familyId: row['family_id']! as String,
      authorId: row['author_id']! as String,
      targetId: row['target_id']! as String,
      contentEntryId: row['content_entry_id']! as String,
      unlockTask: unlockTask,
      state: state,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true),
      openedAt: openedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(openedAt as int, isUtc: true),
    );
  }

  String _assignmentId(String entryId, String targetId) =>
      'capsule:${entryId.length}:$entryId:${targetId.length}:$targetId';
}
