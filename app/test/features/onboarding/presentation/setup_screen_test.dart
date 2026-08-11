import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/app.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/onboarding/presentation/setup_screen.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('first run validates two names and enters the Observatory', (
    tester,
  ) async {
    final fixture = await _WidgetFixture.create();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.scope(const KeepersApp()));
    await tester.pumpAndSettle();

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
    await _pumpUntilFound(tester, find.text('No memories yet.'));

    expect(find.text('The Observatory'), findsOneWidget);
    expect(find.text('No memories yet.'), findsOneWidget);
    expect(await fixture.database.query('families'), hasLength(1));
    expect(await fixture.database.query('members'), hasLength(1));
  });

  testWidgets('whitespace does not enable setup submission', (tester) async {
    final fixture = await _WidgetFixture.create();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.scope(const KeepersApp()));
    await tester.pumpAndSettle();

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

  testWidgets('setup failure is inline and retryable without raw errors', (
    tester,
  ) async {
    final fixture = await _WidgetFixture.create(failMemberInsert: true);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.scope(const KeepersApp()));
    await tester.pumpAndSettle();

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
          localIdentityProvider.overrideWith((ref) async {
            attempts += 1;
            if (attempts == 1) throw StateError('storage details');
            return null;
          }),
        ],
        child: const KeepersApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Keepers could not open local storage.'), findsOneWidget);
    expect(find.textContaining('storage details'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Name your family space'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('startup waits for local identity lookup', (tester) async {
    final identity = Completer<LocalIdentity?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localIdentityProvider.overrideWith((ref) => identity.future),
        ],
        child: const KeepersApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    identity.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Name your family space'), findsOneWidget);
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
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

  Widget scope(Widget child) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(AsyncValue.data(database)),
      secureValueStoreProvider.overrideWithValue(store),
      identityKeyServiceProvider.overrideWithValue(identityKeyService),
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
    for (final statement in KeepersSchema.statementsForUpgrade(0, 2)) {
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
