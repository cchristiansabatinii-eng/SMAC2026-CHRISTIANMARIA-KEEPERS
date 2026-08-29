import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('invalid names never start setup', () async {
    final fixture = await _OnboardingFixture.create();
    addTearDown(fixture.dispose);

    await fixture.container
        .read(setupControllerProvider.notifier)
        .submit(const SetupInput(familyName: '  ', memberName: 'Chris'));

    final state = fixture.container.read(setupControllerProvider);
    expect(state.phase, SetupPhase.idle);
    expect(state.validationMessage, 'Enter both names');
    expect(fixture.generatedIds, 0);
    expect(fixture.secureStore.values, isEmpty);
    expect(await fixture.database.query('families'), isEmpty);
    expect(await fixture.database.query('members'), isEmpty);
  });

  test('names beyond the cloud limit never start setup', () async {
    final fixture = await _OnboardingFixture.create();
    addTearDown(fixture.dispose);

    await fixture.container
        .read(setupControllerProvider.notifier)
        .submit(
          SetupInput(
            familyName: 'F' * (setupNameMaxLength + 1),
            memberName: 'Chris',
          ),
        );

    final state = fixture.container.read(setupControllerProvider);
    expect(state.phase, SetupPhase.idle);
    expect(
      state.validationMessage,
      'Names can be up to $setupNameMaxLength characters',
    );
    expect(fixture.generatedIds, 0);
    expect(fixture.secureStore.values, isEmpty);
    expect(await fixture.database.query('families'), isEmpty);
    expect(await fixture.database.query('members'), isEmpty);
  });

  test(
    'valid setup refuses to start without an authenticated account',
    () async {
      final fixture = await _OnboardingFixture.create(accountId: null);
      addTearDown(fixture.dispose);

      await fixture.container
          .read(setupControllerProvider.notifier)
          .submit(const SetupInput(familyName: 'Sabati', memberName: 'Chris'));

      final state = fixture.container.read(setupControllerProvider);
      expect(state.phase, SetupPhase.failed);
      expect(state.errorMessage, 'Your account session ended. Sign in again.');
      expect(state.requiresAuthentication, isTrue);
      expect(fixture.generatedIds, 0);
      expect(fixture.secureStore.values, isEmpty);
      expect(await fixture.database.query('families'), isEmpty);
      expect(await fixture.database.query('members'), isEmpty);
      expect(await fixture.database.query('local_identity_binding'), isEmpty);
    },
  );

  test('successful setup commits one family and one adult member', () async {
    final fixture = await _OnboardingFixture.create();
    addTearDown(fixture.dispose);

    await fixture.container
        .read(setupControllerProvider.notifier)
        .submit(
          const SetupInput(familyName: '  Sabati  ', memberName: '  Chris  '),
        );

    expect(
      fixture.container.read(setupControllerProvider).phase,
      SetupPhase.idle,
    );
    expect(await fixture.database.query('families'), [
      {
        'id': 'id-1',
        'name': 'Sabati',
        'family_key_ref': 'keepers.family.id-1.entry-key.v1',
        'quorum': 1,
        'created_at': DateTime.utc(2026, 9, 1).millisecondsSinceEpoch,
      },
    ]);
    expect(await fixture.database.query('members'), [
      {
        'id': 'id-2',
        'family_id': 'id-1',
        'name': 'Chris',
        'role': 'adult',
        'birth_date': null,
        'memorial_state': 0,
        'memorial_date': null,
        'created_at': DateTime.utc(2026, 9, 1).millisecondsSinceEpoch,
        'member_key_ref': 'keepers.member.id-2.entry-key.v1',
        'color_token': 'ochre',
        'avatar_config_json': const AvatarConfig.defaults(seed: 'id-2')
            .encode(),
      },
    ]);
    expect(await fixture.database.query('local_identity_binding'), [
      {
        'singleton': 1,
        'family_id': 'id-1',
        'member_id': 'id-2',
        'account_id': null,
      },
    ]);
    expect(fixture.secureStore.values, hasLength(2));
    expect(
      await fixture.container.read(localIdentityProvider.future),
      isNotNull,
    );
  });

  test(
    'successful first-run setup defers account binding until cloud bootstrap',
    () async {
      final fixture = await _OnboardingFixture.create(accountId: 'account-2');
      addTearDown(fixture.dispose);

      await fixture.container
          .read(setupControllerProvider.notifier)
          .submit(const SetupInput(familyName: 'Sabati', memberName: 'Chris'));

      expect(await fixture.database.query('local_identity_binding'), [
        {
          'singleton': 1,
          'family_id': 'id-1',
          'member_id': 'id-2',
          'account_id': null,
        },
      ]);
      expect(
        (await fixture.container.read(localIdentityProvider.future))?.accountId,
        isNull,
      );
    },
  );

  test('session loss before persistence rolls back identity keys', () async {
    final fixture = await _OnboardingFixture.create(holdFirstKeyWrite: true);
    addTearDown(fixture.dispose);
    final submission = fixture.container
        .read(setupControllerProvider.notifier)
        .submit(const SetupInput(familyName: 'Sabati', memberName: 'Chris'));
    await fixture.secureStore.firstWriteStarted;

    fixture.gateway.accountId = null;
    fixture.secureStore.releaseFirstWrite();
    await submission;

    final state = fixture.container.read(setupControllerProvider);
    expect(state.phase, SetupPhase.failed);
    expect(state.errorMessage, 'Your account session ended. Sign in again.');
    expect(fixture.secureStore.values, isEmpty);
    expect(await fixture.database.query('families'), isEmpty);
    expect(await fixture.database.query('members'), isEmpty);
    expect(await fixture.database.query('local_identity_binding'), isEmpty);
  });

  test(
    'account switch inside the transaction rolls back all setup data',
    () async {
      final fixture = await _OnboardingFixture.create(
        accountId: 'account-1',
        accountIdAtTransactionStart: 'account-2',
      );
      addTearDown(fixture.dispose);

      await fixture.container
          .read(setupControllerProvider.notifier)
          .submit(const SetupInput(familyName: 'Sabati', memberName: 'Chris'));

      final state = fixture.container.read(setupControllerProvider);
      expect(state.phase, SetupPhase.failed);
      expect(state.errorMessage, 'Your account session ended. Sign in again.');
      expect(fixture.secureStore.values, isEmpty);
      expect(await fixture.database.query('families'), isEmpty);
      expect(await fixture.database.query('members'), isEmpty);
      expect(await fixture.database.query('local_identity_binding'), isEmpty);
    },
  );

  test(
    'database failure rolls back transaction and created identity keys',
    () async {
      final fixture = await _OnboardingFixture.create(failMemberInsert: true);
      addTearDown(fixture.dispose);

      await fixture.container
          .read(setupControllerProvider.notifier)
          .submit(const SetupInput(familyName: 'Sabati', memberName: 'Chris'));

      final state = fixture.container.read(setupControllerProvider);
      expect(state.phase, SetupPhase.failed);
      expect(
        state.errorMessage,
        'Your family space could not be secured. Try again.',
      );
      expect(fixture.secureStore.values, isEmpty);
      expect(await fixture.database.query('families'), isEmpty);
      expect(await fixture.database.query('members'), isEmpty);
    },
  );

  test('a concurrent second submit cannot create another identity', () async {
    final fixture = await _OnboardingFixture.create();
    addTearDown(fixture.dispose);
    final controller = fixture.container.read(setupControllerProvider.notifier);

    final first = controller.submit(
      const SetupInput(familyName: 'Sabati', memberName: 'Chris'),
    );
    final second = controller.submit(
      const SetupInput(familyName: 'Other', memberName: 'Other'),
    );
    await Future.wait([first, second]);

    expect(await fixture.database.query('families'), hasLength(1));
    expect(await fixture.database.query('members'), hasLength(1));
    expect(fixture.generatedIds, 2);
  });

  test('invalid and valid calls cannot replace an active submission', () async {
    final fixture = await _OnboardingFixture.create(holdFirstKeyWrite: true);
    addTearDown(fixture.dispose);
    final controller = fixture.container.read(setupControllerProvider.notifier);

    final first = controller.submit(
      const SetupInput(familyName: 'Sabati', memberName: 'Chris'),
    );
    await fixture.secureStore.firstWriteStarted;

    await controller.submit(
      const SetupInput(familyName: ' ', memberName: 'Ignored'),
    );
    final following = controller.submit(
      const SetupInput(familyName: 'Other', memberName: 'Other'),
    );
    fixture.secureStore.releaseFirstWrite();
    await Future.wait([first, following]);

    expect(fixture.generatedIds, 2);
    expect(await fixture.database.query('families'), [
      {
        'id': 'id-1',
        'name': 'Sabati',
        'family_key_ref': 'keepers.family.id-1.entry-key.v1',
        'quorum': 1,
        'created_at': DateTime.utc(2026, 9, 1).millisecondsSinceEpoch,
      },
    ]);
    expect(await fixture.database.query('members'), hasLength(1));
  });
}

final class _OnboardingFixture {
  _OnboardingFixture({
    required this.database,
    required this.secureStore,
    required this.gateway,
    required this.container,
    required this._generatedIds,
  });

  final Database database;
  final _MemorySecureValueStore secureStore;
  final _SetupGateway gateway;
  final ProviderContainer container;
  final int Function() _generatedIds;

  int get generatedIds => _generatedIds();

  static Future<_OnboardingFixture> create({
    bool failMemberInsert = false,
    bool holdFirstKeyWrite = false,
    String? accountId = 'account-1',
    String? accountIdAtTransactionStart,
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
    if (failMemberInsert) {
      await database.execute(r'''
CREATE TRIGGER fail_member_insert
BEFORE INSERT ON members
BEGIN
  SELECT RAISE(ABORT, 'member insert failed');
END
''');
    }

    final secureStore = _MemorySecureValueStore(
      holdFirstWrite: holdFirstKeyWrite,
    );
    final gateway = _SetupGateway(accountId: accountId);
    final databaseForProvider = accountIdAtTransactionStart == null
        ? database
        : _AccountChangingDatabase(
            database,
            gateway,
            accountIdAtTransactionStart,
          );
    var nextId = 0;
    final container = ProviderContainer(
      overrides: [
        cloudFamilyGatewayProvider.overrideWithValue(gateway),
        databaseProvider.overrideWithValue(
          AsyncValue.data(databaseForProvider),
        ),
        secureValueStoreProvider.overrideWithValue(secureStore),
        identityKeyServiceProvider.overrideWithValue(
          IdentityKeyService(
            secureStore,
            randomBytesFactory: (length) => List<int>.filled(length, 7),
          ),
        ),
        idFactoryProvider.overrideWithValue(() => 'id-${++nextId}'),
        utcNowProvider.overrideWithValue(() => DateTime.utc(2026, 9, 1)),
      ],
    );
    return _OnboardingFixture(
      database: database,
      secureStore: secureStore,
      gateway: gateway,
      container: container,
      generatedIds: () => nextId,
    );
  }

  Future<void> dispose() async {
    container.dispose();
    await database.close();
  }
}

final class _SetupGateway implements CloudFamilyGateway {
  _SetupGateway({required this.accountId});

  String? accountId;

  @override
  bool get isConfigured => true;

  @override
  String? get authenticatedAccountId => accountId;

  @override
  String? get authenticatedEmail => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _AccountChangingDatabase implements Database {
  _AccountChangingDatabase(this._database, this._gateway, this._accountId);

  final Database _database;
  final _SetupGateway _gateway;
  final String _accountId;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => _database.transaction((transaction) {
    _gateway.accountId = _accountId;
    return action(transaction);
  }, exclusive: exclusive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
