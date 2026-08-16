import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_invite_controller.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/invite_share_service.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'authenticated owner bootstraps, binds locally, and becomes ready',
    () async {
      final fixture = await _InviteFixture.create();
      addTearDown(fixture.dispose);

      await fixture.controller.initialize();

      expect(fixture.state.phase, FamilyInvitePhase.ready);
      expect(fixture.gateway.bootstrappedOwners, hasLength(1));
      expect(fixture.gateway.bootstrappedOwners.single.familyId, _familyId);
      expect(
        fixture.gateway.bootstrappedOwners.single.memberId,
        _ownerMemberId,
      );
      expect(
        (await fixture.container.read(localIdentityProvider.future))?.accountId,
        _ownerAccountId,
      );
      expect(fixture.secureStore.reads, isEmpty);

      await fixture.controller.initialize();
      expect(fixture.gateway.bootstrappedOwners, hasLength(1));
    },
  );

  test(
    'bound owner reopens Invite without replaying immutable bootstrap',
    () async {
      final fixture = await _InviteFixture.create(
        boundAccountId: _ownerAccountId,
      );
      addTearDown(fixture.dispose);

      await fixture.controller.initialize();

      expect(fixture.state.phase, FamilyInvitePhase.ready);
      expect(fixture.gateway.bootstrappedOwners, isEmpty);
    },
  );

  test(
    'bound joined member gets owner-only state before remote mutation',
    () async {
      final fixture = await _InviteFixture.create(
        boundAccountId: _ownerAccountId,
        localMemberIsOwner: false,
      );
      addTearDown(fixture.dispose);

      await fixture.controller.initialize();

      expect(fixture.state.phase, FamilyInvitePhase.failed);
      expect(
        fixture.state.failure,
        const InvitationFailure(InvitationFailureCode.notOwner),
      );
      expect(fixture.state.retryPoint, FamilyInviteRetryPoint.bootstrap);
      expect(fixture.gateway.bootstrappedOwners, isEmpty);
    },
  );

  test('a different bound account fails before remote bootstrap', () async {
    final fixture = await _InviteFixture.create(
      boundAccountId: _differentAccountId,
    );
    addTearDown(fixture.dispose);

    await fixture.controller.initialize();

    expect(fixture.state.phase, FamilyInvitePhase.failed);
    expect(
      fixture.state.failure,
      const InvitationFailure(InvitationFailureCode.differentFamily),
    );
    expect(fixture.gateway.bootstrappedOwners, isEmpty);
  });

  test(
    'owner OTP preserves entered spelling and bootstraps after verification',
    () async {
      final fixture = await _InviteFixture.create(authenticated: false);
      addTearDown(fixture.dispose);
      await fixture.controller.initialize();

      await fixture.controller.requestEmailOtp(' Owner@Example.COM ');
      expect(fixture.state.phase, FamilyInvitePhase.awaitingOtp);
      expect(fixture.state.authenticationEmail, ' Owner@Example.COM ');
      expect(fixture.gateway.requestedEmails, ['owner@example.com']);

      fixture.gateway.accountId = _ownerAccountId;
      fixture.gateway.email = 'owner@example.com';
      await fixture.controller.verifyEmailOtp('123456');

      expect(fixture.state.phase, FamilyInvitePhase.ready);
      expect(fixture.gateway.verifiedEmails, ['owner@example.com']);
      expect(fixture.gateway.bootstrappedOwners, hasLength(1));
    },
  );

  test('account change during OTP request ignores the stale success', () async {
    final gate = Completer<void>();
    final fixture = await _InviteFixture.create(
      authenticated: false,
      otpRequestGate: gate,
    );
    addTearDown(fixture.dispose);
    await fixture.controller.initialize();

    final request = fixture.controller.requestEmailOtp('owner@example.com');
    await Future<void>.delayed(Duration.zero);
    fixture.gateway.accountId = _differentAccountId;
    gate.complete();
    await request;

    expect(fixture.state.phase, FamilyInvitePhase.failed);
    expect(fixture.state.retryPoint, FamilyInviteRetryPoint.requestOtp);
    expect(
      fixture.state.failure,
      const InvitationFailure(InvitationFailureCode.signedOut),
    );
  });

  test('two rapid create calls produce one invitation', () async {
    final gate = Completer<void>();
    final fixture = await _InviteFixture.create(createGate: gate);
    addTearDown(fixture.dispose);
    await fixture.controller.initialize();

    final first = fixture.controller.createInvite('mariam@example.com');
    final second = fixture.controller.createInvite('ignored@example.com');
    await Future<void>.delayed(Duration.zero);

    expect(fixture.gateway.createdDrafts, hasLength(1));
    gate.complete();
    await Future.wait([first, second]);
    expect(fixture.gateway.createdDrafts, hasLength(1));
    expect(fixture.state.phase, FamilyInvitePhase.created);
  });

  test(
    'ambiguous create failure retains recipient and exact retry payload',
    () async {
      final fixture = await _InviteFixture.create(
        createFailures: [
          const InvitationFailure(InvitationFailureCode.networkUnavailable),
        ],
      );
      addTearDown(fixture.dispose);
      await fixture.controller.initialize();

      await fixture.controller.createInvite(' Mariam@Example.com ');
      expect(fixture.state.phase, FamilyInvitePhase.failed);
      expect(fixture.state.retryPoint, FamilyInviteRetryPoint.create);
      expect(fixture.state.recipientEmail, ' Mariam@Example.com ');
      expect(fixture.state.isRecipientLocked, isTrue);
      expect(
        fixture.state.failure,
        const InvitationFailure(InvitationFailureCode.networkUnavailable),
      );
      final first = fixture.gateway.createdDrafts.single;

      await fixture.controller.createInvite('changed@example.com');

      expect(fixture.gateway.createdDrafts, hasLength(2));
      final retry = fixture.gateway.createdDrafts.last;
      expect(retry.inviteId, first.inviteId);
      expect(retry.recipientEmail, first.recipientEmail);
      expect(retry.tokenHash, first.tokenHash);
      expect(retry.envelope, first.envelope);
      expect(fixture.state.phase, FamilyInvitePhase.created);
      expect(fixture.state.recipientEmail, ' Mariam@Example.com ');
    },
  );

  test(
    'invalid server creation response is not exposed and remains retryable',
    () async {
      final fixture = await _InviteFixture.create(
        createdResponses: [
          CreatedInvitation(
            inviteId: '44444444-4444-4444-8444-000000000001',
            familyId: _familyId,
            state: CloudInvitationState.claimed,
            createdAt: DateTime.utc(2026, 9, 5, 8),
            expiresAt: DateTime.utc(2026, 9, 5, 8),
          ),
        ],
      );
      addTearDown(fixture.dispose);
      await fixture.controller.initialize();

      await fixture.controller.createInvite('mariam@example.com');
      final original = fixture.gateway.createdDrafts.single;

      expect(fixture.state.phase, FamilyInvitePhase.failed);
      expect(fixture.state.createdInvitation, isNull);
      expect(fixture.state.retryPoint, FamilyInviteRetryPoint.create);
      expect(
        fixture.state.failure,
        const InvitationFailure(InvitationFailureCode.unknown),
      );

      await fixture.controller.createInvite('changed@example.com');
      final retry = fixture.gateway.createdDrafts.last;
      expect(retry.inviteId, original.inviteId);
      expect(retry.recipientEmail, original.recipientEmail);
      expect(retry.tokenHash, original.tokenHash);
      expect(retry.envelope, original.envelope);
    },
  );

  test('account change during create ignores the stale success', () async {
    final gate = Completer<void>();
    final fixture = await _InviteFixture.create(createGate: gate);
    addTearDown(fixture.dispose);
    await fixture.controller.initialize();

    final create = fixture.controller.createInvite('mariam@example.com');
    await Future<void>.delayed(Duration.zero);
    fixture.gateway.accountId = _differentAccountId;
    gate.complete();
    await create;

    expect(fixture.state.phase, FamilyInvitePhase.failed);
    expect(
      fixture.state.failure,
      const InvitationFailure(InvitationFailureCode.signedOut),
    );
    expect(fixture.state.createdInvitation, isNull);
  });

  test('owner reauthenticates before retrying a signed-out create', () async {
    final fixture = await _InviteFixture.create(
      createFailures: [
        const InvitationFailure(InvitationFailureCode.signedOut),
      ],
    );
    addTearDown(fixture.dispose);
    await fixture.controller.initialize();

    await fixture.controller.createInvite(' Mariam@Example.com ');
    final original = fixture.gateway.createdDrafts.single;
    expect(fixture.state.failure?.code, InvitationFailureCode.signedOut);
    fixture.gateway.accountId = null;

    await fixture.controller.requestEmailOtp('owner@example.com');
    fixture.gateway.accountId = _ownerAccountId;
    fixture.gateway.email = 'owner@example.com';
    await fixture.controller.verifyEmailOtp('123456');

    expect(fixture.state.phase, FamilyInvitePhase.ready);
    expect(fixture.state.retryPoint, FamilyInviteRetryPoint.create);
    await fixture.controller.createInvite('changed@example.com');
    expect(fixture.state.phase, FamilyInvitePhase.created);
    expect(fixture.gateway.createdDrafts.last, original);
  });

  test(
    'revoke is deduplicated, retries exactly, and clears created state',
    () async {
      final fixture = await _InviteFixture.create(
        revokeFailures: [
          const InvitationFailure(InvitationFailureCode.networkUnavailable),
        ],
      );
      addTearDown(fixture.dispose);
      await fixture.controller.initialize();
      await fixture.controller.createInvite('mariam@example.com');
      final inviteId = fixture.state.createdInvitation!.inviteId;

      await fixture.controller.revokeInvite();
      expect(fixture.state.phase, FamilyInvitePhase.failed);
      expect(fixture.state.retryPoint, FamilyInviteRetryPoint.revoke);
      expect(fixture.gateway.revokedIds, [inviteId]);

      final gate = Completer<void>();
      fixture.gateway.revokeGate = gate;
      final first = fixture.controller.revokeInvite();
      final second = fixture.controller.revokeInvite();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.gateway.revokedIds, [inviteId, inviteId]);
      gate.complete();
      await Future.wait([first, second]);

      expect(fixture.state.phase, FamilyInvitePhase.ready);
      expect(fixture.state.createdInvitation, isNull);
    },
  );

  test('owner reauthenticates before retrying a signed-out revoke', () async {
    final fixture = await _InviteFixture.create(
      revokeFailures: [
        const InvitationFailure(InvitationFailureCode.signedOut),
      ],
    );
    addTearDown(fixture.dispose);
    await fixture.controller.initialize();
    await fixture.controller.createInvite('mariam@example.com');
    final created = fixture.state.createdInvitation!;

    await fixture.controller.revokeInvite();
    expect(fixture.state.failure?.code, InvitationFailureCode.signedOut);
    fixture.gateway.accountId = null;

    await fixture.controller.requestEmailOtp('owner@example.com');
    fixture.gateway.accountId = _ownerAccountId;
    fixture.gateway.email = 'owner@example.com';
    await fixture.controller.verifyEmailOtp('123456');

    expect(fixture.state.phase, FamilyInvitePhase.created);
    expect(fixture.state.createdInvitation, created);
    await fixture.controller.revokeInvite();
    expect(fixture.gateway.revokedIds, [created.inviteId, created.inviteId]);
    expect(fixture.state.phase, FamilyInvitePhase.ready);
  });

  test(
    'public state and diagnostics never expose invitation secrets',
    () async {
      final fixture = await _InviteFixture.create();
      addTearDown(fixture.dispose);
      await fixture.controller.initialize();
      await fixture.controller.createInvite('mariam@example.com');
      final draft = fixture.gateway.createdDrafts.single;
      final diagnostics = fixture.state.toString();

      expect(diagnostics, isNot(contains(draft.tokenHash)));
      expect(diagnostics, isNot(contains(draft.envelope.ciphertext)));
      expect(diagnostics, isNot(contains(draft.envelope.mac)));
      expect(fixture.state.toString(), 'FamilyInviteState(created)');
    },
  );

  test(
    'creation exposes created before privately sharing exactly once',
    () async {
      final shareGate = Completer<void>();
      final fixture = await _InviteFixture.create(shareGate: shareGate);
      addTearDown(fixture.dispose);
      await fixture.controller.initialize();

      final create = fixture.controller.createInvite('mariam@example.com');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(fixture.state.phase, FamilyInvitePhase.created);
      expect(fixture.state.isSharing, isTrue);
      expect(fixture.state.createdInvitation, isNotNull);
      expect(fixture.shareService.links, hasLength(1));
      expect(
        fixture.controller.toString(),
        isNot(contains(fixture.shareService.links.single.toString())),
      );

      shareGate.complete();
      await create;
      expect(fixture.state.phase, FamilyInvitePhase.created);
      expect(fixture.state.isSharing, isFalse);
    },
  );

  test(
    'share failure keeps pending invite and retries without public URI',
    () async {
      final fixture = await _InviteFixture.create(
        shareFailures: [StateError('secret details must not escape')],
      );
      addTearDown(fixture.dispose);
      await fixture.controller.initialize();

      await fixture.controller.createInvite('mariam@example.com');

      expect(fixture.state.phase, FamilyInvitePhase.created);
      expect(fixture.state.createdInvitation, isNotNull);
      expect(fixture.state.shareFailure, isNotNull);
      expect(fixture.state.toString(), isNot(contains('secret details')));

      await fixture.controller.shareAgain();

      expect(fixture.shareService.links, hasLength(2));
      expect(fixture.state.phase, FamilyInvitePhase.created);
      expect(fixture.state.shareFailure, isNull);
    },
  );

  test('share and revoke are mutually deduplicated', () async {
    final shareGate = Completer<void>();
    final fixture = await _InviteFixture.create(shareGate: shareGate);
    addTearDown(fixture.dispose);
    await fixture.controller.initialize();
    final create = fixture.controller.createInvite('mariam@example.com');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final repeatShare = fixture.controller.shareAgain();
    final revoke = fixture.controller.revokeInvite();
    expect(fixture.shareService.links, hasLength(1));
    expect(fixture.gateway.revokedIds, isEmpty);

    shareGate.complete();
    await Future.wait([create, repeatShare, revoke]);
  });

  test('share is blocked while revoke is in flight', () async {
    final fixture = await _InviteFixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.initialize();
    await fixture.controller.createInvite('mariam@example.com');
    final initialShares = fixture.shareService.links.length;
    final gate = Completer<void>();
    fixture.gateway.revokeGate = gate;

    final revoke = fixture.controller.revokeInvite();
    final share = fixture.controller.shareAgain();
    await Future<void>.delayed(Duration.zero);

    expect(fixture.gateway.revokedIds, hasLength(1));
    expect(fixture.shareService.links, hasLength(initialShares));
    gate.complete();
    await Future.wait([revoke, share]);
  });

  test(
    'account switch during thrown share clears pending capability',
    () async {
      final shareGate = Completer<void>();
      final fixture = await _InviteFixture.create(
        shareGate: shareGate,
        shareFailures: [StateError('platform failed')],
      );
      addTearDown(fixture.dispose);
      await fixture.controller.initialize();

      final create = fixture.controller.createInvite('mariam@example.com');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      fixture.gateway.accountId = _differentAccountId;
      shareGate.complete();
      await create;

      expect(fixture.state.phase, FamilyInvitePhase.failed);
      expect(
        fixture.state.failure,
        const InvitationFailure(InvitationFailureCode.signedOut),
      );
      expect(fixture.state.createdInvitation, isNull);
      await fixture.controller.shareAgain();
      expect(fixture.shareService.links, hasLength(1));
    },
  );
}

final class _InviteFixture {
  _InviteFixture({
    required this.database,
    required this.container,
    required this.subscription,
    required this.gateway,
    required this.secureStore,
    required this.shareService,
  });

  final Database database;
  final ProviderContainer container;
  final ProviderSubscription<FamilyInviteState> subscription;
  final _FakeGateway gateway;
  final _MemorySecureValueStore secureStore;
  final _FakeInviteShareService shareService;

  FamilyInviteController get controller =>
      container.read(familyInviteControllerProvider.notifier);

  FamilyInviteState get state => container.read(familyInviteControllerProvider);

  static Future<_InviteFixture> create({
    bool authenticated = true,
    String? boundAccountId,
    bool localMemberIsOwner = true,
    Completer<void>? createGate,
    Completer<void>? otpRequestGate,
    List<InvitationFailure> createFailures = const [],
    List<InvitationFailure> revokeFailures = const [],
    List<CreatedInvitation> createdResponses = const [],
    Completer<void>? shareGate,
    List<Object> shareFailures = const [],
  }) async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    await database.execute('PRAGMA foreign_keys = ON');
    for (final statement in KeepersSchema.statementsForUpgrade(
      0,
      KeepersSchema.version,
    )) {
      await database.execute(statement);
    }
    await database.insert('families', {
      'id': _familyId,
      'name': 'Sabati',
      'family_key_ref': _familyKeyRef,
      'quorum': 1,
      'created_at': 1,
    });
    if (!localMemberIsOwner) {
      await database.insert('members', {
        'id': _firstMemberId,
        'family_id': _familyId,
        'name': 'Amina',
        'role': 'adult',
        'member_key_ref': null,
        'color_token': 'sage',
        'avatar_config_json': AvatarConfig.defaults(seed: _firstMemberId)
            .encode(),
        'created_at': 0,
      });
    }
    await database.insert('members', {
      'id': _ownerMemberId,
      'family_id': _familyId,
      'name': 'Chris',
      'role': 'adult',
      'member_key_ref': 'member-key',
      'color_token': 'ochre',
      'avatar_config_json': _ownerAvatar.encode(),
      'created_at': 1,
    });
    await database.insert('local_identity_binding', {
      'singleton': 1,
      'family_id': _familyId,
      'member_id': _ownerMemberId,
      'account_id': boundAccountId,
    });
    final secureStore = _MemorySecureValueStore()
      ..values[_familyKeyRef] = 'BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc=';
    final gateway = _FakeGateway(
      accountId: authenticated ? _ownerAccountId : null,
      email: authenticated ? 'owner@example.com' : null,
      createGate: createGate,
      otpRequestGate: otpRequestGate,
      createFailures: createFailures,
      revokeFailures: revokeFailures,
      createdResponses: createdResponses,
    );
    final shareService = _FakeInviteShareService(
      gate: shareGate,
      failures: shareFailures,
    );
    var nextId = 0;
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(AsyncValue.data(database)),
        secureValueStoreProvider.overrideWithValue(secureStore),
        identityKeyServiceProvider.overrideWithValue(
          IdentityKeyService(secureStore),
        ),
        cloudFamilyGatewayProvider.overrideWithValue(gateway),
        idFactoryProvider.overrideWithValue(
          () =>
              '44444444-4444-4444-8444-${(++nextId).toString().padLeft(12, '0')}',
        ),
        utcNowProvider.overrideWithValue(() => DateTime.utc(2026, 9, 5, 8)),
        inviteShareServiceProvider.overrideWithValue(shareService),
      ],
    );
    final subscription = container.listen(
      familyInviteControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    return _InviteFixture(
      database: database,
      container: container,
      subscription: subscription,
      gateway: gateway,
      secureStore: secureStore,
      shareService: shareService,
    );
  }

  Future<void> dispose() async {
    subscription.close();
    container.dispose();
    await database.close();
  }
}

final class _FakeInviteShareService implements InviteShareService {
  _FakeInviteShareService({this.gate, List<Object> failures = const []})
    : failures = List.of(failures);

  final Completer<void>? gate;
  final List<Object> failures;
  final List<Uri> links = [];

  @override
  Future<void> shareInvitation(
    Uri invitationUri, {
    Rect? sharePositionOrigin,
  }) async {
    links.add(invitationUri);
    if (gate case final pending?) await pending.future;
    if (failures.isNotEmpty) throw failures.removeAt(0);
  }

  @override
  Future<void> shareGatheringNudge({Rect? sharePositionOrigin}) async {}
}

final class _FakeGateway implements CloudFamilyGateway {
  _FakeGateway({
    required this.accountId,
    required this.email,
    this.createGate,
    this.otpRequestGate,
    List<InvitationFailure> createFailures = const [],
    List<InvitationFailure> revokeFailures = const [],
    List<CreatedInvitation> createdResponses = const [],
  }) : createFailures = List.of(createFailures),
       revokeFailures = List.of(revokeFailures),
       createdResponses = List.of(createdResponses);

  String? accountId;
  String? email;
  Completer<void>? createGate;
  Completer<void>? otpRequestGate;
  Completer<void>? revokeGate;
  final List<InvitationFailure> createFailures;
  final List<InvitationFailure> revokeFailures;
  final List<CreatedInvitation> createdResponses;
  final List<String> requestedEmails = [];
  final List<String> verifiedEmails = [];
  final List<LocalOwnerFamily> bootstrappedOwners = [];
  final List<CloudInvitationDraft> createdDrafts = [];
  final List<String> revokedIds = [];

  @override
  bool get isConfigured => true;
  @override
  String? get authenticatedAccountId => accountId;
  @override
  String? get authenticatedEmail => email;

  @override
  Future<void> requestEmailOtp(String email) async {
    requestedEmails.add(email);
    if (otpRequestGate case final gate?) await gate.future;
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    verifiedEmails.add(email);
  }

  @override
  Future<void> bootstrapOwner(LocalOwnerFamily owner) async {
    bootstrappedOwners.add(owner);
  }

  @override
  Future<CreatedInvitation> createInvitation(CloudInvitationDraft draft) async {
    createdDrafts.add(draft);
    if (createFailures.isNotEmpty) throw createFailures.removeAt(0);
    if (createGate case final gate?) await gate.future;
    if (createdResponses.isNotEmpty) return createdResponses.removeAt(0);
    return CreatedInvitation(
      inviteId: draft.inviteId,
      familyId: draft.familyId,
      state: CloudInvitationState.pending,
      createdAt: DateTime.utc(2026, 9, 5, 8),
      expiresAt: DateTime.utc(2026, 9, 6, 8),
    );
  }

  @override
  Future<void> revokeInvitation(String inviteId) async {
    revokedIds.add(inviteId);
    if (revokeFailures.isNotEmpty) throw revokeFailures.removeAt(0);
    if (revokeGate case final gate?) await gate.future;
  }

  @override
  Future<InvitePreview> previewInvitation(FamilyInviteLink link) =>
      throw UnimplementedError();
  @override
  Future<ClaimedFamily> claimInvitation(JoinRequest request) =>
      throw UnimplementedError();
  @override
  Future<void> completeInvitation(String inviteId) =>
      throw UnimplementedError();
  @override
  Future<List<FamilyMember>> listActiveMembers(String familyId) =>
      throw UnimplementedError();
}

final class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = {};
  final List<String> reads = [];

  @override
  Future<String?> read(String key) async {
    reads.add(key);
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

const _familyId = '11111111-1111-4111-8111-111111111111';
const _firstMemberId = '11111111-1111-4111-8111-000000000001';
const _ownerMemberId = '22222222-2222-4222-8222-222222222222';
const _ownerAccountId = '33333333-3333-4333-8333-333333333333';
const _differentAccountId = '99999999-9999-4999-8999-999999999999';
const _familyKeyRef = 'keepers.family.$_familyId.entry-key.v1';
const _ownerAvatar = AvatarConfig.defaults(seed: _ownerMemberId);
