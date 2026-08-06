import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keepers/features/capture/data/encrypted_blob_store.dart';
import 'package:keepers/features/capture/data/entry_cipher.dart';
import 'package:keepers/features/capture/data/entry_key_resolver.dart';
import 'package:keepers/features/capture/data/entry_payload_codec.dart';
import 'package:keepers/features/capture/data/entry_persistence_service.dart';
import 'package:keepers/features/capture/data/entry_repository.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'maintained mobile ABI saves, reloads, and decrypts production storage',
    (_) async {
      const expectedAbiName = String.fromEnvironment('EXPECTED_POSIX_ABI');
      expect(expectedAbiName, isNotEmpty);
      expect(currentPosixNativeAbi().name, expectedAbiName);
      expect(Platform.isAndroid || Platform.isIOS, isTrue);
      final expectedDartAbi = Platform.isAndroid
          ? Abi.androidX64
          : Abi.iosArm64;
      expect(Abi.current(), expectedDartAbi);

      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final supportBase = await getApplicationSupportDirectory();
      final temporaryBase = await getTemporaryDirectory();
      final support = Directory(
        p.join(supportBase.path, 'task-5-mobile-smoke-$suffix'),
      )..createSync();
      final capture = Directory(
        p.join(temporaryBase.path, 'task-5-mobile-smoke-$suffix'),
      )..createSync();
      addTearDown(() async {
        if (support.existsSync()) {
          await support.delete(recursive: true);
        }
        if (capture.existsSync()) {
          await capture.delete(recursive: true);
        }
      });

      final databasePath = p.join(support.path, 'keepers-smoke.db');
      var database = await _openEntryDatabase(databasePath);
      addTearDown(() async {
        if (database.isOpen) {
          await database.close();
        }
      });

      final keyBytes = List<int>.generate(32, (index) => index + 1);
      final secureValues = _MemorySecureValueStore()
        ..values['family-key'] = base64UrlEncode(keyBytes)
        ..values['member-key'] = base64UrlEncode(keyBytes.reversed.toList());
      const identity = LocalIdentity(
        familyId: 'family-mobile-smoke',
        familyName: 'Mobile family',
        familyKeyRef: 'family-key',
        memberId: 'member-mobile-smoke',
        memberName: 'Mobile member',
        memberKeyRef: 'member-key',
        colorToken: 'ochre',
      );
      final metadata = EntryMetadata(
        id: 'mobile-smoke-$suffix',
        familyId: identity.familyId,
        authorId: identity.memberId,
        createdAt: DateTime.utc(2026, 9, 1, 12),
        format: MemoryFormat.text,
        privacy: PrivacyTier.reveal,
      );
      const payload = EntryPayload(
        format: MemoryFormat.text,
        primaryBytes: null,
        text: 'mobile persistence secret',
        caption: 'encrypted mobile caption',
        mediaExtension: null,
        mediaDurationMs: null,
      );
      final plaintext = File(p.join(capture.path, 'source-$suffix.txt'))
        ..writeAsStringSync(payload.text!, flush: true);
      final blobStore = EncryptedBlobStore(
        support,
        captureTemporaryDirectory: capture,
      );
      final cipher = EntryCipher();
      final service = EntryPersistenceService(
        codec: const EntryPayloadCodec(),
        keyResolver: EntryKeyResolver(IdentityKeyService(secureValues)),
        cipher: cipher,
        blobStore: blobStore,
        repository: EntryRepository(),
        database: () async => database,
      );

      final saved = await service.save(
        EntrySaveRequest(
          metadata: metadata,
          payload: payload,
          identity: identity,
          plaintextRefs: [CapturePlaintextRef(p.basename(plaintext.path))],
        ),
      );

      expect(saved.blobRef, isNotNull);
      expect(plaintext.existsSync(), isFalse);
      final rows = await database.query('entries');
      expect(rows, hasLength(1));
      expect(rows.single['blob_ref'], saved.blobRef);
      expect(rows.single['transcript'], isNull);
      expect(rows.single['embedding'], isNull);
      final encrypted = await blobStore.read(saved.blobRef!);
      final wireText = utf8.decode(encrypted);
      expect(wireText, isNot(contains(payload.text!)));
      expect(wireText, isNot(contains(payload.caption!)));

      await database.close();
      final databaseWireText = utf8.decode(
        await File(databasePath).readAsBytes(),
        allowMalformed: true,
      );
      expect(databaseWireText, isNot(startsWith('SQLite format 3')));
      expect(databaseWireText, isNot(contains(payload.text!)));
      expect(databaseWireText, isNot(contains(payload.caption!)));
      database = await _openEntryDatabase(databasePath);
      final reopenedRows = await database.query('entries');
      expect(reopenedRows, hasLength(1));
      final reopenedStore = EncryptedBlobStore(
        support,
        captureTemporaryDirectory: capture,
      );
      final reopenedEnvelope = await reopenedStore.read(saved.blobRef!);
      final plaintextBytes = await cipher.decrypt(
        envelopeBytes: reopenedEnvelope,
        keyBytes: keyBytes,
        metadata: saved,
      );
      expect(const EntryPayloadCodec().decode(plaintextBytes), payload);
    },
  );
}

Future<Database> _openEntryDatabase(String path) {
  return openDatabase(
    path,
    password: 'task-5-mobile-smoke-password',
    version: 1,
    onCreate: (database, _) => database.execute('''
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
  state TEXT NOT NULL,
  expires_at INTEGER,
  revealed_at INTEGER,
  kept_at INTEGER
)
'''),
  );
}

final class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
