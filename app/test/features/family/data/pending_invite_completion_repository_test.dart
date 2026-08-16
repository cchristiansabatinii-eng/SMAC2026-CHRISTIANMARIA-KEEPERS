import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/pending_invite_completion_repository.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'records and reads one pending completion without capability data',
    () async {
      final database = await _openDatabase();
      addTearDown(database.close);
      final repository = PendingInviteCompletionRepository();
      final pending = PendingInviteCompletion(
        inviteId: 'invite-1',
        familyId: 'family-1',
        accountId: 'account-1',
        installedAt: DateTime.utc(2026, 9, 5, 8),
      );

      await repository.recordExact(database, pending);

      expect(await repository.find(database), pending);
      expect(
        (await database.query('pending_family_invite_completion')).single.keys,
        {'singleton', 'invite_id', 'family_id', 'account_id', 'installed_at'},
      );
    },
  );

  test(
    'repeating the same marker preserves its original install time',
    () async {
      final database = await _openDatabase();
      addTearDown(database.close);
      final repository = PendingInviteCompletionRepository();
      final first = PendingInviteCompletion(
        inviteId: 'invite-1',
        familyId: 'family-1',
        accountId: 'account-1',
        installedAt: DateTime.utc(2026, 9, 5, 8),
      );

      await repository.recordExact(database, first);
      await repository.recordExact(
        database,
        PendingInviteCompletion(
          inviteId: 'invite-1',
          familyId: 'family-1',
          accountId: 'account-1',
          installedAt: DateTime.utc(2026, 9, 5, 9),
        ),
      );

      expect(await repository.find(database), first);
    },
  );

  test('a conflicting marker fails closed without mutation', () async {
    final database = await _openDatabase();
    addTearDown(database.close);
    final repository = PendingInviteCompletionRepository();
    final first = PendingInviteCompletion(
      inviteId: 'invite-1',
      familyId: 'family-1',
      accountId: 'account-1',
      installedAt: DateTime.utc(2026, 9, 5, 8),
    );
    await repository.recordExact(database, first);

    await expectLater(
      repository.recordExact(
        database,
        PendingInviteCompletion(
          inviteId: 'invite-2',
          familyId: 'family-1',
          accountId: 'account-1',
          installedAt: DateTime.utc(2026, 9, 5, 9),
        ),
      ),
      throwsStateError,
    );

    expect(await repository.find(database), first);
  });

  test(
    'exact deletion is idempotent and cannot delete another marker',
    () async {
      final database = await _openDatabase();
      addTearDown(database.close);
      final repository = PendingInviteCompletionRepository();
      final pending = PendingInviteCompletion(
        inviteId: 'invite-1',
        familyId: 'family-1',
        accountId: 'account-1',
        installedAt: DateTime.utc(2026, 9, 5, 8),
      );
      await repository.recordExact(database, pending);

      await expectLater(
        repository.deleteExact(
          database,
          PendingInviteCompletion(
            inviteId: 'invite-2',
            familyId: 'family-1',
            accountId: 'account-1',
            installedAt: pending.installedAt,
          ),
        ),
        throwsStateError,
      );
      expect(await repository.find(database), pending);

      await repository.deleteExact(database, pending);
      await repository.deleteExact(database, pending);
      expect(await repository.find(database), isNull);
    },
  );
}

Future<Database> _openDatabase() async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await database.execute('PRAGMA foreign_keys = ON');
  for (final statement in KeepersSchema.statementsForUpgrade(
    0,
    KeepersSchema.version,
  )) {
    await database.execute(statement);
  }
  await database.insert('families', {
    'id': 'family-1',
    'name': 'Sabati',
    'family_key_ref': 'family-key',
    'quorum': 1,
    'created_at': 1,
  });
  return database;
}
