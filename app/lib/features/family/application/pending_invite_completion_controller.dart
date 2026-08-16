import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/family/data/pending_invite_completion_repository.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show DatabaseExecutor;

enum PendingInviteCompletionPhase {
  idle,
  checking,
  completing,
  complete,
  failed,
}

final class PendingInviteCompletionState {
  const PendingInviteCompletionState({
    this.phase = PendingInviteCompletionPhase.idle,
    this.failure,
  });

  final PendingInviteCompletionPhase phase;
  final InvitationFailure? failure;

  @override
  String toString() => 'PendingInviteCompletionState(${phase.name})';
}

final pendingInviteCompletionRepositoryProvider =
    Provider<PendingInviteCompletionRepository>(
      (ref) => const PendingInviteCompletionRepository(),
    );

typedef PendingInviteCompletionDeleteExact = Future<void> Function(
  DatabaseExecutor database,
  PendingInviteCompletion pending,
);

final pendingInviteCompletionDeleteExactProvider =
    Provider<PendingInviteCompletionDeleteExact>(
      (ref) => ref.watch(pendingInviteCompletionRepositoryProvider).deleteExact,
    );

final pendingInviteCompletionControllerProvider =
    NotifierProvider.autoDispose<
      PendingInviteCompletionController,
      PendingInviteCompletionState
    >(PendingInviteCompletionController.new);

final class PendingInviteCompletionController
    extends Notifier<PendingInviteCompletionState> {
  Future<void>? _inFlight;
  var _generation = 0;

  @override
  PendingInviteCompletionState build() {
    ref.onDispose(() => _generation += 1);
    return const PendingInviteCompletionState();
  }

  Future<void> recover() => _deduplicate(() async {
    final generation = ++_generation;
    state = const PendingInviteCompletionState(
      phase: PendingInviteCompletionPhase.checking,
    );
    final gateway = ref.read(cloudFamilyGatewayProvider);
    if (!gateway.isConfigured) {
      _fail(InvitationFailureCode.notConfigured);
      return;
    }
    try {
      final database = await ref.read(databaseProvider.future);
      if (!_isCurrent(generation)) return;
      final pending = await ref
          .read(pendingInviteCompletionRepositoryProvider)
          .find(database);
      if (!_isCurrent(generation)) return;
      if (pending == null) {
        state = const PendingInviteCompletionState();
        return;
      }
      final accountId = gateway.authenticatedAccountId;
      if (accountId == null) {
        _fail(InvitationFailureCode.signedOut);
        return;
      }
      if (accountId != pending.accountId) {
        _fail(InvitationFailureCode.forbidden);
        return;
      }
      state = const PendingInviteCompletionState(
        phase: PendingInviteCompletionPhase.completing,
      );
      await gateway.completeInvitation(pending.inviteId);
      if (!_accountIsCurrent(generation, accountId)) {
        _fail(InvitationFailureCode.signedOut);
        return;
      }
      await ref.read(pendingInviteCompletionDeleteExactProvider)(
        database,
        pending,
      );
      if (!_accountIsCurrent(generation, accountId)) {
        _fail(InvitationFailureCode.signedOut);
        return;
      }
      ref.invalidate(localIdentityProvider);
      ref.invalidate(familyRosterProvider(pending.familyId));
      state = const PendingInviteCompletionState(
        phase: PendingInviteCompletionPhase.complete,
      );
    } on InvitationFailure catch (failure) {
      if (_isCurrent(generation)) {
        state = PendingInviteCompletionState(
          phase: PendingInviteCompletionPhase.failed,
          failure: failure,
        );
      }
    } on Object {
      if (_isCurrent(generation)) {
        _fail(InvitationFailureCode.localPersistenceFailed);
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

  bool _accountIsCurrent(int generation, String accountId) =>
      _isCurrent(generation) &&
      ref.read(cloudFamilyGatewayProvider).authenticatedAccountId == accountId;

  void _fail(InvitationFailureCode code) {
    if (!ref.mounted) return;
    state = PendingInviteCompletionState(
      phase: PendingInviteCompletionPhase.failed,
      failure: InvitationFailure(code),
    );
  }
}
