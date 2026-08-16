import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/members/application/avatar_editor_controller.dart';
import 'package:keepers/features/members/domain/avatar_catalog.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';

const _identity = LocalIdentity(
  familyId: 'family-1',
  familyName: 'Sabati',
  familyKeyRef: 'family-key',
  memberId: 'member-1',
  memberName: 'Chris',
  memberKeyRef: 'member-key',
  colorToken: 'ochre',
  avatar: AvatarConfig.defaults(seed: 'member-1'),
);

void main() {
  test('initial state starts with the identity avatar as a clean draft', () {
    final container = _container();
    addTearDown(container.dispose);

    final state = container.read(avatarEditorControllerProvider(_identity));

    expect(state.original, _identity.avatar);
    expect(state.draft, _identity.avatar);
    expect(state.phase, AvatarSavePhase.idle);
    expect(state.isDirty, isFalse);
    expect(state.canSave, isFalse);
    expect(state.errorMessage, isNull);
  });

  test('selection applies a Humation option as the local draft', () {
    final container = _container();
    addTearDown(container.dispose);
    final controller = container.read(
      avatarEditorControllerProvider(_identity).notifier,
    );
    final option = avatarCatalog.optionsFor(AvatarCategory.head).first;
    final expected = avatarCatalog.sanitize(
      option.apply(_identity.avatar),
      fallbackSeed: _identity.memberId,
    );

    controller.select(option);

    expect(
      container.read(avatarEditorControllerProvider(_identity)).draft,
      expected,
    );
    expect(
      container.read(avatarEditorControllerProvider(_identity)).isDirty,
      isTrue,
    );
  });

  test(
    'duplicate selection remains stable and marks a changed recipe dirty',
    () {
      final container = _container();
      addTearDown(container.dispose);
      final controller = container.read(
        avatarEditorControllerProvider(_identity).notifier,
      );
      final option = avatarCatalog.optionsFor(AvatarCategory.body).first;

      controller.select(option);
      final selected = container.read(
        avatarEditorControllerProvider(_identity),
      );
      controller.select(option);

      expect(selected.draft, isNot(_identity.avatar));
      expect(selected.isDirty, isTrue);
      expect(selected.canSave, isTrue);
      expect(
        container.read(avatarEditorControllerProvider(_identity)).draft,
        selected.draft,
      );
    },
  );

  test(
    'save captures one immutable recipe and ignores later selections',
    () async {
      final gate = Completer<void>();
      AvatarConfig? submitted;
      final container = _container(
        save: ({required memberId, required avatar}) async {
          submitted = avatar;
          await gate.future;
        },
      );
      addTearDown(container.dispose);
      final controller = container.read(
        avatarEditorControllerProvider(_identity).notifier,
      );
      final hair = avatarCatalog.optionsFor(AvatarCategory.body).first;
      final face = avatarCatalog.optionsFor(AvatarCategory.head).first;
      controller.select(hair);
      final expected = container
          .read(avatarEditorControllerProvider(_identity))
          .draft;

      final save = controller.save();
      expect(
        container.read(avatarEditorControllerProvider(_identity)).phase,
        AvatarSavePhase.saving,
      );
      controller.select(face);
      expect(
        container.read(avatarEditorControllerProvider(_identity)).draft,
        expected,
      );
      expect(submitted, expected);

      gate.complete();
      expect(await save, isTrue);
      final state = container.read(avatarEditorControllerProvider(_identity));
      expect(state.original, expected);
      expect(state.draft, expected);
      expect(state.phase, AvatarSavePhase.idle);
    },
  );

  test('synchronous double save issues only one persistence write', () async {
    final gate = Completer<void>();
    var writes = 0;
    final container = _container(
      save: ({required memberId, required avatar}) async {
        writes++;
        await gate.future;
      },
    );
    addTearDown(container.dispose);
    final controller = container.read(
      avatarEditorControllerProvider(_identity).notifier,
    );
    controller.select(avatarCatalog.optionsFor(AvatarCategory.head)[1]);

    final first = controller.save();
    final second = controller.save();
    expect(await second, isFalse);
    expect(writes, 1);
    gate.complete();
    expect(await first, isTrue);
  });

  test(
    'successful save commits the submitted recipe and invalidates identity',
    () async {
      var invalidations = 0;
      final container = _container(
        save: ({required memberId, required avatar}) async {},
        identityBuilder: (ref) {
          invalidations++;
          return _identity;
        },
      );
      addTearDown(container.dispose);
      container.listen<AsyncValue<LocalIdentity?>>(
        localIdentityProvider,
        (_, _) {},
        fireImmediately: true,
      );
      final controller = container.read(
        avatarEditorControllerProvider(_identity).notifier,
      );
      container.listen(
        avatarEditorControllerProvider(_identity),
        (_, _) {},
        fireImmediately: true,
      );
      controller.select(avatarCatalog.optionsFor(AvatarCategory.head)[1]);
      final expected = container
          .read(avatarEditorControllerProvider(_identity))
          .draft;

      expect(await controller.save(), isTrue);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(avatarEditorControllerProvider(_identity));
      expect(state.original, expected);
      expect(state.draft, expected);
      expect(state.errorMessage, isNull);
      expect(invalidations, greaterThan(1));
    },
  );

  test(
    'storage failure preserves the draft and exposes exact retry copy',
    () async {
      var attempts = 0;
      final container = _container(
        save: ({required memberId, required avatar}) async {
          attempts++;
          throw StateError('storage unavailable');
        },
      );
      addTearDown(container.dispose);
      final controller = container.read(
        avatarEditorControllerProvider(_identity).notifier,
      );
      controller.select(avatarCatalog.optionsFor(AvatarCategory.body).first);
      final expected = container
          .read(avatarEditorControllerProvider(_identity))
          .draft;

      expect(await controller.save(), isFalse);
      var state = container.read(avatarEditorControllerProvider(_identity));
      expect(state.draft, expected);
      expect(state.original, _identity.avatar);
      expect(state.phase, AvatarSavePhase.failed);
      expect(state.errorMessage, 'Your avatar could not be saved. Try again.');
      expect(attempts, 1);
    },
  );

  test('retry succeeds and commits the same failed draft', () async {
    var attempts = 0;
    AvatarConfig? submitted;
    final container = _container(
      save: ({required memberId, required avatar}) async {
        attempts++;
        submitted = avatar;
        if (attempts == 1) throw StateError('temporary failure');
      },
    );
    addTearDown(container.dispose);
    final controller = container.read(
      avatarEditorControllerProvider(_identity).notifier,
    );
    controller.select(avatarCatalog.optionsFor(AvatarCategory.body).first);
    final expected = container
        .read(avatarEditorControllerProvider(_identity))
        .draft;

    expect(await controller.save(), isFalse);
    expect(await controller.save(), isTrue);

    final state = container.read(avatarEditorControllerProvider(_identity));
    expect(submitted, expected);
    expect(state.original, expected);
    expect(state.draft, expected);
    expect(state.phase, AvatarSavePhase.idle);
    expect(state.errorMessage, isNull);
    expect(attempts, 2);
  });
}

ProviderContainer _container({
  AvatarSave? save,
  FutureOr<LocalIdentity?> Function(Ref)? identityBuilder,
}) => ProviderContainer(
  overrides: [
    if (save != null) avatarSaveProvider.overrideWithValue(save),
    if (identityBuilder != null)
      localIdentityProvider.overrideWith(identityBuilder),
  ],
);
