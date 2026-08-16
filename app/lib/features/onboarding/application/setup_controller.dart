import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  });

  final SetupPhase phase;
  final String? validationMessage;
  final String? errorMessage;

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
      final database = await ref.read(databaseProvider.future);
      final createdAt = ref.read(utcNowProvider)();

      await database.transaction((transaction) async {
        await ref
            .read(familyRepositoryProvider)
            .insert(
              transaction,
              id: familyId,
              name: input.familyName,
              familyKeyRef: createdKeys.familyKeyRef,
              createdAt: createdAt,
            );
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
        await ref
            .read(memberRepositoryProvider)
            .bindLocalIdentity(
              transaction,
              familyId: familyId,
              memberId: memberId,
            );
      });

      ref.invalidate(localIdentityProvider);
      state = const SetupState();
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
}
