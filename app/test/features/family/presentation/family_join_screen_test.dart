import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/family_join_crypto_providers.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/joining_key_store.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/family/presentation/family_join_screen.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/database_providers.dart';

void main() {
  testWidgets('first-run family link offers every account method', (
    tester,
  ) async {
    final gateway = _Gateway(authenticated: false);
    await _pumpManual(
      tester,
      gateway: gateway,
      screen: FamilyJoinScreen.forCode(_code),
    );

    expect(find.text('Create your Keepers account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Microsoft'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.byKey(const Key('join-email')), findsOneWidget);
    final googleButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Continue with Google'),
    );
    expect(googleButton.focusNode?.hasFocus, isTrue);

    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    await tester.pump();
    expect(gateway.socialProviders, [SocialAuthProvider.google]);
    expect(find.text('Finish in your browser'), findsOneWidget);
    expect(find.text('Continue with Microsoft'), findsNothing);

    await tester.tap(find.text('Choose another way'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Microsoft'), findsOneWidget);
  });

  testWidgets('family-link account choices stay reachable at 1.4x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpManual(
      tester,
      gateway: _Gateway(authenticated: false),
      screen: FamilyJoinScreen.forCode(_code),
      textScale: 1.4,
    );

    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Continue with Google'),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    await tester.ensureVisible(find.text('Continue with email'));
    expect(find.text('Continue with email').hitTestable(), findsOneWidget);
  });

  testWidgets('manual entry accepts pasted formatting and previews a family', (
    tester,
  ) async {
    await _pumpManual(tester);
    await tester.enterText(
      find.byKey(const Key('family-code-field')),
      'k 7 m 4 - p 2 - q 8',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Rahman family'), findsOneWidget);
    expect(find.text('Request to join'), findsOneWidget);
    expect(find.textContaining('memory'), findsNothing);
  });

  testWidgets('forCode skips code entry and preserves callback contract', (
    tester,
  ) async {
    await _pumpManual(tester, screen: FamilyJoinScreen.forCode(_code));
    expect(find.byKey(const Key('family-code-field')), findsNothing);
    expect(find.text('Rahman family'), findsOneWidget);
  });

  testWidgets('preview reveals only the family name and sanitized avatars', (
    tester,
  ) async {
    await _pumpSnapshot(tester, _previewState);

    expect(find.text('Rahman family'), findsOneWidget);
    expect(find.text('Private member name'), findsNothing);
    expect(find.byKey(const Key('family-preview-avatar-0')), findsOneWidget);
    expect(find.textContaining('memory'), findsNothing);
  });

  testWidgets('pending state has exact copy and a 48dp cancel control', (
    tester,
  ) async {
    await _pumpSnapshot(tester, _pendingState);

    expect(
      find.text('Waiting for a family member to let you in'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('cancel-join-request'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  for (final entry in <String, FamilyJoinScreen>{
    'manual': const FamilyJoinScreen.manual(),
    'link': FamilyJoinScreen.forCode(_code),
  }.entries) {
    testWidgets('${entry.key} entry cannot abandon an unresolved request', (
      tester,
    ) async {
      await _pumpManual(tester, screen: entry.value);
      if (find.byKey(const Key('family-code-field')).evaluate().isNotEmpty) {
        await tester.enterText(
          find.byKey(const Key('family-code-field')),
          'K7M4-P2Q8',
        );
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FamilyJoinScreen)),
      );
      final preview = container.read(familyJoinControllerProvider);
      await container
          .read(familyJoinControllerProvider.notifier)
          .requestJoin(
            FamilyJoinProfileDraft(
              memberId: preview.proposedMemberId!,
              displayName: 'Mariam',
              demographicRole: FamilyDemographicRole.adult,
              colorToken: 'ochre',
              avatar: preview.proposedAvatar!,
              joiningPublicKey: preview.proposedJoiningPublicKey!,
            ),
          );
      await tester.pump();

      expect(find.byKey(const Key('leave-family-join')), findsNothing);
      expect(
        tester.widget<PopScope<void>>(find.byType(PopScope<void>)).canPop,
        isFalse,
      );
    });
  }

  testWidgets('callback-free completion pops the join route', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyJoinControllerProvider.overrideWithBuild(
            (ref, _) => ref.watch(_familyJoinSnapshotProvider),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-family-join'),
                onPressed: () => unawaited(
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const FamilyJoinScreen.manual(),
                    ),
                  ),
                ),
                child: const Text('Join a family'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-family-join')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(FamilyJoinScreen), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(FamilyJoinScreen)),
    );
    container
        .read(_familyJoinSnapshotProvider.notifier)
        .emit(
          FamilyJoinState(
            phase: FamilyJoinPhase.complete,
            request: _pendingRequest,
          ),
        );
    await tester.pumpAndSettle();

    expect(find.byType(FamilyJoinScreen), findsNothing);
    expect(find.byKey(const Key('open-family-join')), findsOneWidget);
  });

  testWidgets('terminal requester outcomes remain distinct', (tester) async {
    const cases = <FamilyJoinState, String>{
      FamilyJoinState(phase: FamilyJoinPhase.declined):
          "Your request wasn't accepted",
      FamilyJoinState(phase: FamilyJoinPhase.expired):
          'Your request has expired',
      FamilyJoinState(phase: FamilyJoinPhase.invitationChanged):
          'This family invitation has changed. Ask for the new code.',
      FamilyJoinState(
        phase: FamilyJoinPhase.failed,
        failure: FamilyJoinFailure(FamilyJoinFailureCode.alreadyMember),
      ): 'You already belong to a family',
      FamilyJoinState(
        phase: FamilyJoinPhase.failed,
        failure: FamilyJoinFailure(FamilyJoinFailureCode.familyNotFound),
      ): 'Family not found',
    };
    for (final entry in cases.entries) {
      await _pumpSnapshot(tester, entry.key);
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets('network feedback is a live region and keeps Retry visible', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpSnapshot(
      tester,
      FamilyJoinState(
        phase: FamilyJoinPhase.pending,
        request: _pendingRequest,
        preview: _preview,
        failure: const FamilyJoinFailure(
          FamilyJoinFailureCode.networkUnavailable,
        ),
        retryPoint: FamilyJoinRetryPoint.refreshStatus,
      ),
      textScale: 1.5,
    );

    expect(find.text('Retry'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Keepers could not connect. Try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('explains when the signed-in account has another family', (
    tester,
  ) async {
    await _pumpSnapshot(
      tester,
      FamilyJoinState(
        phase: FamilyJoinPhase.pending,
        request: _pendingRequest,
        preview: _preview,
        failure: const FamilyJoinFailure(
          FamilyJoinFailureCode.accountFamilyConflict,
        ),
        retryPoint: FamilyJoinRetryPoint.refreshStatus,
      ),
    );

    expect(
      find.text('This account is already connected to another family.'),
      findsOneWidget,
    );
  });

  testWidgets('recoverable failure moves focus to Retry', (tester) async {
    await _pumpManual(
      tester,
      gateway: _Gateway(
        previewFailure: const FamilyJoinFailure(
          FamilyJoinFailureCode.networkUnavailable,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('family-code-field')),
      'K7M4-P2Q8',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final retry = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Retry'),
    );
    expect(retry.focusNode?.hasFocus, isTrue);
  });

  testWidgets('malformed route is neutral and cannot create a request', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: FamilyJoinScreen.malformed()),
    );
    expect(find.text('Family not found'), findsOneWidget);
    expect(find.text('Request to join'), findsNothing);
  });
}

final _familyJoinSnapshotProvider =
    NotifierProvider<_FamilyJoinSnapshotController, FamilyJoinState>(
      _FamilyJoinSnapshotController.new,
    );

final class _FamilyJoinSnapshotController extends Notifier<FamilyJoinState> {
  @override
  FamilyJoinState build() => _pendingState;

  void emit(FamilyJoinState next) => state = next;
}

Future<void> _pumpManual(
  WidgetTester tester, {
  Widget screen = const FamilyJoinScreen.manual(),
  _Gateway? gateway,
  double textScale = 1,
}) async {
  final resolvedGateway = gateway ?? _Gateway();
  final values = _MemorySecureValueStore();
  addTearDown(resolvedGateway.dispose);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        cloudFamilyGatewayProvider.overrideWithValue(resolvedGateway),
        familyCodeJoinGatewayProvider.overrideWithValue(resolvedGateway),
        secureValueStoreProvider.overrideWithValue(values),
        joiningKeyStoreProvider.overrideWithValue(
          SecureJoiningKeyStore(
            values,
            seedFactory: (length) => List<int>.filled(length, 7),
          ),
        ),
        idFactoryProvider.overrideWithValue(() => _memberId),
        localIdentityProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        theme: ThemeData(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSnapshot(
  WidgetTester tester,
  FamilyJoinState state, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        familyJoinControllerProvider.overrideWithBuild((ref, _) => state),
      ],
      child: MaterialApp(
        theme: ThemeData(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: TextScaler.linear(textScale),
          ),
          child: const FamilyJoinScreen.manual(),
        ),
      ),
    ),
  );
  await tester.pump();
}

final class _Gateway
    implements
        CloudFamilyGateway,
        FamilyCodeJoinGateway,
        CloudFamilySocialAuth {
  _Gateway({this.previewFailure, bool authenticated = true})
    : accountId = authenticated ? _accountId : null;

  final FamilyJoinFailure? previewFailure;
  String? accountId;
  final socialProviders = <SocialAuthProvider>[];
  final _invalidations = StreamController<void>.broadcast();
  void dispose() => _invalidations.close();
  @override
  bool get isConfigured => true;
  @override
  String? get authenticatedAccountId => accountId;
  @override
  String? get authenticatedEmail => 'mariam@example.com';
  @override
  Future<OwnFamilyJoinRequest?> getOwnJoinRequest() async => null;
  @override
  Future<FamilyJoinPreview> previewFamilyByCode(FamilyCode code) async {
    if (previewFailure case final failure?) throw failure;
    return _preview;
  }

  @override
  Stream<void> watchOwnJoinRequest() => _invalidations.stream;
  @override
  Future<void> requestEmailOtp(String email) async {}

  @override
  Future<void> signInWithProvider(SocialAuthProvider provider) async {
    socialProviders.add(provider);
  }

  @override
  Future<bool> cancelPendingProviderSignIn() async => true;

  @override
  Future<bool> clearFailedProviderSignIn() async => true;

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {}

  @override
  Future<FamilyJoinDecision> approveJoinRequest(
    String requestId,
    FamilyJoinApprovalEnvelope envelope,
  ) => throw UnimplementedError();
  @override
  Future<void> bootstrapOwner(LocalOwnerFamily owner) =>
      throw UnimplementedError();
  @override
  Future<EncryptedFamilyCodeRecord> bootstrapOwnerWithFamilyCode(
    LocalOwnerFamily owner,
    FamilyCodeDraft code,
  ) => throw UnimplementedError();
  @override
  Future<FamilyJoinDecision> cancelJoinRequest(String requestId) =>
      throw UnimplementedError();
  @override
  Future<ClaimedFamily> claimInvitation(JoinRequest request) =>
      throw UnimplementedError();
  @override
  Future<FamilyJoinDecision> completeJoinRequest(String requestId) =>
      throw UnimplementedError();
  @override
  Future<void> completeInvitation(String inviteId) =>
      throw UnimplementedError();
  @override
  Future<CreatedInvitation> createInvitation(CloudInvitationDraft draft) =>
      throw UnimplementedError();
  @override
  Future<OwnFamilyJoinRequest> createFamilyJoinRequest(
    FamilyJoinRequestDraft draft,
  ) async => OwnFamilyJoinRequest.validated(
    requestId: _requestId,
    familyId: _preview.familyId,
    familyName: _preview.familyName,
    requesterAccountId: _accountId,
    memberId: draft.profile.memberId,
    displayName: draft.profile.displayName,
    demographicRole: draft.profile.demographicRole,
    colorToken: draft.profile.colorToken,
    avatar: draft.profile.avatar,
    joiningPublicKey: draft.profile.joiningPublicKey,
    codeVersion: _preview.codeVersion,
    state: FamilyJoinRequestState.pending,
    createdAt: DateTime.utc(2026, 9, 7),
    expiresAt: DateTime.utc(2026, 9, 14),
  );
  @override
  Future<FamilyJoinDecision> declineJoinRequest(String requestId) =>
      throw UnimplementedError();
  @override
  Future<EncryptedFamilyCodeRecord> getFamilyCode(String familyId) =>
      throw UnimplementedError();
  @override
  Future<List<FamilyMember>> listActiveMembers(String familyId) =>
      throw UnimplementedError();
  @override
  Future<List<PendingFamilyJoinRequest>> listPendingJoinRequests(
    String familyId,
  ) => throw UnimplementedError();
  @override
  Future<InvitePreview> previewInvitation(FamilyInviteLink link) =>
      throw UnimplementedError();
  @override
  Future<EncryptedFamilyCodeRecord> regenerateFamilyCode({
    required String familyId,
    required int expectedVersion,
    required FamilyCodeDraft replacement,
  }) => throw UnimplementedError();
  @override
  Future<void> revokeInvitation(String inviteId) => throw UnimplementedError();
  @override
  Stream<void> watchPendingJoinRequests(String familyId) =>
      const Stream.empty();
}

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

FamilyMember _member(String name) => FamilyMember(
  id: _existingMemberId,
  familyId: _familyId,
  name: name,
  role: 'adult',
  colorToken: 'ochre',
  avatar: const AvatarConfig.defaults(seed: _existingMemberId),
  joinedAt: DateTime.utc(2025),
);

final _code = FamilyCode.parse('K7M4-P2Q8');
final _preview = FamilyJoinPreview(
  familyId: _familyId,
  familyName: 'Rahman family',
  codeVersion: 1,
  members: [_member('Private member name')],
);
final _previewState = FamilyJoinState(
  phase: FamilyJoinPhase.preview,
  preview: _preview,
  proposedMemberId: _memberId,
  proposedAvatar: AvatarConfig.defaults(seed: _memberId),
  proposedJoiningPublicKey: _publicKey,
);
final _pendingRequest = OwnFamilyJoinRequest(
  requestId: _requestId,
  familyId: _familyId,
  familyName: 'Rahman family',
  requesterAccountId: _accountId,
  memberId: _memberId,
  displayName: 'Mariam',
  demographicRole: FamilyDemographicRole.adult,
  colorToken: 'ochre',
  avatar: const AvatarConfig.defaults(seed: _memberId),
  joiningPublicKey: _publicKey,
  codeVersion: 1,
  state: FamilyJoinRequestState.pending,
  createdAt: DateTime.utc(2026, 9, 7),
  expiresAt: DateTime.utc(2026, 9, 14),
);
final _pendingState = FamilyJoinState(
  phase: FamilyJoinPhase.pending,
  preview: _preview,
  request: _pendingRequest,
);

const _requestId = '11111111-1111-4111-8111-111111111111';
const _familyId = '22222222-2222-4222-8222-222222222222';
const _accountId = '33333333-3333-4333-8333-333333333333';
const _memberId = '44444444-4444-4444-8444-444444444444';
const _existingMemberId = '55555555-5555-4555-8555-555555555555';
const _publicKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
