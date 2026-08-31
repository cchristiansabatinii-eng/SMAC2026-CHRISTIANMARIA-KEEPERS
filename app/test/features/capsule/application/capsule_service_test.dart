import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capsule/application/capsule_providers.dart';
import 'package:keepers/features/capsule/application/capsule_service.dart';
import 'package:keepers/features/capsule/data/capsule_repository.dart';
import 'package:keepers/features/capsule/domain/capsule_models.dart';
import 'package:keepers/features/capture/application/capture_providers.dart';
import 'package:keepers/features/capture/data/entry_cipher.dart';
import 'package:keepers/features/capture/data/entry_key_resolver.dart';
import 'package:keepers/features/capture/data/entry_payload_codec.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/vault/application/vault_controller.dart';
import 'package:keepers/features/vault/data/vault_repository.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/storage/schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late _CapsuleHarness harness;

  setUp(() async => harness = await _CapsuleHarness.create());
  tearDown(() => harness.close());

  test('missing assignment is unavailable before key or blob access', () async {
    final repository = _ReturningCapsuleRepository(null);

    final result = await harness
        .service(repository)
        .openForCurrentMember('missing-assignment');

    _expectUnavailable(result);
    harness.expectNoDecrypt(repository);
  });

  test('locked assignment is unavailable before key or blob access', () async {
    final repository = _ReturningCapsuleRepository(
      _assignment(state: CapsuleAssignmentState.locked),
    );

    final result = await harness
        .service(repository)
        .openForCurrentMember('capsule-1');

    _expectUnavailable(result);
    harness.expectNoDecrypt(repository);
  });

  test(
    'wrong-target assignment is unavailable before key or blob access',
    () async {
      final repository = _ReturningCapsuleRepository(
        _assignment(targetId: 'member-other'),
      );

      final result = await harness
          .service(repository)
          .openForCurrentMember('capsule-1');

      _expectUnavailable(result);
      harness.expectNoDecrypt(repository);
    },
  );

  test(
    'wrong-family assignment is unavailable before key or blob access',
    () async {
      final repository = _ReturningCapsuleRepository(
        _assignment(
          familyId: 'family-2',
          authorId: 'outsider',
          targetId: 'outsider',
        ),
      );

      final result = await harness
          .service(repository)
          .openForCurrentMember('capsule-1');

      _expectUnavailable(result);
      harness.expectNoDecrypt(repository);
    },
  );

  test(
    'missing canonical entry is unavailable before key or blob access',
    () async {
      final repository = _ReturningCapsuleRepository(
        _assignment(contentEntryId: 'missing-entry'),
      );

      final result = await harness
          .service(repository)
          .openForCurrentMember('capsule-1');

      _expectUnavailable(result);
      harness.expectNoDecrypt(repository);
    },
  );

  test(
    'cross-family entry link is unavailable before key or blob access',
    () async {
      await harness.insertEntry(
        id: 'outside-entry',
        familyId: 'family-2',
        authorId: 'outsider',
        privacy: PrivacyTier.capsule,
      );
      final repository = _ReturningCapsuleRepository(
        _assignment(contentEntryId: 'outside-entry'),
      );

      final result = await harness
          .service(repository)
          .openForCurrentMember('capsule-1');

      _expectUnavailable(result);
      harness.expectNoDecrypt(repository);
    },
  );

  test(
    'wrong-privacy entry is unavailable before key or blob access',
    () async {
      await harness.database.update(
        'entries',
        {'privacy_tier': PrivacyTier.reveal.storageValue},
        where: 'id = ?',
        whereArgs: ['entry-1'],
      );
      final repository = _ReturningCapsuleRepository(_assignment());

      final result = await harness
          .service(repository)
          .openForCurrentMember('capsule-1');

      _expectUnavailable(result);
      harness.expectNoDecrypt(repository);
    },
  );

  test('wrong-author entry is unavailable before key or blob access', () async {
    await harness.database.update(
      'entries',
      {'author_id': 'member-other'},
      where: 'id = ?',
      whereArgs: ['entry-1'],
    );
    final repository = _ReturningCapsuleRepository(_assignment());

    final result = await harness
        .service(repository)
        .openForCurrentMember('capsule-1');

    _expectUnavailable(result);
    harness.expectNoDecrypt(repository);
  });

  test('expired entry is unavailable before key or blob access', () async {
    await harness.database.update(
      'entries',
      {'expires_at': harness.now.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: ['entry-1'],
    );
    final repository = _ReturningCapsuleRepository(_assignment());

    final result = await harness
        .service(repository)
        .openForCurrentMember('capsule-1');

    _expectUnavailable(result);
    harness.expectNoDecrypt(repository);
  });

  test('ready and opened assignments decrypt canonical memory', () async {
    final repository = _ReturningCapsuleRepository(_assignment());

    for (final state in const [
      CapsuleAssignmentState.ready,
      CapsuleAssignmentState.opened,
    ]) {
      repository.assignment = _assignment(state: state);
      final result = await harness
          .service(repository)
          .openForCurrentMember('capsule-1');

      expect(result, isA<OpenedMemory>());
      expect((result as OpenedMemory).payload.text, 'Only in capsule');
    }
    expect(harness.openCalls, 2);
    expect(harness.keyStore.readCount, 2);
    expect(harness.blobReads, 2);
    expect(repository.markOpenedCalls, 2);
    expect(repository.lastOpenedAt, harness.now);
  });

  test('only a successful memory open marks the assignment opened', () async {
    final repository = _ReturningCapsuleRepository(_assignment());
    harness.failBlobRead = true;

    final result = await harness
        .service(repository)
        .openForCurrentMember('capsule-1');

    _expectUnavailable(result);
    expect(harness.openCalls, 1);
    expect(harness.keyStore.readCount, 1);
    expect(harness.blobReads, 1);
    expect(repository.markOpenedCalls, 0);
  });

  test(
    'mismatched opened metadata is wiped and never marks the assignment',
    () async {
      final repository = _ReturningCapsuleRepository(_assignment());
      final canonical = harness.canonicalMetadata;
      final mismatches = [
        canonical.copyWith(id: 'other-entry'),
        canonical.copyWith(familyId: 'family-2'),
        canonical.copyWith(privacy: PrivacyTier.journal),
        canonical.copyWith(blobRef: 'entries/blobs/other.keeper'),
      ];

      for (final mismatched in mismatches) {
        final bytes = Uint8List.fromList([7, 8, 9]);
        final service = harness.service(
          repository,
          openMemory: (_) async => OpenedMemory(
            metadata: mismatched,
            payload: EntryPayload(
              format: mismatched.format,
              primaryBytes: bytes,
              text: null,
              caption: null,
              mediaExtension: 'jpg',
              mediaDurationMs: null,
            ),
          ),
        );

        _expectUnavailable(await service.openForCurrentMember('capsule-1'));
        expect(bytes, everyElement(0));
      }
      expect(repository.markOpenedCalls, 0);
    },
  );

  test('failed opened transition wipes decrypted primary bytes', () async {
    for (final failure in <Object?>[null, StateError('mark opened failed')]) {
      final repository = _ReturningCapsuleRepository(_assignment())
        ..markOpenedResult = false
        ..markOpenedError = failure;
      final bytes = Uint8List.fromList([4, 5, 6]);
      final service = harness.service(
        repository,
        openMemory: (_) async => OpenedMemory(
          metadata: harness.canonicalMetadata,
          payload: EntryPayload(
            format: MemoryFormat.text,
            primaryBytes: bytes,
            text: null,
            caption: null,
            mediaExtension: null,
            mediaDurationMs: null,
          ),
        ),
      );

      _expectUnavailable(await service.openForCurrentMember('capsule-1'));
      expect(bytes, everyElement(0));
      expect(repository.markOpenedCalls, 1);
    }
  });

  test('each open reloads canonical assignment and entry state', () async {
    final repository = _ReturningCapsuleRepository(_assignment());

    expect(
      await harness.service(repository).openForCurrentMember('capsule-1'),
      isA<OpenedMemory>(),
    );
    await harness.database.update(
      'entries',
      {'privacy_tier': PrivacyTier.reveal.storageValue},
      where: 'id = ?',
      whereArgs: ['entry-1'],
    );

    _expectUnavailable(
      await harness.service(repository).openForCurrentMember('capsule-1'),
    );
    expect(repository.findCalls, 2);
    expect(harness.openCalls, 1);
    expect(harness.blobReads, 1);
  });

  test(
    'task completion persists and remains idempotent after reload',
    () async {
      const repository = CapsuleRepository();
      final assignments = await repository.insertAssignments(
        harness.database,
        entry: harness.entry,
        options: CapsuleSaveOptions(unlockTask: 'Tell one family story'),
      );
      final current = assignments.singleWhere(
        (assignment) => assignment.targetId == harness.identity.memberId,
      );
      final service = harness.service(repository);

      expect(await service.completeTask(current.id), isTrue);
      expect(await service.completeTask(current.id), isTrue);

      final reloaded = await repository.findForMember(
        harness.database,
        assignmentId: current.id,
        familyId: harness.identity.familyId,
        memberId: harness.identity.memberId,
      );
      expect(reloaded?.state, CapsuleAssignmentState.ready);
      expect(reloaded?.unlockTask, 'Tell one family story');
      harness.expectNoDecrypt();
    },
  );

  test(
    'assignments provider binds the query to the current local member',
    () async {
      const repository = CapsuleRepository();
      await repository.insertAssignments(
        harness.database,
        entry: harness.entry,
        options: CapsuleSaveOptions(),
      );
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncValue.data(harness.database)),
          localIdentityProvider.overrideWithValue(
            AsyncValue.data(harness.identity),
          ),
          capsuleRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final assignments = await container.read(
        capsuleAssignmentsProvider.future,
      );

      expect(assignments, hasLength(1));
      expect(assignments.single.familyId, harness.identity.familyId);
      expect(assignments.single.targetId, harness.identity.memberId);
    },
  );
}

void _expectUnavailable(MemoryOpenResult result) {
  expect(result, isA<UnavailableMemory>());
  expect(
    (result as UnavailableMemory).message,
    VaultController.unavailableMessage,
  );
}

CapsuleAssignment _assignment({
  String familyId = 'family-1',
  String authorId = 'member-1',
  String targetId = 'member-1',
  String contentEntryId = 'entry-1',
  CapsuleAssignmentState state = CapsuleAssignmentState.ready,
}) => CapsuleAssignment(
  id: 'capsule-1',
  familyId: familyId,
  authorId: authorId,
  targetId: targetId,
  contentEntryId: contentEntryId,
  unlockTask: state == CapsuleAssignmentState.locked
      ? 'Tell one family story'
      : null,
  state: state,
  createdAt: DateTime.utc(2026, 9, 1),
  openedAt: state == CapsuleAssignmentState.opened
      ? DateTime.utc(2026, 9, 7)
      : null,
);

final class _ReturningCapsuleRepository extends CapsuleRepository {
  _ReturningCapsuleRepository(this.assignment);

  CapsuleAssignment? assignment;
  int findCalls = 0;
  int markOpenedCalls = 0;
  DateTime? lastOpenedAt;
  bool markOpenedResult = true;
  Object? markOpenedError;

  @override
  Future<CapsuleAssignment?> findForMember(
    DatabaseExecutor db, {
    required String assignmentId,
    required String familyId,
    required String memberId,
  }) async {
    findCalls += 1;
    return assignment;
  }

  @override
  Future<bool> markOpened(
    DatabaseExecutor db, {
    required String assignmentId,
    required String familyId,
    required String memberId,
    required DateTime openedAt,
  }) async {
    markOpenedCalls += 1;
    lastOpenedAt = openedAt;
    final error = markOpenedError;
    if (error != null) throw error;
    return markOpenedResult;
  }
}

final class _CapsuleHarness {
  _CapsuleHarness({
    required this.database,
    required this.identity,
    required this.entry,
    required this.now,
    required this.keyStore,
    required this.envelope,
    required this.vaultController,
  });

  final Database database;
  final LocalIdentity identity;
  final EntryMetadata entry;
  final DateTime now;
  final _CountingSecureValueStore keyStore;
  final Uint8List envelope;
  final VaultController vaultController;
  int openCalls = 0;
  int blobReads = 0;
  bool failBlobRead = false;

  VaultEntryMetadata get canonicalMetadata => VaultEntryMetadata(
    id: entry.id,
    familyId: entry.familyId,
    authorId: entry.authorId,
    createdAt: entry.createdAt,
    format: entry.format,
    privacy: entry.privacy,
    blobRef: entry.blobRef!,
    state: 'pending',
  );

  static Future<_CapsuleHarness> create() async {
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
    for (final family in const [
      ('family-1', 'Sabati'),
      ('family-2', 'Other'),
    ]) {
      await database.insert('families', {
        'id': family.$1,
        'name': family.$2,
        'family_key_ref': '${family.$1}-key',
        'quorum': 1,
        'created_at': 1,
      });
    }
    for (final member in const [
      ('member-1', 'family-1', 1),
      ('member-other', 'family-1', 2),
      ('outsider', 'family-2', 1),
    ]) {
      await database.insert('members', {
        'id': member.$1,
        'family_id': member.$2,
        'name': member.$1,
        'role': 'adult',
        'member_key_ref': '${member.$1}-key',
        'color_token': 'ochre',
        'avatar_config_json': '{}',
        'created_at': member.$3,
      });
    }
    const identity = LocalIdentity(
      familyId: 'family-1',
      familyName: 'Sabati',
      familyKeyRef: 'family-key',
      memberId: 'member-1',
      memberName: 'Chris',
      memberKeyRef: 'member-key',
      colorToken: 'ochre',
      avatar: AvatarConfig.defaults(seed: 'member-1'),
    );
    final now = DateTime.utc(2026, 9, 8, 12);
    final entry = EntryMetadata(
      id: 'entry-1',
      familyId: identity.familyId,
      authorId: identity.memberId,
      createdAt: DateTime.utc(2026, 9, 1),
      format: MemoryFormat.text,
      privacy: PrivacyTier.capsule,
      blobRef: 'entries/blobs/entry-1.keeper',
    );
    await _insertEntry(database, entry);
    final key = List<int>.filled(32, 7);
    final codec = const EntryPayloadCodec();
    final cipher = EntryCipher(
      nonceFactory: () =>
          Uint8List.fromList(List<int>.generate(12, (index) => index)),
    );
    final envelope = await cipher.encrypt(
      plaintext: codec.encode(
        const EntryPayload(
          format: MemoryFormat.text,
          primaryBytes: null,
          text: 'Only in capsule',
          caption: null,
          mediaExtension: null,
          mediaDurationMs: null,
        ),
      ),
      keyBytes: key,
      metadata: entry,
      keyScope: EntryKeyScope.family,
    );
    final keyStore = _CountingSecureValueStore({
      identity.familyKeyRef: base64UrlEncode(key),
      identity.memberKeyRef: base64UrlEncode(List<int>.filled(32, 8)),
    });
    late _CapsuleHarness harness;
    final controller = VaultController(
      identity: identity,
      keyResolver: EntryKeyResolver(IdentityKeyService(keyStore)),
      cipher: cipher,
      codec: codec,
      utcNow: () => now,
      readEncryptedBlob: (relativeRef) async {
        harness.blobReads += 1;
        if (harness.failBlobRead) throw StateError('blob read failed');
        if (relativeRef != entry.blobRef) {
          throw ArgumentError.value(relativeRef, 'relativeRef');
        }
        return Uint8List.fromList(envelope);
      },
      readEncryptedBlobBounded: (relativeRef, {required maxBytes}) async {
        throw UnsupportedError('Capsule opens do not request previews');
      },
    );
    harness = _CapsuleHarness(
      database: database,
      identity: identity,
      entry: entry,
      now: now,
      keyStore: keyStore,
      envelope: envelope,
      vaultController: controller,
    );
    return harness;
  }

  CapsuleService service(
    CapsuleRepository repository, {
    CapsuleMemoryOpener? openMemory,
  }) => CapsuleService(
    database: database,
    identity: identity,
    capsuleRepository: repository,
    vaultRepository: VaultRepository(),
    openMemory:
        openMemory ??
        (metadata) {
          openCalls += 1;
          return vaultController.open(metadata);
        },
    utcNow: () => now,
  );

  Future<void> insertEntry({
    required String id,
    required String familyId,
    required String authorId,
    required PrivacyTier privacy,
  }) => _insertEntry(
    database,
    EntryMetadata(
      id: id,
      familyId: familyId,
      authorId: authorId,
      createdAt: DateTime.utc(2026, 9, 1),
      format: MemoryFormat.text,
      privacy: privacy,
      blobRef: 'entries/blobs/$id.keeper',
    ),
  );

  void expectNoDecrypt([_ReturningCapsuleRepository? repository]) {
    expect(openCalls, 0);
    expect(keyStore.readCount, 0);
    expect(blobReads, 0);
    expect(repository?.markOpenedCalls ?? 0, 0);
  }

  Future<void> close() => database.close();
}

Future<void> _insertEntry(Database database, EntryMetadata entry) =>
    database.insert('entries', {
      'id': entry.id,
      'family_id': entry.familyId,
      'author_id': entry.authorId,
      'created_at': entry.createdAt.millisecondsSinceEpoch,
      'entry_type': entry.format.name,
      'privacy_tier': entry.privacy.storageValue,
      'blob_ref': entry.blobRef,
      'state': 'pending',
    });

final class _CountingSecureValueStore implements SecureValueStore {
  _CountingSecureValueStore(this.values);

  final Map<String, String> values;
  int readCount = 0;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async {
    readCount += 1;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
