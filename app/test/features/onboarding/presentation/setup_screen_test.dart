import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/app.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/pending_join_completion_controller.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/family/presentation/family_join_screen.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/data/family_repository.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/data/member_repository.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/onboarding/presentation/account_conflict_screen.dart';
import 'package:keepers/features/onboarding/presentation/account_screen.dart';
import 'package:keepers/features/onboarding/presentation/setup_screen.dart';
import 'package:keepers/features/onboarding/presentation/startup_gate.dart';
import 'package:keepers/features/vault/presentation/observatory_screen.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/storage/schema.dart';
import 'package:keepers/ui/family_wheel_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('first run validates two names and enters the Family Wheel', (
    tester,
  ) async {
    final fixture = await _WidgetFixture.create();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.scope(const KeepersApp()));
    await tester.pumpAndSettle();
    await _chooseCreate(tester);

    expect(find.text('Name your family space'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Enter the Observatory'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byKey(const Key('family-name')), 'Sabati');
    await tester.enterText(find.byKey(const Key('member-name')), 'Chris');
    await tester.pump();
    await tester.tap(find.text('Enter the Observatory'));
    await _pumpUntilFound(tester, find.text('THIS WEEK'));

    expect(find.text('SABATI FAMILY'), findsOneWidget);
    expect(find.bySemanticsLabel('Sabati family'), findsOneWidget);
    expect(find.text('YOU'), findsOneWidget);
    expect(find.text('Hold to speak'), findsNothing);
    expect(await fixture.database.query('families'), hasLength(1));
    expect(await fixture.database.query('members'), hasLength(1));
  });

  testWidgets('whitespace does not enable setup submission', (tester) async {
    final fixture = await _WidgetFixture.create();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.scope(const KeepersApp()));
    await tester.pumpAndSettle();
    await _chooseCreate(tester);

    await tester.enterText(find.byKey(const Key('family-name')), '   ');
    await tester.enterText(find.byKey(const Key('member-name')), 'Chris');

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Enter the Observatory'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('setup name fields enforce the cloud name limit', (tester) async {
    final fixture = await _WidgetFixture.create();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.scope(const KeepersApp()));
    await tester.pumpAndSettle();
    await _chooseCreate(tester);

    final oversized = 'N' * (setupNameMaxLength + 12);
    await tester.enterText(find.byKey(const Key('family-name')), oversized);
    await tester.enterText(find.byKey(const Key('member-name')), oversized);
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('family-name')))
          .controller
          ?.text
          .length,
      setupNameMaxLength,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('member-name')))
          .controller
          ?.text
          .length,
      setupNameMaxLength,
    );
  });

  testWidgets('system back returns Create to choice and preserves names', (
    tester,
  ) async {
    final fixture = await _WidgetFixture.create();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.scope(const KeepersApp()));
    await tester.pumpAndSettle();
    await _chooseCreate(tester);
    await tester.enterText(find.byKey(const Key('family-name')), 'Sabati');
    await tester.enterText(find.byKey(const Key('member-name')), 'Chris');

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('create-family-choice')), findsOneWidget);
    await _chooseCreate(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('family-name')))
          .controller
          ?.text,
      'Sabati',
    );
  });

  testWidgets(
    'Join opens manual code entry and system back returns to choice',
    (tester) async {
      final fixture = await _WidgetFixture.create();
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.scope(const KeepersApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('join-family-choice')));
      await tester.pumpAndSettle();

      expect(find.byType(FamilyJoinScreen), findsOneWidget);
      expect(find.byKey(const Key('family-code-field')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('create-family-choice')), findsOneWidget);
    },
  );

  testWidgets('startup resolves identity then recovers before own request', (
    tester,
  ) async {
    final events = <String>[];
    final gateway = _StartupGateway(events: events);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyJoinCompletionRecoveryProvider.overrideWithValue(() async {
            events.add('recovery');
            return const PendingJoinCompletionState();
          }),
          localIdentityProvider.overrideWith((ref) async {
            events.add('identity');
            return null;
          }),
          cloudFamilyGatewayProvider.overrideWithValue(
            const _SignedInCloudGateway(),
          ),
          familyCodeJoinGatewayProvider.overrideWithValue(gateway),
          secureValueStoreProvider.overrideWithValue(_MemorySecureValueStore()),
        ],
        child: const MaterialApp(home: StartupGate()),
      ),
    );
    await tester.pumpAndSettle();

    expect(events, ['identity', 'recovery', 'own']);
    expect(find.byType(SetupScreen), findsOneWidget);
  });

  testWidgets('first run requires an account before family setup', (
    tester,
  ) async {
    final gateway = _AccountGateway();
    addTearDown(gateway.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyJoinCompletionRecoveryProvider.overrideWithValue(
            () async => const PendingJoinCompletionState(),
          ),
          localIdentityProvider.overrideWith((ref) async => null),
          cloudFamilyGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(home: StartupGate()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create your Keepers account'), findsOneWidget);
    expect(find.text('CREATE A FAMILY'), findsNothing);
    expect(find.byType(SetupScreen), findsNothing);
  });

  testWidgets(
    'startup rejects a local family bound to a different signed-in account',
    (tester) async {
      final gateway = _DifferentSignedInCloudGateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            familyJoinCompletionRecoveryProvider.overrideWithValue(
              () async => const PendingJoinCompletionState(),
            ),
            localIdentityProvider.overrideWith((ref) async => _startupIdentity),
            cloudFamilyGatewayProvider.overrideWithValue(gateway),
          ],
          child: const MaterialApp(home: StartupGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ObservatoryScreen), findsNothing);
      expect(find.byType(FamilyWheelScreen), findsNothing);
      expect(
        find.text('THIS KEEPERS PROFILE IS CONNECTED TO A DIFFERENT ACCOUNT.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Use another account'));
      await tester.pumpAndSettle();

      expect(gateway.signOutCalls, 1);
      expect(find.text('Create your Keepers account'), findsOneWidget);
    },
  );

  testWidgets(
    'account already in another family can switch without deleting local data',
    (tester) async {
      final fixture = await _WidgetFixture.create();
      addTearDown(fixture.dispose);
      final keys = await fixture.identityKeyService.createFor(
        familyId: _startupFamilyId,
        memberId: _startupMemberId,
      );
      await fixture.database.transaction((transaction) async {
        await FamilyRepository().insert(
          transaction,
          id: _startupFamilyId,
          name: 'Rahman family',
          familyKeyRef: keys.familyKeyRef,
          createdAt: DateTime.utc(2026, 9, 1),
        );
        await MemberRepository().insert(
          transaction,
          id: _startupMemberId,
          familyId: _startupFamilyId,
          name: 'Mariam',
          memberKeyRef: keys.memberKeyRef,
          colorToken: 'ochre',
          avatar: const AvatarConfig.defaults(seed: _startupMemberId),
          createdAt: DateTime.utc(2026, 9, 1),
        );
        await MemberRepository().bindLocalIdentity(
          transaction,
          familyId: _startupFamilyId,
          memberId: _startupMemberId,
          accountId: _startupAccountId,
        );
      });
      final gateway = _ConflictingFamilyGateway();

      await tester.pumpWidget(
        fixture.scope(const KeepersApp(), gateway: gateway),
      );
      await _pumpUntilFound(
        tester,
        find.text('THIS ACCOUNT IS ALREADY CONNECTED TO ANOTHER FAMILY.'),
      );

      expect(find.byType(FamilyWheelScreen), findsNothing);
      await tester.tap(find.text('Use another account'));
      await _pumpUntilFound(tester, find.text('Create your Keepers account'));

      expect(gateway.signOutCalls, 1);
      expect(await fixture.database.query('families'), hasLength(1));
      expect(await fixture.database.query('members'), hasLength(1));
      expect(
        (await fixture.database.query('local_identity_binding'))
            .single['account_id'],
        isNull,
      );
    },
  );

  testWidgets(
    'signed-out first run reaches account gate before pending recovery',
    (tester) async {
      final gateway = _AccountGateway();
      addTearDown(gateway.dispose);
      var recoveryAttempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            familyJoinCompletionRecoveryProvider.overrideWithValue(() async {
              recoveryAttempts += 1;
              return const PendingJoinCompletionState(
                phase: PendingJoinCompletionPhase.failed,
                failure: FamilyJoinFailure(FamilyJoinFailureCode.signedOut),
              );
            }),
            localIdentityProvider.overrideWith((ref) async => null),
            cloudFamilyGatewayProvider.overrideWithValue(gateway),
          ],
          child: const MaterialApp(home: StartupGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create your Keepers account'), findsOneWidget);
      expect(find.byType(StartupError), findsNothing);
      expect(recoveryAttempts, 0);
    },
  );

  testWidgets(
    'signed-out existing profile reaches account gate before pending recovery',
    (tester) async {
      final gateway = _AccountGateway();
      addTearDown(gateway.dispose);
      var recoveryAttempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            familyJoinCompletionRecoveryProvider.overrideWithValue(() async {
              recoveryAttempts += 1;
              return const PendingJoinCompletionState(
                phase: PendingJoinCompletionPhase.failed,
                failure: FamilyJoinFailure(FamilyJoinFailureCode.signedOut),
              );
            }),
            localIdentityProvider.overrideWith((ref) async => _startupIdentity),
            cloudFamilyGatewayProvider.overrideWithValue(gateway),
          ],
          child: const MaterialApp(home: StartupGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create your Keepers account'), findsOneWidget);
      expect(find.byType(StartupError), findsNothing);
      expect(recoveryAttempts, 0);
    },
  );

  testWidgets(
    'gateway sign-out replaces an established family screen with account recovery',
    (tester) async {
      final gateway = _AccountGateway()..completeSignIn();
      addTearDown(gateway.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            familyJoinCompletionRecoveryProvider.overrideWithValue(
              () async => const PendingJoinCompletionState(),
            ),
            localIdentityProvider.overrideWith((ref) async => _startupIdentity),
            cloudFamilyGatewayProvider.overrideWithValue(gateway),
          ],
          child: const MaterialApp(home: StartupGate()),
        ),
      );
      await _pumpUntilFound(tester, find.byType(ObservatoryScreen));

      gateway.emitSignOut();
      await _pumpUntilFound(tester, find.byType(AccountScreen));

      expect(find.byType(ObservatoryScreen), findsNothing);
      expect(find.byType(AccountScreen), findsOneWidget);
    },
  );

  testWidgets(
    'gateway account change replaces an established family screen with conflict recovery',
    (tester) async {
      final gateway = _AccountGateway()..completeSignIn();
      addTearDown(gateway.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            familyJoinCompletionRecoveryProvider.overrideWithValue(
              () async => const PendingJoinCompletionState(),
            ),
            localIdentityProvider.overrideWith((ref) async => _startupIdentity),
            cloudFamilyGatewayProvider.overrideWithValue(gateway),
          ],
          child: const MaterialApp(home: StartupGate()),
        ),
      );
      await _pumpUntilFound(tester, find.byType(ObservatoryScreen));
      expect(find.byType(ObservatoryScreen), findsOneWidget);

      gateway.switchAccount(_differentStartupAccountId);
      await _pumpUntilFound(tester, find.byType(AccountConflictScreen));

      expect(find.byType(ObservatoryScreen), findsNothing);
      expect(find.byType(AccountConflictScreen), findsOneWidget);
    },
  );

  testWidgets('account session events rebind when the cloud gateway reloads', (
    tester,
  ) async {
    final originalGateway = _AccountGateway()..completeSignIn();
    final reloadedGateway = _AccountGateway()..completeSignIn();
    addTearDown(originalGateway.dispose);
    addTearDown(reloadedGateway.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialCloudFamilyGatewayProvider.overrideWithValue(originalGateway),
          cloudFamilyGatewayLoaderProvider.overrideWithValue(
            () async => reloadedGateway,
          ),
          familyJoinCompletionRecoveryProvider.overrideWithValue(
            () async => const PendingJoinCompletionState(),
          ),
          localIdentityProvider.overrideWith((ref) async => _startupIdentity),
        ],
        child: const MaterialApp(home: StartupGate()),
      ),
    );
    await _pumpUntilFound(tester, find.byType(ObservatoryScreen));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StartupGate)),
    );

    await container.read(cloudFamilyGatewayStateProvider.notifier).reload();
    await tester.pump();
    originalGateway.emitSignOut();
    await tester.pump();

    expect(find.byType(ObservatoryScreen), findsOneWidget);

    reloadedGateway.emitSignOut();
    await _pumpUntilFound(tester, find.byType(AccountScreen));

    expect(find.byType(AccountScreen), findsOneWidget);
  });

  testWidgets('account session subscription closes with StartupGate', (
    tester,
  ) async {
    final gateway = _AccountGateway()..completeSignIn();
    addTearDown(gateway.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyJoinCompletionRecoveryProvider.overrideWithValue(
            () async => const PendingJoinCompletionState(),
          ),
          localIdentityProvider.overrideWith((ref) async => _startupIdentity),
          cloudFamilyGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(home: StartupGate()),
      ),
    );
    await _pumpUntilFound(tester, find.byType(ObservatoryScreen));
    expect(gateway.hasAccountSessionListener, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(gateway.hasAccountSessionListener, isFalse);
  });

  testWidgets(
    'unconfigured account retry installs a loaded gateway and resumes startup',
    (tester) async {
      final loadedGateway = _AccountGateway();
      addTearDown(loadedGateway.dispose);
      var loadAttempts = 0;
      var recoveryAttempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cloudFamilyGatewayLoaderProvider.overrideWithValue(() async {
              loadAttempts += 1;
              return loadedGateway;
            }),
            familyJoinCompletionRecoveryProvider.overrideWithValue(() async {
              recoveryAttempts += 1;
              return const PendingJoinCompletionState();
            }),
            localIdentityProvider.overrideWith((ref) async => null),
          ],
          child: const MaterialApp(home: StartupGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Account setup is unavailable right now.'),
        findsOneWidget,
      );
      expect(loadAttempts, 0);
      expect(recoveryAttempts, 0);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(loadAttempts, 1);
      expect(find.text('Create your Keepers account'), findsOneWidget);
      expect(recoveryAttempts, 0);

      loadedGateway.completeSignIn();
      await tester.pumpAndSettle();

      expect(recoveryAttempts, 1);
      expect(find.byType(SetupScreen), findsOneWidget);
    },
  );

  testWidgets('completed account creation resumes first-run family setup', (
    tester,
  ) async {
    final gateway = _AccountGateway();
    addTearDown(gateway.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyJoinCompletionRecoveryProvider.overrideWithValue(
            () async => const PendingJoinCompletionState(),
          ),
          localIdentityProvider.overrideWith((ref) async => null),
          cloudFamilyGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(home: StartupGate()),
      ),
    );
    await tester.pumpAndSettle();

    gateway.completeSignIn();
    await tester.pumpAndSettle();

    expect(find.byType(SetupScreen), findsOneWidget);
    expect(find.text('CREATE A FAMILY'), findsOneWidget);
    expect(find.text('Create your Keepers account'), findsNothing);
  });

  testWidgets('session loss during Create offers a route back to account', (
    tester,
  ) async {
    final gateway = _AccountGateway()..completeSignIn();
    addTearDown(gateway.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyJoinCompletionRecoveryProvider.overrideWithValue(
            () async => const PendingJoinCompletionState(),
          ),
          localIdentityProvider.overrideWith((ref) async => null),
          cloudFamilyGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(home: StartupGate()),
      ),
    );
    await tester.pumpAndSettle();
    await _chooseCreate(tester);
    gateway.signOut();
    await tester.enterText(find.byKey(const Key('family-name')), 'Sabati');
    await tester.enterText(find.byKey(const Key('member-name')), 'Chris');
    await tester.pump();
    await tester.tap(find.text('Enter the Observatory'));
    await tester.pumpAndSettle();

    expect(
      find.text('Your account session ended. Sign in again.'),
      findsOneWidget,
    );
    expect(find.text('Sign in again'), findsOneWidget);

    await tester.tap(find.text('Sign in again'));
    await tester.pumpAndSettle();

    expect(find.text('Create your Keepers account'), findsOneWidget);
    expect(find.byType(SetupScreen), findsNothing);
  });

  testWidgets('startup resumes a pending request before family setup', (
    tester,
  ) async {
    final gateway = _StartupGateway(
      events: <String>[],
      ownRequest: _startupRequest(FamilyJoinRequestState.pending),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyJoinCompletionRecoveryProvider.overrideWithValue(
            () async => const PendingJoinCompletionState(),
          ),
          localIdentityProvider.overrideWith((ref) async => null),
          cloudFamilyGatewayProvider.overrideWithValue(
            const _SignedInCloudGateway(),
          ),
          familyCodeJoinGatewayProvider.overrideWithValue(gateway),
          secureValueStoreProvider.overrideWithValue(_MemorySecureValueStore()),
        ],
        child: const MaterialApp(home: StartupGate()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(FamilyJoinScreen), findsOneWidget);
    expect(find.byType(SetupScreen), findsNothing);
    expect(
      tester
          .widget<FamilyJoinScreen>(find.byType(FamilyJoinScreen))
          .onAbandoned,
      isNotNull,
    );
    expect(
      tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
      isFalse,
    );
    expect(find.byKey(const Key('leave-family-join')), findsNothing);
  });

  for (final failure in <String, FamilyJoinFailureCode>{
    'wrong account': FamilyJoinFailureCode.forbidden,
    'network': FamilyJoinFailureCode.networkUnavailable,
    'local persistence': FamilyJoinFailureCode.localPersistenceFailed,
  }.entries) {
    testWidgets(
      'startup blocks normal routing for ${failure.key} recovery failure',
      (tester) async {
        var identityReads = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              familyJoinCompletionRecoveryProvider.overrideWithValue(
                () async => PendingJoinCompletionState(
                  phase: PendingJoinCompletionPhase.failed,
                  failure: FamilyJoinFailure(failure.value),
                ),
              ),
              localIdentityProvider.overrideWith((ref) async {
                identityReads += 1;
                return _startupIdentity;
              }),
              cloudFamilyGatewayProvider.overrideWithValue(
                const _SignedInCloudGateway(),
              ),
            ],
            child: const MaterialApp(home: StartupGate()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(StartupError), findsOneWidget);
        expect(find.text('THIS WEEK'), findsNothing);
        expect(find.byType(SetupScreen), findsNothing);
        expect(identityReads, 1);
      },
    );
  }

  testWidgets('startup recovery failure remains retryable until resolved', (
    tester,
  ) async {
    var recoveryAttempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyJoinCompletionRecoveryProvider.overrideWithValue(() async {
            recoveryAttempts += 1;
            if (recoveryAttempts == 1) {
              return const PendingJoinCompletionState(
                phase: PendingJoinCompletionPhase.failed,
                failure: FamilyJoinFailure(
                  FamilyJoinFailureCode.networkUnavailable,
                ),
              );
            }
            return const PendingJoinCompletionState();
          }),
          localIdentityProvider.overrideWith((ref) async => null),
          cloudFamilyGatewayProvider.overrideWithValue(
            const _SignedInCloudGateway(),
          ),
        ],
        child: const MaterialApp(home: StartupGate()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StartupError), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(recoveryAttempts, 2);
    expect(find.byType(SetupScreen), findsOneWidget);
  });

  testWidgets(
    'startup returns declined request to Setup with one live status',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final gateway = _StartupGateway(
        events: <String>[],
        ownRequest: _startupRequest(FamilyJoinRequestState.declined),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            familyJoinCompletionRecoveryProvider.overrideWithValue(
              () async => const PendingJoinCompletionState(),
            ),
            localIdentityProvider.overrideWith((ref) async => null),
            cloudFamilyGatewayProvider.overrideWithValue(
              const _SignedInCloudGateway(),
            ),
            familyCodeJoinGatewayProvider.overrideWithValue(gateway),
            secureValueStoreProvider.overrideWithValue(
              _MemorySecureValueStore(),
            ),
          ],
          child: const MaterialApp(home: StartupGate()),
        ),
      );
      await tester.pumpAndSettle();

      final status = find.bySemanticsLabel("Your request wasn't accepted");
      expect(status, findsOneWidget);
      expect(
        tester
            .getSemantics(status)
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      semantics.dispose();
    },
  );

  for (final outcome in <FamilyJoinRequestCancelReason, String>{
    FamilyJoinRequestCancelReason.requester: 'Your request was cancelled',
    FamilyJoinRequestCancelReason.codeRegenerated:
        'This family invitation has changed. Ask for the new code.',
  }.entries) {
    testWidgets('startup maps authoritative ${outcome.key.name} cancellation', (
      tester,
    ) async {
      final gateway = _StartupGateway(
        events: <String>[],
        ownRequest: _startupRequest(
          FamilyJoinRequestState.cancelled,
          cancelReason: outcome.key,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            familyJoinCompletionRecoveryProvider.overrideWithValue(
              () async => const PendingJoinCompletionState(),
            ),
            localIdentityProvider.overrideWith((ref) async => null),
            cloudFamilyGatewayProvider.overrideWithValue(
              const _SignedInCloudGateway(),
            ),
            familyCodeJoinGatewayProvider.overrideWithValue(gateway),
            secureValueStoreProvider.overrideWithValue(
              _MemorySecureValueStore(),
            ),
          ],
          child: const MaterialApp(home: StartupGate()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(outcome.value), findsOneWidget);
    });
  }

  testWidgets('setup failure is inline and retryable without raw errors', (
    tester,
  ) async {
    final fixture = await _WidgetFixture.create(failMemberInsert: true);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.scope(const KeepersApp()));
    await tester.pumpAndSettle();
    await _chooseCreate(tester);

    await tester.enterText(find.byKey(const Key('family-name')), 'Sabati');
    await tester.enterText(find.byKey(const Key('member-name')), 'Chris');
    await tester.pump();
    await tester.tap(find.text('Enter the Observatory'));
    await tester.pumpAndSettle();

    expect(
      find.text('Your family space could not be secured. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('member insert failed'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Enter the Observatory'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('validation and setup failure are announced as live regions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final fixture = await _WidgetFixture.create(failMemberInsert: true);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.scope(const KeepersApp()));
    await tester.pumpAndSettle();
    await _chooseCreate(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SetupScreen)),
    );
    await container
        .read(setupControllerProvider.notifier)
        .submit(const SetupInput(familyName: ' ', memberName: 'Chris'));
    await tester.pump();

    final validation = find.bySemanticsLabel('Enter both names');
    expect(validation, findsOneWidget);
    expect(
      tester
          .getSemantics(validation)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    await tester.enterText(find.byKey(const Key('family-name')), 'Sabati');
    await tester.enterText(find.byKey(const Key('member-name')), 'Chris');
    await tester.pump();
    await tester.tap(find.text('Enter the Observatory'));
    await tester.pumpAndSettle();

    final failure = find.bySemanticsLabel(
      'Your family space could not be secured. Try again.',
    );
    expect(failure, findsOneWidget);
    expect(
      tester
          .getSemantics(failure)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('setup remains usable at 1.4x text with a 44 pixel target', (
    tester,
  ) async {
    final fixture = await _WidgetFixture.create();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      fixture.scope(
        MaterialApp(
          theme: KeepersTheme.dark(),
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: SetupScreen(),
          ),
        ),
      ),
    );
    await _chooseCreate(tester);

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.widgetWithText(FilledButton, 'Enter the Observatory'))
          .height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('submitting setup exposes an accessible progress button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final fixture = await _WidgetFixture.create(holdFirstKeyWrite: true);
    addTearDown(fixture.dispose);
    addTearDown(fixture.store.releaseFirstWrite);
    await tester.pumpWidget(fixture.scope(const KeepersApp()));
    await tester.pumpAndSettle();
    await _chooseCreate(tester);

    await tester.enterText(find.byKey(const Key('family-name')), 'Sabati');
    await tester.enterText(find.byKey(const Key('member-name')), 'Chris');
    await tester.pump();
    await tester.tap(find.text('Enter the Observatory'));
    await fixture.store.firstWriteStarted;
    await tester.pump();

    final progress = find.bySemanticsLabel('Entering the Observatory');
    expect(progress, findsOneWidget);
    final data = tester.getSemantics(progress).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isLiveRegion, isTrue);

    fixture.store.releaseFirstWrite();
    await _pumpUntilFound(tester, find.text('The Observatory'));
    semantics.dispose();
  });

  testWidgets('startup storage error can be retried', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyJoinCompletionRecoveryProvider.overrideWithValue(
            () async => const PendingJoinCompletionState(),
          ),
          localIdentityProvider.overrideWith((ref) async {
            attempts += 1;
            if (attempts == 1) throw StateError('storage details');
            return null;
          }),
          cloudFamilyGatewayProvider.overrideWithValue(
            const _SignedInCloudGateway(),
          ),
        ],
        child: const KeepersApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Keepers could not open local storage.'), findsOneWidget);
    expect(find.textContaining('storage details'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('CREATE A FAMILY'), findsOneWidget);
  });

  testWidgets('startup retry reaches the database provider again', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async {
            attempts += 1;
            throw StateError('transient database failure $attempts');
          }),
        ],
        child: const KeepersApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Keepers could not open local storage.'), findsOneWidget);
    expect(attempts, 1);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
  });

  testWidgets('startup waits for local identity lookup', (tester) async {
    final identity = Completer<LocalIdentity?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyJoinCompletionRecoveryProvider.overrideWithValue(
            () async => const PendingJoinCompletionState(),
          ),
          localIdentityProvider.overrideWith((ref) => identity.future),
          cloudFamilyGatewayProvider.overrideWithValue(
            const _SignedInCloudGateway(),
          ),
        ],
        child: const KeepersApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    identity.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('CREATE A FAMILY'), findsOneWidget);
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _chooseCreate(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('create-family-choice')));
  await tester.pumpAndSettle();
}

final class _WidgetFixture {
  _WidgetFixture({
    required this.database,
    required this.store,
    required this.identityKeyService,
    required this.idFactory,
  });

  final Database database;
  final _MemorySecureValueStore store;
  final IdentityKeyService identityKeyService;
  final String Function() idFactory;

  Widget scope(Widget child, {CloudFamilyGateway? gateway}) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(AsyncValue.data(database)),
      secureValueStoreProvider.overrideWithValue(store),
      identityKeyServiceProvider.overrideWithValue(identityKeyService),
      cloudFamilyGatewayProvider.overrideWithValue(
        gateway ?? const _SignedInCloudGateway(),
      ),
      idFactoryProvider.overrideWithValue(idFactory),
      utcNowProvider.overrideWithValue(() => DateTime.utc(2026, 9, 1)),
    ],
    child: child,
  );

  static Future<_WidgetFixture> create({
    bool failMemberInsert = false,
    bool holdFirstKeyWrite = false,
  }) async {
    final database = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
    );
    await database.execute('PRAGMA foreign_keys = ON');
    for (final statement in KeepersSchema.statementsForUpgrade(
      0,
      KeepersSchema.version,
    )) {
      await database.execute(statement);
    }
    if (failMemberInsert) {
      await database.execute(r'''
CREATE TRIGGER fail_member_insert
BEFORE INSERT ON members
BEGIN
  SELECT RAISE(ABORT, 'member insert failed');
END
''');
    }
    final store = _MemorySecureValueStore(holdFirstWrite: holdFirstKeyWrite);
    var nextId = 0;
    return _WidgetFixture(
      database: database,
      store: store,
      identityKeyService: IdentityKeyService(
        store,
        randomBytesFactory: (length) => List<int>.filled(length, 7),
      ),
      idFactory: () => 'id-${++nextId}',
    );
  }

  Future<void> dispose() => database.close();
}

final class _MemorySecureValueStore implements SecureValueStore {
  _MemorySecureValueStore({this.holdFirstWrite = false});

  final bool holdFirstWrite;
  final Map<String, String> values = {};
  final Completer<void> _firstWriteStarted = Completer<void>();
  final Completer<void> _resumeFirstWrite = Completer<void>();
  var _writeCount = 0;

  Future<void> get firstWriteStarted => _firstWriteStarted.future;

  void releaseFirstWrite() {
    if (!_resumeFirstWrite.isCompleted) _resumeFirstWrite.complete();
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    _writeCount += 1;
    if (holdFirstWrite && _writeCount == 1) {
      _firstWriteStarted.complete();
      await _resumeFirstWrite.future;
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

final class _StartupGateway implements FamilyCodeJoinGateway {
  _StartupGateway({required this.events, this.ownRequest});

  final List<String> events;
  final OwnFamilyJoinRequest? ownRequest;

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => _startupAccountId;

  @override
  Future<OwnFamilyJoinRequest?> getOwnJoinRequest() async {
    events.add('own');
    return ownRequest;
  }

  @override
  Stream<void> watchOwnJoinRequest() => const Stream<void>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _AccountGateway
    implements
        CloudFamilyGateway,
        CloudFamilyAuthEvents,
        CloudFamilyAccountSessionEvents {
  final _signedIn = StreamController<void>.broadcast(sync: true);
  final _accountSessionChanges = StreamController<String?>.broadcast(
    sync: true,
  );

  String? _accountId;

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => _accountId;

  @override
  String? get authenticatedEmail => null;

  @override
  Stream<void> get signedInEvents => _signedIn.stream;

  @override
  Stream<String?> get accountSessionChangedEvents =>
      _accountSessionChanges.stream;

  bool get hasAccountSessionListener => _accountSessionChanges.hasListener;

  void completeSignIn() {
    _accountId = _startupAccountId;
    _signedIn.add(null);
    _accountSessionChanges.add(_accountId);
  }

  void switchAccount(String accountId) {
    _accountId = accountId;
    _accountSessionChanges.add(_accountId);
  }

  void emitSignOut() {
    _accountId = null;
    _accountSessionChanges.add(_accountId);
  }

  void signOut() => _accountId = null;

  Future<void> dispose() async {
    await _signedIn.close();
    await _accountSessionChanges.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _SignedInCloudGateway implements CloudFamilyGateway {
  const _SignedInCloudGateway();

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => _startupAccountId;

  @override
  String? get authenticatedEmail => 'keeper@example.com';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DifferentSignedInCloudGateway
    implements CloudFamilyGateway, CloudFamilyAccountSession {
  String? _accountId = _differentStartupAccountId;
  var signOutCalls = 0;

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => _accountId;

  @override
  String? get authenticatedEmail => 'different@example.com';

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    _accountId = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ConflictingFamilyGateway
    implements
        CloudFamilyGateway,
        CloudFamilyAccountSession,
        FamilyCodeJoinGateway {
  String? _accountId = _startupAccountId;
  var signOutCalls = 0;

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => _accountId;

  @override
  String? get authenticatedEmail => 'keeper@example.com';

  @override
  Future<EncryptedFamilyCodeRecord> getFamilyCode(String familyId) =>
      Future.error(const FamilyJoinFailure(FamilyJoinFailureCode.forbidden));

  @override
  Future<EncryptedFamilyCodeRecord> bootstrapOwnerWithFamilyCode(
    LocalOwnerFamily owner,
    FamilyCodeDraft code,
  ) => Future.error(
    const FamilyJoinFailure(FamilyJoinFailureCode.accountFamilyConflict),
  );

  @override
  Future<List<FamilyMember>> listActiveMembers(String familyId) =>
      Future.error(const InvitationFailure(InvitationFailureCode.forbidden));

  @override
  Future<List<PendingFamilyJoinRequest>> listPendingJoinRequests(
    String familyId,
  ) async => const [];

  @override
  Future<OwnFamilyJoinRequest?> getOwnJoinRequest() async => null;

  @override
  Stream<void> watchPendingJoinRequests(String familyId) =>
      const Stream<void>.empty();

  @override
  Stream<void> watchOwnJoinRequest() => const Stream<void>.empty();

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    _accountId = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OwnFamilyJoinRequest _startupRequest(
  FamilyJoinRequestState state, {
  FamilyJoinRequestCancelReason? cancelReason,
}) => OwnFamilyJoinRequest(
  requestId: _startupRequestId,
  familyId: _startupFamilyId,
  familyName: 'Rahman family',
  requesterAccountId: _startupAccountId,
  memberId: _startupMemberId,
  displayName: 'Mariam',
  demographicRole: FamilyDemographicRole.adult,
  colorToken: 'ochre',
  avatar: const AvatarConfig.defaults(seed: _startupMemberId),
  joiningPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  codeVersion: 1,
  state: state,
  cancelReason: cancelReason,
  createdAt: DateTime.utc(2026, 9, 7),
  expiresAt: DateTime.utc(2026, 9, 14),
);

const _startupRequestId = '11111111-1111-4111-8111-111111111111';
const _startupFamilyId = '22222222-2222-4222-8222-222222222222';
const _startupAccountId = '33333333-3333-4333-8333-333333333333';
const _differentStartupAccountId = '55555555-5555-4555-8555-555555555555';
const _startupMemberId = '44444444-4444-4444-8444-444444444444';
const _startupIdentity = LocalIdentity(
  familyId: _startupFamilyId,
  familyName: 'Rahman family',
  familyKeyRef: 'family-key',
  memberId: _startupMemberId,
  memberName: 'Mariam',
  memberKeyRef: 'member-key',
  colorToken: 'ochre',
  avatar: AvatarConfig.defaults(seed: _startupMemberId),
  accountId: _startupAccountId,
);
