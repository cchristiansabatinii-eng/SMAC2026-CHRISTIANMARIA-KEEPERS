import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/family_roster_repository.dart';
import 'package:keepers/features/family/data/joined_family_installer.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/data/member_repository.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'joined family install persists keys, roster, and local binding',
    () async {
      final fixture = await _InstallerFixture.create();
      addTearDown(fixture.database.close);

      await fixture.installer.install(
        claim: _claim(),
        familyKey: List<int>.filled(32, 17),
        accountId: 'account-1',
      );

      expect(await fixture.database.query('families'), [
        {
          'id': 'family-1',
          'name': 'Sabati',
          'family_key_ref': 'keepers.family.family-1.entry-key.v1',
          'quorum': 1,
          'created_at': DateTime.utc(2026, 9, 1).millisecondsSinceEpoch,
        },
      ]);
      expect(await fixture.database.query('local_identity_binding'), [
        {
          'singleton': 1,
          'family_id': 'family-1',
          'member_id': 'member-recipient',
          'account_id': 'account-1',
        },
      ]);
      final rows = await fixture.database.query('members', orderBy: 'id');
      expect(rows, hasLength(2));
      expect(rows[0]['id'], 'member-owner');
      expect(rows[0]['member_key_ref'], isNull);
      expect(rows[1]['id'], 'member-recipient');
      expect(
        rows[1]['member_key_ref'],
        'keepers.member.member-recipient.entry-key.v1',
      );
      expect(fixture.secureStore.values, hasLength(2));
      expect(await fixture.database.query('pending_family_invite_completion'), [
        {
          'singleton': 1,
          'invite_id': '11111111-1111-4111-8111-111111111111',
          'family_id': 'family-1',
          'account_id': 'account-1',
          'installed_at': DateTime.utc(2026, 9, 5, 8).millisecondsSinceEpoch,
        },
      ]);
    },
  );

  test('joined family install rolls back secure keys when SQL fails', () async {
    final fixture = await _InstallerFixture.create(failRosterInsert: true);
    addTearDown(fixture.database.close);

    await expectLater(
      fixture.installer.install(
        claim: _claim(),
        familyKey: List<int>.filled(32, 17),
        accountId: 'account-1',
      ),
      throwsA(
        equals(
          const InvitationFailure(InvitationFailureCode.localPersistenceFailed),
        ),
      ),
    );

    expect(fixture.secureStore.values, isEmpty);
    expect(await fixture.database.query('families'), isEmpty);
    expect(await fixture.database.query('members'), isEmpty);
    expect(
      await fixture.database.query('pending_family_invite_completion'),
      isEmpty,
    );
  });

  test('exact joined-family reinstall keeps one completion marker', () async {
    final fixture = await _InstallerFixture.create();
    addTearDown(fixture.database.close);

    await fixture.installer.install(
      claim: _claim(),
      familyKey: List<int>.filled(32, 17),
      accountId: 'account-1',
    );
    fixture.now = DateTime.utc(2026, 9, 5, 9);
    await fixture.installer.install(
      claim: _claim(),
      familyKey: List<int>.filled(32, 17),
      accountId: 'account-1',
    );

    final rows = await fixture.database.query(
      'pending_family_invite_completion',
    );
    expect(rows, hasLength(1));
    expect(
      rows.single['installed_at'],
      DateTime.utc(2026, 9, 5, 8).millisecondsSinceEpoch,
    );
  });

  test('secure cleanup failure preserves typed local failure', () async {
    final fixture = await _InstallerFixture.create(
      failRosterInsert: true,
      failSecureDeletes: true,
    );
    addTearDown(fixture.database.close);

    await expectLater(
      fixture.installer.install(
        claim: _claim(),
        familyKey: List<int>.filled(32, 17),
        accountId: 'account-1',
      ),
      throwsA(
        equals(
          const InvitationFailure(InvitationFailureCode.localPersistenceFailed),
        ),
      ),
    );
  });

  test('failed retry preserves a family key that already existed', () async {
    final fixture = await _InstallerFixture.create(failRosterInsert: true);
    addTearDown(fixture.database.close);
    final existing = await fixture.identityKeys.importFamilyKey(
      familyId: 'family-1',
      familyKey: List<int>.filled(32, 17),
    );

    await expectLater(
      fixture.installer.install(
        claim: _claim(),
        familyKey: List<int>.filled(32, 17),
        accountId: 'account-1',
      ),
      throwsA(isA<InvitationFailure>()),
    );

    expect(fixture.secureStore.values.keys, [existing.reference]);
    expect(
      await fixture.identityKeys.resolve(existing.reference),
      List<int>.filled(32, 17),
    );
  });
}

ClaimedFamily _claim() => ClaimedFamily(
  familyId: 'family-1',
  familyName: 'Sabati',
  localMemberId: 'member-recipient',
  envelope: const InvitationEnvelope(
    version: 1,
    inviteId: '11111111-1111-4111-8111-111111111111',
    familyId: 'family-1',
    nonce: 'unused-by-installer',
    ciphertext: 'unused-by-installer',
    mac: 'unused-by-installer',
  ),
  members: [
    FamilyMember(
      id: 'member-owner',
      familyId: 'family-1',
      name: 'Chris',
      role: 'adult',
      colorToken: 'ochre',
      avatar: const AvatarConfig.defaults(seed: 'member-owner'),
      joinedAt: DateTime.utc(2026, 9, 1),
    ),
    FamilyMember(
      id: 'member-recipient',
      familyId: 'family-1',
      name: 'Mariam',
      role: 'adult',
      colorToken: 'teal',
      avatar: const AvatarConfig.defaults(seed: 'member-recipient'),
      joinedAt: DateTime.utc(2026, 9, 2),
    ),
  ],
);

final class _InstallerFixture {
  _InstallerFixture({
    required this.database,
    required this.secureStore,
    required this.identityKeys,
    required this.installer,
    required this.now,
  });

  final Database database;
  final _MemorySecureValueStore secureStore;
  final IdentityKeyService identityKeys;
  final JoinedFamilyInstaller installer;
  DateTime now;

  static Future<_InstallerFixture> create({
    bool failRosterInsert = false,
    bool failSecureDeletes = false,
  }) async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    await database.execute('PRAGMA foreign_keys = ON');
    for (final statement in KeepersSchema.statementsForUpgrade(
      0,
      KeepersSchema.version,
    )) {
      await database.execute(statement);
    }
    if (failRosterInsert) {
      await database.execute(r'''
CREATE TRIGGER fail_member_insert
BEFORE INSERT ON members
BEGIN
  SELECT RAISE(ABORT, 'member insert failed');
END
''');
    }
    final secureStore = _MemorySecureValueStore(failDeletes: failSecureDeletes);
    final identityKeys = IdentityKeyService(
      secureStore,
      randomBytesFactory: (length) => List<int>.filled(length, 23),
    );
    late final _InstallerFixture fixture;
    final installer = LocalJoinedFamilyInstaller(
      () async => database,
      identityKeys,
      MemberRepository(),
      FamilyRosterRepository(),
      utcNow: () => fixture.now,
    );
    fixture = _InstallerFixture(
      database: database,
      secureStore: secureStore,
      identityKeys: identityKeys,
      installer: installer,
      now: DateTime.utc(2026, 9, 5, 8),
    );
    return fixture;
  }
}

final class _MemorySecureValueStore implements SecureValueStore {
  _MemorySecureValueStore({this.failDeletes = false});

  final bool failDeletes;
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes) throw StateError('secure delete failed');
    values.remove(key);
  }
}
