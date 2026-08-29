import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/database_providers.dart';

enum SetupPhase { idle, submitting, failed }

final class SetupState {
  const SetupState({
    this.phase = SetupPhase.idle,
    this.validationMessage,
    this.errorMessage,
    this.requiresAuthentication = false,
  });

  final SetupPhase phase;
  final String? validationMessage;
  final String? errorMessage;
  final bool requiresAuthentication;

  bool get isSubmitting => phase == SetupPhase.submitting;
}

final setupControllerProvider = NotifierProvider<SetupController, SetupState>(
  SetupController.new,
);

final class SetupController extends Notifier<SetupState> {
  @override
  SetupState build() => const SetupState();

  Future<void> submit(SetupInput input) async {
    if (state.isSubmitting) return;
    if (input.validationMessage case final validationMessage?) {
      state = SetupState(validationMessage: validationMessage);
      return;
    }

    final accountId = ref
        .read(cloudFamilyGatewayProvider)
        .authenticatedAccountId;
    if (accountId == null) {
      _setSessionEnded();
      return;
    }

    state = const SetupState(phase: SetupPhase.submitting);
    final familyId = ref.read(idFactoryProvider)();
    final memberId = ref.read(idFactoryProvider)();
    final avatar = AvatarConfig.defaults(seed: memberId);
    CreatedIdentityKeys? keys;

    try {
      final createdKeys = await ref
          .read(identityKeyServiceProvider)
          .createFor(familyId: familyId, memberId: memberId);
      keys = createdKeys;
      _requireCurrentAccount(accountId);
      final database = await ref.read(databaseProvider.future);
      _requireCurrentAccount(accountId);
      final createdAt = ref.read(utcNowProvider)();

      await database.transaction((transaction) async {
        _requireCurrentAccount(accountId);
        await ref
            .read(familyRepositoryProvider)
            .insert(
              transaction,
              id: familyId,
              name: input.familyName,
              familyKeyRef: createdKeys.familyKeyRef,
              createdAt: createdAt,
            );
        _requireCurrentAccount(accountId);
        await ref
            .read(memberRepositoryProvider)
            .insert(
              transaction,
              id: memberId,
              familyId: familyId,
              name: input.memberName,
              memberKeyRef: createdKeys.memberKeyRef,
              colorToken: 'ochre',
              avatar: avatar,
              createdAt: createdAt,
            );
        _requireCurrentAccount(accountId);
        await ref
            .read(memberRepositoryProvider)
            .bindLocalIdentity(
              transaction,
              familyId: familyId,
              memberId: memberId,
              // The cloud owner bootstrap is the authority that proves this
              // account belongs to the new family. Keep the local profile
              // unbound until that succeeds so an existing account cannot be
              // permanently attached to a conflicting local family.
              accountId: null,
            );
        _requireCurrentAccount(accountId);
      });

      ref.invalidate(localIdentityProvider);
      state = const SetupState();
    } on _SetupSessionEnded {
      if (keys != null) {
        await ref.read(identityKeyServiceProvider).rollback(keys);
      }
      _setSessionEnded();
    } catch (_) {
      if (keys != null) {
        await ref.read(identityKeyServiceProvider).rollback(keys);
      }
      state = const SetupState(
        phase: SetupPhase.failed,
        errorMessage: 'Your family space could not be secured. Try again.',
      );
    }
  }

  void _requireCurrentAccount(String expectedAccountId) {
    if (ref.read(cloudFamilyGatewayProvider).authenticatedAccountId !=
        expectedAccountId) {
      throw const _SetupSessionEnded();
    }
  }

  void _setSessionEnded() {
    state = const SetupState(
      phase: SetupPhase.failed,
      errorMessage: 'Your account session ended. Sign in again.',
      requiresAuthentication: true,
    );
  }
}

final class _SetupSessionEnded implements Exception {
  const _SetupSessionEnded();
}
