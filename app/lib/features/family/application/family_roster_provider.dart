import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

typedef FamilyRosterUpsert = Future<void> Function(
  DatabaseExecutor database, {
  required String familyId,
  required List<FamilyMember> members,
});

final familyRosterUpsertProvider = Provider<FamilyRosterUpsert>((ref) {
  final repository = ref.watch(familyRosterRepositoryProvider);
  return (database, {required familyId, required members}) => repository
      .upsertCloudRoster(database, familyId: familyId, members: members);
});

final class FamilyRosterState {
  FamilyRosterState({
    List<FamilyMember> members = const [],
    this.hasLoadedLocal = false,
    this.isRefreshing = false,
    this.refreshFailure,
  }) : members = List<FamilyMember>.unmodifiable(members);

  final List<FamilyMember> members;
  final bool hasLoadedLocal;
  final bool isRefreshing;
  final InvitationFailure? refreshFailure;

  @override
  String toString() =>
      'FamilyRosterState(loaded: $hasLoadedLocal, refreshing: $isRefreshing)';
}

final familyRosterProvider = NotifierProvider.autoDispose
    .family<FamilyRosterController, FamilyRosterState, String>(
      FamilyRosterController.new,
    );

typedef FamilyRosterRefresh = Future<void> Function();

/// Keeps presentation surfaces dependent on the roster state, while exposing a
/// narrow refresh command that can be replaced in widget and lifecycle tests.
final familyRosterRefreshProvider = Provider.autoDispose
    .family<FamilyRosterRefresh, String>(
      (ref, familyId) =>
          () => ref.read(familyRosterProvider(familyId).notifier).refresh(),
    );

final class FamilyRosterController extends Notifier<FamilyRosterState> {
  FamilyRosterController(this._familyId);

  final String _familyId;
  Future<void>? _inFlight;
  var _generation = 0;

  @override
  FamilyRosterState build() {
    ref.onDispose(() => _generation += 1);
    unawaited(Future<void>.microtask(load));
    return FamilyRosterState();
  }

  Future<void> load() => _deduplicate(() async {
    final generation = ++_generation;
    try {
      final database = await ref.read(databaseProvider.future);
      if (!_isCurrent(generation)) return;
      final local = await ref
          .read(familyRosterRepositoryProvider)
          .listLocal(database, familyId: _familyId);
      if (!_isCurrent(generation)) return;
      state = FamilyRosterState(
        members: local,
        hasLoadedLocal: true,
        isRefreshing: true,
      );
      await _refreshFromCloud(database, generation);
    } on Object {
      if (_isCurrent(generation)) {
        state = FamilyRosterState(
          members: state.members,
          hasLoadedLocal: state.hasLoadedLocal,
          refreshFailure: const InvitationFailure(
            InvitationFailureCode.localPersistenceFailed,
          ),
        );
      }
    }
  });

  Future<void> refresh() {
    if (!state.hasLoadedLocal) return load();
    return _deduplicate(() async {
      final generation = ++_generation;
      state = FamilyRosterState(
        members: state.members,
        hasLoadedLocal: true,
        isRefreshing: true,
      );
      try {
        final database = await ref.read(databaseProvider.future);
        if (!_isCurrent(generation)) return;
        await _refreshFromCloud(database, generation);
      } on Object {
        if (_isCurrent(generation)) {
          state = FamilyRosterState(
            members: state.members,
            hasLoadedLocal: true,
            refreshFailure: const InvitationFailure(
              InvitationFailureCode.localPersistenceFailed,
            ),
          );
        }
      }
    });
  }

  Future<void> _refreshFromCloud(Database database, int generation) async {
    final gateway = ref.read(cloudFamilyGatewayProvider);
    final accountId = gateway.authenticatedAccountId;
    if (!gateway.isConfigured || accountId == null) {
      if (_isCurrent(generation)) {
        state = FamilyRosterState(members: state.members, hasLoadedLocal: true);
      }
      return;
    }
    try {
      final cloud = await gateway.listActiveMembers(_familyId);
      if (!_isCurrent(generation)) return;
      if (gateway.authenticatedAccountId != accountId) {
        state = FamilyRosterState(
          members: state.members,
          hasLoadedLocal: true,
          refreshFailure: const InvitationFailure(
            InvitationFailureCode.signedOut,
          ),
        );
        return;
      }
      await database.transaction((transaction) async {
        await ref.read(familyRosterUpsertProvider)(
          transaction,
          familyId: _familyId,
          members: cloud,
        );
        if (!_accountIsCurrent(generation, accountId)) {
          throw const InvitationFailure(InvitationFailureCode.signedOut);
        }
      });
      if (!_accountIsCurrent(generation, accountId)) return;
      final refreshed = await ref
          .read(familyRosterRepositoryProvider)
          .listLocal(database, familyId: _familyId);
      if (!_accountIsCurrent(generation, accountId)) return;
      state = FamilyRosterState(members: refreshed, hasLoadedLocal: true);
    } on InvitationFailure catch (failure) {
      if (_isCurrent(generation)) {
        state = FamilyRosterState(
          members: state.members,
          hasLoadedLocal: true,
          refreshFailure: failure,
        );
      }
    } on Object {
      if (_isCurrent(generation)) {
        state = FamilyRosterState(
          members: state.members,
          hasLoadedLocal: true,
          refreshFailure: const InvitationFailure(
            InvitationFailureCode.localPersistenceFailed,
          ),
        );
      }
    }
  }

  Future<void> _deduplicate(Future<void> Function() operation) {
    final running = _inFlight;
    if (running != null) return running;
    late final Future<void> future;
    future = operation().whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  bool _accountIsCurrent(int generation, String accountId) =>
      _isCurrent(generation) &&
      ref.read(cloudFamilyGatewayProvider).authenticatedAccountId == accountId;
}
