import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/data/encrypted_blob_store.dart';
import 'package:keepers/features/capture/data/entry_repository.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/data/vault_repository.dart';
import 'package:keepers/features/vault/data/weekly_reveal_cloud_gateway.dart';
import 'package:keepers/features/vault/data/weekly_reveal_sync_service.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../capture/data/test_secure_blob_file_system.dart';

void main() {
  sqfliteFfiInit();

  group('WeeklyRevealSyncService', () {
    late _FakeWeeklyRevealCloudGateway cloud;
    late _SyncDevice firstDevice;
    late _SyncDevice secondDevice;

    setUp(() async {
      cloud = _FakeWeeklyRevealCloudGateway();
      firstDevice = await _SyncDevice.create('weekly-sync-first-');
      secondDevice = await _SyncDevice.create('weekly-sync-second-');
    });

    tearDown(() async {
      await firstDevice.close();
      await secondDevice.close();
      await cloud.close();
    });

    test('a local Weekly Reveal is pushed and another device imports its encrypted blob and metadata once', () async {
      final encryptedBlob = Uint8List.fromList(const [
        0x6b,
        0x65,
        0x65,
        0x70,
        0x65,
        0x72,
        0x01,
        0x9d,
        0x42,
      ]);
      final metadata = _metadata(
        id: 'reveal-photo-1',
        identity: _firstIdentity,
        privacy: PrivacyTier.reveal,
      );
      await firstDevice.seed(metadata, encryptedBlob);

      await firstDevice.service(cloud).synchronize(_firstIdentity);
      await secondDevice.service(cloud).synchronize(_secondIdentity);

      final imported = await secondDevice.listLocal(_familyId);
      expect(imported, hasLength(1));
      expect(imported.single.id, 'reveal-photo-1');
      expect(imported.single.familyId, _familyId);
      expect(imported.single.authorId, _firstMemberId);
      expect(imported.single.format, MemoryFormat.photo);
      expect(imported.single.privacy, PrivacyTier.reveal);
      expect(imported.single.state, 'pending');
      expect(imported.single.createdAt, DateTime.utc(2026, 9, 8, 10));
      expect(
        await secondDevice.readLocalBlob(imported.single.blobRef),
        orderedEquals(encryptedBlob),
      );

      await secondDevice.service(cloud).synchronize(_secondIdentity);
      await firstDevice.service(cloud).synchronize(_firstIdentity);

      expect(await secondDevice.listLocal(_familyId), hasLength(1));
      expect(secondDevice.importAttempts, 1);
      expect(cloud.publishes, 1);
      expect(
        await secondDevice.readLocalBlob(imported.single.blobRef),
        orderedEquals(encryptedBlob),
      );
    });

    test('Private Journal entries never leave their author device', () async {
      final journalBlob = Uint8List.fromList(const [0x01, 0x02, 0x03]);
      await firstDevice.seed(
        _metadata(
          id: 'journal-photo-1',
          identity: _firstIdentity,
          privacy: PrivacyTier.journal,
        ),
        journalBlob,
      );

      await firstDevice.service(cloud).synchronize(_firstIdentity);
      await secondDevice.service(cloud).synchronize(_secondIdentity);

      expect(await firstDevice.listLocal(_familyId), hasLength(1));
      expect(await secondDevice.listLocal(_familyId), isEmpty);
      expect(await cloud.list(_familyId), isEmpty);
    });

    test(
      'a remote entry for another family is ignored before download',
      () async {
        final wrongFamily = _metadata(
          id: 'wrong-family-photo',
          identity: _firstIdentity,
          privacy: PrivacyTier.reveal,
          familyId: 'family-other',
        );
        final bytes = Uint8List.fromList(const [0x10, 0x20, 0x30]);
        await cloud.injectListing(
          requestedFamilyId: _familyId,
          metadata: wrongFamily,
          bytes: bytes,
        );

        await secondDevice.service(cloud).synchronize(_secondIdentity);

        expect(await secondDevice.listLocal(_familyId), isEmpty);
        expect(secondDevice.importAttempts, 0);
        expect(cloud.downloads, 0);
      },
    );

    test(
      'a malformed same-family record cannot suppress a valid local upload',
      () async {
        final metadata = _metadata(
          id: 'local-photo-with-collision',
          identity: _firstIdentity,
          privacy: PrivacyTier.reveal,
        );
        final localBytes = Uint8List.fromList(const [0x31, 0x32, 0x33]);
        await firstDevice.seed(metadata, localBytes);
        await cloud.injectListing(
          requestedFamilyId: _familyId,
          metadata: metadata,
          bytes: Uint8List.fromList(const [0x41, 0x42, 0x43]),
          state: 'kept',
        );

        await firstDevice.service(cloud).synchronize(_firstIdentity);

        expect(cloud.publishes, 1);
      },
    );

    test('a downloaded blob with the wrong SHA-256 is not imported', () async {
      final metadata = _metadata(
        id: 'corrupt-photo',
        identity: _firstIdentity,
        privacy: PrivacyTier.reveal,
      );
      await cloud.injectListing(
        requestedFamilyId: _familyId,
        metadata: metadata,
        bytes: Uint8List.fromList(const [0xaa, 0xbb, 0xcc]),
        downloadedBytes: Uint8List.fromList(const [0xaa, 0xbb, 0xcd]),
      );

      await secondDevice.service(cloud).synchronize(_secondIdentity);

      expect(await secondDevice.listLocal(_familyId), isEmpty);
      expect(secondDevice.importAttempts, 0);
      expect(await secondDevice.blobExistsFor('corrupt-photo'), isFalse);
    });

    test(
      'an offline cloud failure leaves the local row and blob intact',
      () async {
        final encryptedBlob = Uint8List.fromList(const [
          0xde,
          0xad,
          0xbe,
          0xef,
        ]);
        final metadata = _metadata(
          id: 'offline-photo',
          identity: _firstIdentity,
          privacy: PrivacyTier.reveal,
        );
        final saved = await firstDevice.seed(metadata, encryptedBlob);
        cloud.online = false;

        try {
          await firstDevice.service(cloud).synchronize(_firstIdentity);
        } on Object {
          // Reporting versus swallowing transport failure is a presentation
          // decision. The durability contract is that local state survives.
        }

        final local = await firstDevice.listLocal(_familyId);
        expect(local, hasLength(1));
        expect(local.single.id, 'offline-photo');
        expect(
          await firstDevice.readLocalBlob(saved.blobRef!),
          orderedEquals(encryptedBlob),
        );
      },
    );

    test(
      'an oversized local blob is skipped while a later entry still syncs',
      () async {
        final oversized = await firstDevice.seed(
          _metadata(
            id: 'z-oversized-photo',
            identity: _firstIdentity,
            privacy: PrivacyTier.reveal,
          ),
          Uint8List.fromList(const [0x01]),
        );
        final valid = await firstDevice.seed(
          _metadata(
            id: 'a-valid-photo',
            identity: _firstIdentity,
            privacy: PrivacyTier.reveal,
          ),
          Uint8List.fromList(const [0x02, 0x03]),
        );
        final reads = <({String blobRef, int? maxBytes})>[];

        Future<Uint8List> readBounded(String blobRef, {int? maxBytes}) async {
          reads.add((blobRef: blobRef, maxBytes: maxBytes));
          if (blobRef == oversized.blobRef) {
            throw FileSystemException(
              'Encrypted blob exceeds bounded read limit',
              blobRef,
            );
          }
          return firstDevice.blobStore.read(blobRef, maxBytes: maxBytes);
        }

        final service = WeeklyRevealSyncService(
          cloud: cloud,
          listLocal: firstDevice.listLocal,
          readLocalBlob: readBounded,
          importRemote: firstDevice.importRemote,
        );

        await service.synchronize(_firstIdentity);

        expect(reads, [
          (blobRef: oversized.blobRef!, maxBytes: 25 * 1024 * 1024),
          (blobRef: valid.blobRef!, maxBytes: 25 * 1024 * 1024),
        ]);
        expect(
          (await cloud.list(_familyId)).map((entry) => entry.metadata.id),
          ['a-valid-photo'],
        );
        expect(
          (await firstDevice.listLocal(_familyId)).map((entry) => entry.id),
          ['z-oversized-photo', 'a-valid-photo'],
        );
      },
    );
  });
}

const _familyId = 'family-1';
const _firstMemberId = 'member-1';

final _firstIdentity = LocalIdentity(
  familyId: _familyId,
  familyName: 'Shared family',
  familyKeyRef: 'family-key-1',
  memberId: _firstMemberId,
  memberName: 'Amina',
  memberKeyRef: 'member-key-1',
  colorToken: 'ochre',
  avatar: AvatarConfig.defaults(seed: _firstMemberId),
  accountId: 'account-1',
);

final _secondIdentity = LocalIdentity(
  familyId: _familyId,
  familyName: 'Shared family',
  familyKeyRef: 'family-key-1',
  memberId: 'member-2',
  memberName: 'Mariam',
  memberKeyRef: 'member-key-2',
  colorToken: 'sea',
  avatar: AvatarConfig.defaults(seed: 'member-2'),
  accountId: 'account-2',
);

EntryMetadata _metadata({
  required String id,
  required LocalIdentity identity,
  required PrivacyTier privacy,
  String? familyId,
}) => EntryMetadata(
  id: id,
  familyId: familyId ?? identity.familyId,
  authorId: identity.memberId,
  createdAt: DateTime.utc(2026, 9, 8, 10),
  format: MemoryFormat.photo,
  privacy: privacy,
);

final class _SyncDevice {
  _SyncDevice._({
    required this.root,
    required this.database,
    required this.blobStore,
  });

  final Directory root;
  final Database database;
  final EncryptedBlobStore blobStore;
  int importAttempts = 0;

  static Future<_SyncDevice> create(String prefix) async {
    final root = await Directory.systemTemp.createTemp(prefix);
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
    return _SyncDevice._(
      root: root,
      database: database,
      blobStore: EncryptedBlobStore(
        support,
        captureTemporaryDirectory: capture,
        fileSystem: TestSecureBlobFileSystem(
          supportDirectory: support,
          captureTemporaryDirectory: capture,
        ),
      ),
    );
  }

  WeeklyRevealSyncService service(WeeklyRevealCloudGateway cloud) =>
      WeeklyRevealSyncService(
        cloud: cloud,
        listLocal: listLocal,
        readLocalBlob: (blobRef, {required maxBytes}) =>
            blobStore.read(blobRef, maxBytes: maxBytes),
        importRemote: importRemote,
      );

  Future<EntryMetadata> seed(EntryMetadata metadata, Uint8List bytes) async {
    final staged = await blobStore.stage(metadata.id, bytes);
    final finalized = await blobStore.finalize(staged);
    await EntryRepository().insert(database, metadata, finalized.relativeRef);
    return metadata.copyWith(blobRef: finalized.relativeRef);
  }

  Future<List<VaultEntryMetadata>> listLocal(String familyId) =>
      VaultRepository().listForFamily(database, familyId);

  Future<Uint8List> readLocalBlob(String blobRef) => blobStore.read(blobRef);

  Future<void> importRemote(
    RemoteWeeklyRevealEntry remote,
    Uint8List bytes,
  ) async {
    importAttempts += 1;
    final metadata = remote.metadata;
    final staged = await blobStore.stage(metadata.id, bytes);
    final finalized = await blobStore.finalize(staged);
    try {
      await EntryRepository().insert(database, metadata, finalized.relativeRef);
    } on Object {
      await blobStore.rollback(finalized);
      rethrow;
    }
  }

  Future<bool> blobExistsFor(String entryId) =>
      blobStore.exists(p.join('entries', 'blobs', '$entryId.keeper'));

  Future<void> close() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

final class _FakeWeeklyRevealCloudGateway implements WeeklyRevealCloudGateway {
  final Map<String, _RemoteBlob> _records = {};
  final Map<String, List<RemoteWeeklyRevealEntry>> _extraListings = {};
  final Map<String, _RemoteBlob> _extraBlobs = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  bool online = true;
  int downloads = 0;
  int publishes = 0;

  @override
  Future<void> publish(EntryMetadata metadata, Uint8List bytes) async {
    _requireOnline();
    publishes += 1;
    final remoteMetadata = EntryMetadata(
      id: metadata.id,
      familyId: metadata.familyId,
      authorId: metadata.authorId,
      createdAt: metadata.createdAt,
      format: metadata.format,
      privacy: metadata.privacy,
    );
    _records[metadata.id] = _RemoteBlob(
      entry: RemoteWeeklyRevealEntry(
        metadata: remoteMetadata,
        storagePath: _storagePath(remoteMetadata),
        blobSha256: await _sha256Hex(bytes),
        blobBytes: bytes.lengthInBytes,
        state: 'pending',
      ),
      bytes: Uint8List.fromList(bytes),
    );
    _changes.add(null);
  }

  @override
  Future<List<RemoteWeeklyRevealEntry>> list(String familyId) async {
    _requireOnline();
    return [
      for (final record in _records.values)
        if (record.entry.metadata.familyId == familyId) record.entry,
      ...?_extraListings[familyId],
    ];
  }

  @override
  Future<Uint8List> download(RemoteWeeklyRevealEntry entry) async {
    _requireOnline();
    downloads += 1;
    final record =
        _records[entry.metadata.id] ?? _extraBlobs[entry.metadata.id];
    if (record == null) throw StateError('Remote entry is unavailable');
    return Uint8List.fromList(record.bytes);
  }

  @override
  Stream<void> watch(String familyId) => _changes.stream;

  Future<void> injectListing({
    required String requestedFamilyId,
    required EntryMetadata metadata,
    required Uint8List bytes,
    Uint8List? downloadedBytes,
    String state = 'pending',
  }) async {
    final entry = RemoteWeeklyRevealEntry(
      metadata: metadata,
      storagePath: _storagePath(metadata),
      blobSha256: await _sha256Hex(bytes),
      blobBytes: bytes.lengthInBytes,
      state: state,
    );
    (_extraListings[requestedFamilyId] ??= []).add(entry);
    _extraBlobs[metadata.id] = _RemoteBlob(
      entry: entry,
      bytes: Uint8List.fromList(downloadedBytes ?? bytes),
    );
  }

  void _requireOnline() {
    if (!online) throw StateError('offline');
  }

  Future<void> close() => _changes.close();
}

final class _RemoteBlob {
  const _RemoteBlob({required this.entry, required this.bytes});

  final RemoteWeeklyRevealEntry entry;
  final Uint8List bytes;
}

Future<String> _sha256Hex(Uint8List bytes) async {
  final digest = await Sha256().hash(bytes);
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}

String _storagePath(EntryMetadata metadata) =>
    '${metadata.familyId}/${metadata.authorId}/${metadata.id}.keeper';
