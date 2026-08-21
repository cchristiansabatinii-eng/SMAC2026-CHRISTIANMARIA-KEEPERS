import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_code_controller.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/family_join_crypto_providers.dart';
import 'package:keepers/features/family/application/family_join_requests_controller.dart';
import 'package:keepers/features/family/application/pending_join_completion_controller.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/family_code_codec.dart';
import 'package:keepers/features/family/data/family_join_envelope_codec.dart';
import 'package:keepers/features/family/data/invite_share_service.dart';
import 'package:keepers/features/family/data/joining_key_store.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/family/presentation/family_invite_sheet.dart';
import 'package:keepers/features/family/presentation/family_join_request_sheet.dart';
import 'package:keepers/features/family/presentation/family_join_screen.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/app_database.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/ui/family_wheel_screen.dart';
import 'package:keepers/ui/keepers_app_background.dart';
import 'package:path/path.dart' as p;

/// Three process-like installations backed by one stateful development cloud.
///
/// All IDs, code symbols, key seeds, and clock values in this fixture are
/// deterministic and development-only. They must never be used by production.
final class FamilyInvitationFlowHarness {
  FamilyInvitationFlowHarness._({
    required this._root,
    required this._cloud,
    required this._owner,
    required this._approver,
    required this._requester,
  });

  static const developmentOnlyDeterministicFixtures = true;
  static const familyId = '11111111-1111-4111-8111-111111111111';
  static const ownerMemberId = '22222222-2222-4222-8222-222222222222';
  static const approverMemberId = '33333333-3333-4333-8333-333333333333';
  static const requesterMemberId = '44444444-4444-4444-8444-444444444444';
  static const ownerAccountId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  static const approverAccountId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  static const requesterAccountId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  static const safeScreenshotName = 'family-code-flow-success';
  static final fixtureNow = DateTime.utc(2026, 9, 7, 8);

  final Directory _root;
  final _StatefulFamilyCodeCloud _cloud;
  final _Installation _owner;
  final _Installation _approver;
  _Installation _requester;

  ProviderSubscription<FamilyCodeState>? _ownerCodeSubscription;
  ProviderSubscription<FamilyJoinState>? _requesterJoinSubscription;
  ProviderSubscription<FamilyJoinRequestsState>? _approverRequestsSubscription;
  ProviderSubscription<PendingJoinCompletionState>? _completionSubscription;
  FamilyCode? _sharedCode;
  var _disposed = false;

  static Future<FamilyInvitationFlowHarness> create() async {
    final root = await Directory(
      p.join(
        Directory.systemTemp.path,
        'keepers-family-code-${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create(recursive: true);
    final cloud = _StatefulFamilyCodeCloud(now: fixtureNow);
    final owner = await _Installation.create(
      directory: Directory(p.join(root.path, 'owner')),
      store: _IsolatedSecureValueStore(),
      session: _FamilyCodeSession(cloud, ownerAccountId),
      ids: _QueuedIdFactory(const [familyId, ownerMemberId]),
      randomSeed: 17,
      now: fixtureNow,
    );
    final approver = await _Installation.create(
      directory: Directory(p.join(root.path, 'approver')),
      store: _IsolatedSecureValueStore(),
      session: _FamilyCodeSession(cloud, approverAccountId),
      ids: _QueuedIdFactory(const [approverMemberId]),
      randomSeed: 73,
      now: fixtureNow,
    );
    final requester = await _Installation.create(
      directory: Directory(p.join(root.path, 'requester')),
      store: _IsolatedSecureValueStore(),
      session: _FamilyCodeSession(cloud, requesterAccountId),
      ids: _QueuedIdFactory(const [requesterMemberId]),
      randomSeed: 131,
      now: fixtureNow,
    );
    return FamilyInvitationFlowHarness._(
      root: root,
      cloud: cloud,
      owner: owner,
      approver: approver,
      requester: requester,
    );
  }

  bool get installationsAreIsolated {
    final databases = {
      _owner.database,
      _approver.database,
      _requester.database,
    };
    final stores = {_owner.store, _approver.store, _requester.store};
    final sessions = {_owner.session, _approver.session, _requester.session};
    final containers = {
      _owner.container,
      _approver.container,
      _requester.container,
    };
    return databases.length == 3 &&
        stores.length == 3 &&
        sessions.length == 3 &&
        containers.length == 3;
  }

  int get recordedShareCount => _owner.shareService.invocationCount;

  FamilyCode get sharedCode =>
      _sharedCode ?? (throw StateError('The family code has not been loaded'));

  FamilyJoinRequestState? get cloudRequestState =>
      _cloud.ownRequestState(requesterAccountId);

  Future<FamilyCodeState> bootstrapOwnerAndShareCode() async {
    if (!installationsAreIsolated) {
      throw StateError('The family-code installations are not isolated');
    }
    await _owner.container
        .read(setupControllerProvider.notifier)
        .submit(
          const SetupInput(familyName: 'Rahman family', memberName: 'Amina'),
        );
    if (_owner.container.read(setupControllerProvider).phase ==
        SetupPhase.failed) {
      throw StateError('Owner setup failed');
    }

    final codeProvider = familyCodeControllerProvider(familyId);
    _ownerCodeSubscription ??= _owner.container.listen(
      codeProvider,
      (_, _) {},
      fireImmediately: true,
    );
    final controller = _owner.container.read(codeProvider.notifier);
    await controller.load();
    final state = _owner.container.read(codeProvider);
    if (state.phase != FamilyCodePhase.ready || state.displayCode == null) {
      throw StateError('Owner family code did not become ready: $state');
    }
    _sharedCode = FamilyCode.parse(state.displayCode!);
    await controller.shareFamilyLink();

    final ownerIdentity = await _owner.container.read(
      localIdentityProvider.future,
    );
    if (ownerIdentity == null) throw StateError('Owner identity is missing');
    final ownerKey = await _owner.identityKeys.resolve(
      ownerIdentity.familyKeyRef,
    );
    final mutableFamilyKey = List<int>.of(ownerKey, growable: false);
    try {
      final approverMember = _member(
        memberId: approverMemberId,
        name: 'Omar',
        colorToken: 'clay',
      );
      _cloud.addExistingMember(
        familyId: familyId,
        accountId: approverAccountId,
        member: approverMember,
      );
      await _approver.installExistingFamily(
        familyName: 'Rahman family',
        familyKey: mutableFamilyKey,
        localMember: approverMember,
        roster: _cloud.activeMembers(familyId),
      );
    } finally {
      _zero(mutableFamilyKey);
    }
    return state;
  }

  FamilyJoinLink takeSharedJoinLink() =>
      FamilyJoinLink.parse(_owner.shareService.singleUri);

  Widget buildRequesterManualEntryApp() =>
      _requesterApp(const FamilyJoinScreen.manual());

  Widget buildRequesterLinkEntryApp() =>
      _requesterApp(FamilyJoinScreen.forCode(takeSharedJoinLink().code));

  Widget _requesterApp(Widget screen) => UncontrolledProviderScope(
    container: _requester.container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: KeepersTheme.daylight(),
      builder: (context, child) =>
          KeepersAppBackground(child: child ?? const SizedBox.shrink()),
      home: screen,
    ),
  );

  Future<FamilyJoinState> loadRequesterCode({FamilyCode? code}) async {
    _requesterJoinSubscription ??= _requester.container.listen(
      familyJoinControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    await _requester.container
        .read(familyJoinControllerProvider.notifier)
        .loadCode(code ?? sharedCode);
    return _requester.container.read(familyJoinControllerProvider);
  }

  Future<FamilyJoinState> requestAccess({String name = 'Mariam'}) async {
    final state = _requester.container.read(familyJoinControllerProvider);
    final memberId = state.proposedMemberId;
    final avatar = state.proposedAvatar;
    final publicKey = state.proposedJoiningPublicKey;
    if (memberId == null || avatar == null || publicKey == null) {
      throw StateError('Requester proposal was not prepared');
    }
    await _requester.container
        .read(familyJoinControllerProvider.notifier)
        .requestJoin(
          FamilyJoinProfileDraft.validated(
            memberId: memberId,
            displayName: name,
            demographicRole: FamilyDemographicRole.adult,
            colorToken: 'sage',
            avatar: avatar,
            joiningPublicKey: publicKey,
          ),
        );
    return _requester.container.read(familyJoinControllerProvider);
  }

  Future<FamilyJoinRequestsState> loadApproverRequests() async {
    final provider = familyJoinRequestsControllerProvider(familyId);
    _approverRequestsSubscription ??= _approver.container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    await _approver.container.read(provider.notifier).refresh();
    return _approver.container.read(provider);
  }

  Future<FamilyJoinRequestsState> approveFirstRequest() async {
    final provider = familyJoinRequestsControllerProvider(familyId);
    final state = _approver.container.read(provider);
    if (state.requests.length != 1) {
      throw StateError(
        'Expected one pending request, found ${state.requests.length}',
      );
    }
    await _approver.container
        .read(provider.notifier)
        .approve(state.requests.single.requestId);
    return _approver.container.read(provider);
  }

  Future<FamilyJoinRequestsState> declineFirstRequest() async {
    final provider = familyJoinRequestsControllerProvider(familyId);
    final state = _approver.container.read(provider);
    if (state.requests.length != 1) {
      throw StateError(
        'Expected one pending request, found ${state.requests.length}',
      );
    }
    await _approver.container
        .read(provider.notifier)
        .decline(state.requests.single.requestId);
    return _approver.container.read(provider);
  }

  void setRequesterOnline(bool value) => _requester.session.online = value;

  void loseNextCompletionResponse() => _cloud.loseNextCompletionResponse();

  Future<FamilyJoinState> refreshRequester() async {
    await _requester.container
        .read(familyJoinControllerProvider.notifier)
        .refreshStatus();
    return _requester.container.read(familyJoinControllerProvider);
  }

  Future<FamilyJoinState> restartRequesterAndRestorePending() async {
    await _restartRequester();
    return loadRequesterCode();
  }

  Future<PendingJoinCompletionState>
  restartRequesterAndRecoverCompletion() async {
    await _restartRequester();
    _completionSubscription = _requester.container.listen(
      pendingJoinCompletionControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    await _requester.container
        .read(pendingJoinCompletionControllerProvider.notifier)
        .recover();
    return _requester.container.read(pendingJoinCompletionControllerProvider);
  }

  Future<void> _restartRequester() async {
    _requesterJoinSubscription?.close();
    _requesterJoinSubscription = null;
    _completionSubscription?.close();
    _completionSubscription = null;
    _requester = await _requester.restart(
      ids: _QueuedIdFactory(const ['77777777-7777-4777-8777-777777777777']),
      randomSeed: 197,
    );
  }

  Future<bool> requesterIdentityIsInstalled() async {
    final database = await _requester.container.read(databaseProvider.future);
    final identity = await _requester.container
        .read(memberRepositoryProvider)
        .findLocalIdentity(database);
    return identity?.familyId == familyId &&
        identity?.memberId == requesterMemberId &&
        identity?.accountId == requesterAccountId;
  }

  Future<bool> hasPendingCompletion() async {
    final database = await _requester.container.read(databaseProvider.future);
    return await _requester.container
            .read(pendingJoinCompletionRepositoryProvider)
            .find(database) !=
        null;
  }

  Future<List<FamilyMember>> requesterLocalRoster() async {
    final database = await _requester.container.read(databaseProvider.future);
    return _requester.container
        .read(familyRosterRepositoryProvider)
        .listLocal(database, familyId: familyId);
  }

  Future<Widget> buildInstalledRosterApp() async {
    final roster = await requesterLocalRoster();
    final current = roster.singleWhere(
      (member) => member.id == requesterMemberId,
    );
    final others = roster
        .where((member) => member.id != requesterMemberId)
        .map(
          (member) => FamilyWheelMember(
            id: member.id,
            name: member.name,
            color: Colors.orange,
            avatar: member.avatar,
            contribution: 0,
            presence: FamilyPresence.away,
          ),
        )
        .toList(growable: false);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: KeepersTheme.daylight(),
      builder: (context, child) =>
          KeepersAppBackground(child: child ?? const SizedBox.shrink()),
      home: FamilyWheelScreen(
        familyName: 'Rahman family',
        currentMemberName: current.name,
        currentMemberAvatar: current.avatar,
        yourContribution: 0,
        members: others,
        familyCode: sharedCode.display,
        onFamilyCodeTap: () {},
        onCapture: () {},
        onMemberSelected: (_) {},
      ),
    );
  }

  List<FamilyMember> get cloudRoster => _cloud.activeMembers(familyId);

  int activeMembershipCount(String memberId) => _cloud
      .activeMembers(familyId)
      .where((member) => member.id == memberId)
      .length;

  Future<FamilyCodeState> regenerateOwnerCode() async {
    final provider = familyCodeControllerProvider(familyId);
    await _owner.container.read(provider.notifier).regenerate();
    final state = _owner.container.read(provider);
    if (state.displayCode != null) {
      _sharedCode = FamilyCode.parse(state.displayCode!);
    }
    return state;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ownerCodeSubscription?.close();
    _requesterJoinSubscription?.close();
    _approverRequestsSubscription?.close();
    _completionSubscription?.close();
    await _owner.dispose();
    await _approver.dispose();
    await _requester.dispose();
    await _cloud.dispose();
    if (await _root.exists()) await _root.delete(recursive: true);
  }
}

FamilyMember _member({
  required String memberId,
  required String name,
  required String colorToken,
}) => FamilyMember(
  id: memberId,
  familyId: FamilyInvitationFlowHarness.familyId,
  name: name,
  role: 'adult',
  colorToken: colorToken,
  avatar: AvatarConfig.defaults(seed: memberId),
  joinedAt: FamilyInvitationFlowHarness.fixtureNow,
);

final class _Installation {
  _Installation._({
    required this.directory,
    required this.store,
    required this.session,
    required this.shareService,
    required this.identityKeys,
    required this.database,
    required this.container,
    required this.now,
  });

  final Directory directory;
  final _IsolatedSecureValueStore store;
  final _FamilyCodeSession session;
  final _RecordingFamilyCodeShareService shareService;
  final IdentityKeyService identityKeys;
  final AppDatabase database;
  final ProviderContainer container;
  final DateTime now;
  var _disposed = false;

  static Future<_Installation> create({
    required Directory directory,
    required _IsolatedSecureValueStore store,
    required _FamilyCodeSession session,
    required _QueuedIdFactory ids,
    required int randomSeed,
    required DateTime now,
  }) async {
    await directory.create(recursive: true);
    final random = _DeterministicBytes(randomSeed);
    final symbols = _DeterministicCodeSymbols('K7M4P2Q8R9X2T6W3');
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
    final shareService = _RecordingFamilyCodeShareService();
    final container = ProviderContainer(
      overrides: [
        secureValueStoreProvider.overrideWithValue(store),
        databaseKeyStoreProvider.overrideWithValue(databaseKeyStore),
        appDatabaseProvider.overrideWithValue(database),
        identityKeyServiceProvider.overrideWithValue(identityKeys),
        familyCodeJoinGatewayProvider.overrideWithValue(session),
        familyCodeCodecProvider.overrideWithValue(
          CryptographicFamilyCodeCodec(
            randomSymbolIndex: symbols.next,
            randomBytes: random.next,
          ),
        ),
        familyJoinEnvelopeCodecProvider.overrideWithValue(
          CryptographicFamilyJoinEnvelopeCodec(randomBytes: random.next),
        ),
        joiningKeyStoreProvider.overrideWithValue(
          SecureJoiningKeyStore(store, seedFactory: random.next),
        ),
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
      identityKeys: identityKeys,
      database: database,
      container: container,
      now: now,
    );
  }

  Future<void> installExistingFamily({
    required String familyName,
    required List<int> familyKey,
    required FamilyMember localMember,
    required List<FamilyMember> roster,
  }) async {
    final familyKeyHandle = await identityKeys.importFamilyKey(
      familyId: localMember.familyId,
      familyKey: familyKey,
    );
    final memberKeyHandle = await identityKeys.createMemberKey(
      memberId: localMember.id,
    );
    final db = await container.read(databaseProvider.future);
    await db.transaction((transaction) async {
      await container
          .read(familyRepositoryProvider)
          .insert(
            transaction,
            id: localMember.familyId,
            name: familyName,
            familyKeyRef: familyKeyHandle.reference,
            createdAt: now,
          );
      await container
          .read(memberRepositoryProvider)
          .insert(
            transaction,
            id: localMember.id,
            familyId: localMember.familyId,
            name: localMember.name,
            memberKeyRef: memberKeyHandle.reference,
            colorToken: localMember.colorToken,
            avatar: localMember.avatar,
            createdAt: now,
          );
      await container
          .read(familyRosterRepositoryProvider)
          .upsertCloudRoster(
            transaction,
            familyId: localMember.familyId,
            members: roster,
          );
      await container
          .read(memberRepositoryProvider)
          .bindLocalIdentity(
            transaction,
            familyId: localMember.familyId,
            memberId: localMember.id,
            accountId: session.authenticatedAccountId,
          );
    });
    container.invalidate(localIdentityProvider);
    final identity = await container.read(localIdentityProvider.future);
    if (identity?.accountId != session.authenticatedAccountId) {
      throw StateError('Existing member identity was not bound');
    }
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
      ids: ids,
      randomSeed: randomSeed,
      now: now,
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
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  String toString() => '_IsolatedSecureValueStore(<redacted>)';
}

final class _RecordingFamilyCodeShareService extends InviteShareService {
  final List<Uri> _uris = [];

  int get invocationCount => _uris.length;

  Uri get singleUri {
    if (_uris.length != 1) {
      throw StateError('Expected exactly one shared family link');
    }
    return _uris.single;
  }

  @override
  Future<void> shareFamilyLink(
    FamilyCode code, {
    Rect? sharePositionOrigin,
  }) async {
    _uris.add(code.joinUri);
  }
}

final class _QueuedIdFactory {
  _QueuedIdFactory(List<String> ids) : _ids = List<String>.of(ids);

  final List<String> _ids;

  String next() {
    if (_ids.isEmpty) throw StateError('The deterministic ID queue is empty');
    return _ids.removeAt(0);
  }
}

final class _DeterministicCodeSymbols {
  _DeterministicCodeSymbols(this._symbols);

  final String _symbols;
  var _cursor = 0;

  int next() {
    final symbol = _symbols[_cursor % _symbols.length];
    _cursor += 1;
    return FamilyCode.alphabet.indexOf(symbol);
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

void _zero(List<int> bytes) {
  for (var index = 0; index < bytes.length; index += 1) {
    bytes[index] = 0;
  }
}

final class _FamilyCodeSession implements FamilyCodeJoinGateway {
  _FamilyCodeSession(this._cloud, this._accountId);

  final _StatefulFamilyCodeCloud _cloud;
  final String? _accountId;
  bool online = true;

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => _accountId;

  String _authorize() {
    if (!online) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable);
    }
    return _accountId ??
        (throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut));
  }

  @override
  Future<EncryptedFamilyCodeRecord> bootstrapOwnerWithFamilyCode(
    LocalOwnerFamily owner,
    FamilyCodeDraft code,
  ) => _cloud.bootstrapOwner(_authorize(), owner, code);

  @override
  Future<EncryptedFamilyCodeRecord> getFamilyCode(String familyId) =>
      _cloud.getFamilyCode(_authorize(), familyId);

  @override
  Future<FamilyJoinPreview> previewFamilyByCode(FamilyCode code) =>
      _cloud.previewFamily(_authorize(), code);

  @override
  Future<OwnFamilyJoinRequest> createFamilyJoinRequest(
    FamilyJoinRequestDraft draft,
  ) => _cloud.createRequest(_authorize(), draft);

  @override
  Future<List<PendingFamilyJoinRequest>> listPendingJoinRequests(
    String familyId,
  ) => _cloud.listPendingRequests(_authorize(), familyId);

  @override
  Future<OwnFamilyJoinRequest?> getOwnJoinRequest() =>
      _cloud.getOwnRequest(_authorize());

  @override
  Future<FamilyJoinDecision> approveJoinRequest(
    String requestId,
    FamilyJoinApprovalEnvelope envelope,
  ) => _cloud.approve(_authorize(), requestId, envelope);

  @override
  Future<FamilyJoinDecision> declineJoinRequest(String requestId) =>
      _cloud.decline(_authorize(), requestId);

  @override
  Future<FamilyJoinDecision> cancelJoinRequest(String requestId) =>
      _cloud.cancel(_authorize(), requestId);

  @override
  Future<FamilyJoinDecision> completeJoinRequest(String requestId) =>
      _cloud.complete(_authorize(), requestId);

  @override
  Future<EncryptedFamilyCodeRecord> regenerateFamilyCode({
    required String familyId,
    required int expectedVersion,
    required FamilyCodeDraft replacement,
  }) => _cloud.regenerate(
    _authorize(),
    familyId: familyId,
    expectedVersion: expectedVersion,
    replacement: replacement,
  );

  @override
  Stream<void> watchOwnJoinRequest() {
    final accountId = _accountId;
    return accountId == null
        ? const Stream<void>.empty()
        : _cloud.watchOwnRequest(accountId);
  }

  @override
  Stream<void> watchPendingJoinRequests(String familyId) =>
      _cloud.watchPendingRequests(familyId);

  @override
  String toString() => '_FamilyCodeSession(<redacted account>)';
}

final class _StatefulFamilyCodeCloud {
  _StatefulFamilyCodeCloud({required DateTime now}) : _now = now.toUtc();

  final DateTime _now;
  final Map<String, _CloudFamily> _families = {};
  final Map<String, String> _familyByAccount = {};
  final Map<String, _CloudJoinRequest> _requests = {};
  final Map<String, List<String>> _requestsByAccount = {};
  final Map<String, StreamController<void>> _ownSignals = {};
  final Map<String, StreamController<void>> _pendingSignals = {};
  var _requestCounter = 1;
  var _loseNextCompletionResponse = false;

  FamilyJoinRequestState? ownRequestState(String accountId) {
    final request = _latestRequest(accountId);
    if (request == null) return null;
    _expireIfNeeded(request);
    return request.state;
  }

  List<FamilyMember> activeMembers(String familyId) =>
      List<FamilyMember>.unmodifiable(
        _families[familyId]?.members.values ?? const <FamilyMember>[],
      );

  void loseNextCompletionResponse() => _loseNextCompletionResponse = true;

  Future<EncryptedFamilyCodeRecord> bootstrapOwner(
    String accountId,
    LocalOwnerFamily owner,
    FamilyCodeDraft draft,
  ) async {
    if (_families.containsKey(owner.familyId) ||
        _familyByAccount.containsKey(accountId)) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.alreadyMember);
    }
    if (draft.material.familyId != owner.familyId ||
        draft.material.codeVersion != 1) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
    }
    if (_familyForCode(draft.code) != null) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.codeCollision);
    }
    final ownerMember = FamilyMember(
      id: owner.memberId,
      familyId: owner.familyId,
      name: owner.displayName,
      role: owner.demographicRole.name,
      colorToken: owner.colorToken,
      avatar: owner.avatar,
      joinedAt: _now,
    );
    final record = EncryptedFamilyCodeRecord(
      material: draft.material,
      creatorAccountId: accountId,
      createdAt: _now,
      updatedAt: _now,
    );
    _families[owner.familyId] = _CloudFamily(
      id: owner.familyId,
      name: owner.familyName,
      creatorAccountId: accountId,
      code: draft.code,
      record: record,
      members: {ownerMember.id: ownerMember},
    );
    _familyByAccount[accountId] = owner.familyId;
    return record;
  }

  void addExistingMember({
    required String familyId,
    required String accountId,
    required FamilyMember member,
  }) {
    final family = _families[familyId];
    if (family == null || member.familyId != familyId) {
      throw StateError('Cannot add a member to an unknown family');
    }
    family.members[member.id] = member;
    _familyByAccount[accountId] = familyId;
  }

  Future<EncryptedFamilyCodeRecord> getFamilyCode(
    String accountId,
    String familyId,
  ) async {
    _requireMember(accountId, familyId);
    return _families[familyId]!.record;
  }

  Future<FamilyJoinPreview> previewFamily(
    String accountId,
    FamilyCode code,
  ) async {
    if (_familyByAccount.containsKey(accountId)) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.alreadyMember);
    }
    final family = _familyForCode(code);
    if (family == null) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.familyNotFound);
    }
    return FamilyJoinPreview(
      familyId: family.id,
      familyName: family.name,
      codeVersion: family.record.material.codeVersion,
      members: family.members.values.toList(growable: false),
    );
  }

  Future<OwnFamilyJoinRequest> createRequest(
    String accountId,
    FamilyJoinRequestDraft draft,
  ) async {
    if (_familyByAccount.containsKey(accountId)) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.alreadyMember);
    }
    final family = _familyForCode(draft.code);
    if (family == null) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.invitationChanged);
    }
    final existing = _latestRequest(accountId);
    if (existing != null) {
      _expireIfNeeded(existing);
      if (existing.state == FamilyJoinRequestState.pending ||
          existing.state == FamilyJoinRequestState.approved) {
        throw const FamilyJoinFailure(
          FamilyJoinFailureCode.requestAlreadyPending,
        );
      }
      if (existing.state == FamilyJoinRequestState.installed) {
        throw const FamilyJoinFailure(FamilyJoinFailureCode.alreadyMember);
      }
    }
    final requestId = _nextRequestId();
    final request = _CloudJoinRequest(
      requestId: requestId,
      familyId: family.id,
      requesterAccountId: accountId,
      profile: draft.profile,
      codeVersion: family.record.material.codeVersion,
      createdAt: _now,
      expiresAt: _now.add(const Duration(days: 7)),
    );
    _requests[requestId] = request;
    _requestsByAccount.putIfAbsent(accountId, () => []).add(requestId);
    _emitPending(family.id);
    return _ownProjection(request);
  }

  Future<List<PendingFamilyJoinRequest>> listPendingRequests(
    String accountId,
    String familyId,
  ) async {
    _requireMember(accountId, familyId);
    final result = <PendingFamilyJoinRequest>[];
    for (final request in _requests.values.where(
      (candidate) => candidate.familyId == familyId,
    )) {
      _expireIfNeeded(request);
      if (request.state == FamilyJoinRequestState.pending) {
        result.add(_pendingProjection(request));
      }
    }
    return List<PendingFamilyJoinRequest>.unmodifiable(result);
  }

  Future<OwnFamilyJoinRequest?> getOwnRequest(String accountId) async {
    final request = _latestRequest(accountId);
    if (request == null) return null;
    _expireIfNeeded(request);
    return _ownProjection(request);
  }

  Future<FamilyJoinDecision> approve(
    String accountId,
    String requestId,
    FamilyJoinApprovalEnvelope envelope,
  ) async {
    final request = _requireRequest(requestId);
    _requireMember(accountId, request.familyId);
    _expireIfNeeded(request);
    if (request.state != FamilyJoinRequestState.pending) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.requestCancelled);
    }
    final context = envelope.context;
    if (context.requestId != request.requestId ||
        context.familyId != request.familyId ||
        context.requesterAccountId != request.requesterAccountId ||
        context.codeVersion != request.codeVersion) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
    }
    request
      ..state = FamilyJoinRequestState.approved
      ..approvalEnvelope = envelope;
    _emitResolution(request);
    return _decision(request);
  }

  Future<FamilyJoinDecision> decline(String accountId, String requestId) async {
    final request = _requireRequest(requestId);
    _requireMember(accountId, request.familyId);
    _expireIfNeeded(request);
    if (request.state != FamilyJoinRequestState.pending) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.requestCancelled);
    }
    request.state = FamilyJoinRequestState.declined;
    _emitResolution(request);
    return _decision(request);
  }

  Future<FamilyJoinDecision> cancel(String accountId, String requestId) async {
    final request = _requireRequest(requestId);
    if (request.requesterAccountId != accountId) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.forbidden);
    }
    _expireIfNeeded(request);
    if (request.state != FamilyJoinRequestState.pending) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.requestCancelled);
    }
    request
      ..state = FamilyJoinRequestState.cancelled
      ..cancelReason = FamilyJoinRequestCancelReason.requester;
    _emitResolution(request);
    return _decision(request);
  }

  Future<FamilyJoinDecision> complete(
    String accountId,
    String requestId,
  ) async {
    final request = _requireRequest(requestId);
    if (request.requesterAccountId != accountId) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.forbidden);
    }
    if (request.state != FamilyJoinRequestState.approved &&
        request.state != FamilyJoinRequestState.installed) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.requestCancelled);
    }
    if (request.state == FamilyJoinRequestState.approved) {
      final family = _families[request.familyId]!;
      family.members.putIfAbsent(
        request.profile.memberId,
        () => _memberFromRequest(request),
      );
      _familyByAccount[accountId] = request.familyId;
      request.state = FamilyJoinRequestState.installed;
      _emitResolution(request);
    }
    if (_loseNextCompletionResponse) {
      _loseNextCompletionResponse = false;
      throw const FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable);
    }
    return _decision(request);
  }

  Future<EncryptedFamilyCodeRecord> regenerate(
    String accountId, {
    required String familyId,
    required int expectedVersion,
    required FamilyCodeDraft replacement,
  }) async {
    final family = _families[familyId];
    if (family == null) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.familyNotFound);
    }
    if (family.creatorAccountId != accountId) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.notCreator);
    }
    if (family.record.material.codeVersion != expectedVersion) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.codeVersionChanged);
    }
    if (replacement.material.familyId != familyId ||
        replacement.material.codeVersion != expectedVersion + 1) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
    }
    final collision = _familyForCode(replacement.code);
    if (collision != null && collision.id != familyId) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.codeCollision);
    }
    family
      ..code = replacement.code
      ..record = EncryptedFamilyCodeRecord(
        material: replacement.material,
        creatorAccountId: accountId,
        createdAt: family.record.createdAt,
        updatedAt: _now,
      );
    for (final request in _requests.values.where(
      (candidate) =>
          candidate.familyId == familyId &&
          candidate.state == FamilyJoinRequestState.pending,
    )) {
      request
        ..state = FamilyJoinRequestState.cancelled
        ..cancelReason = FamilyJoinRequestCancelReason.codeRegenerated;
      _emitOwn(request.requesterAccountId);
    }
    _emitPending(familyId);
    return family.record;
  }

  Stream<void> watchOwnRequest(String accountId) => _ownSignals
      .putIfAbsent(accountId, () => StreamController<void>.broadcast())
      .stream;

  Stream<void> watchPendingRequests(String familyId) => _pendingSignals
      .putIfAbsent(familyId, () => StreamController<void>.broadcast())
      .stream;

  Future<void> dispose() async {
    for (final controller in _ownSignals.values) {
      await controller.close();
    }
    for (final controller in _pendingSignals.values) {
      await controller.close();
    }
  }

  _CloudFamily? _familyForCode(FamilyCode code) {
    for (final family in _families.values) {
      if (family.code == code) return family;
    }
    return null;
  }

  void _requireMember(String accountId, String familyId) {
    if (_familyByAccount[accountId] != familyId ||
        !_families.containsKey(familyId)) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.forbidden);
    }
  }

  _CloudJoinRequest _requireRequest(String requestId) =>
      _requests[requestId] ??
      (throw const FamilyJoinFailure(FamilyJoinFailureCode.familyNotFound));

  _CloudJoinRequest? _latestRequest(String accountId) {
    final ids = _requestsByAccount[accountId];
    return ids == null || ids.isEmpty ? null : _requests[ids.last];
  }

  void _expireIfNeeded(_CloudJoinRequest request) {
    if (request.state == FamilyJoinRequestState.pending &&
        !_now.isBefore(request.expiresAt)) {
      request.state = FamilyJoinRequestState.expired;
      _emitResolution(request);
    }
  }

  PendingFamilyJoinRequest _pendingProjection(_CloudJoinRequest request) =>
      PendingFamilyJoinRequest(
        requestId: request.requestId,
        familyId: request.familyId,
        requesterAccountId: request.requesterAccountId,
        memberId: request.profile.memberId,
        displayName: request.profile.displayName,
        demographicRole: request.profile.demographicRole,
        colorToken: request.profile.colorToken,
        avatar: request.profile.avatar,
        joiningPublicKey: request.profile.joiningPublicKey,
        codeVersion: request.codeVersion,
        state: request.state,
        createdAt: request.createdAt,
        expiresAt: request.expiresAt,
      );

  OwnFamilyJoinRequest _ownProjection(_CloudJoinRequest request) {
    final family = _families[request.familyId]!;
    final roster = family.members.values.toList(growable: true);
    if ((request.state == FamilyJoinRequestState.approved ||
            request.state == FamilyJoinRequestState.installed) &&
        !roster.any((member) => member.id == request.profile.memberId)) {
      roster.add(_memberFromRequest(request));
    }
    return OwnFamilyJoinRequest(
      requestId: request.requestId,
      familyId: request.familyId,
      familyName: family.name,
      requesterAccountId: request.requesterAccountId,
      memberId: request.profile.memberId,
      displayName: request.profile.displayName,
      demographicRole: request.profile.demographicRole,
      colorToken: request.profile.colorToken,
      avatar: request.profile.avatar,
      joiningPublicKey: request.profile.joiningPublicKey,
      codeVersion: request.codeVersion,
      state: request.state,
      createdAt: request.createdAt,
      expiresAt: request.expiresAt,
      cancelReason: request.cancelReason,
      approvalEnvelope: request.approvalEnvelope,
      roster: roster,
    );
  }

  FamilyMember _memberFromRequest(_CloudJoinRequest request) => FamilyMember(
    id: request.profile.memberId,
    familyId: request.familyId,
    name: request.profile.displayName,
    role: request.profile.demographicRole.name,
    colorToken: request.profile.colorToken,
    avatar: request.profile.avatar,
    joinedAt: _now,
  );

  FamilyJoinDecision _decision(_CloudJoinRequest request) => FamilyJoinDecision(
    requestId: request.requestId,
    familyId: request.familyId,
    state: request.state,
    updatedAt: _now,
  );

  String _nextRequestId() {
    final suffix = (_requestCounter++).toString().padLeft(12, '0');
    return '70000000-0000-4000-8000-$suffix';
  }

  void _emitResolution(_CloudJoinRequest request) {
    _emitOwn(request.requesterAccountId);
    _emitPending(request.familyId);
  }

  void _emitOwn(String accountId) => _ownSignals[accountId]?.add(null);

  void _emitPending(String familyId) => _pendingSignals[familyId]?.add(null);
}

final class _CloudFamily {
  _CloudFamily({
    required this.id,
    required this.name,
    required this.creatorAccountId,
    required this.code,
    required this.record,
    required this.members,
  });

  final String id;
  final String name;
  final String creatorAccountId;
  FamilyCode code;
  EncryptedFamilyCodeRecord record;
  final Map<String, FamilyMember> members;
}

final class _CloudJoinRequest {
  _CloudJoinRequest({
    required this.requestId,
    required this.familyId,
    required this.requesterAccountId,
    required this.profile,
    required this.codeVersion,
    required this.createdAt,
    required this.expiresAt,
  });

  final String requestId;
  final String familyId;
  final String requesterAccountId;
  final FamilyJoinProfileDraft profile;
  final int codeVersion;
  final DateTime createdAt;
  final DateTime expiresAt;
  FamilyJoinRequestState state = FamilyJoinRequestState.pending;
  FamilyJoinRequestCancelReason? cancelReason;
  FamilyJoinApprovalEnvelope? approvalEnvelope;
}

const familyInvitationQaStates = <String>[
  'main-code-loaded',
  'main-code-offline',
  'noncreator-code-sheet',
  'creator-regeneration-confirmation',
  'manual-code-entry',
  'family-preview',
  'pending-cancel',
  'join-request-notice',
  'approval-sheet',
  'decline',
  'expiry',
  'invitation-changed',
  'network-failure-retry',
  'installed-avatar-arrival',
];

const _familyInvitationQaSizes = <({String slug, Size size})>[
  (slug: '390x844', size: Size(390, 844)),
  (slug: '430x932', size: Size(430, 932)),
];

final List<String> familyInvitationQaScreenshotNames = List.unmodifiable([
  for (final viewport in _familyInvitationQaSizes)
    for (final state in familyInvitationQaStates)
      '$state-${viewport.slug}-text-1_4-reduced-motion',
]);

bool privateJoinMaterialAppearsInPaintOrSemantics(WidgetTester tester) =>
    _visibleOrSpokenContains(tester, const [
      _qaJoiningPublicKey,
      'family key',
      'joining private key',
      'shared secret',
      'ciphertext',
      'ephemeral public key',
    ]);

bool _visibleOrSpokenContains(WidgetTester tester, Iterable<String> forbidden) {
  bool containsForbidden(String value) {
    final normalized = value.toLowerCase();
    return forbidden.any((part) => normalized.contains(part.toLowerCase()));
  }

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
    if ([
      data.label,
      data.value,
      data.hint,
      data.tooltip,
      data.increasedValue,
      data.decreasedValue,
    ].any(containsForbidden)) {
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
  if (!Platform.isAndroid) {
    throw StateError('Family-code screenshot capture is Android-only');
  }
  await harness.bootstrapOwnerAndShareCode();
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.4;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(
        accessibleNavigation: true,
        disableAnimations: true,
        reduceMotion: true,
      );
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final semantics = tester.ensureSemantics();
  final captured = <String>[];
  var converted = false;
  try {
    for (final viewport in _familyInvitationQaSizes) {
      tester.view.physicalSize = viewport.size;
      for (final state in familyInvitationQaStates) {
        final proof = await _pumpQaState(
          tester,
          state: state,
          size: viewport.size,
          code: harness.sharedCode,
        );
        if (proof.evaluate().isEmpty) {
          throw TestFailure('The QA state did not render: $state');
        }
        if (privateJoinMaterialAppearsInPaintOrSemantics(tester)) {
          throw TestFailure('Private join material reached a QA frame');
        }
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
          await tester.pump(const Duration(milliseconds: 300));
        }
        final name = '$state-${viewport.slug}-text-1_4-reduced-motion';
        final bytes = await binding.takeScreenshot(name);
        if (bytes.isEmpty) throw TestFailure('Empty QA screenshot: $name');
        captured.add(name);
      }
    }
    return List<String>.unmodifiable(captured);
  } finally {
    semantics.dispose();
  }
}

Future<Finder> _pumpQaState(
  WidgetTester tester, {
  required String state,
  required Size size,
  required FamilyCode code,
}) async {
  switch (state) {
    case 'main-code-loaded':
      await _pumpQaWheel(tester, size: size, code: code.display);
      return find.byKey(const Key('family-code-action'));
    case 'main-code-offline':
      await _pumpQaCodeSheet(
        tester,
        size: size,
        state: FamilyCodeState(
          phase: FamilyCodePhase.ready,
          displayCode: code.display,
          codeVersion: 1,
          isOffline: true,
        ),
      );
      return find.text('Showing the code saved on this device');
    case 'noncreator-code-sheet':
      await _pumpQaCodeSheet(
        tester,
        size: size,
        state: FamilyCodeState(
          phase: FamilyCodePhase.ready,
          displayCode: code.display,
          codeVersion: 1,
        ),
      );
      return find.byKey(const Key('copy-family-code'));
    case 'creator-regeneration-confirmation':
      await _pumpQaCodeSheet(
        tester,
        size: size,
        state: FamilyCodeState(
          phase: FamilyCodePhase.ready,
          displayCode: code.display,
          codeVersion: 1,
          isCreator: true,
        ),
      );
      await tester.tap(find.byKey(const Key('regenerate-family-code')));
      await tester.pumpAndSettle();
      return find.text('Regenerate family code?');
    case 'manual-code-entry':
      await _pumpQaJoin(tester, size: size, state: const FamilyJoinState());
      return find.byKey(const Key('family-code-field'));
    case 'family-preview':
      await _pumpQaJoin(tester, size: size, state: _qaPreviewState);
      return find.text('Rahman family');
    case 'pending-cancel':
      await _pumpQaJoin(tester, size: size, state: _qaPendingState);
      return find.byKey(const Key('cancel-join-request'));
    case 'join-request-notice':
      await _pumpQaWheel(
        tester,
        size: size,
        code: code.display,
        pendingRequestName: 'Mariam',
      );
      return find.byKey(const Key('family-join-request-notice'));
    case 'approval-sheet':
      await _pumpQaRequestSheet(tester, size: size);
      return find.byKey(const Key('approve-join-request'));
    case 'decline':
      await _pumpQaJoin(
        tester,
        size: size,
        state: const FamilyJoinState(phase: FamilyJoinPhase.declined),
      );
      return find.text("Your request wasn't accepted");
    case 'expiry':
      await _pumpQaJoin(
        tester,
        size: size,
        state: const FamilyJoinState(phase: FamilyJoinPhase.expired),
      );
      return find.text('Your request has expired');
    case 'invitation-changed':
      await _pumpQaJoin(
        tester,
        size: size,
        state: const FamilyJoinState(phase: FamilyJoinPhase.invitationChanged),
      );
      return find.text(
        'This family invitation has changed. Ask for the new code.',
      );
    case 'network-failure-retry':
      await _pumpQaJoin(tester, size: size, state: _qaNetworkState);
      return find.widgetWithText(TextButton, 'Retry');
    case 'installed-avatar-arrival':
      await _pumpQaWheel(
        tester,
        size: size,
        code: code.display,
        installed: true,
      );
      return find.bySemanticsLabel('You, Mariam, 0% sealed');
  }
  throw StateError('Unknown family-code QA state: $state');
}

Future<void> _pumpQaCodeSheet(
  WidgetTester tester, {
  required Size size,
  required FamilyCodeState state,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        familyCodeControllerProvider(FamilyInvitationFlowHarness.familyId)
            .overrideWith(() => _QaCodeController(state)),
      ],
      child: _qaApp(
        size,
        const Scaffold(
          body: FamilyInviteSheet(
            familyId: FamilyInvitationFlowHarness.familyId,
            initializeOnMount: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpQaJoin(
  WidgetTester tester, {
  required Size size,
  required FamilyJoinState state,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        familyJoinControllerProvider.overrideWithBuild(
          (ref, notifier) => state,
        ),
      ],
      child: _qaApp(size, const FamilyJoinScreen.manual()),
    ),
  );
  await tester.pump();
}

Future<void> _pumpQaRequestSheet(
  WidgetTester tester, {
  required Size size,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        familyJoinRequestsControllerProvider(
          FamilyInvitationFlowHarness.familyId,
        ).overrideWith(
          () => _QaRequestsController(
            FamilyJoinRequestsState(requests: [_qaApproverRequest]),
          ),
        ),
      ],
      child: _qaApp(
        size,
        Scaffold(
          body: FamilyJoinRequestSheet(
            familyId: FamilyInvitationFlowHarness.familyId,
            request: _qaApproverRequest,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpQaWheel(
  WidgetTester tester, {
  required Size size,
  required String code,
  String? pendingRequestName,
  bool installed = false,
}) async {
  final currentName = installed ? 'Mariam' : 'Amina';
  final currentId = installed
      ? FamilyInvitationFlowHarness.requesterMemberId
      : FamilyInvitationFlowHarness.ownerMemberId;
  final members = <FamilyWheelMember>[
    FamilyWheelMember(
      id: FamilyInvitationFlowHarness.approverMemberId,
      name: 'Omar',
      color: Colors.orange,
      avatar: const AvatarConfig.defaults(
        seed: FamilyInvitationFlowHarness.approverMemberId,
      ),
      contribution: 0,
      presence: FamilyPresence.away,
    ),
    if (installed)
      FamilyWheelMember(
        id: FamilyInvitationFlowHarness.ownerMemberId,
        name: 'Amina',
        color: Colors.purple,
        avatar: const AvatarConfig.defaults(
          seed: FamilyInvitationFlowHarness.ownerMemberId,
        ),
        contribution: 0,
        presence: FamilyPresence.away,
      ),
  ];
  await tester.pumpWidget(
    _qaApp(
      size,
      FamilyWheelScreen(
        familyName: 'Rahman family',
        currentMemberName: currentName,
        currentMemberAvatar: AvatarConfig.defaults(seed: currentId),
        yourContribution: 0,
        members: members,
        familyCode: code,
        onFamilyCodeTap: () {},
        pendingJoinRequestName: pendingRequestName,
        onPendingJoinRequestTap: pendingRequestName == null ? null : () {},
        onCapture: () {},
        onMemberSelected: (_) {},
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Widget _qaApp(Size size, Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: KeepersTheme.daylight(),
  home: MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: const TextScaler.linear(1.4),
      disableAnimations: true,
      accessibleNavigation: true,
    ),
    child: KeepersAppBackground(child: child),
  ),
);

final class _QaCodeController extends FamilyCodeController {
  _QaCodeController(this.initial) : super(FamilyInvitationFlowHarness.familyId);

  final FamilyCodeState initial;

  @override
  FamilyCodeState build() => initial;

  @override
  Future<void> load() async {}

  @override
  Future<void> regenerate() async {}
}

final class _QaRequestsController extends FamilyJoinRequestsController {
  _QaRequestsController(this.initial)
    : super(FamilyInvitationFlowHarness.familyId);

  final FamilyJoinRequestsState initial;

  @override
  FamilyJoinRequestsState build() => initial;

  @override
  Future<void> approve(String requestId) async {}

  @override
  Future<void> decline(String requestId) async {}
}

const _qaJoiningPublicKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

final _qaPreview = FamilyJoinPreview(
  familyId: FamilyInvitationFlowHarness.familyId,
  familyName: 'Rahman family',
  codeVersion: 1,
  members: [
    _member(
      memberId: FamilyInvitationFlowHarness.ownerMemberId,
      name: 'Amina',
      colorToken: 'ochre',
    ),
    _member(
      memberId: FamilyInvitationFlowHarness.approverMemberId,
      name: 'Omar',
      colorToken: 'clay',
    ),
  ],
);

final _qaOwnRequest = OwnFamilyJoinRequest(
  requestId: '70000000-0000-4000-8000-000000000001',
  familyId: FamilyInvitationFlowHarness.familyId,
  familyName: 'Rahman family',
  requesterAccountId: FamilyInvitationFlowHarness.requesterAccountId,
  memberId: FamilyInvitationFlowHarness.requesterMemberId,
  displayName: 'Mariam',
  demographicRole: FamilyDemographicRole.adult,
  colorToken: 'sage',
  avatar: const AvatarConfig.defaults(
    seed: FamilyInvitationFlowHarness.requesterMemberId,
  ),
  joiningPublicKey: _qaJoiningPublicKey,
  codeVersion: 1,
  state: FamilyJoinRequestState.pending,
  createdAt: FamilyInvitationFlowHarness.fixtureNow,
  expiresAt: FamilyInvitationFlowHarness.fixtureNow.add(
    const Duration(days: 7),
  ),
  roster: _qaPreview.members,
);

final _qaApproverRequest = PendingFamilyJoinRequest(
  requestId: _qaOwnRequest.requestId,
  familyId: _qaOwnRequest.familyId,
  requesterAccountId: _qaOwnRequest.requesterAccountId,
  memberId: _qaOwnRequest.memberId,
  displayName: _qaOwnRequest.displayName,
  demographicRole: _qaOwnRequest.demographicRole,
  colorToken: _qaOwnRequest.colorToken,
  avatar: _qaOwnRequest.avatar,
  joiningPublicKey: _qaOwnRequest.joiningPublicKey,
  codeVersion: _qaOwnRequest.codeVersion,
  state: FamilyJoinRequestState.pending,
  createdAt: _qaOwnRequest.createdAt,
  expiresAt: _qaOwnRequest.expiresAt,
);

final _qaPreviewState = FamilyJoinState(
  phase: FamilyJoinPhase.preview,
  preview: _qaPreview,
  proposedMemberId: FamilyInvitationFlowHarness.requesterMemberId,
  proposedAvatar: const AvatarConfig.defaults(
    seed: FamilyInvitationFlowHarness.requesterMemberId,
  ),
  proposedJoiningPublicKey: _qaJoiningPublicKey,
);

final _qaPendingState = FamilyJoinState(
  phase: FamilyJoinPhase.pending,
  preview: _qaPreview,
  request: _qaOwnRequest,
);

final _qaNetworkState = FamilyJoinState(
  phase: FamilyJoinPhase.pending,
  preview: _qaPreview,
  request: _qaOwnRequest,
  failure: const FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable),
  retryPoint: FamilyJoinRetryPoint.refreshStatus,
);
