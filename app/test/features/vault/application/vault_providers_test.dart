import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/application/capture_providers.dart';
import 'package:keepers/features/capture/data/encrypted_blob_store.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/application/vault_providers.dart';
import 'package:keepers/features/vault/data/weekly_reveal_cloud_gateway.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../capture/data/test_secure_blob_file_system.dart';

void main() {
  sqfliteFfiInit();

  test(
    'cached local entries resolve before a stalled cloud manifest',
    () async {
      final cloud = _LifecycleCloudGateway(stallFirstList: true);
      final harness = await _ProviderHarness.create(cloud);
      addTearDown(harness.close);

      final entries = await harness.container
          .read(vaultEntriesProvider.future)
          .timeout(const Duration(milliseconds: 750));

      expect(entries.map((entry) => entry.id), ['cached-journal']);
      await _eventually(
        () => cloud.listCalls == 1,
        reason: 'the background cloud reconciliation should start once',
      );
    },
  );

  test(
    'an import refresh does not start a no-op synchronization loop',
    () async {
      final cloud = _LifecycleCloudGateway();
      await cloud.addRemote(id: 'single-remote', bytes: [0x31, 0x32]);
      final harness = await _ProviderHarness.create(cloud);
      addTearDown(harness.close);
      final subscription = harness.container.listen(
        vaultEntriesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await _eventuallyAsync(
        () async => (await harness.entryIds()).contains('single-remote'),
        reason: 'the first synchronization should import the remote entry',
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        cloud.listCalls,
        1,
        reason: 'the local refresh must not schedule another cloud manifest',
      );
    },
  );

  test(
    'in-flight invalidations coalesce into one trailing synchronization',
    () async {
      final cloud = _LifecycleCloudGateway(stallFirstList: true);
      final harness = await _ProviderHarness.create(cloud);
      addTearDown(harness.close);
      final subscription = harness.container.listen(
        vaultEntriesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await _eventually(
        () => cloud.listCalls == 1,
        reason: 'the first cloud reconciliation should start',
      );
      for (var index = 0; index < 3; index += 1) {
        harness.container.invalidate(vaultEntriesProvider);
        await harness.container.read(vaultEntriesProvider.future);
      }

      cloud.completeFirstList();
      await _eventually(
        () => cloud.listCalls == 2,
        reason: 'one trailing reconciliation should consume every trigger',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        cloud.listCalls,
        2,
        reason: 'N in-flight triggers must result in exactly one trailing run',
      );
    },
  );

  test('a stalled gateway scope cannot starve its replacement scope', () async {
    final first = _LifecycleCloudGateway(stallFirstList: true);
    final second = _LifecycleCloudGateway();
    final harness = await _ProviderHarness.create(first);
    addTearDown(harness.close);
    final subscription = harness.container.listen(
      vaultEntriesProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await _eventually(
      () => first.listCalls == 1,
      reason: 'the first scope should begin reconciliation',
    );
    await harness.switchCloud(second);

    await _eventually(
      () => second.listCalls == 1,
      reason: 'the replacement scope must not wait for the stalled scope',
    );
    expect(first.listCalls, 1);
  });

  test('an in-place account switch makes the old scope stale', () async {
    final cloud = _LifecycleCloudGateway(stallFirstList: true);
    await cloud.addRemote(id: 'old-account-entry', bytes: [0x41, 0x42]);
    final harness = await _ProviderHarness.create(cloud);
    addTearDown(harness.close);
    final subscription = harness.container.listen(
      vaultEntriesProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await _eventually(
      () => cloud.listCalls == 1,
      reason: 'the original account scope should begin its manifest',
    );
    cloud.setAccountId('account-2');
    cloud.completeFirstList();
    cloud.signalChange();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(cloud.downloadCalls, 0);
    expect(cloud.listCalls, 1);
    expect(await harness.entryIds(), isNot(contains('old-account-entry')));
  });

  test('a family and member switch starts an independent worker', () async {
    final cloud = _LifecycleCloudGateway(stallFirstList: true);
    final harness = await _ProviderHarness.create(cloud);
    addTearDown(harness.close);
    final subscription = harness.container.listen(
      vaultEntriesProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await _eventually(
      () => cloud.listCalls == 1,
      reason: 'the original family scope should begin its manifest',
    );
    await harness.switchIdentity(_replacementIdentity);

    await _eventually(
      () =>
          cloud.listCalls == 2 &&
          cloud.listedFamilyIds.last == _replacementIdentity.familyId,
      reason: 'the replacement family must not wait for the old manifest',
    );
    expect(cloud.listedFamilyIds, [
      _identity.familyId,
      _replacementIdentity.familyId,
    ]);
  });

  test('an account mismatch leaves cached rows offline', () async {
    final cloud = _LifecycleCloudGateway(accountId: 'different-account');
    final harness = await _ProviderHarness.create(cloud);
    addTearDown(harness.close);

    final entries = await harness.container.read(vaultEntriesProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(entries.map((entry) => entry.id), ['cached-journal']);
    expect(cloud.listCalls, 0);
    expect(cloud.watchCalls, 0);
  });

  test(
    'a stale manifest cannot start a download after a scope switch',
    () async {
      final first = _LifecycleCloudGateway(stallFirstList: true);
      await first.addRemote(id: 'stale-list-entry', bytes: [1, 2, 3]);
      final second = _LifecycleCloudGateway();
      final harness = await _ProviderHarness.create(first);
      addTearDown(harness.close);
      final subscription = harness.container.listen(
        vaultEntriesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await _eventually(
        () => first.listCalls == 1,
        reason: 'the first manifest should be pending',
      );
      await harness.switchCloud(second);
      first.completeFirstList();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(first.downloadCalls, 0);
      expect(await harness.entryIds(), isNot(contains('stale-list-entry')));
    },
  );

  test('a stale download cannot import after a scope switch', () async {
    final first = _LifecycleCloudGateway(stallFirstDownload: true);
    await first.addRemote(id: 'stale-download-entry', bytes: [4, 5, 6]);
    final second = _LifecycleCloudGateway();
    final harness = await _ProviderHarness.create(first);
    addTearDown(harness.close);
    final subscription = harness.container.listen(
      vaultEntriesProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await _eventually(
      () => first.downloadCalls == 1,
      reason: 'the first scope should await its download',
    );
    await harness.switchCloud(second);
    first.completeFirstDownload();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(await harness.entryIds(), isNot(contains('stale-download-entry')));
  });

  test(
    'an event after a manifest snapshot is recovered by one trailing sync',
    () async {
      final cloud = _LifecycleCloudGateway(stallFirstDownload: true);
      await cloud.addRemote(id: 'first-remote', bytes: [7, 8, 9]);
      final harness = await _ProviderHarness.create(cloud);
      addTearDown(harness.close);
      final subscription = harness.container.listen(
        vaultEntriesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await _eventually(
        () => cloud.downloadCalls == 1,
        reason: 'the first manifest snapshot should reach download',
      );
      await cloud.addRemote(id: 'late-remote', bytes: [10, 11, 12]);
      cloud.signalChange();
      await harness.container.pump();
      await harness.container.read(vaultEntriesProvider.future);
      for (var index = 0; index < 3; index += 1) {
        harness.container.invalidate(vaultEntriesProvider);
        await harness.container.read(vaultEntriesProvider.future);
      }
      expect(cloud.listCalls, 1);

      cloud.completeFirstDownload();
      await _eventually(
        () => cloud.listCalls == 2,
        reason: 'all in-flight triggers should produce one trailing manifest',
      );
      await _eventually(
        () => cloud.downloadCalls == 2,
        reason: 'the trailing manifest should download the late entry',
      );
      await _eventuallyAsync(
        () async => (await harness.entryIds()).contains('late-remote'),
        reason: 'the late remote entry should become durable locally',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(cloud.listCalls, 2);
      expect(
        await harness.entryIds(),
        containsAll(['first-remote', 'late-remote']),
      );
    },
  );

  test('watch errors back off until a healthy stream recovers', () async {
    final uncaught = <Object>[];
    late _ProviderHarness harness;
    late List<VaultEntryMetadata> entries;
    late ProviderSubscription<AsyncValue<List<VaultEntryMetadata>>>
    subscription;
    await runZonedGuarded(() async {
      final cloud = _LifecycleCloudGateway();
      harness = await _ProviderHarness.create(cloud);
      subscription = harness.container.listen(
        vaultEntriesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      entries = await harness.container.read(vaultEntriesProvider.future);
      await _eventually(
        () => cloud.listCalls == 1,
        reason: 'the initial authoritative manifest should complete',
      );

      cloud.controllers.single.addError(StateError('realtime unavailable'));
      await _eventually(
        () => cloud.watchCalls == 2,
        reason: 'the first backoff should replace the failed stream',
      );
      cloud.controllers[1].addError(StateError('still unavailable'));
      await _eventually(
        () => cloud.watchCalls == 3,
        reason: 'the second failure should schedule another replacement',
      );
      await _eventually(
        () => cloud.listCalls >= 3,
        reason: 'each rebind should request an authoritative manifest',
      );
      cloud.controllers[2].add(null);
      await _eventually(
        () => cloud.listCalls >= 4,
        reason: 'a healthy event should request another manifest',
      );
    }, (error, _) => uncaught.add(error));
    addTearDown(subscription.close);
    addTearDown(harness.close);

    expect(uncaught, isEmpty);
    expect(entries.map((entry) => entry.id), ['cached-journal']);
    expect(harness.cloud.watchCalls, 3);
    expect(
      (await harness.container.read(vaultEntriesProvider.future)).single.id,
      'cached-journal',
    );
  });

  test('events from a replaced gateway scope are ignored', () async {
    final first = _LifecycleCloudGateway(stallFirstList: true);
    final second = _LifecycleCloudGateway();
    final harness = await _ProviderHarness.create(first);
    addTearDown(harness.close);
    final subscription = harness.container.listen(
      vaultEntriesProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await _eventually(
      () => first.listCalls == 1 && first.watchCalls == 1,
      reason: 'the first scope should own the initial worker and watch',
    );
    await harness.switchCloud(second);
    await _eventually(
      () => second.listCalls == 1 && second.watchCalls == 1,
      reason: 'the replacement scope should own a fresh worker and watch',
    );
    final replacementLists = second.listCalls;

    first.signalChange();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(second.listCalls, replacementLists);
  });

  test('watch completion causes a delayed rebind', () async {
    final uncaught = <Object>[];
    late _ProviderHarness harness;
    late List<VaultEntryMetadata> entries;
    late ProviderSubscription<AsyncValue<List<VaultEntryMetadata>>>
    subscription;
    await runZonedGuarded(() async {
      final cloud = _LifecycleCloudGateway();
      harness = await _ProviderHarness.create(cloud);
      subscription = harness.container.listen(
        vaultEntriesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      entries = await harness.container.read(vaultEntriesProvider.future);

      await cloud.controllers.single.close();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }, (error, _) => uncaught.add(error));
    addTearDown(subscription.close);
    addTearDown(harness.close);

    expect(uncaught, isEmpty);
    expect(entries.map((entry) => entry.id), ['cached-journal']);
    expect(harness.cloud.watchCalls, 2);
    expect(
      (await harness.container.read(vaultEntriesProvider.future)).single.id,
      'cached-journal',
    );
  });

  test('disposing the provider scope cancels a pending watch retry', () async {
    final cloud = _LifecycleCloudGateway();
    final harness = await _ProviderHarness.create(cloud);
    addTearDown(harness.close);
    final subscription = harness.container.listen(
      vaultEntriesProvider,
      (_, _) {},
      fireImmediately: true,
    );
    await harness.container.read(vaultEntriesProvider.future);

    cloud.controllers.single.addError(StateError('realtime unavailable'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    subscription.close();
    harness.container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(cloud.watchCalls, 1);
  });
}

Future<void> _eventually(
  bool Function() condition, {
  required String reason,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: reason);
}

Future<void> _eventuallyAsync(
  Future<bool> Function() condition, {
  required String reason,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  var matched = await condition();
  while (!matched && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    matched = await condition();
  }
  expect(matched, isTrue, reason: reason);
}

final class _ProviderHarness {
  const _ProviderHarness._({
    required this.container,
    required this.gateways,
    required this.identities,
    required this.database,
    required this.root,
  });

  final ProviderContainer container;
  final _GatewaySelection gateways;
  final _IdentitySelection identities;
  final Database database;
  final Directory root;

  _LifecycleCloudGateway get cloud => gateways.current;

  static Future<_ProviderHarness> create(_LifecycleCloudGateway cloud) async {
    final root = await Directory.systemTemp.createTemp('vault-provider-');
    final support = Directory(p.join(root.path, 'support'));
    final capture = Directory(p.join(root.path, 'capture'));
    await support.create(recursive: true);
    await capture.create(recursive: true);
    final database = await databaseFactoryFfi.openDatabase(
      p.join(root.path, 'keepers-test.db'),
    );
    await database.execute('''
CREATE TABLE entries (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  author_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  entry_type TEXT NOT NULL,
  privacy_tier TEXT NOT NULL,
  blob_ref TEXT NOT NULL,
  transcript TEXT,
  embedding BLOB,
  state TEXT NOT NULL DEFAULT 'pending',
  expires_at INTEGER,
  revealed_at INTEGER,
  kept_at INTEGER
)
''');
    await database.insert('entries', {
      'id': 'cached-journal',
      'family_id': _identity.familyId,
      'author_id': _identity.memberId,
      'created_at': DateTime.utc(2026, 9, 8, 12).millisecondsSinceEpoch,
      'entry_type': MemoryFormat.text.name,
      'privacy_tier': PrivacyTier.journal.storageValue,
      'blob_ref': 'entries/blobs/cached-journal.keeper',
      'state': 'pending',
    });
    final blobStore = EncryptedBlobStore(
      support,
      captureTemporaryDirectory: capture,
      fileSystem: TestSecureBlobFileSystem(
        supportDirectory: support,
        captureTemporaryDirectory: capture,
      ),
    );
    final gateways = _GatewaySelection(cloud);
    final identities = _IdentitySelection(_identity);
    final container = ProviderContainer(
      overrides: [
        localIdentityProvider.overrideWith((ref) async => identities.current),
        databaseProvider.overrideWithValue(AsyncValue.data(database)),
        entryBlobStoreProvider.overrideWithValue(AsyncValue.data(blobStore)),
        initialCloudFamilyGatewayProvider.overrideWithValue(cloud),
        cloudFamilyGatewayLoaderProvider.overrideWithValue(gateways.load),
        familyRosterProvider(_identity.familyId).overrideWithBuild(
          (ref, notifier) => FamilyRosterState(hasLoadedLocal: true),
        ),
        familyRosterProvider(_replacementIdentity.familyId).overrideWithBuild(
          (ref, notifier) => FamilyRosterState(hasLoadedLocal: true),
        ),
      ],
    );
    return _ProviderHarness._(
      container: container,
      gateways: gateways,
      identities: identities,
      database: database,
      root: root,
    );
  }

  Future<void> switchCloud(_LifecycleCloudGateway next) async {
    gateways.select(next);
    await container.read(cloudFamilyGatewayStateProvider.notifier).reload();
  }

  Future<void> switchIdentity(LocalIdentity next) async {
    identities.select(next);
    container.invalidate(localIdentityProvider);
    await container.read(localIdentityProvider.future);
  }

  Future<Set<String>> entryIds() async {
    final rows = await database.query('entries', columns: const ['id']);
    return {for (final row in rows) row['id']! as String};
  }

  Future<void> close() async {
    container.dispose();
    for (final gateway in gateways.all) {
      gateway.completeFirstList();
      gateway.completeFirstDownload();
      await gateway.close();
    }
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

final class _IdentitySelection {
  _IdentitySelection(this.current);

  LocalIdentity current;

  void select(LocalIdentity next) => current = next;
}

final class _GatewaySelection {
  _GatewaySelection(this.current) : all = [current];

  _LifecycleCloudGateway current;
  final List<_LifecycleCloudGateway> all;

  Future<CloudFamilyGateway?> load() async => current;

  void select(_LifecycleCloudGateway next) {
    current = next;
    if (!all.contains(next)) all.add(next);
  }
}

final class _LifecycleCloudGateway
    implements CloudFamilyGateway, WeeklyRevealCloudGateway {
  _LifecycleCloudGateway({
    bool stallFirstList = false,
    bool stallFirstDownload = false,
    this.accountId = 'account-1',
  }) : _firstList = stallFirstList
           ? Completer<List<RemoteWeeklyRevealEntry>>()
           : null,
       _firstDownload = stallFirstDownload ? Completer<void>() : null;

  final Completer<List<RemoteWeeklyRevealEntry>>? _firstList;
  final Completer<void>? _firstDownload;
  String? accountId;
  final List<StreamController<void>> controllers = [];
  final List<RemoteWeeklyRevealEntry> _remote = [];
  final Map<String, Uint8List> _remoteBytes = {};
  int listCalls = 0;
  int watchCalls = 0;
  int downloadCalls = 0;
  final List<String> listedFamilyIds = [];

  @override
  String? get authenticatedAccountId => accountId;

  @override
  String? get authenticatedEmail => 'keeper@example.com';

  @override
  bool get isConfigured => true;

  @override
  Future<List<RemoteWeeklyRevealEntry>> list(String familyId) async {
    listCalls += 1;
    listedFamilyIds.add(familyId);
    final first = _firstList;
    if (listCalls == 1 && first != null) await first.future;
    return List<RemoteWeeklyRevealEntry>.unmodifiable(
      _remote.where((entry) => entry.metadata.familyId == familyId),
    );
  }

  @override
  Future<void> publish(EntryMetadata metadata, Uint8List encryptedBlob) async {}

  @override
  Future<Uint8List> download(RemoteWeeklyRevealEntry entry) async {
    downloadCalls += 1;
    final first = _firstDownload;
    if (downloadCalls == 1 && first != null) await first.future;
    final bytes = _remoteBytes[entry.metadata.id];
    if (bytes == null) throw StateError('Remote entry is unavailable');
    return Uint8List.fromList(bytes);
  }

  @override
  Stream<void> watch(String familyId) {
    watchCalls += 1;
    final controller = StreamController<void>.broadcast();
    controllers.add(controller);
    return controller.stream;
  }

  void completeFirstList() {
    final first = _firstList;
    if (first != null && !first.isCompleted) {
      first.complete(List<RemoteWeeklyRevealEntry>.of(_remote));
    }
  }

  void completeFirstDownload() {
    final first = _firstDownload;
    if (first != null && !first.isCompleted) first.complete();
  }

  void setAccountId(String? nextAccountId) => accountId = nextAccountId;

  Future<void> addRemote({required String id, required List<int> bytes}) async {
    final encrypted = Uint8List.fromList(bytes);
    final digest = base64UrlEncode((await Sha256().hash(encrypted)).bytes)
        .replaceAll('=', '');
    _remote.add(
      RemoteWeeklyRevealEntry(
        metadata: EntryMetadata(
          id: id,
          familyId: _identity.familyId,
          authorId: 'remote-member',
          createdAt: DateTime.utc(2026, 9, 8, 13),
          format: MemoryFormat.photo,
          privacy: PrivacyTier.reveal,
        ),
        storagePath: '${_identity.familyId}/remote-member/$id.keeper',
        blobSha256: digest,
        blobBytes: encrypted.lengthInBytes,
        state: 'pending',
      ),
    );
    _remoteBytes[id] = encrypted;
  }

  void signalChange() {
    final active = controllers.lastWhere((controller) => !controller.isClosed);
    active.add(null);
  }

  Future<void> close() async {
    for (final controller in controllers) {
      if (!controller.isClosed) await controller.close();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

const _identity = LocalIdentity(
  familyId: 'family-1',
  familyName: 'Keepers',
  familyKeyRef: 'family-key-1',
  memberId: 'member-1',
  memberName: 'Christian',
  memberKeyRef: 'member-key-1',
  colorToken: 'ochre',
  avatar: AvatarConfig.defaults(seed: 'member-1'),
  accountId: 'account-1',
);

const _replacementIdentity = LocalIdentity(
  familyId: 'family-2',
  familyName: 'Second Keepers family',
  familyKeyRef: 'family-key-2',
  memberId: 'member-2',
  memberName: 'Maria',
  memberKeyRef: 'member-key-2',
  colorToken: 'sea',
  avatar: AvatarConfig.defaults(seed: 'member-2'),
  accountId: 'account-1',
);
