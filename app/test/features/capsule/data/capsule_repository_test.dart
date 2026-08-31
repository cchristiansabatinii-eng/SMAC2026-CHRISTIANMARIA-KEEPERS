import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capsule/data/capsule_repository.dart';
import 'package:keepers/features/capsule/domain/capsule_models.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  const repository = CapsuleRepository();

  setUp(() async {
    database = await _openDatabase();
    await _seedRosterAndEntry(database);
  });

  tearDown(() => database.close());

  test('save options trim tasks and reject invalid configured text', () {
    expect(CapsuleSaveOptions().unlockTask, isNull);
    expect(
      CapsuleSaveOptions(unlockTask: '  Call Grandma together  ').unlockTask,
      'Call Grandma together',
    );
    for (final invalid in ['', '   ', ''.padRight(181, 'x')]) {
      expect(
        () => CapsuleSaveOptions(unlockTask: invalid),
        throwsArgumentError,
        reason:
            'Unexpectedly accepted a configured task of length '
            '${invalid.length}',
      );
    }
  });

  test(
    'task Capsule creates one locked assignment for every roster member',
    () async {
      final assignments = await repository.insertAssignments(
        database,
        entry: _entry,
        options: CapsuleSaveOptions(unlockTask: '  Share one family story  '),
      );

      expect(assignments.map((assignment) => assignment.targetId), [
        'member-1',
        'member-2',
      ]);
      expect(assignments.map((assignment) => assignment.state).toSet(), {
        CapsuleAssignmentState.locked,
      });
      expect(assignments.map((assignment) => assignment.unlockTask).toSet(), {
        'Share one family story',
      });
      expect(
        assignments.map((assignment) => assignment.id).toSet(),
        hasLength(2),
      );

      final rows = await database.query('capsules', orderBy: 'target_id ASC');
      expect(rows.map((row) => row['trigger_type']).toSet(), {'milestone'});
      expect(rows.map((row) => row['trigger_value']).toSet(), {
        'Share one family story',
      });
      expect(rows.map((row) => row['state']).toSet(), {'locked'});

      final currentMember = await repository.listForMember(
        database,
        familyId: 'family-1',
        memberId: 'member-2',
      );
      expect(currentMember, [
        assignments.singleWhere((item) => item.targetId == 'member-2'),
      ]);
    },
  );

  test('taskless Capsule creates ready shelf assignments', () async {
    final assignments = await repository.insertAssignments(
      database,
      entry: _entry,
      options: CapsuleSaveOptions(),
    );

    expect(assignments.map((assignment) => assignment.state).toSet(), {
      CapsuleAssignmentState.ready,
    });
    expect(
      assignments.every((assignment) => assignment.unlockTask == null),
      isTrue,
    );
    final rows = await database.query('capsules');
    expect(rows.map((row) => row['trigger_type']).toSet(), {'shelf'});
    expect(rows.every((row) => row['trigger_value'] == null), isTrue);
    expect(rows.map((row) => row['state']).toSet(), {'ready'});
  });

  test('completion and opening are member-scoped and idempotent', () async {
    final assignments = await repository.insertAssignments(
      database,
      entry: _entry,
      options: CapsuleSaveOptions(unlockTask: 'Tell the story'),
    );
    final memberTwo = assignments.singleWhere(
      (assignment) => assignment.targetId == 'member-2',
    );
    final memberOne = assignments.singleWhere(
      (assignment) => assignment.targetId == 'member-1',
    );

    expect(
      await repository.completeTask(
        database,
        assignmentId: memberTwo.id,
        familyId: 'family-1',
        memberId: 'member-1',
      ),
      isFalse,
    );
    expect(
      await repository.completeTask(
        database,
        assignmentId: memberTwo.id,
        familyId: 'family-1',
        memberId: 'member-2',
      ),
      isTrue,
    );
    expect(
      await repository.completeTask(
        database,
        assignmentId: memberTwo.id,
        familyId: 'family-1',
        memberId: 'member-2',
      ),
      isTrue,
    );
    expect(
      (await repository.findForMember(
        database,
        assignmentId: memberTwo.id,
        familyId: 'family-1',
        memberId: 'member-2',
      ))!.state,
      CapsuleAssignmentState.ready,
    );
    expect(
      await repository.markOpened(
        database,
        assignmentId: memberOne.id,
        familyId: 'family-1',
        memberId: 'member-1',
        openedAt: DateTime.utc(2026, 9, 2),
      ),
      isFalse,
    );

    expect(
      await repository.markOpened(
        database,
        assignmentId: memberTwo.id,
        familyId: 'family-1',
        memberId: 'member-2',
        openedAt: DateTime.utc(2026, 9, 2),
      ),
      isTrue,
    );
    expect(
      await repository.markOpened(
        database,
        assignmentId: memberTwo.id,
        familyId: 'family-1',
        memberId: 'member-2',
        openedAt: DateTime.utc(2026, 9, 3),
      ),
      isTrue,
    );
    final opened = await repository.findForMember(
      database,
      assignmentId: memberTwo.id,
      familyId: 'family-1',
      memberId: 'member-2',
    );
    expect(opened!.state, CapsuleAssignmentState.opened);
    expect(opened.openedAt, DateTime.utc(2026, 9, 2));
  });

  test('lookups and inserts reject cross-family data', () async {
    final assignments = await repository.insertAssignments(
      database,
      entry: _entry,
      options: CapsuleSaveOptions(),
    );
    final current = assignments.first;

    expect(
      await repository.findForMember(
        database,
        assignmentId: current.id,
        familyId: 'family-2',
        memberId: current.targetId,
      ),
      isNull,
    );
    expect(
      await repository.listForMember(
        database,
        familyId: 'family-2',
        memberId: current.targetId,
      ),
      isEmpty,
    );

    await database.delete('capsules');
    await expectLater(
      repository.insertAssignments(
        database,
        entry: _entry.copyWith(familyId: 'family-2'),
        options: CapsuleSaveOptions(),
      ),
      throwsStateError,
    );
    expect(await database.query('capsules'), isEmpty);
  });
}

final _entry = EntryMetadata(
  id: 'entry-1',
  familyId: 'family-1',
  authorId: 'member-1',
  createdAt: DateTime.utc(2026, 9, 1),
  format: MemoryFormat.text,
  privacy: PrivacyTier.capsule,
  blobRef: 'entries/blobs/entry-1.keeper',
);

Future<Database> _openDatabase() async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await database.execute('PRAGMA foreign_keys = ON');
  for (final statement in KeepersSchema.statementsForUpgrade(
    0,
    KeepersSchema.version,
  )) {
    await database.execute(statement);
  }
  return database;
}

Future<void> _seedRosterAndEntry(Database database) async {
  for (final family in const [('family-1', 'Sabati'), ('family-2', 'Other')]) {
    await database.insert('families', {
      'id': family.$1,
      'name': family.$2,
      'family_key_ref': '${family.$1}-key',
      'quorum': 1,
      'created_at': 1,
    });
  }
  for (final member in const [
    ('member-1', 'family-1', 1),
    ('member-2', 'family-1', 2),
    ('outsider', 'family-2', 1),
  ]) {
    await database.insert('members', {
      'id': member.$1,
      'family_id': member.$2,
      'name': member.$1,
      'role': 'adult',
      'member_key_ref': '${member.$1}-key',
      'color_token': 'ochre',
      'avatar_config_json': '{}',
      'created_at': member.$3,
    });
  }
  await database.insert('entries', {
    'id': _entry.id,
    'family_id': _entry.familyId,
    'author_id': _entry.authorId,
    'created_at': _entry.createdAt.millisecondsSinceEpoch,
    'entry_type': _entry.format.name,
    'privacy_tier': 'legacy',
    'blob_ref': _entry.blobRef,
    'state': 'pending',
  });
}
