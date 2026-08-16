import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/pending_invite_completion_controller.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/pending_invite_completion_repository.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('matching account completes and deletes exact marker', () async {
    final fixture = await _RecoveryFixture.create();
    addTearDown(fixture.dispose);

    await fixture.controller.recover();

    expect(fixture.gateway.completedIds, [_inviteId]);
    expect(fixture.state.phase, PendingInviteCompletionPhase.complete);
    expect(await fixture.repository.find(fixture.database), isNull);
    expect(fixture.state.toString(), 'PendingInviteCompletionState(complete)');
  });

  test('wrong account retains marker without remote mutation', () async {
    final fixture = await _RecoveryFixture.create(accountId: 'other-account');
    addTearDown(fixture.dispose);

    await fixture.controller.recover();

    expect(fixture.gateway.completedIds, isEmpty);
    expect(fixture.state.failure?.code, InvitationFailureCode.forbidden);
    expect(await fixture.repository.find(fixture.database), isNotNull);
  });

  test('network failure retains marker for exact retry', () async {
    final fixture = await _RecoveryFixture.create(
      failures: [
        const InvitationFailure(InvitationFailureCode.networkUnavailable),
      ],
    );
    addTearDown(fixture.dispose);

    await fixture.controller.recover();
    expect(await fixture.repository.find(fixture.database), isNotNull);
    await fixture.controller.recover();

    expect(fixture.gateway.completedIds, [_inviteId, _inviteId]);
    expect(await fixture.repository.find(fixture.database), isNull);
  });

  test(
    'account change during completion retains marker and ignores success',
    () async {
      final gate = Completer<void>();
      final fixture = await _RecoveryFixture.create(gate: gate);
      addTearDown(fixture.dispose);

      final recovery = fixture.controller.recover();
      await _waitUntil(() => fixture.gateway.completedIds.isNotEmpty);
      fixture.gateway.accountId = 'other-account';
      gate.complete();
      await recovery;

      expect(fixture.state.failure?.code, InvitationFailureCode.signedOut);
      expect(await fixture.repository.find(fixture.database), isNotNull);
    },
  );

  test(
    'marker deletion failure retains marker after accepted completion',
    () async {
      final fixture = await _RecoveryFixture.create(failMarkerDelete: true);
      addTearDown(fixture.dispose);

      await fixture.controller.recover();

      expect(fixture.gateway.completedIds, [_inviteId]);
      expect(
        fixture.state.failure?.code,
        InvitationFailureCode.localPersistenceFailed,
      );
      expect(await fixture.repository.find(fixture.database), isNotNull);
    },
  );

  test(
    'account switch during exact marker deletion ends signed out and non-busy',
    () async {
      final deleteEntered = Completer<void>();
      final deleteRelease = Completer<void>();
      final repository = const PendingInviteCompletionRepository();
      final fixture = await _RecoveryFixture.create(
        deleteExact: (database, pending) async {
          await repository.deleteExact(database, pending);
          deleteEntered.complete();
          await deleteRelease.future;
        },
      );
      addTearDown(fixture.dispose);
      addTearDown(() {
        if (!deleteRelease.isCompleted) deleteRelease.complete();
      });

      final recovery = fixture.controller.recover();
      await deleteEntered.future;
      expect(await repository.find(fixture.database), isNull);
      fixture.gateway.accountId = 'other-account';
      deleteRelease.complete();
      await recovery;

      expect(fixture.state.phase, PendingInviteCompletionPhase.failed);
      expect(fixture.state.failure?.code, InvitationFailureCode.signedOut);
    },
  );

  test('rapid recovery calls share one completion request', () async {
    final gate = Completer<void>();
    final fixture = await _RecoveryFixture.create(gate: gate);
    addTearDown(fixture.dispose);

    final first = fixture.controller.recover();
    final second = fixture.controller.recover();
    await _waitUntil(() => fixture.gateway.completedIds.isNotEmpty);
    expect(fixture.gateway.completedIds, [_inviteId]);
    gate.complete();
    await Future.wait([first, second]);
    expect(fixture.gateway.completedIds, [_inviteId]);
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 50 && !condition(); attempt += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

final class _RecoveryFixture {
  _RecoveryFixture(
    this.database,
    this.container,
    this.subscription,
    this.gateway,
  );
  final Database database;
  final ProviderContainer container;
  final ProviderSubscription<PendingInviteCompletionState> subscription;
  final _RecoveryGateway gateway;
  final repository = const PendingInviteCompletionRepository();
  PendingInviteCompletionController get controller =>
      container.read(pendingInviteCompletionControllerProvider.notifier);
  PendingInviteCompletionState get state =>
      container.read(pendingInviteCompletionControllerProvider);

  static Future<_RecoveryFixture> create({
    String? accountId = _accountId,
    Completer<void>? gate,
    List<InvitationFailure> failures = const [],
    bool failMarkerDelete = false,
    PendingInviteCompletionDeleteExact? deleteExact,
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
    await database.insert('families', {
      'id': _familyId,
      'name': 'Sabati',
      'family_key_ref': 'family-key',
      'quorum': 1,
      'created_at': 1,
    });
    await const PendingInviteCompletionRepository().recordExact(
      database,
      PendingInviteCompletion(
        inviteId: _inviteId,
        familyId: _familyId,
        accountId: _accountId,
        installedAt: DateTime.utc(2026, 9, 5),
      ),
    );
    if (failMarkerDelete) {
      await database.execute('''
CREATE TRIGGER fail_pending_delete
BEFORE DELETE ON pending_family_invite_completion
BEGIN
  SELECT RAISE(ABORT, 'delete failed');
END
''');
    }
    final gateway = _RecoveryGateway(accountId, gate, failures);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(AsyncValue.data(database)),
        cloudFamilyGatewayProvider.overrideWithValue(gateway),
        if (deleteExact != null)
          pendingInviteCompletionDeleteExactProvider.overrideWithValue(
            deleteExact,
          ),
      ],
    );
    final subscription = container.listen(
      pendingInviteCompletionControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    return _RecoveryFixture(database, container, subscription, gateway);
  }

  Future<void> dispose() async {
    subscription.close();
    container.dispose();
    await database.close();
  }
}

final class _RecoveryGateway implements CloudFamilyGateway {
  _RecoveryGateway(this.accountId, this.gate, List<InvitationFailure> failures)
    : failures = List.of(failures);
  String? accountId;
  final Completer<void>? gate;
  final List<InvitationFailure> failures;
  final List<String> completedIds = [];
  @override
  bool get isConfigured => true;
  @override
  String? get authenticatedAccountId => accountId;
  @override
  String? get authenticatedEmail => 'mariam@example.com';
  @override
  Future<void> completeInvitation(String inviteId) async {
    completedIds.add(inviteId);
    if (failures.isNotEmpty) throw failures.removeAt(0);
    if (gate case final value?) await value.future;
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
  Future<void> revokeInvitation(String inviteId) => throw UnimplementedError();
  @override
  Future<List<FamilyMember>> listActiveMembers(String familyId) =>
      throw UnimplementedError();
}

const _inviteId = 'invite-1';
const _familyId = 'family-1';
const _accountId = 'account-1';
