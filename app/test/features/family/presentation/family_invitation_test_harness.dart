import 'dart:ui' show Rect, SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/family/application/family_code_controller.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/family_join_requests_controller.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/family/presentation/family_invite_sheet.dart';
import 'package:keepers/features/family/presentation/family_join_request_sheet.dart';
import 'package:keepers/features/family/presentation/family_join_screen.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';

const familyInvitationPhone = Size(390, 844);
const familyInvitationLargePhone = Size(430, 932);
const familyInvitationTextScale = 1.4;

const familyInvitationFamilyId = '11111111-1111-4111-8111-111111111111';
const familyInvitationRequestId = '22222222-2222-4222-8222-222222222222';
const familyInvitationRequesterAccountId =
    '33333333-3333-4333-8333-333333333333';
const familyInvitationRequesterMemberId =
    '44444444-4444-4444-8444-444444444444';
const familyInvitationOwnerMemberId = '55555555-5555-4555-8555-555555555555';
const familyInvitationApproverMemberId = '66666666-6666-4666-8666-666666666666';
const familyInvitationJoiningPublicKey =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

final familyInvitationCode = FamilyCode.parse('K7M4-P2Q8');

final familyInvitationPreview = FamilyJoinPreview(
  familyId: familyInvitationFamilyId,
  familyName: 'Rahman family',
  codeVersion: 1,
  members: [
    familyInvitationMember(
      id: familyInvitationOwnerMemberId,
      name: 'Private owner name',
      colorToken: 'ochre',
    ),
    familyInvitationMember(
      id: familyInvitationApproverMemberId,
      name: 'Private approver name',
      colorToken: 'clay',
    ),
  ],
);

final familyInvitationPendingRequest = OwnFamilyJoinRequest(
  requestId: familyInvitationRequestId,
  familyId: familyInvitationFamilyId,
  familyName: 'Rahman family',
  requesterAccountId: familyInvitationRequesterAccountId,
  memberId: familyInvitationRequesterMemberId,
  displayName: 'Mariam',
  demographicRole: FamilyDemographicRole.adult,
  colorToken: 'clay',
  avatar: const AvatarConfig.defaults(seed: familyInvitationRequesterMemberId),
  joiningPublicKey: familyInvitationJoiningPublicKey,
  codeVersion: 1,
  state: FamilyJoinRequestState.pending,
  createdAt: DateTime.utc(2026, 9, 7),
  expiresAt: DateTime.utc(2026, 9, 14),
  roster: familyInvitationPreview.members,
);

final familyInvitationApproverRequest = PendingFamilyJoinRequest.validated(
  requestId: familyInvitationRequestId,
  familyId: familyInvitationFamilyId,
  requesterAccountId: familyInvitationRequesterAccountId,
  memberId: familyInvitationRequesterMemberId,
  displayName: 'Mariam',
  demographicRole: FamilyDemographicRole.adult,
  colorToken: 'clay',
  avatar: const AvatarConfig.defaults(seed: familyInvitationRequesterMemberId),
  joiningPublicKey: familyInvitationJoiningPublicKey,
  codeVersion: 1,
  state: FamilyJoinRequestState.pending,
  createdAt: DateTime.utc(2026, 9, 7),
  expiresAt: DateTime.utc(2026, 9, 14),
);

FamilyMember familyInvitationMember({
  required String id,
  required String name,
  required String colorToken,
}) => FamilyMember(
  id: id,
  familyId: familyInvitationFamilyId,
  name: name,
  role: 'adult',
  colorToken: colorToken,
  avatar: AvatarConfig.defaults(seed: id),
  joinedAt: DateTime.utc(2026, 9, 7),
);

Future<void> configureFamilyInvitationViewport(
  WidgetTester tester, {
  Size size = familyInvitationPhone,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

MediaQueryData familyInvitationMediaQuery({
  Size size = familyInvitationPhone,
  double keyboardInset = 0,
  double textScale = familyInvitationTextScale,
}) => MediaQueryData(
  size: size,
  textScaler: TextScaler.linear(textScale),
  viewInsets: EdgeInsets.only(bottom: keyboardInset),
  disableAnimations: true,
  accessibleNavigation: true,
);

Future<void> pumpFamilyCodeSheet(
  WidgetTester tester,
  InvitationTestFamilyCodeController controller, {
  Size size = familyInvitationPhone,
  double textScale = familyInvitationTextScale,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        familyCodeControllerProvider(familyInvitationFamilyId)
            .overrideWith(() => controller),
      ],
      child: MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: familyInvitationMediaQuery(size: size, textScale: textScale),
          child: const Scaffold(
            body: FamilyInviteSheet(
              familyId: familyInvitationFamilyId,
              initializeOnMount: false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> pumpFamilyJoinSnapshot(
  WidgetTester tester,
  FamilyJoinState state, {
  Size size = familyInvitationPhone,
  double keyboardInset = 0,
  double textScale = familyInvitationTextScale,
  bool resumePendingRequest = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        familyJoinControllerProvider.overrideWithBuild(
          (ref, notifier) => state,
        ),
      ],
      child: MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: familyInvitationMediaQuery(
            size: size,
            keyboardInset: keyboardInset,
            textScale: textScale,
          ),
          child: FamilyJoinScreen.manual(
            resumePendingRequest: resumePendingRequest,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> pumpFamilyJoinRequestSheet(
  WidgetTester tester,
  InvitationTestJoinRequestsController controller, {
  Size size = familyInvitationPhone,
  double textScale = familyInvitationTextScale,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        familyJoinRequestsControllerProvider(familyInvitationFamilyId)
            .overrideWith(() => controller),
      ],
      child: MaterialApp(
        theme: KeepersTheme.daylight(),
        home: MediaQuery(
          data: familyInvitationMediaQuery(size: size, textScale: textScale),
          child: Scaffold(
            body: FamilyJoinRequestSheet(
              familyId: familyInvitationFamilyId,
              request: familyInvitationApproverRequest,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void expectMinimumFamilyTarget(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final size = tester.getSize(finder);
  expect(size.width, greaterThanOrEqualTo(48), reason: '$finder width');
  expect(size.height, greaterThanOrEqualTo(48), reason: '$finder height');
}

void expectFamilyButtonSemantics(
  WidgetTester tester,
  String label, {
  bool enabled = true,
  bool liveRegion = false,
}) {
  final labelled = find.bySemanticsLabel(label);
  final buttons = <Finder>[];
  for (var index = 0; index < labelled.evaluate().length; index += 1) {
    final candidate = labelled.at(index);
    if (tester
        .getSemantics(candidate)
        .getSemanticsData()
        .flagsCollection
        .isButton) {
      buttons.add(candidate);
    }
  }
  expect(buttons, hasLength(1), reason: '$label must expose one button node');
  final finder = buttons.single;
  final data = tester.getSemantics(finder).getSemanticsData();
  expect(
    data.flagsCollection.isEnabled,
    enabled ? Tristate.isTrue : Tristate.isFalse,
    reason: label,
  );
  expect(data.hasAction(SemanticsAction.tap), enabled, reason: '$label tap');
  expect(data.flagsCollection.isLiveRegion, liveRegion, reason: label);
  expectMinimumFamilyTarget(tester, finder);
}

void expectFamilyLiveRegion(WidgetTester tester, String label) {
  final finder = find.bySemanticsLabel(label);
  expect(finder, findsOneWidget);
  expect(
    tester.getSemantics(finder).getSemanticsData().flagsCollection.isLiveRegion,
    isTrue,
    reason: label,
  );
}

void expectNoPrivateFamilyJoinMaterial() {
  const forbidden = <String>[
    familyInvitationJoiningPublicKey,
    'Private owner name',
    'Private approver name',
    'family-key',
    'joining-key',
    'ciphertext',
    'shared secret',
  ];
  for (final value in forbidden) {
    expect(
      find.textContaining(value, findRichText: true),
      findsNothing,
      reason: 'Private join material must not reach painted text',
    );
    expect(
      find.bySemanticsLabel(RegExp(RegExp.escape(value), caseSensitive: false)),
      findsNothing,
      reason: 'Private join material must not reach spoken text',
    );
  }
}

final class InvitationTestFamilyCodeController extends FamilyCodeController {
  InvitationTestFamilyCodeController(this.initial)
    : super(familyInvitationFamilyId);

  final FamilyCodeState initial;
  var loadCalls = 0;
  var shareCalls = 0;
  var copyCodeCalls = 0;
  var copyLinkCalls = 0;
  var regenerateCalls = 0;

  @override
  FamilyCodeState build() => initial;

  void show(FamilyCodeState value) => state = value;

  @override
  Future<void> load() async => loadCalls += 1;

  @override
  Future<void> shareFamilyLink({Rect? sharePositionOrigin}) async {
    shareCalls += 1;
  }

  @override
  Future<void> copyFamilyCode() async => copyCodeCalls += 1;

  @override
  Future<void> copyFamilyLink() async => copyLinkCalls += 1;

  @override
  Future<void> regenerate() async => regenerateCalls += 1;
}

final class InvitationTestJoinRequestsController
    extends FamilyJoinRequestsController {
  InvitationTestJoinRequestsController(this.initial)
    : super(familyInvitationFamilyId);

  final FamilyJoinRequestsState initial;
  var approveCalls = 0;
  var declineCalls = 0;

  @override
  FamilyJoinRequestsState build() => initial;

  void show(FamilyJoinRequestsState value) => state = value;

  @override
  Future<void> approve(String requestId) async => approveCalls += 1;

  @override
  Future<void> decline(String requestId) async => declineCalls += 1;
}
