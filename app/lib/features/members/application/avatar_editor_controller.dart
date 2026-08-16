import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/members/domain/avatar_catalog.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/database_providers.dart';

enum AvatarSavePhase { idle, saving, failed }

final class AvatarEditorState {
  const AvatarEditorState({
    required this.original,
    required this.draft,
    this.phase = AvatarSavePhase.idle,
    this.errorMessage,
  });

  final AvatarConfig original;
  final AvatarConfig draft;
  final AvatarSavePhase phase;
  final String? errorMessage;

  bool get isDirty => draft != original;
  bool get canSave => isDirty && phase != AvatarSavePhase.saving;
}

final avatarEditorControllerProvider = NotifierProvider.autoDispose
    .family<AvatarEditorController, AvatarEditorState, LocalIdentity>(
      AvatarEditorController.new,
    );

typedef AvatarSave = Future<void> Function({
  required String memberId,
  required AvatarConfig avatar,
});

final avatarSaveProvider = Provider<AvatarSave>((ref) {
  return ({required memberId, required avatar}) async {
    final db = await ref.read(databaseProvider.future);
    await ref
        .read(memberRepositoryProvider)
        .updateAvatar(db, memberId: memberId, avatar: avatar);
  };
});

final class AvatarEditorController extends Notifier<AvatarEditorState> {
  AvatarEditorController(this.identity);

  final LocalIdentity identity;
  Future<bool>? _inFlightSave;

  @override
  AvatarEditorState build() =>
      AvatarEditorState(original: identity.avatar, draft: identity.avatar);

  void select(AvatarOption option) {
    if (state.phase == AvatarSavePhase.saving) return;

    final next = avatarCatalog.sanitize(
      option.apply(state.draft),
      fallbackSeed: identity.memberId,
    );
    state = AvatarEditorState(original: state.original, draft: next);
  }

  Future<bool> save() {
    if (state.phase == AvatarSavePhase.saving || _inFlightSave != null) {
      return Future.value(false);
    }
    if (!state.isDirty) return Future.value(false);

    final submitted = state.draft;
    final operation = _persist(submitted);
    _inFlightSave = operation;
    return operation;
  }

  Future<bool> _persist(AvatarConfig submitted) async {
    if (ref.mounted) {
      state = AvatarEditorState(
        original: state.original,
        draft: state.draft,
        phase: AvatarSavePhase.saving,
      );
    }

    try {
      await ref.read(avatarSaveProvider)(
        memberId: identity.memberId,
        avatar: submitted,
      );

      if (ref.mounted) {
        state = AvatarEditorState(original: submitted, draft: submitted);
        ref.invalidate(localIdentityProvider);
      }
      return true;
    } catch (_) {
      if (ref.mounted) {
        state = AvatarEditorState(
          original: state.original,
          draft: submitted,
          phase: AvatarSavePhase.failed,
          errorMessage: 'Your avatar could not be saved. Try again.',
        );
      }
      return false;
    } finally {
      _inFlightSave = null;
    }
  }
}
