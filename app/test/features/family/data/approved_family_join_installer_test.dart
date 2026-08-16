import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/approved_family_join_installer.dart';
import 'package:keepers/features/family/data/family_roster_repository.dart';
import 'package:keepers/features/family/data/pending_join_completion_repository.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
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
    'records completion only inside the local install transaction',
    () async {
      final fixture = await _InstallerFixture.create();
      addTearDown(fixture.database.close);

      final pending = await fixture.installer.install(
        approval: _approval(),
        familyKey: List<int>.filled(32, 17),
        accountId: _accountId,
      );

      expect(pending.requestId, _requestId);
      expect(await fixture.markers.find(fixture.database), pending);
      expect(
        (await MemberRepository().findLocalIdentity(fixture.database))!
            .accountId,
        _accountId,
      );
      expect(await fixture.database.query('families'), hasLength(1));
      expect(await fixture.database.query('members'), hasLength(2));
    },
  );

  test('rejects a missing local roster member before writing keys', () async {
    final fixture = await _InstallerFixture.create();
    addTearDown(fixture.database.close);

    await expectLater(
      fixture.installer.install(
        approval: _approval(roster: [_owner]),
        familyKey: List<int>.filled(32, 17),
        accountId: _accountId,
      ),
      throwsA(
        equals(
          const FamilyJoinFailure(FamilyJoinFailureCode.localPersistenceFailed),
        ),
      ),
    );

    expect(fixture.secureStore.values, isEmpty);
    expect(await fixture.database.query('families'), isEmpty);
  });

  test('SQL failure rolls back only keys created by this attempt', () async {
    final fixture = await _InstallerFixture.create(failRosterInsert: true);
    addTearDown(fixture.database.close);
    final existingFamily = await fixture.identityKeys.importFamilyKey(
      familyId: _familyId,
      familyKey: List<int>.filled(32, 17),
    );
    final existingMember = await fixture.identityKeys.createMemberKey(
      memberId: _memberId,
    );

    await expectLater(
      fixture.installer.install(
        approval: _approval(),
        familyKey: List<int>.filled(32, 17),
        accountId: _accountId,
      ),
      throwsA(isA<FamilyJoinFailure>()),
    );

    expect(fixture.secureStore.values.keys.toSet(), {
      existingFamily.reference,
      existingMember.reference,
    });
    expect(await fixture.database.query('families'), isEmpty);
    expect(await fixture.markers.find(fixture.database), isNull);
  });

  test('SQL failure removes newly created secure keys', () async {
    final fixture = await _InstallerFixture.create(failRosterInsert: true);
    addTearDown(fixture.database.close);

    await expectLater(
      fixture.installer.install(
        approval: _approval(),
        familyKey: List<int>.filled(32, 17),
        accountId: _accountId,
      ),
      throwsA(isA<FamilyJoinFailure>()),
    );

    expect(fixture.secureStore.values, isEmpty);
    expect(await fixture.database.query('families'), isEmpty);
    expect(await fixture.markers.find(fixture.database), isNull);
  });
}

final class _InstallerFixture {
  _InstallerFixture(
    this.database,
    this.secureStore,
    this.identityKeys,
    this.installer,
  );

  final Database database;
  final _MemorySecureValueStore secureStore;
  final IdentityKeyService identityKeys;
  final ApprovedFamilyJoinInstaller installer;
  final markers = const PendingJoinCompletionRepository();

  static Future<_InstallerFixture> create({
    bool failRosterInsert = false,
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
    final secureStore = _MemorySecureValueStore();
    final identityKeys = IdentityKeyService(
      secureStore,
      randomBytesFactory: (length) => List<int>.filled(length, 23),
    );
    final installer = LocalApprovedFamilyJoinInstaller(
      () async => database,
      identityKeys,
      MemberRepository(),
      FamilyRosterRepository(),
      utcNow: () => DateTime.utc(2026, 9, 5, 8),
    );
    return _InstallerFixture(database, secureStore, identityKeys, installer);
  }
}

ApprovedFamilyJoin _approval({List<FamilyMember>? roster}) =>
    ApprovedFamilyJoin(
      requestId: _requestId,
      familyId: _familyId,
      familyName: 'Sabati',
      localMemberId: _memberId,
      joiningPublicKey: 'joining-public-key',
      approvalEnvelope: const FamilyJoinApprovalEnvelope(
        version: 1,
        context: JoinEnvelopeContext(
          requestId: _requestId,
          familyId: _familyId,
          requesterAccountId: _accountId,
          codeVersion: 1,
        ),
        ephemeralPublicKey: 'ephemeral-public-key',
        nonce: 'nonce',
        ciphertext: 'ciphertext',
        mac: 'mac',
      ),
      roster: roster ?? [_owner, _localMember],
    );

final _owner = FamilyMember(
  id: '55555555-5555-4555-8555-555555555555',
  familyId: _familyId,
  name: 'Chris',
  role: 'adult',
  colorToken: 'ochre',
  avatar: const AvatarConfig.defaults(seed: 'owner'),
  joinedAt: DateTime.utc(2026, 9, 1),
);

final _localMember = FamilyMember(
  id: _memberId,
  familyId: _familyId,
  name: 'Mariam',
  role: 'adult',
  colorToken: 'teal',
  avatar: const AvatarConfig.defaults(seed: 'local'),
  joinedAt: DateTime.utc(2026, 9, 2),
);

final class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

const _requestId = '11111111-1111-4111-8111-111111111111';
const _familyId = '22222222-2222-4222-8222-222222222222';
const _accountId = '33333333-3333-4333-8333-333333333333';
const _memberId = '44444444-4444-4444-8444-444444444444';
