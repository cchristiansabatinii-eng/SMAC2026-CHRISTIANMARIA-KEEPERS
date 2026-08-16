import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keepers/app.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_invite_controller.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/family/application/pending_invite_completion_controller.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/family_key_envelope_codec.dart';
import 'package:keepers/features/family/data/invite_link_coordinator.dart';
import 'package:keepers/features/family/data/invite_share_service.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/family/presentation/family_invite_screen.dart';
import 'package:keepers/features/family/presentation/family_join_screen.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/onboarding/presentation/setup_screen.dart';
import 'package:keepers/features/vault/presentation/observatory_screen.dart';
import 'package:keepers/storage/app_database.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/ui/keepers_app_background.dart';
import 'package:path/path.dart' as p;

/// A device integration fixture with two process-like local installations.
///
/// The installations share only [_StatefulFamilyCloud]. The invitation
/// capability moves from owner to recipient exclusively through the recording
/// share service and a cold-start URI source.
final class FamilyInvitationFlowHarness {
  FamilyInvitationFlowHarness._({
    required this._root,
    required this._cloud,
    required this._owner,
    required this._recipient,
  });

  static const familyId = '11111111-1111-4111-8111-111111111111';
  static const ownerMemberId = '22222222-2222-4222-8222-222222222222';
  static const inviteId = '33333333-3333-4333-8333-333333333333';
  static const recipientMemberId = '44444444-4444-4444-8444-444444444444';
  static const safeScreenshotName = 'family-invitation-flow-success';

  static const _ownerAccountId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  static const _recipientAccountId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  static const _ownerEmail = 'amina@example.com';
  static const _recipientEmail = 'mariam@example.com';
  static final _now = DateTime.utc(2026, 9, 5, 8);

  final Directory _root;
  final _StatefulFamilyCloud _cloud;
  final _Installation _owner;
  _Installation _recipient;

  ProviderSubscription<FamilyInviteState>? _ownerInviteSubscription;
  ProviderSubscription<FamilyJoinState>? _recipientJoinSubscription;
  ProviderSubscription<PendingInviteCompletionState>? _recoverySubscription;
  ProviderSubscription<FamilyRosterState>? _ownerRosterSubscription;
  var _disposed = false;

  static Future<FamilyInvitationFlowHarness> create() async {
    final root = await Directory(
      p.join(
        Directory.systemTemp.path,
        'keepers-family-invitation-${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create(recursive: true);
    final cloud = _StatefulFamilyCloud(
      now: _now,
      accounts: const {
        _ownerEmail: _ownerAccountId,
        _recipientEmail: _recipientAccountId,
      },
    );
    final owner = await _Installation.create(
      directory: Directory(p.join(root.path, 'owner')),
      store: _IsolatedSecureValueStore(),
      session: _FakeGatewaySession(cloud),
      shareService: _RecordingInviteShareService(),
      ids: _QueuedIdFactory(const [familyId, ownerMemberId, inviteId]),
      now: _now,
      randomSeed: 17,
    );
    final recipient = await _Installation.create(
      directory: Directory(p.join(root.path, 'recipient')),
      store: _IsolatedSecureValueStore(),
      session: _FakeGatewaySession(cloud),
      shareService: _RecordingInviteShareService(),
      ids: _QueuedIdFactory(const [recipientMemberId]),
      now: _now,
      randomSeed: 113,
    );
    return FamilyInvitationFlowHarness._(
      root: root,
      cloud: cloud,
      owner: owner,
      recipient: recipient,
    );
  }

  bool get installationsAreIsolated =>
      !identical(_owner.database, _recipient.database) &&
      !identical(_owner.store, _recipient.store) &&
      !identical(_owner.container, _recipient.container) &&
      !identical(_owner.session, _recipient.session);

  int get recordedShareCount => _owner.shareService.invocationCount;

  CloudInvitationState get invitationState => _cloud.invitationState(inviteId);

  Future<void> revokeOwnerInvitation() =>
      _owner.session.revokeInvitation(inviteId);

  Future<FamilyInviteState> bootstrapOwnerAndShareInvitation() async {
    if (!installationsAreIsolated) {
      throw StateError('The invitation installations are not isolated');
    }
    await _owner.container
        .read(setupControllerProvider.notifier)
        .submit(const SetupInput(familyName: 'Rahman', memberName: 'Amina'));
    if (_owner.container.read(setupControllerProvider).phase ==
        SetupPhase.failed) {
      throw StateError('Owner setup failed');
    }

    _ownerInviteSubscription ??= _owner.container.listen(
      familyInviteControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    final controller = _owner.container.read(
      familyInviteControllerProvider.notifier,
    );
    await controller.initialize();
    _requireInvitePhase(FamilyInvitePhase.needsAuthentication);
    await controller.requestEmailOtp(_ownerEmail);
    _requireInvitePhase(FamilyInvitePhase.awaitingOtp);
    await controller.verifyEmailOtp(_cloud.otpFor(_ownerEmail));
    _requireInvitePhase(FamilyInvitePhase.ready);
    await controller.createInvite(_recipientEmail);
    _requireInvitePhase(FamilyInvitePhase.created);
    return _owner.container.read(familyInviteControllerProvider);
  }

  Future<FamilyInviteLink> takeRecipientColdStartLink() async {
    final coordinator = InviteLinkCoordinator(
      _owner.shareService.coldStartUriSource(),
    );
    try {
      final event = await coordinator.takeInitialLink();
      if (event case ValidInviteLinkEvent(:final link)) return link;
      throw StateError('The recorded share did not resolve as a cold link');
    } finally {
      await coordinator.dispose();
    }
  }

  Widget buildRecipientColdStartApp() => UncontrolledProviderScope(
    container: _recipient.container,
    child: KeepersApp(
      inviteUriSource: _owner.shareService.coldStartUriSource(),
    ),
  );

  Future<FamilyJoinState> authenticateRecipientAndPreview(
    FamilyInviteLink coldLink,
  ) async {
    _recipientJoinSubscription ??= _recipient.container.listen(
      familyJoinControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    final controller = _recipient.container.read(
      familyJoinControllerProvider.notifier,
    );
    await controller.load(coldLink);
    _requireJoinPhase(FamilyJoinPhase.needsAuthentication);
    await controller.requestEmailOtp(_recipientEmail);
    _requireJoinPhase(FamilyJoinPhase.awaitingOtp);
    await controller.verifyEmailOtp(_cloud.otpFor(_recipientEmail));
    _requireJoinPhase(FamilyJoinPhase.preview);
    return _recipient.container.read(familyJoinControllerProvider);
  }

  Future<FamilyJoinState> claimInstallAndInterruptComplete() async {
    _cloud.interruptNextCompletion();
    await _recipient.container
        .read(familyJoinControllerProvider.notifier)
        .accept(
          name: 'Mariam',
          avatar: const AvatarConfig.defaults(seed: recipientMemberId),
        );
    return _recipient.container.read(familyJoinControllerProvider);
  }

  Future<bool> recipientIdentityIsInstalled() async {
    final database = await _recipient.container.read(databaseProvider.future);
    final identity = await _recipient.container
        .read(memberRepositoryProvider)
        .findLocalIdentity(database);
    return identity?.familyId == familyId &&
        identity?.memberId == recipientMemberId &&
        identity?.accountId == _recipientAccountId;
  }

  Future<bool> hasPendingCompletion() async {
    final database = await _recipient.container.read(databaseProvider.future);
    final pending = await _recipient.container
        .read(pendingInviteCompletionRepositoryProvider)
        .find(database);
    return pending != null;
  }

  Future<bool> recipientPersistenceContainsCapability(
    FamilyInviteLink link,
  ) async {
    final capabilityParts = [link.token, link.wrappingSecret];
    if (_recipient.store.containsAny(capabilityParts)) return true;
    final database = await _recipient.container.read(databaseProvider.future);
    final tableRows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%'",
    );
    for (final tableRow in tableRows) {
      final tableName = tableRow['name'];
      if (tableName is! String) continue;
      final escaped = tableName.replaceAll('"', '""');
      final rows = await database.rawQuery('SELECT * FROM "$escaped"');
      for (final row in rows) {
        for (final value in row.values.whereType<String>()) {
          if (capabilityParts.any(value.contains)) return true;
        }
      }
    }
    return false;
  }

  Future<PendingInviteCompletionState> restartRecipientAndRecover() async {
    _recipientJoinSubscription?.close();
    _recipientJoinSubscription = null;
    _recoverySubscription?.close();
    _recoverySubscription = null;
    _recipient = await _recipient.restart(
      ids: _QueuedIdFactory(const ['55555555-5555-4555-8555-555555555555']),
      randomSeed: 173,
    );
    _recoverySubscription = _recipient.container.listen(
      pendingInviteCompletionControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    await _recipient.container
        .read(pendingInviteCompletionControllerProvider.notifier)
        .recover();
    return _recipient.container.read(pendingInviteCompletionControllerProvider);
  }

  Future<List<FamilyMember>> refreshOwnerRoster() async {
    final provider = familyRosterProvider(familyId);
    _ownerRosterSubscription ??= _owner.container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    await _owner.container.read(provider.notifier).load();
    final state = _owner.container.read(provider);
    if (state.refreshFailure != null) {
      throw StateError('Owner roster refresh failed');
    }
    return state.members;
  }

  Widget buildSafePostSuccessApp() => UncontrolledProviderScope(
    container: _recipient.container,
    child: const KeepersApp(),
  );

  Future<Widget> buildOwnerLocalOnlyQaApp() => _buildObservatoryQaApp(_owner);

  Future<Widget> buildRecipientPostSuccessQaApp() =>
      _buildObservatoryQaApp(_recipient);

  Future<Widget> _buildObservatoryQaApp(_Installation installation) async {
    final identity = await installation.container.read(
      localIdentityProvider.future,
    );
    if (identity == null) {
      throw StateError('The QA installation has no local identity');
    }
    return UncontrolledProviderScope(
      container: installation.container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KeepersTheme.daylight(),
        builder: _qaBackground,
        home: MediaQuery(
          data: _qaMediaQuery(),
          child: ObservatoryScreen(identity: identity),
        ),
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ownerInviteSubscription?.close();
    _recipientJoinSubscription?.close();
    _recoverySubscription?.close();
    _ownerRosterSubscription?.close();
    await _owner.dispose();
    await _recipient.dispose();
    if (await _root.exists()) await _root.delete(recursive: true);
  }

  void _requireInvitePhase(FamilyInvitePhase expected) {
    final actual = _owner.container.read(familyInviteControllerProvider).phase;
    if (actual != expected) {
      throw StateError('Unexpected owner invitation phase: ${actual.name}');
    }
  }

  void _requireJoinPhase(FamilyJoinPhase expected) {
    final actual = _recipient.container
        .read(familyJoinControllerProvider)
        .phase;
    if (actual != expected) {
      throw StateError('Unexpected recipient join phase: ${actual.name}');
    }
  }
}

/// Checks only rendered and spoken strings and reports a redacted boolean.
/// Capability values never become matcher descriptions or failure messages.
bool capabilityAppearsInPaintOrSemantics(
  WidgetTester tester,
  FamilyInviteLink link,
) => _visibleOrSpokenContains(tester, [link.token, link.wrappingSecret]);

bool _visibleOrSpokenContains(WidgetTester tester, Iterable<String> forbidden) {
  bool containsForbidden(String value) => forbidden.any(value.contains);

  for (final richText in tester.widgetList<RichText>(
    find.byType(RichText, skipOffstage: false),
  )) {
    if (containsForbidden(richText.text.toPlainText())) return true;
  }
  for (final editable in tester.widgetList<EditableText>(
    find.byType(EditableText, skipOffstage: false),
  )) {
    if (containsForbidden(editable.controller.text)) return true;
  }

  final root =
      tester.binding.rootPipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root == null) return false;
  var found = false;
  void inspect(SemanticsNode node) {
    final data = node.getSemanticsData();
    final spoken = [
      data.label,
      data.value,
      data.increasedValue,
      data.decreasedValue,
      data.hint,
      data.tooltip,
    ];
    if (spoken.any(containsForbidden)) {
      found = true;
      return;
    }
    node.visitChildren((child) {
      if (!found) inspect(child);
      return !found;
    });
  }

  inspect(root);
  return found;
}

Future<List<String>> captureFamilyInvitationVisualQa({
  required IntegrationTestWidgetsFlutterBinding binding,
  required WidgetTester tester,
  required FamilyInvitationFlowHarness harness,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = 1.4;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(
        accessibleNavigation: true,
        disableAnimations: true,
        reduceMotion: true,
      );
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final semantics = tester.ensureSemantics();
  try {
    await harness.bootstrapOwnerAndShareInvitation();
    final link = await harness.takeRecipientColdStartLink();
    final created = CreatedInvitation(
      inviteId: FamilyInvitationFlowHarness.inviteId,
      familyId: FamilyInvitationFlowHarness.familyId,
      state: CloudInvitationState.pending,
      createdAt: DateTime.utc(2026, 9, 5, 8),
      expiresAt: DateTime.utc(2026, 9, 6, 8),
    );
    final preview = InvitePreview(
      inviteId: FamilyInvitationFlowHarness.inviteId,
      familyId: FamilyInvitationFlowHarness.familyId,
      familyName: 'Rahman',
      ownerName: 'Amina',
      expiresAt: DateTime.utc(2026, 9, 6, 8),
      state: CloudInvitationState.pending,
    );
    final captured = <String>[];

    Future<void> capture(String name, Finder evidence) async {
      debugPrint('[invitation-qa] preparing $name');
      if (evidence.evaluate().isEmpty) {
        throw TestFailure(
          'The requested safe QA state was not rendered: $name',
        );
      }
      if (capabilityAppearsInPaintOrSemantics(tester, link) ||
          _visibleOrSpokenContains(tester, const ['keepers://join'])) {
        throw TestFailure(
          'Bearer capability material reached a screenshot candidate.',
        );
      }
      final png = await binding.takeScreenshot(name);
      if (png.isEmpty) throw TestFailure('The QA screenshot was empty: $name');
      captured.add(name);
      debugPrint('[invitation-qa] captured $name');
    }

    await tester.pumpWidget(_qaSetupApp());
    await _pumpUntilQa(tester, find.byKey(const Key('create-family-choice')));
    await binding.convertFlutterSurfaceToImage();
    await tester.pump(const Duration(milliseconds: 300));
    await capture(
      'setup-choice-390x844-text-1_4',
      find.byKey(const Key('join-family-choice')),
    );
    await tester.tap(find.byKey(const Key('join-family-choice')));
    await tester.pump(const Duration(milliseconds: 500));
    await capture(
      'setup-manual-join-390x844-text-1_4',
      find.text(
        'Open a family invitation link on this device to join. '
        'For privacy, there is no link field here.',
      ),
    );

    await tester.pumpWidget(await harness.buildOwnerLocalOnlyQaApp());
    await _pumpUntilQa(tester, find.bySemanticsLabel('You, Amina, 0% sealed'));
    await capture(
      'wheel-local-only-390x844-text-1_4',
      find.bySemanticsLabel('Invite family'),
    );

    final inviteStates =
        <({String name, FamilyInviteState state, Finder proof})>[
          (
            name: 'invite-unconfigured-390x844-text-1_4',
            state: const FamilyInviteState(
              phase: FamilyInvitePhase.failed,
              failure: InvitationFailure(InvitationFailureCode.notConfigured),
              retryPoint: FamilyInviteRetryPoint.initialize,
            ),
            proof: find.text(
              'CLOUD INVITATIONS ARE NOT CONFIGURED FOR THIS BUILD.',
            ),
          ),
          (
            name: 'invite-owner-email-390x844-text-1_4',
            state: const FamilyInviteState(
              phase: FamilyInvitePhase.needsAuthentication,
            ),
            proof: find.byKey(const Key('invite-owner-email')),
          ),
          (
            name: 'invite-owner-otp-390x844-text-1_4',
            state: const FamilyInviteState(
              phase: FamilyInvitePhase.awaitingOtp,
              authenticationEmail: 'amina@example.com',
            ),
            proof: find.byKey(const Key('invite-owner-otp')),
          ),
          (
            name: 'invite-owner-ready-recipient-entry-390x844-text-1_4',
            state: const FamilyInviteState(phase: FamilyInvitePhase.ready),
            proof: find.byKey(const Key('invite-recipient-email')),
          ),
          (
            name: 'invite-creating-390x844-text-1_4',
            state: const FamilyInviteState(
              phase: FamilyInvitePhase.creating,
              recipientEmail: 'mariam@example.com',
            ),
            proof: find.bySemanticsLabel('CREATING INVITATION'),
          ),
          (
            name: 'invite-pending-390x844-text-1_4',
            state: FamilyInviteState(
              phase: FamilyInvitePhase.created,
              recipientEmail: 'mariam@example.com',
              createdInvitation: created,
            ),
            proof: find.text('INVITATION READY'),
          ),
          (
            name: 'invite-sharing-390x844-text-1_4',
            state: FamilyInviteState(
              phase: FamilyInvitePhase.created,
              recipientEmail: 'mariam@example.com',
              createdInvitation: created,
              isSharing: true,
            ),
            proof: find.text('Opening share options'),
          ),
          (
            name: 'invite-revoke-failure-390x844-text-1_4',
            state: FamilyInviteState(
              phase: FamilyInvitePhase.failed,
              recipientEmail: 'mariam@example.com',
              createdInvitation: created,
              failure: const InvitationFailure(
                InvitationFailureCode.networkUnavailable,
              ),
              retryPoint: FamilyInviteRetryPoint.revoke,
            ),
            proof: find.text(
              'KEEPERS COULD NOT REACH THE INVITATION SERVICE. TRY AGAIN.',
            ),
          ),
        ];
    for (final snapshot in inviteStates) {
      await _pumpInviteQa(tester, snapshot.state);
      await capture(snapshot.name, snapshot.proof);
    }

    await _pumpJoinQa(
      tester,
      _QaJoinGateway(),
      link,
      identityLoading: true,
      settle: false,
    );
    await capture(
      'join-loading-390x844-text-1_4',
      find.bySemanticsLabel('CHECKING YOUR INVITATION'),
    );

    final authenticationGateway = _QaJoinGateway();
    await _pumpJoinQa(tester, authenticationGateway, link);
    await _pumpUntilQa(tester, find.byKey(const Key('join-email')));
    await capture(
      'join-email-390x844-text-1_4',
      find.byKey(const Key('join-email')),
    );
    await tester.enterText(
      find.byKey(const Key('join-email')),
      'mariam@example.com',
    );
    await tester.tap(find.text('SEND CODE'));
    await _pumpUntilQa(tester, find.byKey(const Key('join-email-otp')));
    await tester.pump(const Duration(milliseconds: 500));
    await capture(
      'join-otp-390x844-text-1_4',
      find.byKey(const Key('join-email-otp')),
    );
    await tester.enterText(find.byKey(const Key('join-email-otp')), '250914');
    await tester.tap(find.text('VERIFY CODE'));
    await _pumpUntilQa(tester, find.text('Created by Amina'));
    await tester.pump(const Duration(milliseconds: 500));
    await capture(
      'join-preview-390x844-text-1_4',
      find.text('Created by Amina'),
    );

    await _pumpJoinSnapshotQa(
      tester,
      link,
      FamilyJoinState(
        phase: FamilyJoinPhase.joining,
        preview: preview,
        draftMemberId: FamilyInvitationFlowHarness.recipientMemberId,
        draftAvatar: const AvatarConfig.defaults(
          seed: FamilyInvitationFlowHarness.recipientMemberId,
        ),
      ),
    );
    await capture(
      'join-joining-390x844-text-1_4',
      find.bySemanticsLabel('WORKING'),
    );

    await _pumpJoinQa(tester, _QaJoinGateway(), link, keyboardInset: 300);
    await _pumpUntilQa(tester, find.byKey(const Key('join-email')));
    await tester.showKeyboard(find.byKey(const Key('join-email')));
    await tester.enterText(
      find.byKey(const Key('join-email')),
      'mariam@example.com',
    );
    await tester.ensureVisible(find.bySemanticsLabel('SEND CODE'));
    await capture(
      'join-keyboard-open-390x844-text-1_4',
      find.bySemanticsLabel('SEND CODE'),
    );

    await _pumpJoinQa(
      tester,
      _QaJoinGateway(
        account: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        previewFailure: const InvitationFailure(
          InvitationFailureCode.networkUnavailable,
        ),
      ),
      link,
    );
    await _pumpUntilQa(
      tester,
      find.text('KEEPERS COULD NOT REACH THE INVITATION SERVICE. TRY AGAIN.'),
    );
    await capture(
      'join-recoverable-failure-390x844-text-1_4',
      find.text('KEEPERS COULD NOT REACH THE INVITATION SERVICE. TRY AGAIN.'),
    );

    await _pumpJoinQa(
      tester,
      _QaJoinGateway(
        account: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        previewFailure: const InvitationFailure(
          InvitationFailureCode.emailMismatch,
        ),
      ),
      link,
    );
    await _pumpUntilQa(
      tester,
      find.text('SIGN IN WITH THE EMAIL ADDRESS THIS INVITATION WAS SENT TO.'),
    );
    await capture(
      'join-protected-failure-390x844-text-1_4',
      find.text('SIGN IN WITH THE EMAIL ADDRESS THIS INVITATION WAS SENT TO.'),
    );

    await _pumpJoinSnapshotQa(
      tester,
      link,
      FamilyJoinState(
        phase: FamilyJoinPhase.preview,
        preview: InvitePreview(
          inviteId: FamilyInvitationFlowHarness.inviteId,
          familyId: FamilyInvitationFlowHarness.familyId,
          familyName: 'Rahman Al Noor Extended Family Archive',
          ownerName: 'Amina Bint Noor Al Rahman',
          expiresAt: DateTime.utc(2026, 9, 6, 8),
          state: CloudInvitationState.pending,
        ),
        draftMemberId: FamilyInvitationFlowHarness.recipientMemberId,
        draftAvatar: const AvatarConfig.defaults(
          seed: FamilyInvitationFlowHarness.recipientMemberId,
        ),
      ),
    );
    await capture(
      'join-long-content-reduced-motion-390x844-text-1_4',
      find.text('RAHMAN AL NOOR EXTENDED FAMILY ARCHIVE FAMILY'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await harness.authenticateRecipientAndPreview(link);
    await harness.claimInstallAndInterruptComplete();
    await harness.restartRecipientAndRecover();
    await harness.refreshOwnerRoster();
    await tester.pumpWidget(await harness.buildRecipientPostSuccessQaApp());
    await _pumpUntilQa(tester, find.bySemanticsLabel('You, Mariam, 0% sealed'));
    await capture(
      'wheel-post-acceptance-reduced-motion-390x844-text-1_4',
      find.bySemanticsLabel('Amina, away'),
    );

    return List<String>.unmodifiable(captured);
  } finally {
    semantics.dispose();
  }
}

Widget _qaSetupApp() => ProviderScope(
  overrides: [
    localIdentityProvider.overrideWithValue(
      const AsyncValue<LocalIdentity?>.data(null),
    ),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: KeepersTheme.daylight(),
    builder: _qaBackground,
    home: MediaQuery(data: _qaMediaQuery(), child: const SetupScreen()),
  ),
);

Future<void> _pumpInviteQa(WidgetTester tester, FamilyInviteState state) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        familyInviteControllerProvider.overrideWith(
          () => _QaInviteController(state),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KeepersTheme.daylight(),
        builder: _qaBackground,
        home: MediaQuery(
          data: _qaMediaQuery(),
          child: const FamilyInviteScreen(initializeOnMount: false),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpJoinQa(
  WidgetTester tester,
  _QaJoinGateway gateway,
  FamilyInviteLink link, {
  bool identityLoading = false,
  bool settle = true,
  double keyboardInset = 0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        cloudFamilyGatewayProvider.overrideWithValue(gateway),
        localIdentityProvider.overrideWithValue(
          identityLoading
              ? const AsyncValue<LocalIdentity?>.loading()
              : const AsyncValue<LocalIdentity?>.data(null),
        ),
        idFactoryProvider.overrideWithValue(
          () => 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        ),
        utcNowProvider.overrideWithValue(() => DateTime.utc(2026, 9, 5, 8)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KeepersTheme.daylight(),
        builder: _qaBackground,
        home: MediaQuery(
          data: _qaMediaQuery(keyboardInset: keyboardInset),
          child: FamilyJoinScreen(link: link),
        ),
      ),
    ),
  );
  if (settle) {
    for (var pump = 0; pump < 5; pump += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _pumpJoinSnapshotQa(
  WidgetTester tester,
  FamilyInviteLink link,
  FamilyJoinState state,
) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        familyJoinControllerProvider.overrideWithBuild(
          (ref, notifier) => state,
        ),
        localIdentityProvider.overrideWithValue(
          const AsyncValue<LocalIdentity?>.loading(),
        ),
        idFactoryProvider.overrideWithValue(
          () => 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KeepersTheme.daylight(),
        builder: _qaBackground,
        home: MediaQuery(
          data: _qaMediaQuery(),
          child: FamilyJoinScreen(link: link),
        ),
      ),
    ),
  );
}

Widget _qaBackground(BuildContext context, Widget? child) =>
    KeepersAppBackground(
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 390,
          height: 844,
          child: MediaQuery(
            data: _qaMediaQuery(),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

MediaQueryData _qaMediaQuery({double keyboardInset = 0}) => MediaQueryData(
  size: const Size(390, 844),
  textScaler: const TextScaler.linear(1.4),
  viewInsets: EdgeInsets.only(bottom: keyboardInset),
  disableAnimations: true,
  accessibleNavigation: true,
);

Future<void> _pumpUntilQa(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 100,
}) async {
  for (var pump = 0; pump < maxPumps; pump += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('A safe QA state did not finish rendering.');
}

final class _QaInviteController extends FamilyInviteController {
  _QaInviteController(this._initialState);

  final FamilyInviteState _initialState;

  @override
  FamilyInviteState build() => _initialState;

  @override
  Future<void> initialize() async {}
}

final class _QaJoinGateway implements CloudFamilyGateway {
  _QaJoinGateway({this.account, this.previewFailure});

  String? account;
  final InvitationFailure? previewFailure;
  String? _email;

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => account;

  @override
  String? get authenticatedEmail => _email;

  @override
  Future<void> requestEmailOtp(String email) async => _email = email;

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    _email = email;
    account = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  }

  @override
  Future<InvitePreview> previewInvitation(FamilyInviteLink link) async {
    if (previewFailure case final failure?) throw failure;
    return InvitePreview(
      inviteId: link.inviteId,
      familyId: FamilyInvitationFlowHarness.familyId,
      familyName: 'Rahman',
      ownerName: 'Amina',
      expiresAt: DateTime.utc(2026, 9, 6, 8),
      state: CloudInvitationState.pending,
    );
  }

  @override
  Future<void> bootstrapOwner(LocalOwnerFamily owner) async =>
      throw UnsupportedError('Owner bootstrap is outside this visual state');

  @override
  Future<CreatedInvitation> createInvitation(
    CloudInvitationDraft draft,
  ) async => throw UnsupportedError(
    'Invitation creation is outside this visual state',
  );

  @override
  Future<ClaimedFamily> claimInvitation(JoinRequest request) async =>
      throw UnsupportedError('Claim is outside this visual state');

  @override
  Future<void> completeInvitation(String inviteId) async =>
      throw UnsupportedError('Completion is outside this visual state');

  @override
  Future<void> revokeInvitation(String inviteId) async =>
      throw UnsupportedError('Revocation is outside this visual state');

  @override
  Future<List<FamilyMember>> listActiveMembers(String familyId) async =>
      throw UnsupportedError('Roster is outside this visual state');
}

final class _Installation {
  _Installation._({
    required this.directory,
    required this.store,
    required this.session,
    required this.shareService,
    required this.database,
    required this.container,
    required this.now,
  });

  final Directory directory;
  final _IsolatedSecureValueStore store;
  final _FakeGatewaySession session;
  final _RecordingInviteShareService shareService;
  final AppDatabase database;
  final ProviderContainer container;
  final DateTime now;
  var _disposed = false;

  static Future<_Installation> create({
    required Directory directory,
    required _IsolatedSecureValueStore store,
    required _FakeGatewaySession session,
    required _RecordingInviteShareService shareService,
    required _QueuedIdFactory ids,
    required DateTime now,
    required int randomSeed,
  }) async {
    await directory.create(recursive: true);
    final random = _DeterministicBytes(randomSeed);
    final databaseKeyStore = DatabaseKeyStore(
      store,
      randomBytesFactory: random.next,
    );
    final identityKeys = IdentityKeyService(
      store,
      randomBytesFactory: random.next,
    );
    final database = AppDatabase(
      databaseKeyStore,
      applicationSupportDirectory: () async => directory,
    );
    final container = ProviderContainer(
      overrides: [
        secureValueStoreProvider.overrideWithValue(store),
        databaseKeyStoreProvider.overrideWithValue(databaseKeyStore),
        appDatabaseProvider.overrideWithValue(database),
        identityKeyServiceProvider.overrideWithValue(identityKeys),
        familyKeyEnvelopeCodecProvider.overrideWithValue(
          CryptographicFamilyKeyEnvelopeCodec(randomBytes: random.next),
        ),
        cloudFamilyGatewayProvider.overrideWithValue(session),
        inviteShareServiceProvider.overrideWithValue(shareService),
        idFactoryProvider.overrideWithValue(ids.next),
        utcNowProvider.overrideWithValue(() => now),
      ],
    );
    await container.read(databaseProvider.future);
    return _Installation._(
      directory: directory,
      store: store,
      session: session,
      shareService: shareService,
      database: database,
      container: container,
      now: now,
    );
  }

  Future<_Installation> restart({
    required _QueuedIdFactory ids,
    required int randomSeed,
  }) async {
    await dispose();
    return create(
      directory: directory,
      store: store,
      session: session,
      shareService: _RecordingInviteShareService(),
      ids: ids,
      now: now,
      randomSeed: randomSeed,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
    await database.close();
  }
}

final class _IsolatedSecureValueStore implements SecureValueStore {
  final _values = <String, String>{};

  bool containsAny(Iterable<String> capabilityParts) => _values.entries.any(
    (entry) => capabilityParts.any(
      (part) => entry.key.contains(part) || entry.value.contains(part),
    ),
  );

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  String toString() => '_IsolatedSecureValueStore(<redacted>)';
}

final class _RecordingInviteShareService implements InviteShareService {
  final _invocations = <Uri>[];

  int get invocationCount => _invocations.length;

  @override
  Future<void> shareInvitation(
    Uri invitationUri, {
    Rect? sharePositionOrigin,
  }) async {
    _invocations.add(invitationUri);
  }

  @override
  Future<void> shareGatheringNudge({Rect? sharePositionOrigin}) async {}

  InviteUriSource coldStartUriSource() {
    if (_invocations.length != 1) {
      throw StateError('Expected exactly one recorded invitation share');
    }
    return _ColdStartInviteUriSource(_invocations.single);
  }

  @override
  String toString() => '_RecordingInviteShareService(<redacted>)';
}

final class _ColdStartInviteUriSource implements InviteUriSource {
  const _ColdStartInviteUriSource(this._uri);

  final Uri _uri;

  @override
  Stream<Uri> get uriLinkStream => Stream<Uri>.value(_uri);

  @override
  Future<Uri?> getInitialUri() async => _uri;

  @override
  String toString() => '_ColdStartInviteUriSource(<redacted>)';
}

final class _QueuedIdFactory {
  _QueuedIdFactory(List<String> ids) : _ids = List<String>.of(ids);

  final List<String> _ids;

  String next() {
    if (_ids.isEmpty) throw StateError('The deterministic ID queue is empty');
    return _ids.removeAt(0);
  }
}

final class _DeterministicBytes {
  _DeterministicBytes(this._cursor);

  int _cursor;

  List<int> next(int length) {
    final result = List<int>.generate(
      length,
      (index) => (_cursor + index) & 0xff,
      growable: false,
    );
    _cursor = (_cursor + length + 29) & 0xff;
    return result;
  }
}

final class _FakeGatewaySession implements CloudFamilyGateway {
  _FakeGatewaySession(this._cloud);

  final _StatefulFamilyCloud _cloud;
  String? _pendingEmail;
  String? _accountId;
  String? _email;

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => _accountId;

  @override
  String? get authenticatedEmail => _email;

  @override
  Future<void> requestEmailOtp(String email) async {
    final normalized = email.trim().toLowerCase();
    if (!_cloud.hasAccount(normalized)) {
      throw const InvitationFailure(InvitationFailureCode.forbidden);
    }
    _pendingEmail = normalized;
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (_pendingEmail != normalized || token != _cloud.otpFor(normalized)) {
      throw const InvitationFailure(InvitationFailureCode.invalidOtp);
    }
    _accountId = _cloud.accountIdFor(normalized);
    _email = normalized;
    _pendingEmail = null;
  }

  @override
  Future<void> bootstrapOwner(LocalOwnerFamily owner) =>
      _cloud.bootstrapOwner(this, owner);

  @override
  Future<CreatedInvitation> createInvitation(CloudInvitationDraft draft) =>
      _cloud.createInvitation(this, draft);

  @override
  Future<InvitePreview> previewInvitation(FamilyInviteLink link) =>
      _cloud.previewInvitation(this, link);

  @override
  Future<ClaimedFamily> claimInvitation(JoinRequest request) =>
      _cloud.claimInvitation(this, request);

  @override
  Future<void> completeInvitation(String inviteId) =>
      _cloud.completeInvitation(this, inviteId);

  @override
  Future<void> revokeInvitation(String inviteId) =>
      _cloud.revokeInvitation(this, inviteId);

  @override
  Future<List<FamilyMember>> listActiveMembers(String familyId) =>
      _cloud.listActiveMembers(this, familyId);

  @override
  String toString() => '_FakeGatewaySession(<redacted>)';
}

final class _StatefulFamilyCloud {
  _StatefulFamilyCloud({
    required this.now,
    required Map<String, String> accounts,
  }) : _accounts = Map<String, String>.unmodifiable(accounts);

  final DateTime now;
  final Map<String, String> _accounts;
  final _families = <String, _CloudFamily>{};
  final _familyByAccount = <String, String>{};
  final _invitations = <String, _CloudInvitation>{};
  var _failNextCompletion = false;

  CloudInvitationState invitationState(String inviteId) {
    final invitation = _invitations[inviteId];
    if (invitation == null) {
      throw StateError('Invitation does not exist');
    }
    return invitation.state;
  }

  bool hasAccount(String email) => _accounts.containsKey(email);

  String accountIdFor(String email) => _accounts[email]!;

  String otpFor(String email) =>
      email == FamilyInvitationFlowHarness._ownerEmail ? '140925' : '250914';

  void interruptNextCompletion() => _failNextCompletion = true;

  Future<void> bootstrapOwner(
    _FakeGatewaySession session,
    LocalOwnerFamily owner,
  ) async {
    final accountId = _requireAccount(session);
    final existingFamily = _families[owner.familyId];
    if (existingFamily != null) {
      if (existingFamily.ownerAccountId != accountId ||
          existingFamily.owner.id != owner.memberId) {
        throw const InvitationFailure(InvitationFailureCode.forbidden);
      }
      return;
    }
    if (_familyByAccount.containsKey(accountId)) {
      throw const InvitationFailure(InvitationFailureCode.differentFamily);
    }
    final ownerMember = FamilyMember(
      id: owner.memberId,
      familyId: owner.familyId,
      name: owner.displayName,
      role: owner.demographicRole.name,
      colorToken: owner.colorToken,
      avatar: owner.avatar,
      joinedAt: now,
    );
    _families[owner.familyId] = _CloudFamily(
      id: owner.familyId,
      name: owner.familyName,
      ownerAccountId: accountId,
      owner: ownerMember,
    );
    _familyByAccount[accountId] = owner.familyId;
  }

  Future<CreatedInvitation> createInvitation(
    _FakeGatewaySession session,
    CloudInvitationDraft draft,
  ) async {
    final accountId = _requireAccount(session);
    final family = _families[draft.familyId];
    if (family == null || family.ownerAccountId != accountId) {
      throw const InvitationFailure(InvitationFailureCode.notOwner);
    }
    if (_invitations.containsKey(draft.inviteId) ||
        draft.envelope.inviteId != draft.inviteId ||
        draft.envelope.familyId != draft.familyId) {
      throw const InvitationFailure(InvitationFailureCode.unknown);
    }
    final invitation = _CloudInvitation(
      draft: draft,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
    );
    _invitations[draft.inviteId] = invitation;
    return invitation.created;
  }

  Future<InvitePreview> previewInvitation(
    _FakeGatewaySession session,
    FamilyInviteLink link,
  ) async {
    final invitation = await _authorizedInvitation(session, link);
    final family = _families[invitation.draft.familyId]!;
    return InvitePreview(
      inviteId: invitation.draft.inviteId,
      familyId: family.id,
      familyName: family.name,
      ownerName: family.owner.name,
      expiresAt: invitation.expiresAt,
      state: invitation.state,
    );
  }

  Future<ClaimedFamily> claimInvitation(
    _FakeGatewaySession session,
    JoinRequest request,
  ) async {
    final accountId = _requireAccount(session);
    final invitation = await _authorizedInvitation(session, request.link);
    final family = _families[invitation.draft.familyId]!;
    if (invitation.state == CloudInvitationState.revoked) {
      throw const InvitationFailure(InvitationFailureCode.revoked);
    }
    if (invitation.claimedAccountId != null &&
        invitation.claimedAccountId != accountId) {
      throw const InvitationFailure(InvitationFailureCode.alreadyClaimed);
    }
    final otherFamily = _familyByAccount[accountId];
    if (otherFamily != null && otherFamily != family.id) {
      throw const InvitationFailure(InvitationFailureCode.differentFamily);
    }
    if (invitation.claimedMember == null) {
      invitation.claimedMember = FamilyMember(
        id: request.memberId,
        familyId: family.id,
        name: request.displayName,
        role: request.demographicRole.name,
        colorToken: request.colorToken,
        avatar: request.avatar,
        joinedAt: now.add(const Duration(minutes: 1)),
      );
      invitation.claimedAccountId = accountId;
      invitation.state = CloudInvitationState.claimed;
    }
    return ClaimedFamily(
      familyId: family.id,
      familyName: family.name,
      localMemberId: invitation.claimedMember!.id,
      envelope: invitation.draft.envelope,
      members: [family.owner, invitation.claimedMember!],
    );
  }

  Future<void> completeInvitation(
    _FakeGatewaySession session,
    String inviteId,
  ) async {
    final accountId = _requireAccount(session);
    final invitation = _invitations[inviteId];
    if (invitation == null || invitation.claimedAccountId != accountId) {
      throw const InvitationFailure(InvitationFailureCode.forbidden);
    }
    if (_failNextCompletion) {
      _failNextCompletion = false;
      throw const InvitationFailure(InvitationFailureCode.networkUnavailable);
    }
    if (invitation.state != CloudInvitationState.claimed &&
        invitation.state != CloudInvitationState.accepted) {
      throw const InvitationFailure(InvitationFailureCode.forbidden);
    }
    invitation.state = CloudInvitationState.accepted;
    invitation.active = true;
    _familyByAccount[accountId] = invitation.draft.familyId;
  }

  Future<void> revokeInvitation(
    _FakeGatewaySession session,
    String inviteId,
  ) async {
    final accountId = _requireAccount(session);
    final invitation = _invitations[inviteId];
    final family = invitation == null
        ? null
        : _families[invitation.draft.familyId];
    if (invitation == null || family?.ownerAccountId != accountId) {
      throw const InvitationFailure(InvitationFailureCode.notOwner);
    }
    if (invitation.state == CloudInvitationState.claimed) {
      throw const InvitationFailure(InvitationFailureCode.alreadyClaimed);
    }
    if (invitation.state == CloudInvitationState.accepted) {
      throw const InvitationFailure(InvitationFailureCode.unknown);
    }
    if (invitation.state == CloudInvitationState.pending) {
      invitation.state = CloudInvitationState.revoked;
    }
  }

  Future<List<FamilyMember>> listActiveMembers(
    _FakeGatewaySession session,
    String familyId,
  ) async {
    final accountId = _requireAccount(session);
    if (_familyByAccount[accountId] != familyId) {
      throw const InvitationFailure(InvitationFailureCode.forbidden);
    }
    final family = _families[familyId];
    if (family == null) {
      throw const InvitationFailure(InvitationFailureCode.forbidden);
    }
    final members = <FamilyMember>[family.owner];
    for (final invitation in _invitations.values) {
      if (invitation.draft.familyId == familyId &&
          invitation.active &&
          invitation.claimedMember != null) {
        members.add(invitation.claimedMember!);
      }
    }
    members.sort((left, right) => left.joinedAt.compareTo(right.joinedAt));
    return List<FamilyMember>.unmodifiable(members);
  }

  Future<_CloudInvitation> _authorizedInvitation(
    _FakeGatewaySession session,
    FamilyInviteLink link,
  ) async {
    _requireAccount(session);
    final email = session.authenticatedEmail;
    final invitation = _invitations[link.inviteId];
    if (invitation == null ||
        await _tokenHash(link.token) != invitation.draft.tokenHash) {
      throw const InvitationFailure(InvitationFailureCode.malformedLink);
    }
    if (email != invitation.draft.recipientEmail) {
      throw const InvitationFailure(InvitationFailureCode.emailMismatch);
    }
    if (invitation.state == CloudInvitationState.revoked) {
      throw const InvitationFailure(InvitationFailureCode.revoked);
    }
    if (invitation.state == CloudInvitationState.pending &&
        !invitation.expiresAt.isAfter(now)) {
      throw const InvitationFailure(InvitationFailureCode.expired);
    }
    return invitation;
  }

  String _requireAccount(_FakeGatewaySession session) {
    final accountId = session.authenticatedAccountId;
    if (accountId == null) {
      throw const InvitationFailure(InvitationFailureCode.signedOut);
    }
    return accountId;
  }

  Future<String> _tokenHash(String token) async {
    final bytes = base64Url.decode(base64Url.normalize(token));
    final digest = await Sha256().hash(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  @override
  String toString() => '_StatefulFamilyCloud(<redacted>)';
}

final class _CloudFamily {
  _CloudFamily({
    required this.id,
    required this.name,
    required this.ownerAccountId,
    required this.owner,
  });

  final String id;
  final String name;
  final String ownerAccountId;
  final FamilyMember owner;
}

final class _CloudInvitation {
  _CloudInvitation({
    required this.draft,
    required this.createdAt,
    required this.expiresAt,
  });

  final CloudInvitationDraft draft;
  final DateTime createdAt;
  final DateTime expiresAt;
  CloudInvitationState state = CloudInvitationState.pending;
  String? claimedAccountId;
  FamilyMember? claimedMember;
  bool active = false;

  CreatedInvitation get created => CreatedInvitation(
    inviteId: draft.inviteId,
    familyId: draft.familyId,
    state: state,
    createdAt: createdAt,
    expiresAt: expiresAt,
  );
}
