import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/members/application/avatar_editor_controller.dart';
import 'package:keepers/features/members/domain/avatar_catalog.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/members/presentation/avatar_editor_screen.dart';
import 'package:keepers/features/members/presentation/widgets/keepers_avatar.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/onboarding/presentation/startup_gate.dart';
import 'package:keepers/features/settings/presentation/settings_screen.dart';
import 'package:keepers/features/vault/application/vault_providers.dart';

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
  testWidgets(
    'identity row presents the current avatar and editing affordance',
    (tester) async {
      await _pumpSettings(tester);

      final identityRow = find.byKey(const ValueKey('settings-identity'));
      final avatarSurface = find.descendant(
        of: identityRow,
        matching: find.byType(KeepersAvatarSurface),
      );
      final avatar = find.descendant(
        of: identityRow,
        matching: find.byType(KeepersAvatar),
      );

      expect(find.text('Chris'), findsOneWidget);
      expect(find.text('Edit avatar'), findsOneWidget);
      expect(
        find.descendant(
          of: identityRow,
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsOneWidget,
      );
      expect(tester.getSize(avatarSurface), const Size(48, 48));
      expect(tester.widget<KeepersAvatar>(avatar).config, _identity.avatar);
    },
  );

  testWidgets('identity row is an accessible edit button with a touch target', (
    tester,
  ) async {
    await _pumpSettings(tester);

    final identityRow = find.byKey(const ValueKey('settings-identity'));
    expect(find.bySemanticsLabel('Edit avatar for Chris'), findsOneWidget);
    expect(tester.getSize(identityRow).height, greaterThanOrEqualTo(44));
  });

  testWidgets('identity row opens the contextual avatar editor route', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.byKey(const ValueKey('settings-identity')));
    await tester.pumpAndSettle();

    expect(find.byType(AvatarEditorScreen), findsOneWidget);
  });

  testWidgets('settings remains usable at phone width and 1.4x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpSettings(
      tester,
      mediaQuery: const MediaQueryData(
        textScaler: TextScaler.linear(1.4),
        disableAnimations: true,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('settings-identity')), findsOneWidget);
  });

  testWidgets(
    'avatar save refreshes the settings identity without changing destination',
    (tester) async {
      var identityLoads = 0;
      var refreshedIdentity = _identity;
      AvatarConfig? savedAvatar;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localIdentityProvider.overrideWith((ref) async {
              identityLoads += 1;
              return refreshedIdentity;
            }),
            avatarSaveProvider.overrideWithValue(({
              required memberId,
              required avatar,
            }) async {
              savedAvatar = avatar;
              refreshedIdentity = _identityWithAvatar(avatar);
            }),
            vaultEntriesProvider.overrideWithValue(const AsyncValue.data([])),
            familyRosterProvider(_identity.familyId).overrideWithBuild(
              (ref, notifier) => FamilyRosterState(
                members: [
                  FamilyMember(
                    id: _identity.memberId,
                    familyId: _identity.familyId,
                    name: _identity.memberName,
                    role: 'adult',
                    colorToken: _identity.colorToken,
                    avatar: _identity.avatar,
                    joinedAt: DateTime.utc(2026, 9, 1),
                  ),
                ],
                hasLoadedLocal: true,
              ),
            ),
            familyRosterRefreshProvider(_identity.familyId)
                .overrideWithValue(() async {}),
          ],
          child: MaterialApp(
            theme: KeepersTheme.daylight(),
            home: const StartupGate(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.bySemanticsLabel('Settings'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('settings-identity')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final option = avatarCatalog.optionsFor(AvatarCategory.head).first;
      await tester.tap(find.byKey(Key('avatar-option-${option.id}')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save avatar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 50));

      final avatar = tester.widget<KeepersAvatar>(
        find.descendant(
          of: find.byKey(const ValueKey('settings-identity')),
          matching: find.byType(KeepersAvatar),
        ),
      );
      expect(savedAvatar, isNotNull);
      expect(identityLoads, greaterThanOrEqualTo(2));
      expect(avatar.config, savedAvatar);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.bySemanticsLabel('Settings, selected'), findsOneWidget);
    },
  );
}

LocalIdentity _identityWithAvatar(AvatarConfig avatar) => LocalIdentity(
  familyId: _identity.familyId,
  familyName: _identity.familyName,
  familyKeyRef: _identity.familyKeyRef,
  memberId: _identity.memberId,
  memberName: _identity.memberName,
  memberKeyRef: _identity.memberKeyRef,
  colorToken: _identity.colorToken,
  avatar: avatar,
);

Future<void> _pumpSettings(WidgetTester tester, {MediaQueryData? mediaQuery}) =>
    tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: KeepersTheme.daylight(),
          home: MediaQuery(
            data: mediaQuery ?? const MediaQueryData(disableAnimations: true),
            child: SettingsScreen(
              identity: _identity,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      ),
    );
