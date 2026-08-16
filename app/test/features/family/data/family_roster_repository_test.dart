import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/family_roster_repository.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/data/member_repository.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'cloud roster upsert preserves bound local-only member fields',
    () async {
      final database = await _openDatabase();
      addTearDown(database.close);
      final localAvatar = const AvatarConfig.defaults(seed: 'member-local')
          .copyWith(selections: const {'head': 'hm1-p-000001'});
      await _insertFamily(database);
      final members = MemberRepository();
      await members.insert(
        database,
        id: 'member-local',
        familyId: 'family-1',
        name: 'Local draft',
        memberKeyRef: 'member-key-local',
        colorToken: 'ochre',
        avatar: localAvatar,
        createdAt: DateTime.utc(2026, 9, 1),
      );
      await members.bindLocalIdentity(
        database,
        familyId: 'family-1',
        memberId: 'member-local',
      );
      final repository = FamilyRosterRepository();

      await repository.upsertCloudRoster(
        database,
        familyId: 'family-1',
        members: [
          FamilyMember(
            id: 'member-local',
            familyId: 'family-1',
            name: 'Chris',
            role: 'adult',
            colorToken: 'gold',
            avatar: const AvatarConfig.defaults(seed: 'cloud-stale'),
            joinedAt: DateTime.utc(2026, 9, 1),
          ),
          FamilyMember(
            id: 'member-remote',
            familyId: 'family-1',
            name: 'Mariam',
            role: 'elder',
            colorToken: 'teal',
            avatar: const AvatarConfig.defaults(seed: 'member-remote'),
            joinedAt: DateTime.utc(2026, 9, 2),
          ),
        ],
      );

      final rows = await database.query('members', orderBy: 'id');
      expect(rows[0]['id'], 'member-local');
      expect(rows[0]['member_key_ref'], 'member-key-local');
      expect(rows[0]['color_token'], 'ochre');
      expect(rows[0]['avatar_config_json'], localAvatar.encode());
      expect(rows[1]['id'], 'member-remote');
      expect(rows[1]['member_key_ref'], isNull);
      expect(await repository.listLocal(database, familyId: 'family-1'), [
        FamilyMember(
          id: 'member-local',
          familyId: 'family-1',
          name: 'Chris',
          role: 'adult',
          colorToken: 'ochre',
          avatar: localAvatar,
          joinedAt: DateTime.utc(2026, 9, 1),
        ),
        FamilyMember(
          id: 'member-remote',
          familyId: 'family-1',
          name: 'Mariam',
          role: 'elder',
          colorToken: 'teal',
          avatar: const AvatarConfig.defaults(seed: 'member-remote'),
          joinedAt: DateTime.utc(2026, 9, 2),
        ),
      ]);
    },
  );

  test('cross-family cloud members cause no local mutation', () async {
    final database = await _openDatabase();
    addTearDown(database.close);
    await _insertFamily(database);
    final repository = FamilyRosterRepository();

    await expectLater(
      repository.upsertCloudRoster(
        database,
        familyId: 'family-1',
        members: [
          FamilyMember(
            id: 'member-other',
            familyId: 'family-2',
            name: 'Other',
            role: 'adult',
            colorToken: 'ochre',
            avatar: const AvatarConfig.defaults(seed: 'member-other'),
            joinedAt: DateTime.utc(2026, 9, 2),
          ),
        ],
      ),
      throwsArgumentError,
    );

    expect(await database.query('members'), isEmpty);
  });
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
  return database;
}

Future<void> _insertFamily(Database database) async {
  await database.insert('families', {
    'id': 'family-1',
    'name': 'Sabati',
    'family_key_ref': 'family-key',
    'quorum': 1,
    'created_at': DateTime.utc(2026, 9, 1).millisecondsSinceEpoch,
  });
}
