import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_join_crypto_providers.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/family/data/joining_key_store.dart';
import 'package:keepers/features/family/data/pending_join_completion_repository.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show DatabaseExecutor;

enum PendingJoinCompletionPhase { idle, checking, completing, complete, failed }

final class PendingJoinCompletionState {
  const PendingJoinCompletionState({
    this.phase = PendingJoinCompletionPhase.idle,
    this.failure,
  });

  final PendingJoinCompletionPhase phase;
  final FamilyJoinFailure? failure;

  @override
  String toString() => 'PendingJoinCompletionState(${phase.name})';
}

typedef PendingJoinCompletionDeleteExact = Future<void> Function(
  DatabaseExecutor database,
  PendingJoinCompletion pending,
);

final pendingJoinCompletionDeleteExactProvider =
    Provider<PendingJoinCompletionDeleteExact>(
      (ref) => ref.watch(pendingJoinCompletionRepositoryProvider).deleteExact,
    );

final pendingJoinCompletionControllerProvider =
    NotifierProvider.autoDispose<
      PendingJoinCompletionController,
      PendingJoinCompletionState
    >(PendingJoinCompletionController.new);

final class PendingJoinCompletionController
    extends Notifier<PendingJoinCompletionState> {
  Future<void>? _inFlight;
  var _generation = 0;

  @override
  PendingJoinCompletionState build() {
    ref.onDispose(() => _generation += 1);
    return const PendingJoinCompletionState();
  }

  Future<void> recover() => _deduplicate(() async {
    final generation = ++_generation;
    state = const PendingJoinCompletionState(
      phase: PendingJoinCompletionPhase.checking,
    );
    try {
      final database = await ref.read(databaseProvider.future);
      if (!_isCurrent(generation)) return;
      final pending = await ref
          .read(pendingJoinCompletionRepositoryProvider)
          .find(database);
      if (!_isCurrent(generation)) return;
      if (pending == null) {
        state = const PendingJoinCompletionState();
        return;
      }

      final gateway = ref.read(familyCodeJoinGatewayProvider);
      if (!gateway.isConfigured) {
        _fail(FamilyJoinFailureCode.notConfigured);
        return;
      }
      final accountId = gateway.authenticatedAccountId;
      if (accountId == null) {
        _fail(FamilyJoinFailureCode.signedOut);
        return;
      }
      if (accountId != pending.accountId) {
        _fail(FamilyJoinFailureCode.forbidden);
        return;
      }

      state = const PendingJoinCompletionState(
        phase: PendingJoinCompletionPhase.completing,
      );
      final joiningKeys = ref.read(joiningKeyStoreProvider);
      final joiningKey = await joiningKeys.find(
        accountId: pending.accountId,
        memberId: pending.memberId,
      );
      if (!_accountIsCurrent(generation, accountId)) {
        _fail(FamilyJoinFailureCode.signedOut);
        return;
      }
      final expectedReference = SecureJoiningKeyStore.referenceFor(
        accountId: pending.accountId,
        memberId: pending.memberId,
      );
      if (joiningKey != null && joiningKey.reference != expectedReference) {
        throw const FamilyJoinFailure(FamilyJoinFailureCode.invalidJoinKey);
      }

      if (joiningKey == null) {
        final ownRequest = await gateway.getOwnJoinRequest();
        if (!_accountIsCurrent(generation, accountId)) {
          _fail(FamilyJoinFailureCode.signedOut);
          return;
        }
        final isExactInstalledRequest =
            ownRequest != null &&
            ownRequest.state == FamilyJoinRequestState.installed &&
            ownRequest.requestId == pending.requestId &&
            ownRequest.familyId == pending.familyId &&
            ownRequest.memberId == pending.memberId &&
            ownRequest.requesterAccountId == pending.accountId;
        if (!isExactInstalledRequest) {
          throw const FamilyJoinFailure(FamilyJoinFailureCode.invalidJoinKey);
        }
      } else {
        final decision = await gateway.completeJoinRequest(pending.requestId);
        if (!_accountIsCurrent(generation, accountId)) {
          _fail(FamilyJoinFailureCode.signedOut);
          return;
        }
        if (decision.requestId != pending.requestId ||
            decision.familyId != pending.familyId ||
            decision.state != FamilyJoinRequestState.installed) {
          throw const FamilyJoinFailure(FamilyJoinFailureCode.unknown);
        }

        await joiningKeys.deleteExact(joiningKey);
        if (!_accountIsCurrent(generation, accountId)) {
          _fail(FamilyJoinFailureCode.signedOut);
          return;
        }
        final remainingJoiningKey = await joiningKeys.find(
          accountId: pending.accountId,
          memberId: pending.memberId,
        );
        if (!_accountIsCurrent(generation, accountId)) {
          _fail(FamilyJoinFailureCode.signedOut);
          return;
        }
        if (remainingJoiningKey != null) {
          throw const FamilyJoinFailure(FamilyJoinFailureCode.invalidJoinKey);
        }
      }
      await ref.read(pendingJoinCompletionDeleteExactProvider)(
        database,
        pending,
      );

      ref.invalidate(localIdentityProvider);
      ref.invalidate(familyRosterProvider(pending.familyId));
      state = const PendingJoinCompletionState(
        phase: PendingJoinCompletionPhase.complete,
      );
    } on FamilyJoinFailure catch (failure) {
      if (_isCurrent(generation)) {
        state = PendingJoinCompletionState(
          phase: PendingJoinCompletionPhase.failed,
          failure: failure,
        );
      }
    } on Object {
      if (_isCurrent(generation)) {
        _fail(FamilyJoinFailureCode.localPersistenceFailed);
      }
    }
  });

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

  bool _accountIsCurrent(int generation, String accountId) {
    if (!_isCurrent(generation)) return false;
    final gateway = ref.read(familyCodeJoinGatewayProvider);
    return gateway.isConfigured && gateway.authenticatedAccountId == accountId;
  }

  void _fail(FamilyJoinFailureCode code) {
    if (!ref.mounted) return;
    state = PendingJoinCompletionState(
      phase: PendingJoinCompletionPhase.failed,
      failure: FamilyJoinFailure(code),
    );
  }
}
