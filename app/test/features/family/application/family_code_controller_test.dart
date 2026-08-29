import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_code_controller.dart';
import 'package:keepers/features/family/application/family_join_crypto_providers.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/family_code_cache_repository.dart';
import 'package:keepers/features/family/data/family_code_codec.dart';
import 'package:keepers/features/family/data/invite_share_service.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/storage/schema.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('publishes only the authoritative committed code', () async {
    final fixture = await _Fixture.create(
      gateway: _CodeGateway(
        code: null,
        bootstrapFailures: const [
          FamilyJoinFailure(FamilyJoinFailureCode.codeCollision),
        ],
      ),
      candidates: ['AAAA0001', 'BBBB0002'],
    );
    addTearDown(fixture.dispose);

    await fixture.controller.load();

    expect(fixture.codec.createCalls, 2);
    expect(fixture.state.displayCode, 'BBBB-0002');
    expect(fixture.state.displayCode, isNot('AAAA-0001'));
    final cached = await const FamilyCodeCacheRepository().find(
      fixture.database,
      familyId: _familyId,
    );
    expect(cached?.material.ciphertext, 'draft-2');
  });

  test(
    'bootstraps a bound local owner after a forbidden cloud lookup',
    () async {
      final gateway = _CodeGateway(
        code: null,
        getFailures: const [FamilyJoinFailure(FamilyJoinFailureCode.forbidden)],
      );
      final fixture = await _Fixture.create(
        gateway: gateway,
        candidates: ['ABCD1234'],
      );
      addTearDown(fixture.dispose);

      await fixture.controller.load();

      expect(gateway.bootstrapCalls, 1);
      expect(fixture.state.phase, FamilyCodePhase.ready);
      expect(fixture.state.displayCode, 'ABCD-1234');
    },
  );

  test('opens cached encrypted material while offline', () async {
    final material = _material(version: 3, ciphertext: 'cached-material');
    final gateway = _CodeGateway(
      code: null,
      getFailures: const [
        FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable),
      ],
    );
    final fixture = await _Fixture.create(gateway: gateway);
    addTearDown(fixture.dispose);
    fixture.codec.openedCodes[material.ciphertext] = FamilyCode.parse(
      'K7M4P2Q8',
    );
    await const FamilyCodeCacheRepository().upsert(
      fixture.database,
      FamilyCodeCacheRecord(
        material: material,
        creatorAccountId: _accountId,
        updatedAt: DateTime.utc(2026, 9, 6),
        cachedAt: DateTime.utc(2026, 9, 7),
      ),
    );

    await fixture.controller.load();

    expect(fixture.state.displayCode, 'K7M4-P2Q8');
    expect(fixture.state.codeVersion, 3);
    expect(fixture.state.isOffline, isTrue);
    expect(fixture.state.phase, FamilyCodePhase.ready);
  });

  test(
    'signed-out load never exposes cached code from a bound account',
    () async {
      final material = _material(version: 3, ciphertext: 'cached-material');
      final gateway = _CodeGateway(code: null)..accountId = null;
      final fixture = await _Fixture.create(gateway: gateway);
      addTearDown(fixture.dispose);
      fixture.codec.openedCodes[material.ciphertext] = FamilyCode.parse(
        'K7M4P2Q8',
      );
      await _seedCache(fixture.database, material);

      await fixture.controller.load();
      await fixture.controller.copyFamilyCode();
      await fixture.controller.copyFamilyLink();
      await fixture.controller.shareFamilyLink();

      expect(fixture.codec.openCalls, 0);
      expect(fixture.state.displayCode, isNull);
      expect(fixture.clipboard.values, isEmpty);
      expect(fixture.sharedUris, isEmpty);
      expect(
        fixture.state.failure,
        const FamilyJoinFailure(FamilyJoinFailureCode.signedOut),
      );
    },
  );

  test('account mismatch never decrypts or displays cached material', () async {
    final material = _material(version: 1, ciphertext: 'cached-material');
    final gateway = _CodeGateway(code: null)..accountId = _differentAccountId;
    final fixture = await _Fixture.create(gateway: gateway);
    addTearDown(fixture.dispose);
    fixture.codec.openedCodes[material.ciphertext] = FamilyCode.parse(
      'K7M4P2Q8',
    );
    await const FamilyCodeCacheRepository().upsert(
      fixture.database,
      FamilyCodeCacheRecord(
        material: material,
        creatorAccountId: _accountId,
        updatedAt: DateTime.utc(2026, 9, 6),
        cachedAt: DateTime.utc(2026, 9, 7),
      ),
    );

    await fixture.controller.load();

    expect(fixture.codec.openCalls, 0);
    expect(fixture.state.displayCode, isNull);
    expect(
      fixture.state.failure,
      const FamilyJoinFailure(FamilyJoinFailureCode.forbidden),
    );
  });

  test(
    'account switch during cloud refresh clears the cached plaintext',
    () async {
      final material = _material(version: 1, ciphertext: 'cached-material');
      final cloudGate = Completer<void>();
      final gateway = _CodeGateway(
        code: _record(material: material),
        getGate: cloudGate,
      );
      final fixture = await _Fixture.create(gateway: gateway);
      addTearDown(fixture.dispose);
      fixture.codec.openedCodes[material.ciphertext] = FamilyCode.parse(
        'K7M4P2Q8',
      );
      await const FamilyCodeCacheRepository().upsert(
        fixture.database,
        FamilyCodeCacheRecord(
          material: material,
          creatorAccountId: _accountId,
          updatedAt: DateTime.utc(2026, 9, 6),
          cachedAt: DateTime.utc(2026, 9, 7),
        ),
      );

      final load = fixture.controller.load();
      await _waitUntil(() => fixture.state.displayCode == 'K7M4-P2Q8');
      gateway.accountId = _differentAccountId;
      cloudGate.complete();
      await load;

      expect(fixture.state.displayCode, isNull);
      expect(
        fixture.state.failure,
        const FamilyJoinFailure(FamilyJoinFailureCode.signedOut),
      );
    },
  );

  test('account switch still clears cache when cloud refresh fails', () async {
    final material = _material(version: 1, ciphertext: 'cached-material');
    final cloudGate = Completer<void>();
    final gateway = _CodeGateway(
      code: null,
      getGate: cloudGate,
      getFailures: const [
        FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable),
      ],
    );
    final fixture = await _Fixture.create(gateway: gateway);
    addTearDown(fixture.dispose);
    fixture.codec.openedCodes[material.ciphertext] = FamilyCode.parse(
      'K7M4P2Q8',
    );
    await const FamilyCodeCacheRepository().upsert(
      fixture.database,
      FamilyCodeCacheRecord(
        material: material,
        creatorAccountId: _accountId,
        updatedAt: DateTime.utc(2026, 9, 6),
        cachedAt: DateTime.utc(2026, 9, 7),
      ),
    );

    final load = fixture.controller.load();
    await _waitUntil(() => fixture.state.displayCode == 'K7M4-P2Q8');
    gateway.accountId = _differentAccountId;
    cloudGate.complete();
    await load;

    expect(fixture.state.displayCode, isNull);
    expect(
      fixture.state.failure,
      const FamilyJoinFailure(FamilyJoinFailureCode.signedOut),
    );
  });

  test(
    'account changes during the first database await expose no code',
    () async {
      for (final accounts in <(String?, String)>[
        (null, _accountId),
        (_accountId, _differentAccountId),
      ]) {
        final databaseGate = Completer<Database>();
        final gateway = _CodeGateway(code: null)..accountId = accounts.$1;
        final fixture = await _Fixture.create(
          gateway: gateway,
          databaseGate: databaseGate,
        );
        try {
          final material = _material(version: 1, ciphertext: 'cached-material');
          fixture.codec.openedCodes[material.ciphertext] = FamilyCode.parse(
            'K7M4P2Q8',
          );
          await _seedCache(fixture.database, material);

          final load = fixture.controller.load();
          gateway.accountId = accounts.$2;
          databaseGate.complete(fixture.database);
          await load;

          expect(fixture.codec.openCalls, 0, reason: '$accounts');
          expect(fixture.state.displayCode, isNull, reason: '$accounts');
          expect(
            fixture.state.failure,
            const FamilyJoinFailure(FamilyJoinFailureCode.signedOut),
            reason: '$accounts',
          );
        } finally {
          if (!databaseGate.isCompleted) {
            databaseGate.complete(fixture.database);
          }
          await fixture.dispose();
        }
      }
    },
  );

  test('creator authority comes only from the server account id', () async {
    final codec = _CodeCodec();
    final record = _record(
      material: _material(version: 1, ciphertext: 'existing'),
      creatorAccountId: _differentAccountId,
    );
    codec.openedCodes['existing'] = FamilyCode.parse('K7M4P2Q8');
    final fixture = await _Fixture.create(
      gateway: _CodeGateway(code: record),
      codec: codec,
    );
    addTearDown(fixture.dispose);

    await fixture.controller.load();

    expect(fixture.state.displayCode, 'K7M4-P2Q8');
    expect(fixture.state.isCreator, isFalse);
    await fixture.controller.regenerate();
    expect(fixture.gateway.regenerateCalls, 0);
    expect(
      fixture.state.failure,
      const FamilyJoinFailure(FamilyJoinFailureCode.notCreator),
    );
  });

  test('regeneration failure preserves the visible and cached code', () async {
    final codec = _CodeCodec(candidates: ['BBBB0002']);
    final original = _record(
      material: _material(version: 1, ciphertext: 'existing'),
    );
    codec.openedCodes['existing'] = FamilyCode.parse('K7M4P2Q8');
    final gateway = _CodeGateway(
      code: original,
      regenerateFailures: const [
        FamilyJoinFailure(FamilyJoinFailureCode.codeVersionChanged),
      ],
    );
    final fixture = await _Fixture.create(gateway: gateway, codec: codec);
    addTearDown(fixture.dispose);
    await fixture.controller.load();

    await fixture.controller.regenerate();

    expect(fixture.state.displayCode, 'K7M4-P2Q8');
    expect(fixture.state.codeVersion, 1);
    expect(fixture.state.phase, FamilyCodePhase.failed);
    expect(
      fixture.state.failure,
      const FamilyJoinFailure(FamilyJoinFailureCode.codeVersionChanged),
    );
    final cached = await const FamilyCodeCacheRepository().find(
      fixture.database,
      familyId: _familyId,
    );
    expect(cached?.material, original.material);
  });

  test('account switch during regeneration clears the old plaintext', () async {
    final codec = _CodeCodec(candidates: ['BBBB0002']);
    final original = _record(
      material: _material(version: 1, ciphertext: 'existing'),
    );
    codec.openedCodes['existing'] = FamilyCode.parse('K7M4P2Q8');
    final regenerationGate = Completer<void>();
    final gateway = _CodeGateway(
      code: original,
      regenerateGate: regenerationGate,
      regenerateFailures: const [
        FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable),
      ],
    );
    final fixture = await _Fixture.create(gateway: gateway, codec: codec);
    addTearDown(fixture.dispose);
    await fixture.controller.load();

    final regenerate = fixture.controller.regenerate();
    await _waitUntil(() => fixture.state.phase == FamilyCodePhase.regenerating);
    gateway.accountId = _differentAccountId;
    regenerationGate.complete();
    await regenerate;

    expect(fixture.state.displayCode, isNull);
    expect(
      fixture.state.failure,
      const FamilyJoinFailure(FamilyJoinFailureCode.signedOut),
    );
  });

  test('collision retry stops after five candidate submissions', () async {
    final fixture = await _Fixture.create(
      gateway: _CodeGateway(
        code: null,
        bootstrapFailures: List<FamilyJoinFailure>.filled(
          5,
          const FamilyJoinFailure(FamilyJoinFailureCode.codeCollision),
        ),
      ),
      candidates: const [
        'AAAA0001',
        'BBBB0002',
        'CCCC0003',
        'DDDD0004',
        'EEEE0005',
      ],
    );
    addTearDown(fixture.dispose);

    await fixture.controller.load();

    expect(fixture.gateway.bootstrapCalls, 5);
    expect(fixture.codec.createCalls, 5);
    expect(fixture.state.displayCode, isNull);
    expect(fixture.state.phase, FamilyCodePhase.failed);
    expect(
      fixture.state.failure,
      const FamilyJoinFailure(FamilyJoinFailureCode.codeCollision),
    );
  });

  test(
    'account switch stops collision retries before another candidate',
    () async {
      final bootstrapGate = Completer<void>();
      final gateway = _CodeGateway(
        code: null,
        bootstrapGate: bootstrapGate,
        bootstrapFailures: const [
          FamilyJoinFailure(FamilyJoinFailureCode.codeCollision),
        ],
      );
      final fixture = await _Fixture.create(
        gateway: gateway,
        candidates: const ['AAAA0001', 'BBBB0002'],
      );
      addTearDown(() async {
        if (!bootstrapGate.isCompleted) bootstrapGate.complete();
        await fixture.dispose();
      });

      final load = fixture.controller.load();
      await _waitUntil(() => gateway.bootstrapCalls == 1);
      gateway.accountId = _differentAccountId;
      bootstrapGate.complete();
      await load;

      expect(gateway.bootstrapCalls, 1);
      expect(fixture.codec.createCalls, 1);
      expect(fixture.state.displayCode, isNull);
      expect(
        fixture.state.failure,
        const FamilyJoinFailure(FamilyJoinFailureCode.signedOut),
      );
    },
  );

  test(
    'plaintext leaves the controller only after explicit copy or share',
    () async {
      final codec = _CodeCodec();
      final record = _record(
        material: _material(version: 1, ciphertext: 'existing'),
      );
      codec.openedCodes['existing'] = FamilyCode.parse('K7M4P2Q8');
      final fixture = await _Fixture.create(
        gateway: _CodeGateway(code: record),
        codec: codec,
      );
      addTearDown(fixture.dispose);
      await fixture.controller.load();

      expect(fixture.clipboard.values, isEmpty);
      expect(fixture.sharedUris, isEmpty);

      await fixture.controller.copyFamilyCode();
      await fixture.controller.copyFamilyLink();
      await fixture.controller.shareFamilyLink(
        sharePositionOrigin: const Rect.fromLTWH(1, 2, 48, 48),
      );

      expect(fixture.clipboard.values, [
        'K7M4-P2Q8',
        'https://join.keepers.app/f/K7M4-P2Q8',
      ]);
      expect(fixture.sharedUris, [
        Uri.parse('https://join.keepers.app/f/K7M4-P2Q8'),
      ]);
      expect(fixture.state.feedback, 'Share options opened');
    },
  );

  test('explicit copy and share refuse an account-switched code', () async {
    final codec = _CodeCodec();
    final record = _record(
      material: _material(version: 1, ciphertext: 'existing'),
    );
    codec.openedCodes['existing'] = FamilyCode.parse('K7M4P2Q8');
    final fixture = await _Fixture.create(
      gateway: _CodeGateway(code: record),
      codec: codec,
    );
    addTearDown(fixture.dispose);
    await fixture.controller.load();
    fixture.gateway.accountId = _differentAccountId;

    await fixture.controller.copyFamilyCode();
    await fixture.controller.copyFamilyLink();
    await fixture.controller.shareFamilyLink();

    expect(fixture.clipboard.values, isEmpty);
    expect(fixture.sharedUris, isEmpty);
    expect(fixture.state.displayCode, isNull);
    expect(
      fixture.state.failure,
      const FamilyJoinFailure(FamilyJoinFailureCode.signedOut),
    );
  });

  test('creator binding is repaired after bootstrap bind failure', () async {
    final gateway = _CodeGateway(code: null);
    final fixture = await _Fixture.create(
      gateway: gateway,
      candidates: const ['AAAA0001'],
      identityAccountBound: false,
      beforeListen: (database) => database.execute(r'''
CREATE TRIGGER fail_creator_bind
BEFORE UPDATE OF account_id ON local_identity_binding
BEGIN
  SELECT RAISE(ABORT, 'bind failed');
END
'''),
    );
    addTearDown(fixture.dispose);

    await fixture.controller.load();
    expect(fixture.state.phase, FamilyCodePhase.failed);
    expect(
      fixture.state.failure,
      const FamilyJoinFailure(FamilyJoinFailureCode.localPersistenceFailed),
    );
    expect(gateway.bootstrapCalls, 1);

    await fixture.database.execute('DROP TRIGGER fail_creator_bind');
    await fixture.controller.load();

    expect(gateway.bootstrapCalls, 1);
    expect(fixture.state.phase, FamilyCodePhase.ready);
    expect(fixture.state.isCreator, isTrue);
    final binding = (await fixture.database.query('local_identity_binding'))
        .single;
    expect(binding['account_id'], _accountId);
  });
}

final class _Fixture {
  _Fixture({
    required this.database,
    required this.gateway,
    required this.codec,
    required this.clipboard,
    required this.sharedUris,
    required this.container,
    required this.subscription,
  });

  final Database database;
  final _CodeGateway gateway;
  final _CodeCodec codec;
  final _Clipboard clipboard;
  final List<Uri> sharedUris;
  final ProviderContainer container;
  final ProviderSubscription<FamilyCodeState> subscription;

  FamilyCodeController get controller =>
      container.read(familyCodeControllerProvider(_familyId).notifier);

  FamilyCodeState get state =>
      container.read(familyCodeControllerProvider(_familyId));

  static Future<_Fixture> create({
    required _CodeGateway gateway,
    _CodeCodec? codec,
    List<String> candidates = const [],
    Completer<Database>? databaseGate,
    bool identityAccountBound = true,
    Future<void> Function(Database database)? beforeListen,
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
      'name': 'Rahman',
      'family_key_ref': _familyKeyRef,
      'quorum': 1,
      'created_at': 1,
    });
    await database.insert('members', {
      'id': _memberId,
      'family_id': _familyId,
      'name': 'Chris',
      'role': 'adult',
      'member_key_ref': 'member-key',
      'color_token': 'ochre',
      'avatar_config_json': const AvatarConfig.defaults(seed: _memberId)
          .encode(),
      'created_at': 1,
    });
    await database.insert('local_identity_binding', {
      'singleton': 1,
      'family_id': _familyId,
      'member_id': _memberId,
      'account_id': identityAccountBound ? _accountId : null,
    });
    await beforeListen?.call(database);

    final secureValues = _MemorySecureValueStore({
      _familyKeyRef: base64UrlEncode(List<int>.generate(32, (index) => index)),
    });
    final actualCodec = codec ?? _CodeCodec(candidates: candidates);
    final clipboard = _Clipboard();
    final sharedUris = <Uri>[];
    final shareService = InviteShareService(
      share: (params) async {
        final text = params.text;
        sharedUris.add(Uri.parse(text!.split('\n').last));
        return const ShareResult('', ShareResultStatus.dismissed);
      },
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith(
          (ref) async =>
              databaseGate == null ? database : await databaseGate.future,
        ),
        familyCodeJoinGatewayProvider.overrideWithValue(gateway),
        familyCodeCodecProvider.overrideWithValue(actualCodec),
        identityKeyServiceProvider.overrideWithValue(
          IdentityKeyService(secureValues),
        ),
        inviteShareServiceProvider.overrideWithValue(shareService),
        familyClipboardProvider.overrideWithValue(clipboard),
        utcNowProvider.overrideWithValue(() => DateTime.utc(2026, 9, 7)),
      ],
    );
    final subscription = container.listen(
      familyCodeControllerProvider(_familyId),
      (_, _) {},
    );
    return _Fixture(
      database: database,
      gateway: gateway,
      codec: actualCodec,
      clipboard: clipboard,
      sharedUris: sharedUris,
      container: container,
      subscription: subscription,
    );
  }

  Future<void> dispose() async {
    subscription.close();
    container.dispose();
    await database.close();
  }
}

final class _CodeCodec implements FamilyCodeCodec {
  _CodeCodec({List<String> candidates = const []})
    : candidates = List<String>.of(candidates);

  final List<String> candidates;
  final Map<String, FamilyCode> openedCodes = {};
  var createCalls = 0;
  var openCalls = 0;

  @override
  Future<FamilyCodeDraft> createDraft({
    required String familyId,
    required int codeVersion,
    required List<int> familyKey,
  }) async {
    createCalls += 1;
    final code = FamilyCode.parse(candidates[createCalls - 1]);
    final material = _material(
      version: codeVersion,
      ciphertext: 'draft-$createCalls',
    );
    openedCodes[material.ciphertext] = code;
    return FamilyCodeDraft(
      code: code,
      lookupHash: 'hash-$createCalls',
      material: material,
    );
  }

  @override
  Future<FamilyCode> open({
    required EncryptedFamilyCodeMaterial material,
    required List<int> familyKey,
  }) async {
    openCalls += 1;
    return openedCodes[material.ciphertext]!;
  }

  @override
  Future<String> lookupHash(FamilyCode code) async => 'unused';
}

final class _CodeGateway implements FamilyCodeJoinGateway {
  _CodeGateway({
    required this.code,
    List<FamilyJoinFailure> getFailures = const [],
    List<FamilyJoinFailure> bootstrapFailures = const [],
    List<FamilyJoinFailure> regenerateFailures = const [],
    this.getGate,
    this.bootstrapGate,
    this.regenerateGate,
  }) : getFailures = List<FamilyJoinFailure>.of(getFailures),
       bootstrapFailures = List<FamilyJoinFailure>.of(bootstrapFailures),
       regenerateFailures = List<FamilyJoinFailure>.of(regenerateFailures);

  EncryptedFamilyCodeRecord? code;
  final List<FamilyJoinFailure> getFailures;
  final List<FamilyJoinFailure> bootstrapFailures;
  final List<FamilyJoinFailure> regenerateFailures;
  final Completer<void>? getGate;
  final Completer<void>? bootstrapGate;
  final Completer<void>? regenerateGate;
  String? accountId = _accountId;
  var bootstrapCalls = 0;
  var regenerateCalls = 0;

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => accountId;

  @override
  Future<EncryptedFamilyCodeRecord> getFamilyCode(String familyId) async {
    await getGate?.future;
    if (getFailures.isNotEmpty) throw getFailures.removeAt(0);
    final result = code;
    if (result == null) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.familyNotFound);
    }
    return result;
  }

  @override
  Future<EncryptedFamilyCodeRecord> bootstrapOwnerWithFamilyCode(
    LocalOwnerFamily owner,
    FamilyCodeDraft draft,
  ) async {
    bootstrapCalls += 1;
    await bootstrapGate?.future;
    if (bootstrapFailures.isNotEmpty) {
      throw bootstrapFailures.removeAt(0);
    }
    final result = _record(material: draft.material);
    code = result;
    return result;
  }

  @override
  Future<EncryptedFamilyCodeRecord> regenerateFamilyCode({
    required String familyId,
    required int expectedVersion,
    required FamilyCodeDraft replacement,
  }) async {
    regenerateCalls += 1;
    await regenerateGate?.future;
    if (regenerateFailures.isNotEmpty) {
      throw regenerateFailures.removeAt(0);
    }
    final result = _record(material: replacement.material);
    code = result;
    return result;
  }

  @override
  Future<FamilyJoinDecision> approveJoinRequest(
    String requestId,
    FamilyJoinApprovalEnvelope envelope,
  ) => throw UnimplementedError();

  @override
  Future<FamilyJoinDecision> cancelJoinRequest(String requestId) =>
      throw UnimplementedError();

  @override
  Future<FamilyJoinDecision> completeJoinRequest(String requestId) =>
      throw UnimplementedError();

  @override
  Future<OwnFamilyJoinRequest> createFamilyJoinRequest(
    FamilyJoinRequestDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<FamilyJoinDecision> declineJoinRequest(String requestId) =>
      throw UnimplementedError();

  @override
  Future<OwnFamilyJoinRequest?> getOwnJoinRequest() =>
      throw UnimplementedError();

  @override
  Future<List<PendingFamilyJoinRequest>> listPendingJoinRequests(
    String familyId,
  ) => throw UnimplementedError();

  @override
  Future<FamilyJoinPreview> previewFamilyByCode(FamilyCode code) =>
      throw UnimplementedError();

  @override
  Stream<void> watchOwnJoinRequest() => const Stream<void>.empty();

  @override
  Stream<void> watchPendingJoinRequests(String familyId) =>
      const Stream<void>.empty();
}

final class _Clipboard implements FamilyClipboard {
  final values = <String>[];

  @override
  Future<void> writeText(String value) async => values.add(value);
}

final class _MemorySecureValueStore implements SecureValueStore {
  _MemorySecureValueStore(Map<String, String> values)
    : _values = Map<String, String>.of(values);

  final Map<String, String> _values;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

EncryptedFamilyCodeMaterial _material({
  required int version,
  required String ciphertext,
}) => EncryptedFamilyCodeMaterial(
  codecVersion: 1,
  familyId: _familyId,
  codeVersion: version,
  nonce: 'nonce',
  ciphertext: ciphertext,
  mac: 'mac',
);

EncryptedFamilyCodeRecord _record({
  required EncryptedFamilyCodeMaterial material,
  String creatorAccountId = _accountId,
}) => EncryptedFamilyCodeRecord(
  material: material,
  creatorAccountId: creatorAccountId,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 7),
);

const _familyId = '11111111-1111-4111-8111-111111111111';
const _memberId = '22222222-2222-4222-8222-222222222222';
const _accountId = '33333333-3333-4333-8333-333333333333';
const _differentAccountId = '44444444-4444-4444-8444-444444444444';
const _familyKeyRef = 'keepers.family.$_familyId.entry-key.v1';

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Condition was not reached');
}

Future<void> _seedCache(
  Database database,
  EncryptedFamilyCodeMaterial material,
) => const FamilyCodeCacheRepository().upsert(
  database,
  FamilyCodeCacheRecord(
    material: material,
    creatorAccountId: _accountId,
    updatedAt: DateTime.utc(2026, 9, 6),
    cachedAt: DateTime.utc(2026, 9, 7),
  ),
);
