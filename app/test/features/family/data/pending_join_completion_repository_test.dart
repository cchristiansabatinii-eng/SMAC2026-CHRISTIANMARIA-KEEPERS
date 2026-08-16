import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/pending_join_completion_repository.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  const repository = PendingJoinCompletionRepository();

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    for (final statement in KeepersSchema.statementsForUpgrade(
      0,
      KeepersSchema.version,
    )) {
      await database.execute(statement);
    }
    await _insertFamilyAndMember(database);
  });

  tearDown(() => database.close());

  test('completion marker is idempotent only for the exact identity', () async {
    final pending = _pending();
    await repository.recordExact(database, pending);
    await repository.recordExact(database, pending);

    await expectLater(
      repository.recordExact(
        database,
        _pending(accountId: '55555555-5555-4555-8555-555555555555'),
      ),
      throwsStateError,
    );

    expect(await repository.find(database), pending);
    expect(
      await database.query('pending_family_join_completion'),
      hasLength(1),
    );
  });

  test(
    'exact marker identity includes request family member and account',
    () async {
      final pending = _pending();
      await repository.recordExact(database, pending);

      final conflicts = [
        _pending(requestId: '66666666-6666-4666-8666-666666666666'),
        _pending(familyId: '77777777-7777-4777-8777-777777777777'),
        _pending(memberId: '88888888-8888-4888-8888-888888888888'),
        _pending(accountId: '99999999-9999-4999-8999-999999999999'),
      ];
      for (final conflict in conflicts) {
        await expectLater(
          repository.recordExact(database, conflict),
          throwsStateError,
        );
        await expectLater(
          repository.deleteExact(database, conflict),
          throwsStateError,
        );
      }

      expect(await repository.find(database), pending);
    },
  );

  test('deleteExact removes only the matching marker', () async {
    final pending = _pending();
    await repository.recordExact(database, pending);

    await repository.deleteExact(database, pending);

    expect(await repository.find(database), isNull);
    await repository.deleteExact(database, pending);
  });
}

PendingJoinCompletion _pending({
  String requestId = _requestId,
  String familyId = _familyId,
  String memberId = _memberId,
  String accountId = _accountId,
}) => PendingJoinCompletion(
  requestId: requestId,
  familyId: familyId,
  memberId: memberId,
  accountId: accountId,
  installedAt: DateTime.utc(2026, 9, 5),
);

Future<void> _insertFamilyAndMember(Database database) async {
  await database.insert('families', {
    'id': _familyId,
    'name': 'Sabati',
    'family_key_ref': 'family-key',
    'quorum': 1,
    'created_at': 1,
  });
  await database.insert('members', {
    'id': _memberId,
    'family_id': _familyId,
    'name': 'Mariam',
    'role': 'adult',
    'created_at': 1,
    'color_token': 'teal',
    'avatar_config_json': '{}',
  });
}

const _requestId = '33333333-3333-4333-8333-333333333333';
const _familyId = '11111111-1111-4111-8111-111111111111';
const _memberId = '44444444-4444-4444-8444-444444444444';
const _accountId = '22222222-2222-4222-8222-222222222222';
