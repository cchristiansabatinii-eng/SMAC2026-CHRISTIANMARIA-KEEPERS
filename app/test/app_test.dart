import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/app.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/family/application/pending_join_completion_controller.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/invite_link_coordinator.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/family/presentation/family_join_screen.dart';
import 'package:keepers/features/launch/presentation/keepers_launch_sequence.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/application/vault_providers.dart';

void main() {
  testWidgets(
    'ordinary cold launch begins with the Keepers wordmark on black',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            familyJoinCompletionRecoveryProvider.overrideWithValue(
              _idleJoinRecovery,
            ),
            localIdentityProvider.overrideWithValue(
              const AsyncValue.data(null),
            ),
            cloudFamilyGatewayProvider.overrideWithValue(
              const _ConfiguredAccountGateway(),
            ),
          ],
          child: const KeepersApp(playLaunchSequence: true),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('keepers-launch-sequence')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('keepers-launch-logo')), findsOneWidget);
      expect(find.text('CREATE A FAMILY').hitTestable(), findsNothing);
    },
  );

  testWidgets('ordinary launch hands control to the resolved app after intro', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyJoinCompletionRecoveryProvider.overrideWithValue(
            _idleJoinRecovery,
          ),
          localIdentityProvider.overrideWithValue(const AsyncValue.data(null)),
          cloudFamilyGatewayProvider.overrideWithValue(
            const _ConfiguredAccountGateway(),
          ),
        ],
        child: const KeepersApp(playLaunchSequence: true),
      ),
    );
    await _finishLaunchLogoPrecache(tester);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(find.byKey(const ValueKey('keepers-launch-sequence')), findsNothing);
    expect(
      find.text('Create your Keepers account').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('routes a first run to account creation', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyJoinCompletionRecoveryProvider.overrideWithValue(
            _idleJoinRecovery,
          ),
          localIdentityProvider.overrideWithValue(const AsyncValue.data(null)),
          cloudFamilyGatewayProvider.overrideWithValue(
            const _ConfiguredAccountGateway(),
          ),
        ],
        child: const KeepersApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('keepers-global-background')),
      findsOneWidget,
    );
    expect(find.text('Create your Keepers account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Microsoft'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('CREATE A FAMILY'), findsNothing);
  });

  testWidgets('routes an established identity to the Family Wheel', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyJoinCompletionRecoveryProvider.overrideWithValue(
            _idleJoinRecovery,
          ),
          localIdentityProvider.overrideWithValue(
            const AsyncValue.data(
              LocalIdentity(
                familyId: 'family-1',
                familyName: 'Sabati',
                familyKeyRef: 'family-key',
                memberId: 'member-1',
                memberName: 'Chris',
                memberKeyRef: 'member-key',
                colorToken: 'ochre',
                avatar: AvatarConfig.defaults(seed: 'member-1'),
              ),
            ),
          ),
          cloudFamilyGatewayProvider.overrideWithValue(
            const _SignedInAccountGateway(),
          ),
          vaultEntriesProvider.overrideWithValue(const AsyncValue.data([])),
          familyRosterProvider('family-1').overrideWithBuild(
            (ref, notifier) => FamilyRosterState(
              members: [
                FamilyMember(
                  id: 'member-1',
                  familyId: 'family-1',
                  name: 'Chris',
                  role: 'adult',
                  colorToken: 'ochre',
                  avatar: const AvatarConfig.defaults(seed: 'member-1'),
                  joinedAt: DateTime.utc(2026, 9, 1),
                ),
              ],
              hasLoadedLocal: true,
            ),
          ),
          familyRosterRefreshProvider('family-1')
              .overrideWithValue(() async {}),
        ],
        child: const KeepersApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('keepers-wordmark')), findsOneWidget);
    expect(find.text('One more\nto open.'), findsNothing);
    expect(find.text('SABATI FAMILY'), findsOneWidget);
    expect(find.bySemanticsLabel('Sabati family'), findsOneWidget);
    expect(find.text('KEPT FOREVER'), findsNothing);
    expect(find.text('KEPT\nMEMORIES'), findsNothing);
    expect(find.text('YOU'), findsOneWidget);
    expect(find.text('Hold to speak'), findsNothing);
    expect(find.text('NOURA'), findsNothing);
    expect(find.text('MARIAM'), findsNothing);
    expect(find.text('YOUSSEF'), findsNothing);
    expect(find.text('LAYLA'), findsNothing);
    expect(
      find.byKey(const ValueKey('family-invite-node-action')),
      findsOneWidget,
    );
    expect(find.text('Add family to begin the circle'), findsNothing);
    expect(find.bySemanticsLabel('Memory Key'), findsOneWidget);
    expect(find.bySemanticsLabel('Wheel, selected'), findsOneWidget);
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
  });

  testWidgets('cold verified family link opens Join before ordinary setup', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localIdentityProvider.overrideWithValue(const AsyncValue.data(null)),
        ],
        child: KeepersApp(
          inviteUriSource: _TestInviteUriSource(
            const Stream<Uri>.empty(),
            _familyJoinUri,
          ),
        ),
      ),
    );
    await _pumpRoot(tester);

    expect(find.byType(FamilyJoinScreen, skipOffstage: false), findsOneWidget);
    expect(find.text('CREATE A FAMILY'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'a cold active code coalesces duplicates and can reopen after route close',
    (tester) async {
      final canceled = Completer<void>();
      final stream = StreamController<Uri>.broadcast(
        onCancel: () {
          if (!canceled.isCompleted) canceled.complete();
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localIdentityProvider.overrideWithValue(
              const AsyncValue.data(null),
            ),
          ],
          child: KeepersApp(
            inviteUriSource: _TestInviteUriSource(
              stream.stream,
              _familyJoinUri,
            ),
          ),
        ),
      );
      await _pumpRoot(tester);

      stream
        ..add(_familyJoinUri)
        ..add(_familyJoinUri);
      await tester.idle();
      await tester.pump();
      expect(
        find.byType(FamilyJoinScreen, skipOffstage: false),
        findsOneWidget,
      );

      tester
          .widget<FamilyJoinScreen>(find.byType(FamilyJoinScreen))
          .onAbandoned!
          .call();
      await _pumpRouteTransition(tester);
      expect(find.byType(FamilyJoinScreen, skipOffstage: false), findsNothing);

      stream.add(_familyJoinUri);
      await _pumpWarmRoute(tester);
      expect(
        find.byType(FamilyJoinScreen, skipOffstage: false),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await canceled.future;
      await stream.close();
    },
  );

  testWidgets('pre-resolved coordinator hands its cold Join to the app once', (
    tester,
  ) async {
    final coordinator = InviteLinkCoordinator(
      _TestInviteUriSource(const Stream<Uri>.empty(), _familyJoinUri),
    );
    expect(
      await coordinator.resolveInitialLink(),
      isA<ValidFamilyJoinLinkEvent>(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localIdentityProvider.overrideWithValue(const AsyncValue.data(null)),
        ],
        child: KeepersApp(inviteLinkCoordinator: coordinator),
      ),
    );
    await _pumpRoot(tester);
    expect(find.byType(FamilyJoinScreen, skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'an active warm code coalesces duplicates and can reopen after route close',
    (tester) async {
      final canceled = Completer<void>();
      final stream = StreamController<Uri>.broadcast(
        onCancel: () {
          if (!canceled.isCompleted) canceled.complete();
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localIdentityProvider.overrideWithValue(
              const AsyncValue.data(null),
            ),
          ],
          child: KeepersApp(
            inviteUriSource: _TestInviteUriSource(stream.stream, null),
          ),
        ),
      );
      await _pumpRoot(tester);
      expect(find.byType(FamilyJoinScreen, skipOffstage: false), findsNothing);

      stream
        ..add(_familyJoinUri)
        ..add(_familyJoinUri);
      await _pumpWarmRoute(tester);

      expect(
        find.byType(FamilyJoinScreen, skipOffstage: false),
        findsOneWidget,
      );
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await _pumpRouteTransition(tester);

      expect(find.byType(FamilyJoinScreen, skipOffstage: false), findsNothing);

      stream.add(_familyJoinUri);
      await _pumpWarmRoute(tester);
      expect(
        find.byType(FamilyJoinScreen, skipOffstage: false),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await canceled.future;
      await stream.close();
    },
  );

  testWidgets(
    'holds a different warm code until the active Join route closes',
    (tester) async {
      final canceled = Completer<void>();
      final stream = StreamController<Uri>.broadcast(
        onCancel: () {
          if (!canceled.isCompleted) canceled.complete();
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localIdentityProvider.overrideWithValue(
              const AsyncValue.data(null),
            ),
          ],
          child: KeepersApp(
            inviteUriSource: _TestInviteUriSource(stream.stream, null),
          ),
        ),
      );
      await _pumpRoot(tester);

      stream.add(_familyJoinUri);
      await _pumpWarmRoute(tester);
      stream.add(_otherFamilyJoinUri);
      await tester.pump();
      expect(
        find.byType(FamilyJoinScreen, skipOffstage: false),
        findsOneWidget,
      );

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await _pumpRouteTransition(tester);
      expect(
        find.byType(FamilyJoinScreen, skipOffstage: false),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await canceled.future;
      await stream.close();
    },
  );

  testWidgets('auth callback stays outside family-link navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localIdentityProvider.overrideWithValue(const AsyncValue.data(null)),
        ],
        child: KeepersApp(
          inviteUriSource: _TestInviteUriSource(
            const Stream<Uri>.empty(),
            Uri.parse('keepers://auth-callback?code=authorization-code'),
          ),
        ),
      ),
    );
    await _pumpRoot(tester);

    expect(find.byType(FamilyJoinScreen, skipOffstage: false), findsNothing);
  });

  testWidgets('malformed family namespace opens the neutral Join route', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localIdentityProvider.overrideWithValue(const AsyncValue.data(null)),
        ],
        child: KeepersApp(
          inviteUriSource: _TestInviteUriSource(
            const Stream<Uri>.empty(),
            Uri.parse('https://join.keepers.app/f/K7M4-P2Q8?token=do-not-log'),
          ),
        ),
      ),
    );
    await _pumpRoot(tester);

    expect(find.byType(FamilyJoinScreen, skipOffstage: false), findsOneWidget);
    expect(find.text('CREATE A FAMILY'), findsNothing);
    expect(find.textContaining('do-not-log'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('legacy capability link stays outside family-link navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localIdentityProvider.overrideWithValue(const AsyncValue.data(null)),
        ],
        child: KeepersApp(
          inviteUriSource: _TestInviteUriSource(
            const Stream<Uri>.empty(),
            Uri.parse(
              'keepers://join?v=1&i=123e4567-e89b-12d3-a456-426614174000&t=secret&s=secret',
            ),
          ),
        ),
      ),
    );
    await _pumpRoot(tester);

    expect(find.byType(FamilyJoinScreen, skipOffstage: false), findsNothing);
  });
}

Future<PendingJoinCompletionState> _idleJoinRecovery() async =>
    const PendingJoinCompletionState();

Future<void> _finishLaunchLogoPrecache(WidgetTester tester) async {
  await tester.runAsync(
    () => precacheImage(
      const AssetImage(keepersLaunchWordmarkAsset),
      tester.element(find.byType(KeepersLaunchSequence)),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpRoot(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpRouteTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

Future<void> _pumpWarmRoute(WidgetTester tester) async {
  await tester.idle();
  expect(tester.binding.hasScheduledFrame, isTrue);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

final _familyJoinUri = Uri.parse('https://join.keepers.app/f/K7M4-P2Q8');
final _otherFamilyJoinUri = Uri.parse('https://join.keepers.app/f/1111-1111');

final class _TestInviteUriSource implements InviteUriSource {
  const _TestInviteUriSource(this.uriLinkStream, this._initial);
  @override
  final Stream<Uri> uriLinkStream;
  final Uri? _initial;
  @override
  Future<Uri?> getInitialUri() async => _initial;
}

final class _ConfiguredAccountGateway implements CloudFamilyGateway {
  const _ConfiguredAccountGateway();

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => null;

  @override
  String? get authenticatedEmail => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _SignedInAccountGateway implements CloudFamilyGateway {
  const _SignedInAccountGateway();

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => 'account-1';

  @override
  String? get authenticatedEmail => 'keeper@example.com';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
