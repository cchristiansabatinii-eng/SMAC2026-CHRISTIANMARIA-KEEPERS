import 'dart:async';
import 'dart:ui' show Rect, SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_invite_controller.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/family/presentation/family_invite_screen.dart';
import 'package:keepers/features/family/presentation/family_join_screen.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/storage/schema.dart';
import 'package:keepers/theme/keepers_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const familyInvitationViewport = Size(390, 844);
const familyInvitationTextScale = 1.4;
Database? _activeJoinHarnessDatabase;

const invitationTestLink = FamilyInviteLink(
  inviteId: '123e4567-e89b-12d3-a456-426614174000',
  token: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  wrappingSecret: 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE',
);

CreatedInvitation invitationTestCreated() => CreatedInvitation(
  inviteId: '44444444-4444-4444-8444-444444444444',
  familyId: '11111111-1111-4111-8111-111111111111',
  state: CloudInvitationState.pending,
  createdAt: DateTime.utc(2026, 9, 5, 8),
  expiresAt: DateTime.utc(2026, 9, 6, 8),
);

Future<void> configureFamilyInvitationViewport(WidgetTester tester) async {
  tester.view.physicalSize = familyInvitationViewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

MediaQueryData invitationMediaQuery({double keyboardInset = 0}) =>
    MediaQueryData(
      size: familyInvitationViewport,
      textScaler: const TextScaler.linear(familyInvitationTextScale),
      viewInsets: EdgeInsets.only(bottom: keyboardInset),
      disableAnimations: true,
      accessibleNavigation: true,
    );

Future<void> pumpInviteHarness(
  WidgetTester tester,
  InvitationTestInviteController controller, {
  double keyboardInset = 0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        familyInviteControllerProvider.overrideWith(() => controller),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: KeepersType.primary),
        home: MediaQuery(
          data: invitationMediaQuery(keyboardInset: keyboardInset),
          child: const FamilyInviteScreen(initializeOnMount: false),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> pumpJoinHarness(
  WidgetTester tester,
  InvitationTestGateway gateway, {
  bool identityLoading = false,
  bool settle = true,
  double keyboardInset = 0,
  VoidCallback? onAbandoned,
}) async {
  final database = await _joinHarnessDatabase();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        databaseProvider.overrideWithValue(AsyncValue.data(database)),
        cloudFamilyGatewayProvider.overrideWithValue(gateway),
        localIdentityProvider.overrideWithValue(
          identityLoading
              ? const AsyncValue<LocalIdentity?>.loading()
              : const AsyncValue<LocalIdentity?>.data(null),
        ),
        idFactoryProvider.overrideWithValue(() => 'draft-member'),
        utcNowProvider.overrideWithValue(() => DateTime.utc(2026, 9, 5)),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: KeepersType.primary),
        home: MediaQuery(
          data: invitationMediaQuery(keyboardInset: keyboardInset),
          child: FamilyJoinScreen(
            link: invitationTestLink,
            onAbandoned: onAbandoned,
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<Database> _joinHarnessDatabase() async {
  if (_activeJoinHarnessDatabase case final database?) return database;
  sqfliteFfiInit();
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
  _activeJoinHarnessDatabase = database;
  addTearDown(() async {
    if (identical(_activeJoinHarnessDatabase, database)) {
      _activeJoinHarnessDatabase = null;
    }
    await database.close();
  });
  return database;
}

Future<void> pumpJoinSnapshotHarness(
  WidgetTester tester,
  FamilyJoinState state,
) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        familyJoinControllerProvider.overrideWithBuild(
          (ref, notifier) => state,
        ),
        cloudFamilyGatewayProvider.overrideWithValue(InvitationTestGateway()),
        localIdentityProvider.overrideWithValue(
          const AsyncValue<LocalIdentity?>.loading(),
        ),
        idFactoryProvider.overrideWithValue(() => 'draft-member'),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: KeepersType.primary),
        home: MediaQuery(
          data: invitationMediaQuery(),
          child: const FamilyJoinScreen(link: invitationTestLink),
        ),
      ),
    ),
  );
}

void expectMinimumTarget(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final size = tester.getSize(finder);
  expect(size.width, greaterThanOrEqualTo(44), reason: '$finder width');
  expect(size.height, greaterThanOrEqualTo(44), reason: '$finder height');
}

void expectOperableSemantics(
  WidgetTester tester,
  String label, {
  bool enabled = true,
  bool liveRegion = false,
}) {
  final labelled = find.bySemanticsLabel(label);
  final buttons = <Finder>[];
  for (var index = 0; index < labelled.evaluate().length; index += 1) {
    final candidate = labelled.at(index);
    final data = tester.getSemantics(candidate).getSemanticsData();
    if (data.flagsCollection.isButton) buttons.add(candidate);
  }
  expect(buttons, hasLength(1), reason: '$label must expose one button node');
  final finder = buttons.single;
  final data = tester.getSemantics(finder).getSemanticsData();
  expect(data.flagsCollection.isButton, isTrue, reason: label);
  expect(
    data.flagsCollection.isEnabled,
    enabled ? Tristate.isTrue : Tristate.isFalse,
    reason: label,
  );
  expect(
    data.hasAction(SemanticsAction.tap),
    enabled,
    reason: '$label tap action',
  );
  expect(data.flagsCollection.isLiveRegion, liveRegion, reason: label);
  expectMinimumTarget(tester, finder);
}

void expectLiveRegion(WidgetTester tester, String label) {
  final finder = find.bySemanticsLabel(label);
  expect(finder, findsOneWidget);
  expect(
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isLiveRegion,
    isTrue,
    reason: label,
  );
}

void expectNoInvitationSecrets() {
  final forbidden = [
    invitationTestLink.token,
    invitationTestLink.wrappingSecret,
    invitationTestLink.inviteId,
    invitationTestLink.toUri().toString(),
    'keepers://join',
  ];
  for (final secret in forbidden) {
    expect(
      find.textContaining(secret, findRichText: true),
      findsNothing,
      reason: 'Secret text must stay out of the widget tree',
    );
    expect(
      find.bySemanticsLabel(RegExp(RegExp.escape(secret))),
      findsNothing,
      reason: 'Secret text must stay out of accessibility labels',
    );
  }
}

final class InvitationTestInviteController extends FamilyInviteController {
  InvitationTestInviteController(this.initialState);

  final FamilyInviteState initialState;
  final requestedEmails = <String>[];
  final verifiedTokens = <String>[];
  final createdRecipients = <String>[];
  var initializeCalls = 0;
  var shareCalls = 0;
  var revokeCalls = 0;

  @override
  FamilyInviteState build() => initialState;

  void show(FamilyInviteState value) => state = value;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<void> requestEmailOtp(String email) async {
    requestedEmails.add(email);
    state = FamilyInviteState(
      phase: FamilyInvitePhase.awaitingOtp,
      authenticationEmail: email,
    );
  }

  @override
  Future<void> verifyEmailOtp(String token) async {
    verifiedTokens.add(token);
    state = FamilyInviteState(
      phase: FamilyInvitePhase.ready,
      authenticationEmail: state.authenticationEmail,
    );
  }

  @override
  Future<void> createInvite(
    String recipientEmail, {
    Rect? sharePositionOrigin,
  }) async {
    createdRecipients.add(recipientEmail);
  }

  @override
  Future<void> shareAgain({Rect? sharePositionOrigin}) async {
    shareCalls += 1;
  }

  @override
  Future<void> revokeInvite() async {
    revokeCalls += 1;
  }
}

final class InvitationTestGateway implements CloudFamilyGateway {
  InvitationTestGateway({
    this.account,
    this.configured = true,
    this.previewFailure,
    this.verifyFailure,
    this.requestGate,
    this.verifyGate,
    this.claimGate,
  });

  String? account;
  final bool configured;
  InvitationFailure? previewFailure;
  InvitationFailure? verifyFailure;
  final Completer<void>? requestGate;
  final Completer<void>? verifyGate;
  final Completer<ClaimedFamily>? claimGate;
  final requestedEmails = <String>[];
  final verifiedTokens = <String>[];
  var previewCalls = 0;
  var claimCalls = 0;

  @override
  bool get isConfigured => configured;

  @override
  String? get authenticatedAccountId => account;

  @override
  String? get authenticatedEmail => null;

  @override
  Future<void> requestEmailOtp(String email) async {
    requestedEmails.add(email);
    if (requestGate case final gate?) await gate.future;
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    verifiedTokens.add(token);
    if (verifyFailure case final failure?) throw failure;
    if (verifyGate case final gate?) await gate.future;
    account = 'recipient';
  }

  @override
  Future<InvitePreview> previewInvitation(FamilyInviteLink link) async {
    previewCalls += 1;
    if (previewFailure case final failure?) throw failure;
    return InvitePreview(
      inviteId: link.inviteId,
      familyId: 'family',
      familyName: 'Rahman',
      ownerName: 'Amina',
      expiresAt: DateTime.utc(2026, 9, 6),
      state: CloudInvitationState.pending,
    );
  }

  @override
  Future<ClaimedFamily> claimInvitation(JoinRequest request) async {
    claimCalls += 1;
    if (claimGate case final gate?) return gate.future;
    throw const InvitationFailure(InvitationFailureCode.unknown);
  }

  @override
  Future<void> bootstrapOwner(LocalOwnerFamily owner) async =>
      throw UnsupportedError('Unused by the join harness');

  @override
  Future<CreatedInvitation> createInvitation(
    CloudInvitationDraft draft,
  ) async => throw UnsupportedError('Unused by the join harness');

  @override
  Future<void> completeInvitation(String inviteId) async =>
      throw UnsupportedError('Unused by the join harness');

  @override
  Future<List<FamilyMember>> listActiveMembers(String familyId) async =>
      throw UnsupportedError('Unused by the join harness');

  @override
  Future<void> revokeInvitation(String inviteId) async =>
      throw UnsupportedError('Unused by the join harness');
}
