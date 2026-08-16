import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/family_code_cache_repository.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  const repository = FamilyCodeCacheRepository();

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    for (final statement in KeepersSchema.statementsForUpgrade(
      0,
      KeepersSchema.version,
    )) {
      await database.execute(statement);
    }
    await database.insert('families', {
      'id': _familyId,
      'name': 'Sabati',
      'family_key_ref': 'family-key',
      'quorum': 1,
      'created_at': 1,
    });
  });

  tearDown(() => database.close());

  test(
    'round trips encrypted material without plaintext code storage',
    () async {
      final record = _record(version: 2);

      await repository.upsert(database, record);

      expect(await repository.find(database, familyId: _familyId), record);
      final row = (await database.query('family_code_cache')).single;
      expect(row.keys, {
        'family_id',
        'code_version',
        'codec_version',
        'nonce',
        'ciphertext',
        'mac',
        'creator_account_id',
        'updated_at',
        'cached_at',
      });
      expect(row.values, isNot(contains('ABCD1234')));
    },
  );

  test(
    'cache refuses to roll a family back to an older code version',
    () async {
      final newer = _record(version: 2);
      final older = _record(version: 1);
      await repository.upsert(database, newer);

      await expectLater(repository.upsert(database, older), throwsStateError);

      expect(await repository.find(database, familyId: _familyId), newer);
    },
  );

  test('normalizes timestamps to SQLite millisecond precision', () async {
    final record = FamilyCodeCacheRecord(
      material: _record(version: 2).material,
      creatorAccountId: _accountId,
      updatedAt: DateTime.utc(2026, 9, 2, 3, 4, 5, 678, 901),
      cachedAt: DateTime.utc(2026, 9, 5, 6, 7, 8, 987, 654),
    );

    await repository.upsert(database, record);
    await repository.upsert(database, record);

    expect(record.updatedAt.microsecond, 0);
    expect(record.cachedAt.microsecond, 0);
    expect(await repository.find(database, familyId: _familyId), record);
  });

  test('same version is idempotent only for the exact cached record', () async {
    final record = _record(version: 2);
    await repository.upsert(database, record);
    await repository.upsert(database, record);

    await expectLater(
      repository.upsert(
        database,
        _record(version: 2, ciphertext: 'changed-ciphertext'),
      ),
      throwsStateError,
    );
    expect(await repository.find(database, familyId: _familyId), record);
  });

  test('higher code version replaces the cached encrypted record', () async {
    await repository.upsert(database, _record(version: 1));
    final newer = _record(version: 2, ciphertext: 'new-ciphertext');

    await repository.upsert(database, newer);

    expect(await repository.find(database, familyId: _familyId), newer);
  });
}

FamilyCodeCacheRecord _record({
  required int version,
  String ciphertext = 'ciphertext',
}) => FamilyCodeCacheRecord(
  material: EncryptedFamilyCodeMaterial(
    codecVersion: 1,
    familyId: _familyId,
    codeVersion: version,
    nonce: 'nonce',
    ciphertext: ciphertext,
    mac: 'mac',
  ),
  creatorAccountId: _accountId,
  updatedAt: DateTime.utc(2026, 9, version),
  cachedAt: DateTime.utc(2026, 9, 5),
);

const _familyId = '11111111-1111-4111-8111-111111111111';
const _accountId = '22222222-2222-4222-8222-222222222222';
