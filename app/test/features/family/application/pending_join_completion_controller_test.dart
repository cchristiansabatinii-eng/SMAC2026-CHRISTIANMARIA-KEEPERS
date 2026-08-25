import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_join_crypto_providers.dart';
import 'package:keepers/features/family/application/pending_join_completion_controller.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/joining_key_store.dart';
import 'package:keepers/features/family/data/pending_join_completion_repository.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('completion validates joining key before cloud mutation', () async {
    final fixture = await _RecoveryFixture.create();
    addTearDown(fixture.dispose);

    await fixture.controller.recover();

    expect(fixture.events, [
      'find-key',
      'complete',
      'delete-key',
      'find-key',
      'delete-marker',
    ]);
    expect(fixture.state.phase, PendingJoinCompletionPhase.complete);
    expect(await fixture.repository.find(fixture.database), isNull);
    expect(
      await fixture.keys.find(accountId: _accountId, memberId: _memberId),
      isNull,
    );
  });

  test(
    'retains marker through a network failure and retries idempotently',
    () async {
      final fixture = await _RecoveryFixture.create(
        failures: [
          const FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable),
        ],
      );
      addTearDown(fixture.dispose);

      await fixture.controller.recover();
      expect(await fixture.repository.find(fixture.database), fixture.pending);
      await fixture.controller.recover();

      expect(await fixture.repository.find(fixture.database), isNull);
      expect(fixture.gateway.completedRequestIds, [_requestId, _requestId]);
    },
  );

  test('wrong account retains marker without cloud completion', () async {
    final fixture = await _RecoveryFixture.create(accountId: _otherAccountId);
    addTearDown(fixture.dispose);

    await fixture.controller.recover();

    expect(fixture.gateway.completedRequestIds, isEmpty);
    expect(fixture.state.failure?.code, FamilyJoinFailureCode.forbidden);
    expect(await fixture.repository.find(fixture.database), fixture.pending);
  });

  test(
    'missing joining key for approved request fails before completion',
    () async {
      final fixture = await _RecoveryFixture.create(createJoiningKey: false);
      addTearDown(fixture.dispose);

      await fixture.controller.recover();

      expect(fixture.events, ['find-key', 'get-own']);
      expect(fixture.gateway.completedRequestIds, isEmpty);
      expect(fixture.state.failure?.code, FamilyJoinFailureCode.invalidJoinKey);
      expect(await fixture.repository.find(fixture.database), fixture.pending);
    },
  );

  test(
    'non-null mismatched joining key is rejected before completion',
    () async {
      final fixture = await _RecoveryFixture.create(mismatchedJoiningKey: true);
      addTearDown(fixture.dispose);

      await fixture.controller.recover();

      expect(fixture.events, ['find-key']);
      expect(fixture.gateway.completedRequestIds, isEmpty);
      expect(fixture.state.failure?.code, FamilyJoinFailureCode.invalidJoinKey);
      expect(await fixture.repository.find(fixture.database), fixture.pending);
    },
  );

  test(
    'retained marker with already-cleaned key completes on next recovery',
    () async {
      final fixture = await _RecoveryFixture.create(failMarkerDelete: true);
      addTearDown(fixture.dispose);

      await fixture.controller.recover();

      expect(
        fixture.state.failure?.code,
        FamilyJoinFailureCode.localPersistenceFailed,
      );
      expect(await fixture.repository.find(fixture.database), fixture.pending);
      expect(
        await fixture.keys.find(accountId: _accountId, memberId: _memberId),
        isNull,
      );
      await fixture.database.execute('DROP TRIGGER fail_pending_join_delete');
      fixture.events.clear();

      await fixture.controller.recover();

      expect(fixture.events, ['find-key', 'get-own', 'delete-marker']);
      expect(fixture.gateway.completedRequestIds, [_requestId]);
      expect(fixture.state.phase, PendingJoinCompletionPhase.complete);
      expect(await fixture.repository.find(fixture.database), isNull);
    },
  );

  test('missing key does not clean a mismatched installed request', () async {
    final fixture = await _RecoveryFixture.create(
      createJoiningKey: false,
      requestState: FamilyJoinRequestState.installed,
      ownRequestId: _otherRequestId,
    );
    addTearDown(fixture.dispose);

    await fixture.controller.recover();

    expect(fixture.events, ['find-key', 'get-own']);
    expect(fixture.gateway.completedRequestIds, isEmpty);
    expect(fixture.state.failure?.code, FamilyJoinFailureCode.invalidJoinKey);
    expect(await fixture.repository.find(fixture.database), fixture.pending);
  });

  test('key replacement during exact deletion preserves the marker', () async {
    final fixture = await _RecoveryFixture.create(
      replaceJoiningKeyBeforeDelete: true,
    );
    addTearDown(fixture.dispose);

    await fixture.controller.recover();

    expect(fixture.events, ['find-key', 'complete', 'delete-key', 'find-key']);
    expect(fixture.state.failure?.code, FamilyJoinFailureCode.invalidJoinKey);
    expect(await fixture.repository.find(fixture.database), fixture.pending);
    expect(
      await fixture.keys.find(accountId: _accountId, memberId: _memberId),
      isNotNull,
    );
  });

  test('marker deletion failure preserves the exact marker', () async {
    final fixture = await _RecoveryFixture.create(failMarkerDelete: true);
    addTearDown(fixture.dispose);

    await fixture.controller.recover();

    expect(fixture.events, [
      'find-key',
      'complete',
      'delete-key',
      'find-key',
      'delete-marker',
    ]);
    expect(
      fixture.state.failure?.code,
      FamilyJoinFailureCode.localPersistenceFailed,
    );
    expect(await fixture.repository.find(fixture.database), fixture.pending);
  });
}

final class _RecoveryFixture {
  _RecoveryFixture({
    required this.database,
    required this.container,
    required this.subscription,
    required this.gateway,
    required this.keys,
    required this.pending,
    required this.events,
  });

  final Database database;
  final ProviderContainer container;
  final ProviderSubscription<PendingJoinCompletionState> subscription;
  final _RecoveryGateway gateway;
  final JoiningKeyStore keys;
  final PendingJoinCompletion pending;
  final List<String> events;
  final repository = const PendingJoinCompletionRepository();

  PendingJoinCompletionController get controller =>
      container.read(pendingJoinCompletionControllerProvider.notifier);
  PendingJoinCompletionState get state =>
      container.read(pendingJoinCompletionControllerProvider);

  static Future<_RecoveryFixture> create({
    String? accountId = _accountId,
    List<FamilyJoinFailure> failures = const [],
    bool createJoiningKey = true,
    bool mismatchedJoiningKey = false,
    bool replaceJoiningKeyBeforeDelete = false,
    bool failMarkerDelete = false,
    FamilyJoinRequestState requestState = FamilyJoinRequestState.approved,
    String ownRequestId = _requestId,
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
    await database.insert('members', {
      'id': _memberId,
      'family_id': _familyId,
      'name': 'Mariam',
      'role': 'adult',
      'created_at': 1,
      'member_key_ref': 'member-key',
      'color_token': 'teal',
      'avatar_config_json': '{}',
    });
    final pending = PendingJoinCompletion(
      requestId: _requestId,
      familyId: _familyId,
      memberId: _memberId,
      accountId: _accountId,
      installedAt: DateTime.utc(2026, 9, 5),
    );
    const repository = PendingJoinCompletionRepository();
    await repository.recordExact(database, pending);
    if (failMarkerDelete) {
      await database.execute(r'''
CREATE TRIGGER fail_pending_join_delete
BEFORE DELETE ON pending_family_join_completion
BEGIN
  SELECT RAISE(ABORT, 'delete failed');
END
''');
    }

    final values = _MemorySecureValueStore();
    final delegate = SecureJoiningKeyStore(
      values,
      seedFactory: (length) => List<int>.generate(length, (index) => index),
    );
    if (createJoiningKey) {
      await delegate.getOrCreate(
        accountId: mismatchedJoiningKey ? _otherAccountId : _accountId,
        memberId: _memberId,
      );
    }
    final events = <String>[];
    final keys = _TrackingJoiningKeyStore(
      delegate,
      events,
      lookupAccountId: mismatchedJoiningKey ? _otherAccountId : null,
      beforeDelete: replaceJoiningKeyBeforeDelete
          ? (key) {
              values.values[key.reference] = unpaddedFamilyJoinBase64Url(
                List<int>.filled(SecureJoiningKeyStore.seedLength, 29),
              );
            }
          : null,
    );
    final gateway = _RecoveryGateway(
      accountId,
      failures,
      events,
      requestState: requestState,
      ownRequestId: ownRequestId,
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(AsyncValue.data(database)),
        familyCodeJoinGatewayProvider.overrideWithValue(gateway),
        joiningKeyStoreProvider.overrideWithValue(keys),
        pendingJoinCompletionDeleteExactProvider.overrideWithValue((
          database,
          pending,
        ) async {
          events.add('delete-marker');
          await repository.deleteExact(database, pending);
        }),
      ],
    );
    final subscription = container.listen(
      pendingJoinCompletionControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    return _RecoveryFixture(
      database: database,
      container: container,
      subscription: subscription,
      gateway: gateway,
      keys: keys,
      pending: pending,
      events: events,
    );
  }

  Future<void> dispose() async {
    subscription.close();
    container.dispose();
    await database.close();
  }
}

final class _TrackingJoiningKeyStore implements JoiningKeyStore {
  _TrackingJoiningKeyStore(
    this.delegate,
    this.events, {
    this.lookupAccountId,
    this.beforeDelete,
  });

  final JoiningKeyStore delegate;
  final List<String> events;
  final String? lookupAccountId;
  final void Function(StoredJoiningKey key)? beforeDelete;

  @override
  Future<StoredJoiningKey> getOrCreate({
    required String accountId,
    required String memberId,
  }) => delegate.getOrCreate(accountId: accountId, memberId: memberId);

  @override
  Future<StoredJoiningKey?> find({
    required String accountId,
    required String memberId,
  }) {
    events.add('find-key');
    return delegate.find(
      accountId: lookupAccountId ?? accountId,
      memberId: memberId,
    );
  }

  @override
  Future<T> use<T>({
    required StoredJoiningKey key,
    required Future<T> Function(SimpleKeyPair keyPair) operation,
  }) => delegate.use(key: key, operation: operation);

  @override
  Future<void> deleteExact(StoredJoiningKey key) {
    events.add('delete-key');
    beforeDelete?.call(key);
    return delegate.deleteExact(key);
  }
}

final class _RecoveryGateway implements FamilyCodeJoinGateway {
  _RecoveryGateway(
    this.accountId,
    List<FamilyJoinFailure> failures,
    this.events, {
    required this.requestState,
    required this.ownRequestId,
  }) : failures = List.of(failures);

  String? accountId;
  final List<FamilyJoinFailure> failures;
  final List<String> events;
  final List<String> completedRequestIds = [];
  FamilyJoinRequestState requestState;
  final String ownRequestId;

  @override
  bool get isConfigured => true;
  @override
  String? get authenticatedAccountId => accountId;

  @override
  Future<FamilyJoinDecision> completeJoinRequest(String requestId) async {
    events.add('complete');
    completedRequestIds.add(requestId);
    if (failures.isNotEmpty) throw failures.removeAt(0);
    requestState = FamilyJoinRequestState.installed;
    return FamilyJoinDecision(
      requestId: requestId,
      familyId: _familyId,
      state: FamilyJoinRequestState.installed,
      updatedAt: DateTime.utc(2026, 9, 5),
    );
  }

  @override
  Future<FamilyJoinDecision> approveJoinRequest(
    String requestId,
    FamilyJoinApprovalEnvelope envelope,
  ) => throw UnimplementedError();
  @override
  Future<EncryptedFamilyCodeRecord> bootstrapOwnerWithFamilyCode(
    LocalOwnerFamily owner,
    FamilyCodeDraft code,
  ) => throw UnimplementedError();
  @override
  Future<FamilyJoinDecision> cancelJoinRequest(String requestId) =>
      throw UnimplementedError();
  @override
  Future<OwnFamilyJoinRequest> createFamilyJoinRequest(
    FamilyJoinRequestDraft draft,
  ) => throw UnimplementedError();
  @override
  Future<FamilyJoinDecision> declineJoinRequest(String requestId) =>
      throw UnimplementedError();
  @override
  Future<EncryptedFamilyCodeRecord> getFamilyCode(String familyId) =>
      throw UnimplementedError();
  @override
  Future<OwnFamilyJoinRequest?> getOwnJoinRequest() async {
    events.add('get-own');
    return _ownRequest(requestId: ownRequestId, state: requestState);
  }

  @override
  Future<List<PendingFamilyJoinRequest>> listPendingJoinRequests(
    String familyId,
  ) => throw UnimplementedError();
  @override
  Future<FamilyJoinPreview> previewFamilyByCode(FamilyCode code) =>
      throw UnimplementedError();
  @override
  Future<EncryptedFamilyCodeRecord> regenerateFamilyCode({
    required String familyId,
    required int expectedVersion,
    required FamilyCodeDraft replacement,
  }) => throw UnimplementedError();
  @override
  Stream<void> watchOwnJoinRequest() => const Stream.empty();
  @override
  Stream<void> watchPendingJoinRequests(String familyId) =>
      const Stream.empty();
}

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const _requestId = '11111111-1111-4111-8111-111111111111';
const _otherRequestId = '66666666-6666-4666-8666-666666666666';
const _familyId = '22222222-2222-4222-8222-222222222222';
const _accountId = '33333333-3333-4333-8333-333333333333';
const _memberId = '44444444-4444-4444-8444-444444444444';
const _otherAccountId = '55555555-5555-4555-8555-555555555555';

OwnFamilyJoinRequest _ownRequest({
  required String requestId,
  required FamilyJoinRequestState state,
}) => OwnFamilyJoinRequest(
  requestId: requestId,
  familyId: _familyId,
  familyName: 'Sabati',
  requesterAccountId: _accountId,
  memberId: _memberId,
  displayName: 'Mariam',
  demographicRole: FamilyDemographicRole.adult,
  colorToken: 'teal',
  avatar: AvatarConfig.defaults(seed: _memberId),
  joiningPublicKey: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
  codeVersion: 1,
  state: state,
  createdAt: DateTime.utc(2026, 9, 5),
  expiresAt: DateTime.utc(2026, 9, 12),
);
