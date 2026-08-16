import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/family_roster_repository.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'emits local roster before cloud and replaces it transactionally',
    () async {
      final database = await _databaseWithMember(_localMember);
      addTearDown(database.close);
      final gate = Completer<void>();
      final gateway = _RosterGateway(gate: gate, members: [_cloudMember]);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncValue.data(database)),
          cloudFamilyGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        familyRosterProvider(_familyId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final load = container
          .read(familyRosterProvider(_familyId).notifier)
          .load();
      await _waitUntil(() => gateway.calls == 1);
      expect(container.read(familyRosterProvider(_familyId)).members, [
        _localMember,
      ]);
      expect(
        container.read(familyRosterProvider(_familyId)).isRefreshing,
        isTrue,
      );
      gate.complete();
      await load;

      expect(container.read(familyRosterProvider(_familyId)).members, [
        _cloudMember,
      ]);
      expect(
        container.read(familyRosterProvider(_familyId)).refreshFailure,
        isNull,
      );
    },
  );

  test(
    'network failure retains cached roster as non-blocking status',
    () async {
      final database = await _databaseWithMember(_localMember);
      addTearDown(database.close);
      final gateway = _RosterGateway(
        failures: [
          const InvitationFailure(InvitationFailureCode.networkUnavailable),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncValue.data(database)),
          cloudFamilyGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        familyRosterProvider(_familyId),
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container.read(familyRosterProvider(_familyId).notifier).load();

      final state = container.read(familyRosterProvider(_familyId));
      expect(state.members, [_localMember]);
      expect(
        state.refreshFailure?.code,
        InvitationFailureCode.networkUnavailable,
      );
      expect(state.hasLoadedLocal, isTrue);
    },
  );

  test('rapid refreshes share one cloud request', () async {
    final database = await _databaseWithMember(_localMember);
    addTearDown(database.close);
    final gate = Completer<void>();
    final gateway = _RosterGateway(gate: gate, members: [_cloudMember]);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(AsyncValue.data(database)),
        cloudFamilyGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      familyRosterProvider(_familyId),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final controller = container.read(familyRosterProvider(_familyId).notifier);

    final first = controller.load();
    final second = controller.refresh();
    await _waitUntil(() => gateway.calls == 1);
    expect(gateway.calls, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(gateway.calls, 1);
  });

  test(
    'failed multi-statement cloud upsert rolls back as one transaction',
    () async {
      final database = await _databaseWithMember(_localMember);
      addTearDown(database.close);
      await database.execute('''
CREATE TRIGGER fail_second_member
BEFORE INSERT ON members WHEN NEW.id = 'member-2'
BEGIN
  SELECT RAISE(ABORT, 'second insert failed');
END
''');
      final gateway = _RosterGateway(
        members: [
          _cloudMember,
          FamilyMember(
            id: 'member-2',
            familyId: _familyId,
            name: 'Second',
            role: 'adult',
            colorToken: 'gold',
            avatar: const AvatarConfig.defaults(seed: 'member-2'),
            joinedAt: DateTime.utc(2026, 9, 3),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncValue.data(database)),
          cloudFamilyGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        familyRosterProvider(_familyId),
        (_, _) {},
      );
      addTearDown(subscription.close);

      await container.read(familyRosterProvider(_familyId).notifier).load();

      expect(container.read(familyRosterProvider(_familyId)).members, [
        _localMember,
      ]);
      expect(
        container.read(familyRosterProvider(_familyId)).refreshFailure?.code,
        InvitationFailureCode.localPersistenceFailed,
      );
      final rows = await database.query('members');
      expect(rows, hasLength(1));
      expect(rows.single['name'], 'Cached');
    },
  );

  test(
    'watch automatically loads local roster and invalidation reloads it',
    () async {
      final database = await _databaseWithMember(_localMember);
      addTearDown(database.close);
      final gateway = _RosterGateway(configured: false);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncValue.data(database)),
          cloudFamilyGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        familyRosterProvider(_familyId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await _waitUntil(
        () => container.read(familyRosterProvider(_familyId)).hasLoadedLocal,
      );
      expect(
        container.read(familyRosterProvider(_familyId)).members.single.name,
        'Cached',
      );
      expect(
        container.read(familyRosterProvider(_familyId)).refreshFailure,
        isNull,
      );

      await database.update(
        'members',
        {'name': 'Reloaded'},
        where: 'id = ?',
        whereArgs: ['member-1'],
      );
      container.invalidate(familyRosterProvider(_familyId));
      await _waitUntil(
        () =>
            container
                .read(familyRosterProvider(_familyId))
                .members
                .firstOrNull
                ?.name ==
            'Reloaded',
      );
      expect(
        container.read(familyRosterProvider(_familyId)).members.single.name,
        'Reloaded',
      );
      expect(gateway.calls, 0);
    },
  );

  test('signed-out refresh-before-load completes with cached roster', () async {
    final database = await _databaseWithMember(_localMember);
    addTearDown(database.close);
    final gateway = _RosterGateway(accountId: null);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(AsyncValue.data(database)),
        cloudFamilyGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      familyRosterProvider(_familyId),
      (_, _) {},
    );
    addTearDown(subscription.close);

    await container.read(familyRosterProvider(_familyId).notifier).refresh();

    final state = container.read(familyRosterProvider(_familyId));
    expect(state.members, [_localMember]);
    expect(state.isRefreshing, isFalse);
    expect(state.refreshFailure, isNull);
    expect(gateway.calls, 0);
  });

  test('account change suppresses a stale cloud roster response', () async {
    final database = await _databaseWithMember(_localMember);
    addTearDown(database.close);
    final gate = Completer<void>();
    final gateway = _RosterGateway(gate: gate, members: [_cloudMember]);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(AsyncValue.data(database)),
        cloudFamilyGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      familyRosterProvider(_familyId),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final load = container
        .read(familyRosterProvider(_familyId).notifier)
        .load();
    await _waitUntil(() => gateway.calls == 1);

    gateway.accountId = 'other-account';
    gate.complete();
    await load;

    final state = container.read(familyRosterProvider(_familyId));
    expect(state.members, [_localMember]);
    expect(state.refreshFailure?.code, InvitationFailureCode.signedOut);
    expect((await database.query('members')).single['name'], 'Cached');
  });

  test(
    'account change during upsert rolls back the roster transaction',
    () async {
      final database = await _databaseWithMember(_localMember);
      addTearDown(database.close);
      final entered = Completer<void>();
      final release = Completer<void>();
      final gateway = _RosterGateway(members: [_cloudMember]);
      final repository = FamilyRosterRepository();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncValue.data(database)),
          cloudFamilyGatewayProvider.overrideWithValue(gateway),
          familyRosterUpsertProvider.overrideWithValue((
            transaction, {
            required familyId,
            required members,
          }) async {
            await repository.upsertCloudRoster(
              transaction,
              familyId: familyId,
              members: members,
            );
            entered.complete();
            await release.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        familyRosterProvider(_familyId),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await entered.future;

      gateway.accountId = 'other-account';
      release.complete();
      await _waitUntil(
        () => !container.read(familyRosterProvider(_familyId)).isRefreshing,
      );

      final state = container.read(familyRosterProvider(_familyId));
      expect(state.members, [_localMember]);
      expect(state.refreshFailure?.code, InvitationFailureCode.signedOut);
      expect((await database.query('members')).single['name'], 'Cached');
    },
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 50 && !condition(); attempt += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

Future<Database> _databaseWithMember(FamilyMember member) async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
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
  await database.insert('members', {
    'id': member.id,
    'family_id': member.familyId,
    'name': member.name,
    'role': member.role,
    'member_key_ref': null,
    'color_token': member.colorToken,
    'avatar_config_json': member.avatar.encode(),
    'created_at': member.joinedAt.millisecondsSinceEpoch,
  });
  return database;
}

final class _RosterGateway implements CloudFamilyGateway {
  _RosterGateway({
    this.gate,
    this.members = const [],
    List<InvitationFailure> failures = const [],
    this.configured = true,
    this.accountId = 'account',
  }) : failures = List.of(failures);
  final Completer<void>? gate;
  final List<FamilyMember> members;
  final List<InvitationFailure> failures;
  final bool configured;
  String? accountId;
  int calls = 0;
  @override
  bool get isConfigured => configured;
  @override
  String? get authenticatedAccountId => accountId;
  @override
  String? get authenticatedEmail => 'email@example.com';
  @override
  Future<List<FamilyMember>> listActiveMembers(String familyId) async {
    calls += 1;
    if (failures.isNotEmpty) throw failures.removeAt(0);
    if (gate case final value?) await value.future;
    return members;
  }

  @override
  Future<void> requestEmailOtp(String email) => throw UnimplementedError();
  @override
  Future<void> verifyEmailOtp({required String email, required String token}) =>
      throw UnimplementedError();
  @override
  Future<void> bootstrapOwner(LocalOwnerFamily owner) =>
      throw UnimplementedError();
  @override
  Future<CreatedInvitation> createInvitation(CloudInvitationDraft draft) =>
      throw UnimplementedError();
  @override
  Future<InvitePreview> previewInvitation(FamilyInviteLink link) =>
      throw UnimplementedError();
  @override
  Future<ClaimedFamily> claimInvitation(JoinRequest request) =>
      throw UnimplementedError();
  @override
  Future<void> completeInvitation(String inviteId) =>
      throw UnimplementedError();
  @override
  Future<void> revokeInvitation(String inviteId) => throw UnimplementedError();
}

const _familyId = 'family-1';
final _localMember = FamilyMember(
  id: 'member-1',
  familyId: _familyId,
  name: 'Cached',
  role: 'adult',
  colorToken: 'ochre',
  avatar: const AvatarConfig.defaults(seed: 'member-1'),
  joinedAt: DateTime.utc(2026, 9, 1),
);
final _cloudMember = FamilyMember(
  id: 'member-1',
  familyId: _familyId,
  name: 'Cloud',
  role: 'adult',
  colorToken: 'teal',
  avatar: const AvatarConfig.defaults(seed: 'member-1'),
  joinedAt: DateTime.utc(2026, 9, 2),
);
