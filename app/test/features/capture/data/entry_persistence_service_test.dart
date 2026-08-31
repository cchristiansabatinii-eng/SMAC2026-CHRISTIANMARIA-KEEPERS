import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capsule/data/capsule_repository.dart';
import 'package:keepers/features/capsule/domain/capsule_models.dart';
import 'package:keepers/features/capture/data/encrypted_blob_store.dart';
import 'package:keepers/features/capture/data/entry_cipher.dart';
import 'package:keepers/features/capture/data/entry_key_resolver.dart';
import 'package:keepers/features/capture/data/entry_payload_codec.dart';
import 'package:keepers/features/capture/data/entry_persistence_service.dart';
import 'package:keepers/features/capture/data/entry_repository.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';
import 'package:keepers/features/onboarding/data/identity_key_service.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/database_key_store.dart';
import 'package:keepers/storage/schema.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_secure_blob_file_system.dart';

void main() {
  sqfliteFfiInit();
  final requiresPosix = Platform.isWindows
      ? 'The production encrypted-blob filesystem intentionally does not '
            'support Windows.'
      : false;

  group('encrypted blob lifecycle', () {
    test('same-ID staging attempts use distinct exclusive locations', () async {
      final roots = await _TestRoots.create('keepers-exclusive-stage-');
      addTearDown(roots.close);
      final store = testEncryptedBlobStore(roots.support, roots.capture);

      final first = await store.stage('entry-1', Uint8List.fromList([1]));
      final second = await store.stage('entry-1', Uint8List.fromList([2]));

      expect(first.file.path, isNot(second.file.path));
      expect(await first.file.readAsBytes(), [1]);
      expect(await second.file.readAsBytes(), [2]);
      expect(
        p.basename(first.attemptDirectory.path),
        isNot(contains('entry-1.part')),
      );
    });

    test(
      'concurrent same-ID finalization commits exactly one staged blob',
      () async {
        final roots = await _TestRoots.create('keepers-concurrent-');
        addTearDown(roots.close);
        final store = testEncryptedBlobStore(roots.support, roots.capture);
        final first = await store.stage('entry-1', Uint8List.fromList([1]));
        final second = await store.stage('entry-1', Uint8List.fromList([2]));

        final results = await Future.wait(
          [first, second].map((staged) async {
            try {
              return await store.finalize(staged);
            } catch (error) {
              return error;
            }
          }),
        );

        expect(results.whereType<FinalizedEncryptedBlob>(), hasLength(1));
        expect(
          results.where((result) => result is! FinalizedEncryptedBlob),
          hasLength(1),
        );
        final finalFile = File(
          p.join(roots.support.path, 'entries', 'blobs', 'entry-1.keeper'),
        );
        expect(await finalFile.readAsBytes(), anyOf(equals([1]), equals([2])));
      },
    );

    test('entry IDs reject platform-special and non-generated names', () async {
      final roots = await _TestRoots.create('keepers-special-id-');
      addTearDown(roots.close);
      final store = testEncryptedBlobStore(roots.support, roots.capture);

      for (final id in ['CON', 'name:stream', 'trailing.', 'has space']) {
        await expectLater(
          store.stage(id, Uint8List.fromList([1])),
          throwsArgumentError,
        );
      }
    });

    test('sibling-prefix encrypted references are rejected', () async {
      final roots = await _TestRoots.create('keepers-ref-prefix-');
      addTearDown(roots.close);
      final store = testEncryptedBlobStore(roots.support, roots.capture);

      expect(
        () => store.read(
          p.join('entries', 'blobs', '..', 'blobs-evil', 'entry-1.keeper'),
        ),
        throwsArgumentError,
      );
    });

    test('finalize and staging-cleanup failures are both retained', () async {
      final roots = await _TestRoots.create('keepers-finalize-cleanup-');
      addTearDown(roots.close);
      final store = testEncryptedBlobStore(
        roots.support,
        roots.capture,
        finalizeError: StateError('final commit failed'),
        blockAttemptCleanup: true,
      );
      final staged = await store.stage('entry-1', Uint8List.fromList([1]));

      EncryptedBlobStoreFailure? failure;
      try {
        await store.finalize(staged);
      } on EncryptedBlobStoreFailure catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      expect(failure!.primary.phase, EntrySavePhase.finalizeBlob);
      expect(failure.primary.error, isA<StateError>());
      expect(failure.additionalFailures.map((cause) => cause.phase), [
        EntrySavePhase.stagingCleanup,
      ]);
      expect(failure.publishedBlobRef, isNull);
      expect(failure.stagingMayRemain, isTrue);
      expect(
        File(p.join(roots.support.path, 'entries', 'blobs', 'entry-1.keeper'))
            .existsSync(),
        isFalse,
      );
      final stagedValue = staged.secure as TestStagedBlob;
      expect(File(stagedValue.attempt.path).existsSync(), isTrue);
    });

    test('finalize layout failure still cleans its staged attempt', () async {
      final roots = await _TestRoots.create('keepers-finalize-layout-');
      addTearDown(roots.close);
      final store = testEncryptedBlobStore(roots.support, roots.capture);
      final staged = await store.stage('entry-1', Uint8List.fromList([1]));
      final blobs = Directory(p.join(roots.support.path, 'entries', 'blobs'));
      await blobs.delete();
      await File(blobs.path).writeAsString('unsafe');

      EncryptedBlobStoreFailure? failure;
      try {
        await store.finalize(staged);
      } on EncryptedBlobStoreFailure catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      expect(failure!.primary.phase, EntrySavePhase.finalizeBlob);
      expect(failure.additionalFailures, isEmpty);
      expect(failure.stagingMayRemain, isFalse);
      expect(staged.attemptDirectory.existsSync(), isFalse);
    });

    test(
      'stages encrypted bytes, finalizes atomically, and rolls back',
      () async {
        final roots = await _TestRoots.create('keepers-blobs-');
        addTearDown(roots.close);
        final support = roots.support;
        final store = testEncryptedBlobStore(support, roots.capture);
        final encrypted = Uint8List.fromList([9, 8, 7]);

        final staging = await store.stage('entry-1', encrypted);
        expect(await staging.file.readAsBytes(), encrypted);

        final finalized = await store.finalize(staging);

        expect(
          finalized.relativeRef,
          p.join('entries', 'blobs', 'entry-1.keeper'),
        );
        expect(staging.attemptDirectory.existsSync(), isFalse);
        expect(await store.read(finalized.relativeRef), encrypted);

        await store.rollback(finalized);
        expect(await store.exists(finalized.relativeRef), isFalse);
        await expectLater(store.rollback(finalized), throwsArgumentError);
      },
    );

    test(
      'finalized rollback capability is bound to its creating store',
      () async {
        final roots = await _TestRoots.create('keepers-finalized-owner-');
        addTearDown(roots.close);
        final owner = testEncryptedBlobStore(roots.support, roots.capture);
        final other = testEncryptedBlobStore(roots.support, roots.capture);
        final staged = await owner.stage('entry-1', Uint8List.fromList([1]));
        final finalized = await owner.finalize(staged);

        await expectLater(other.rollback(finalized), throwsArgumentError);
        expect(await owner.exists(finalized.relativeRef), isTrue);

        await owner.rollback(finalized);
        expect(await owner.exists(finalized.relativeRef), isFalse);
      },
    );

    test('rejects absolute, traversal, and unsafe entry references', () async {
      final roots = await _TestRoots.create('keepers-blobs-');
      addTearDown(roots.close);
      final support = roots.support;
      final store = testEncryptedBlobStore(support, roots.capture);

      for (final reference in [
        p.join(support.path, 'entries', 'blobs', 'entry-1.keeper'),
        p.join('..', 'outside.keeper'),
        p.join('entries', 'blobs', '..', '..', '..', 'outside.keeper'),
      ]) {
        expect(() => store.read(reference), throwsArgumentError);
      }
      await expectLater(
        store.stage(p.join('..', 'entry-1'), Uint8List(0)),
        throwsArgumentError,
      );
      await expectLater(
        store.stage(p.join('nested', 'entry-1'), Uint8List(0)),
        throwsArgumentError,
      );
    });

    test(
      'plaintext cleanup ignores missing files and surfaces other I/O errors',
      () async {
        final roots = await _TestRoots.create('keepers-blobs-');
        addTearDown(roots.close);
        final store = testEncryptedBlobStore(roots.support, roots.capture);
        final plaintext = File(p.join(roots.capture.path, 'capture.tmp'));
        await plaintext.writeAsString('private');

        final cleanup = await store.validatePlaintextRefs(const [
          CapturePlaintextRef('capture.tmp'),
          CapturePlaintextRef('missing.tmp'),
        ]);
        await store.deletePlaintext(cleanup);

        expect(plaintext.existsSync(), isFalse);
        await expectLater(
          store.validatePlaintextRefs(const [CapturePlaintextRef('../x')]),
          throwsArgumentError,
        );
        await expectLater(
          store.validatePlaintextRefs([
            CapturePlaintextRef(
              p.join('KeEpErS-QuArAnTiNe', 'retained-candidate'),
            ),
          ]),
          throwsArgumentError,
        );
      },
    );
  });

  test('plaintext cleanup retains every path failure', () async {
    final roots = await _TestRoots.create('keepers-cleanup-causes-');
    addTearDown(roots.close);
    final store = testEncryptedBlobStore(roots.support, roots.capture);
    final first = File(p.join(roots.capture.path, 'first.tmp'));
    final second = File(p.join(roots.capture.path, 'second.tmp'));
    await first.writeAsBytes([1]);
    await second.writeAsBytes([2]);
    final cleanup = await store.validatePlaintextRefs(const [
      CapturePlaintextRef('first.tmp'),
      CapturePlaintextRef('second.tmp'),
    ]);
    await first.delete();
    await second.delete();
    await Directory(first.path).create();
    await Directory(second.path).create();

    EncryptedBlobStoreFailure? failure;
    try {
      await store.deletePlaintext(cleanup);
    } on EncryptedBlobStoreFailure catch (error) {
      failure = error;
    }

    expect(failure, isNotNull);
    expect(failure!.primary.phase, EntrySavePhase.plaintextCleanup);
    expect(failure.additionalFailures, hasLength(1));
    expect(
      failure.additionalFailures.single.phase,
      EntrySavePhase.plaintextCleanup,
    );
    expect(Directory(first.path).existsSync(), isTrue);
    expect(Directory(second.path).existsSync(), isTrue);
  });

  test(
    'save orders encryption, finalization, insert, and plaintext cleanup',
    () async {
      final events = <String>[];
      final harness = await _PersistenceHarness.create(events: events);
      addTearDown(harness.close);
      final source = await harness.writePlaintext('recognizable camera bytes');

      final saved = await harness.service.save(
        _saveRequest(plaintextRefs: [harness.plaintextRef(source)]),
      );

      expect(events, [
        'encode',
        'resolve-key',
        'encrypt',
        'stage',
        'finalize',
        'insert',
        'delete-plaintext',
      ]);
      expect(source.existsSync(), isFalse);
      expect(saved.blobRef, p.join('entries', 'blobs', 'entry-1.keeper'));
      final envelopeBytes = await harness.blobStore.read(saved.blobRef!);
      expect(
        File(p.join(harness.support.path, 'entries', 'staging', 'entry-1.part'))
            .existsSync(),
        isFalse,
      );

      final rows = await harness.database.query('entries');
      expect(rows, hasLength(1));
      expect(rows.single, {
        'id': 'entry-1',
        'family_id': 'family-1',
        'author_id': 'member-1',
        'created_at': DateTime.utc(2026, 9, 1).millisecondsSinceEpoch,
        'entry_type': 'text',
        'privacy_tier': 'journal',
        'blob_ref': p.join('entries', 'blobs', 'entry-1.keeper'),
        'transcript': null,
        'embedding': null,
        'state': 'pending',
        'expires_at': null,
        'revealed_at': null,
        'kept_at': null,
      });
      expect(rows.single.values, isNot(contains('Only encrypted')));
      expect(rows.single.values, isNot(contains('private caption')));
      expect(rows.single.values, isNot(contains(source.path)));
      expect(rows.single.values, isNot(contains(List<int>.filled(32, 9))));

      expect(utf8.decode(envelopeBytes), isNot(contains('Only encrypted')));
      expect(utf8.decode(envelopeBytes), isNot(contains('private caption')));
      final payloadBytes = await harness.cipher.decrypt(
        envelopeBytes: envelopeBytes,
        keyBytes: List<int>.filled(32, 9),
        metadata: saved,
      );
      expect(harness.codec.decode(payloadBytes).text, 'Only encrypted');
      expect(harness.codec.decode(payloadBytes).caption, 'private caption');
    },
  );

  test(
    'database failure deletes finalized encrypted blob and source plaintext',
    () async {
      final events = <String>[];
      final harness = await _PersistenceHarness.create(
        events: events,
        failInsert: true,
      );
      addTearDown(harness.close);
      final source = await harness.writePlaintext('recognizable camera bytes');

      await expectLater(
        harness.service.save(
          _saveRequest(plaintextRefs: [harness.plaintextRef(source)]),
        ),
        throwsA(
          isA<EntrySaveFailure>().having(
            (failure) => failure.primary.phase,
            'primary phase',
            EntrySavePhase.metadataInsert,
          ),
        ),
      );

      expect(events, [
        'encode',
        'resolve-key',
        'encrypt',
        'stage',
        'finalize',
        'insert',
        'rollback-final',
        'delete-plaintext',
      ]);
      expect(source.existsSync(), isFalse);
      expect(
        File(p.join(harness.support.path, 'entries', 'blobs', 'entry-1.keeper'))
            .existsSync(),
        isFalse,
      );
      expect(await harness.database.query('entries'), isEmpty);
    },
  );

  test(
    'key-resolution failure deletes source without creating encrypted files',
    () async {
      final events = <String>[];
      final harness = await _PersistenceHarness.create(
        events: events,
        omitMemberKey: true,
      );
      addTearDown(harness.close);
      final source = await harness.writePlaintext('recognizable camera bytes');

      await expectLater(
        harness.service.save(
          _saveRequest(plaintextRefs: [harness.plaintextRef(source)]),
        ),
        throwsA(
          isA<EntrySaveFailure>().having(
            (failure) => failure.primary.phase,
            'primary phase',
            EntrySavePhase.keyResolution,
          ),
        ),
      );

      expect(events, ['encode', 'resolve-key', 'delete-plaintext']);
      expect(source.existsSync(), isFalse);
      expect(
        Directory(p.join(harness.support.path, 'entries')).existsSync(),
        isFalse,
      );
      expect(await harness.database.query('entries'), isEmpty);
    },
  );

  test('save rejects mismatched author, family, or payload metadata before key lookup', () async {
    for (final mismatch in [
      _metadata.copyWith(authorId: 'different-member'),
      _metadata.copyWith(familyId: 'different-family'),
      _metadata.copyWith(format: MemoryFormat.photo),
    ]) {
      final events = <String>[];
      final harness = await _PersistenceHarness.create(events: events);
      final source = await harness.writePlaintext('owned temporary bytes');
      try {
        await expectLater(
          harness.service.save(
            _saveRequest(
              metadata: mismatch,
              plaintextRefs: [harness.plaintextRef(source)],
            ),
          ),
          throwsA(
            isA<EntrySaveFailure>()
                .having(
                  (failure) => failure.primary.phase,
                  'primary phase',
                  EntrySavePhase.requestValidation,
                )
                .having(
                  (failure) => failure.primary.error,
                  'primary error',
                  isA<ArgumentError>(),
                ),
          ),
        );

        expect(events, ['encode', 'delete-plaintext']);
        expect(source.existsSync(), isFalse);
        expect(await harness.database.query('entries'), isEmpty);
      } finally {
        await harness.close();
      }
    }
  });

  test('repository rejects non-relative encrypted blob references', () async {
    final database = await _openEntryDatabase();
    addTearDown(database.close);
    final repository = EntryRepository();

    for (final blobRef in [
      p.join(Directory.systemTemp.path, 'entry-1.keeper'),
      p.join('..', 'entry-1.keeper'),
    ]) {
      await expectLater(
        repository.insert(database, _metadata, blobRef),
        throwsArgumentError,
      );
    }

    expect(await database.query('entries'), isEmpty);
  });

  test(
    'request snapshots cleanup refs before asynchronous save work',
    () async {
      final events = <String>[];
      final harness = await _PersistenceHarness.create(events: events);
      addTearDown(harness.close);
      final source = await harness.writePlaintext('owned temporary bytes');
      final refs = <CapturePlaintextRef>[
        CapturePlaintextRef(p.basename(source.path)),
      ];
      final request = EntrySaveRequest(
        metadata: _metadata,
        payload: _textPayload,
        identity: _identity,
        plaintextRefs: refs,
      );

      refs.clear();
      await harness.service.save(request);

      expect(source.existsSync(), isFalse);
    },
  );

  test(
    'support and capture-temp alias fails before insert or deletion',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('keepers-alias-');
      addTearDown(() => sandbox.delete(recursive: true));
      final support = Directory(p.join(sandbox.path, 'support'));
      final captureAlias = Directory(p.join(support.path, 'entries', 'blobs'));
      await captureAlias.create(recursive: true);
      final protected = File(p.join(captureAlias.path, 'protected.tmp'));
      await protected.writeAsString('do not delete', flush: true);
      final database = await _openEntryDatabase();
      addTearDown(database.close);
      final store = testEncryptedBlobStore(support, captureAlias);
      final service = _realService(database: database, blobStore: store);

      await expectLater(
        service.save(
          EntrySaveRequest(
            metadata: _metadata,
            payload: _textPayload,
            identity: _identity,
            plaintextRefs: const [CapturePlaintextRef('protected.tmp')],
          ),
        ),
        throwsA(
          isA<EntrySaveFailure>()
              .having(
                (failure) => failure.primary.phase,
                'primary phase',
                EntrySavePhase.plaintextValidation,
              )
              .having(
                (failure) => failure.primary.error,
                'primary error',
                isA<ArgumentError>(),
              ),
        ),
      );

      expect(await protected.readAsString(), 'do not delete');
      expect(await database.query('entries'), isEmpty);
    },
  );

  group('aggregate save failures', () {
    test(
      'insert and rollback failures preserve primary and orphan state',
      () async {
        final fixture = await _FailureFixture.create(
          failInsert: true,
          failRollback: true,
        );
        addTearDown(fixture.close);

        final failure = await fixture.saveFailure();

        expect(failure.primary.phase, EntrySavePhase.metadataInsert);
        expect(failure.primary.error, isA<StateError>());
        expect(failure.compensations.map((cause) => cause.phase), [
          EntrySavePhase.finalBlobRollback,
        ]);
        expect(failure.consistency.metadataCommitted, isFalse);
        expect(
          failure.consistency.finalizedBlobState,
          EntryArtifactState.unknown,
        );
        expect(failure.consistency.plaintextMayRemain, isFalse);
        expect(await fixture.database.query('entries'), isEmpty);
        expect(fixture.finalBlob.existsSync(), isTrue);
        expect(fixture.plaintext.existsSync(), isFalse);
      },
    );

    test(
      'insert and plaintext cleanup failures preserve both causes',
      () async {
        final fixture = await _FailureFixture.create(
          failInsert: true,
          failPlaintextCleanup: true,
        );
        addTearDown(fixture.close);

        final failure = await fixture.saveFailure();

        expect(failure.primary.phase, EntrySavePhase.metadataInsert);
        expect(failure.compensations.map((cause) => cause.phase), [
          EntrySavePhase.plaintextCleanup,
        ]);
        expect(failure.consistency.finalizedBlobPresent, isFalse);
        expect(failure.consistency.plaintextMayRemain, isTrue);
        expect(fixture.finalBlob.existsSync(), isFalse);
        expect(fixture.plaintext.existsSync(), isTrue);
      },
    );

    test('rollback and plaintext cleanup failures are both retained', () async {
      final fixture = await _FailureFixture.create(
        failInsert: true,
        failRollback: true,
        failPlaintextCleanup: true,
      );
      addTearDown(fixture.close);

      final failure = await fixture.saveFailure();

      expect(failure.primary.phase, EntrySavePhase.metadataInsert);
      expect(failure.compensations.map((cause) => cause.phase), [
        EntrySavePhase.finalBlobRollback,
        EntrySavePhase.plaintextCleanup,
      ]);
      expect(
        failure.consistency.finalizedBlobState,
        EntryArtifactState.unknown,
      );
      expect(failure.consistency.plaintextMayRemain, isTrue);
      expect(fixture.finalBlob.existsSync(), isTrue);
      expect(fixture.plaintext.existsSync(), isTrue);
    });

    test('post-commit cleanup failure reports committed consistency', () async {
      final fixture = await _FailureFixture.create(failPlaintextCleanup: true);
      addTearDown(fixture.close);

      final failure = await fixture.saveFailure();

      expect(failure.primary.phase, EntrySavePhase.plaintextCleanup);
      expect(failure.compensations, isEmpty);
      expect(failure.consistency.metadataCommitted, isTrue);
      expect(failure.committedMetadata?.id, 'entry-1');
      expect(
        failure.committedMetadata?.blobRef,
        p.join('entries', 'blobs', 'entry-1.keeper'),
      );
      expect(
        failure.consistency.finalizedBlobState,
        EntryArtifactState.present,
      );
      expect(failure.consistency.plaintextMayRemain, isTrue);
      expect(await fixture.database.query('entries'), hasLength(1));
      expect(fixture.finalBlob.existsSync(), isTrue);
      expect(fixture.plaintext.existsSync(), isTrue);
    });

    test('committed consistency requires authoritative metadata', () {
      expect(
        () => EntrySaveFailure(
          primary: EntrySaveCause(
            phase: EntrySavePhase.plaintextCleanup,
            error: StateError('cleanup'),
            stackTrace: StackTrace.current,
          ),
          compensations: const [],
          consistency: const EntrySaveConsistency(
            metadataCommitted: true,
            finalizedBlobState: EntryArtifactState.present,
            stagedBlobState: EntryArtifactState.absent,
            plaintextMayRemain: true,
          ),
        ),
        throwsArgumentError,
      );
    });

    test(
      'finalize and plaintext cleanup failures retain exact state',
      () async {
        final fixture = await _FailureFixture.create(
          failFinalize: true,
          failPlaintextCleanup: true,
        );
        addTearDown(fixture.close);

        final failure = await fixture.saveFailure();

        expect(failure.primary.phase, EntrySavePhase.finalizeBlob);
        expect(failure.compensations.map((cause) => cause.phase), [
          EntrySavePhase.plaintextCleanup,
        ]);
        expect(failure.consistency.metadataCommitted, isFalse);
        expect(failure.consistency.finalizedBlobPresent, isFalse);
        expect(failure.consistency.stagedBlobMayRemain, isFalse);
        expect(failure.consistency.plaintextMayRemain, isTrue);
        expect(await fixture.database.query('entries'), isEmpty);
        expect(fixture.finalBlob.existsSync(), isFalse);
        expect(fixture.plaintext.existsSync(), isTrue);
      },
    );

    test('uncertain publication is never reported as final absence', () async {
      final fixture = await _FailureFixture.create(
        failFinalize: true,
        finalBlobMayRemain: true,
      );
      addTearDown(fixture.close);

      final failure = await fixture.saveFailure();

      expect(failure.primary.phase, EntrySavePhase.finalizeBlob);
      expect(
        failure.consistency.finalizedBlobState,
        EntryArtifactState.unknown,
      );
      expect(failure.consistency.metadataCommitted, isFalse);
      expect(await fixture.database.query('entries'), isEmpty);
    });

    test(
      'finalize release failure follows the primary and keeps state unknown',
      () async {
        final releaseError = StateError('private authority release failed');
        final fixture = await _FailureFixture.create(
          failFinalize: true,
          finalBlobMayRemain: true,
          finalizeAdditionalFailures: [
            EntrySaveCause(
              phase: EntrySavePhase.finalBlobRollback,
              error: releaseError,
              stackTrace: StackTrace.current,
            ),
          ],
        );
        addTearDown(fixture.close);

        final failure = await fixture.saveFailure();

        expect(failure.primary.phase, EntrySavePhase.finalizeBlob);
        expect(
          (failure.primary.error as StateError).message,
          'finalize failed',
        );
        expect(failure.compensations, hasLength(1));
        expect(
          failure.compensations.single.phase,
          EntrySavePhase.finalBlobRollback,
        );
        expect(failure.compensations.single.error, same(releaseError));
        expect(
          failure.consistency.finalizedBlobState,
          EntryArtifactState.unknown,
        );
        expect(await fixture.database.query('entries'), isEmpty);
      },
    );
  });

  group('real persistence boundaries', () {
    test(
      'Capsule assignment failure rolls back entry rows and finalized blob',
      () async {
        final roots = await _TestRoots.create('keepers-capsule-rollback-');
        addTearDown(roots.close);
        final database = await _openCapsuleDatabase();
        addTearDown(database.close);
        await _seedCapsuleFamily(database);
        final blobStore = testEncryptedBlobStore(roots.support, roots.capture);
        final keys = _MemorySecureValueStore()
          ..values['member-key'] = base64UrlEncode(List<int>.filled(32, 9))
          ..values['family-key'] = base64UrlEncode(List<int>.filled(32, 7));
        final service = EntryPersistenceService(
          codec: const EntryPayloadCodec(),
          keyResolver: EntryKeyResolver(IdentityKeyService(keys)),
          cipher: EntryCipher(
            nonceFactory: () =>
                Uint8List.fromList(List<int>.generate(12, (index) => index)),
          ),
          blobStore: blobStore,
          repository: EntryRepository(),
          capsuleRepository: const _WriteThenThrowCapsuleRepository(),
          database: () async => database,
        );
        final metadata = _metadata.copyWith(privacy: PrivacyTier.capsule);

        await expectLater(
          service.save(
            _saveRequest(
              metadata: metadata,
              capsuleOptions: CapsuleSaveOptions(unlockTask: 'Tell a story'),
              plaintextRefs: const [],
            ),
          ),
          throwsA(
            isA<EntrySaveFailure>().having(
              (failure) => failure.primary.phase,
              'primary phase',
              EntrySavePhase.metadataInsert,
            ),
          ),
        );

        expect(await database.query('entries'), isEmpty);
        expect(await database.query('capsules'), isEmpty);
        expect(await blobStore.exists('entries/blobs/entry-1.keeper'), isFalse);
      },
    );

    test(
      'pre-rollback replacement survives and moved publication is unknown',
      () async {
        final roots = await _TestRoots.create('keepers-native-swap-');
        addTearDown(roots.close);
        final database = await _openEntryDatabase();
        addTearDown(database.close);
        final plaintext = File(p.join(roots.capture.path, 'capture-source.tmp'))
          ..writeAsStringSync('owned plaintext', flush: true);
        final repository = _SwapPublishedBlobThenThrowRepository(
          EntryRepository(),
          roots.support,
        );
        final keys = _MemorySecureValueStore()
          ..values['member-key'] = base64UrlEncode(List<int>.filled(32, 9))
          ..values['family-key'] = base64UrlEncode(List<int>.filled(32, 7));
        final service = EntryPersistenceService(
          codec: const EntryPayloadCodec(),
          keyResolver: EntryKeyResolver(IdentityKeyService(keys)),
          cipher: EntryCipher(
            nonceFactory: () =>
                Uint8List.fromList(List<int>.generate(12, (index) => index)),
          ),
          blobStore: EncryptedBlobStore(
            roots.support,
            captureTemporaryDirectory: roots.capture,
          ),
          repository: repository,
          database: () async => database,
        );

        EntrySaveFailure? failure;
        try {
          await service.save(
            _saveRequest(
              plaintextRefs: const [CapturePlaintextRef('capture-source.tmp')],
            ),
          );
        } on EntrySaveFailure catch (error) {
          failure = error;
        }

        expect(failure, isNotNull);
        expect(failure!.primary.phase, EntrySavePhase.metadataInsert);
        expect(
          failure.consistency.finalizedBlobState,
          EntryArtifactState.unknown,
        );
        expect(
          failure.compensations.map((cause) => cause.phase),
          contains(EntrySavePhase.finalBlobRollback),
        );
        expect(await repository.replacement!.readAsBytes(), [8, 8, 8]);
        expect(repository.movedPublication!.existsSync(), isTrue);
        expect(await repository.movedPublication!.length(), greaterThan(3));
        expect(await database.query('entries'), isEmpty);
        expect(plaintext.existsSync(), isFalse);
      },
      skip: requiresPosix,
    );

    test(
      'hard-link alias surviving SQLite failure makes rollback state unknown',
      () async {
        final roots = await _TestRoots.create('keepers-native-alias-');
        addTearDown(roots.close);
        final database = await _openEntryDatabase();
        addTearDown(database.close);
        final plaintext = File(p.join(roots.capture.path, 'capture-source.tmp'))
          ..writeAsStringSync('owned plaintext', flush: true);
        final repository = _AliasPublishedBlobThenThrowRepository(
          EntryRepository(),
          roots.support,
        );
        final keys = _MemorySecureValueStore()
          ..values['member-key'] = base64UrlEncode(List<int>.filled(32, 9))
          ..values['family-key'] = base64UrlEncode(List<int>.filled(32, 7));
        final service = EntryPersistenceService(
          codec: const EntryPayloadCodec(),
          keyResolver: EntryKeyResolver(IdentityKeyService(keys)),
          cipher: EntryCipher(
            nonceFactory: () =>
                Uint8List.fromList(List<int>.generate(12, (index) => index)),
          ),
          blobStore: EncryptedBlobStore(
            roots.support,
            captureTemporaryDirectory: roots.capture,
          ),
          repository: repository,
          database: () async => database,
        );

        EntrySaveFailure? failure;
        try {
          await service.save(
            _saveRequest(
              plaintextRefs: const [CapturePlaintextRef('capture-source.tmp')],
            ),
          );
        } on EntrySaveFailure catch (error) {
          failure = error;
        }

        expect(failure, isNotNull);
        expect(failure!.primary.phase, EntrySavePhase.metadataInsert);
        expect(
          failure.consistency.finalizedBlobState,
          EntryArtifactState.unknown,
        );
        expect(
          failure.compensations.map((cause) => cause.phase),
          contains(EntrySavePhase.finalBlobRollback),
        );
        expect(repository.alias, isNotNull);
        expect(repository.alias!.existsSync(), isTrue);
        expect(await repository.alias!.length(), greaterThan(3));
        expect(
          File(
            p.join(
              roots.support.path,
              'entries',
              'blobs',
              '${_metadata.id}.keeper',
            ),
          ).existsSync(),
          isFalse,
        );
        expect(await database.query('entries'), isEmpty);
        expect(plaintext.existsSync(), isFalse);
      },
      skip: requiresPosix,
    );

    test(
      'SQLite uniqueness failure rolls back final blob and transaction',
      () async {
        final fixture = await _RealBoundaryFixture.create();
        addTearDown(fixture.close);
        await EntryRepository().insert(
          fixture.database,
          _metadata,
          p.join('entries', 'blobs', 'preexisting.keeper'),
        );

        final failure = await fixture.saveFailure();

        expect(failure.primary.phase, EntrySavePhase.metadataInsert);
        expect(failure.primary.error, isA<DatabaseException>());
        expect(
          failure.consistency.finalizedBlobState,
          EntryArtifactState.absent,
        );
        expect(failure.consistency.stagedBlobState, EntryArtifactState.absent);
        expect(failure.consistency.plaintextMayRemain, isFalse);
        final rows = await fixture.database.query('entries');
        expect(rows, hasLength(1));
        expect(
          rows.single['blob_ref'],
          p.join('entries', 'blobs', 'preexisting.keeper'),
        );
        expect(fixture.finalBlob.existsSync(), isFalse);
        expect(fixture.plaintext.existsSync(), isFalse);
        expect(await fixture.stagingEntities(), isEmpty);
      },
    );

    test('write-then-throw repository work is rolled back by SQLite', () async {
      final fixture = await _RealBoundaryFixture.create(
        repository: _WriteThenThrowRepository(EntryRepository()),
      );
      addTearDown(fixture.close);

      final failure = await fixture.saveFailure();

      expect(failure.primary.phase, EntrySavePhase.metadataInsert);
      expect(failure.primary.error, isA<StateError>());
      expect(await fixture.database.query('entries'), isEmpty);
      expect(fixture.finalBlob.existsSync(), isFalse);
      expect(fixture.plaintext.existsSync(), isFalse);
      expect(await fixture.stagingEntities(), isEmpty);
    });

    test(
      'database acquisition failure compensates finalized storage',
      () async {
        final fixture = await _RealBoundaryFixture.create(
          databaseFactory: () async => throw StateError('database open failed'),
        );
        addTearDown(fixture.close);

        final failure = await fixture.saveFailure();

        expect(failure.primary.phase, EntrySavePhase.databaseOpen);
        expect(failure.primary.error, isA<StateError>());
        expect(fixture.finalBlob.existsSync(), isFalse);
        expect(fixture.plaintext.existsSync(), isFalse);
        expect(await fixture.database.query('entries'), isEmpty);
        expect(await fixture.stagingEntities(), isEmpty);
      },
    );

    test('closed-database transaction failure compensates files', () async {
      final fixture = await _RealBoundaryFixture.create();
      await fixture.database.close();
      addTearDown(fixture.closeFilesOnly);

      final failure = await fixture.saveFailure();

      expect(failure.primary.phase, EntrySavePhase.metadataInsert);
      expect(failure.primary.error, isA<DatabaseException>());
      expect(fixture.finalBlob.existsSync(), isFalse);
      expect(fixture.plaintext.existsSync(), isFalse);
      expect(await fixture.stagingEntities(), isEmpty);
    });

    test('unsafe staging component fails before any SQL write', () async {
      final fixture = await _RealBoundaryFixture.create(
        prepareSupport: (support) async {
          final entries = Directory(p.join(support.path, 'entries'));
          await entries.create();
          await File(p.join(entries.path, 'staging')).writeAsString('unsafe');
        },
      );
      addTearDown(fixture.close);

      final failure = await fixture.saveFailure();

      expect(failure.primary.phase, EntrySavePhase.stageBlob);
      expect(failure.consistency.stagedBlobState, EntryArtifactState.absent);
      expect(await fixture.database.query('entries'), isEmpty);
      expect(fixture.finalBlob.existsSync(), isFalse);
      expect(fixture.plaintext.existsSync(), isFalse);
    });

    test(
      'existing final survives real-service finalize failure unchanged',
      () async {
        final fixture = await _RealBoundaryFixture.create(
          prepareSupport: (support) async {
            final blob = File(
              p.join(support.path, 'entries', 'blobs', 'entry-1.keeper'),
            );
            await blob.parent.create(recursive: true);
            await blob.writeAsBytes([9, 9, 9], flush: true);
          },
        );
        addTearDown(fixture.close);

        final failure = await fixture.saveFailure();

        expect(failure.primary.phase, EntrySavePhase.finalizeBlob);
        expect(await fixture.finalBlob.readAsBytes(), [9, 9, 9]);
        expect(await fixture.database.query('entries'), isEmpty);
        expect(fixture.plaintext.existsSync(), isFalse);
        expect(await fixture.stagingEntities(), isEmpty);
      },
    );

    test('concurrent same-ID saves publish one row and one blob', () async {
      final fixture = await _RealBoundaryFixture.create();
      addTearDown(fixture.close);
      final secondPlaintext = File(
        p.join(fixture.roots.capture.path, 'capture-second.tmp'),
      );
      await secondPlaintext.writeAsString('second plaintext', flush: true);
      final requests = [
        _saveRequest(
          plaintextRefs: const [CapturePlaintextRef('capture-source.tmp')],
        ),
        _saveRequest(
          plaintextRefs: const [CapturePlaintextRef('capture-second.tmp')],
        ),
      ];

      final results = await Future.wait(
        requests.map((request) async {
          try {
            return await fixture.service.save(request);
          } on EntrySaveFailure catch (failure) {
            return failure;
          }
        }),
      );

      expect(results.whereType<EntryMetadata>(), hasLength(1));
      expect(results.whereType<EntrySaveFailure>(), hasLength(1));
      expect(await fixture.database.query('entries'), hasLength(1));
      expect(fixture.finalBlob.existsSync(), isTrue);
      expect(fixture.plaintext.existsSync(), isFalse);
      expect(secondPlaintext.existsSync(), isFalse);
      expect(await fixture.stagingEntities(), isEmpty);
    });
  });
}

final class _RealBoundaryFixture {
  _RealBoundaryFixture._({
    required this.roots,
    required this.database,
    required this.plaintext,
    required this.service,
  });

  final _TestRoots roots;
  final Database database;
  final File plaintext;
  final EntryPersistenceService service;

  File get finalBlob =>
      File(p.join(roots.support.path, 'entries', 'blobs', 'entry-1.keeper'));

  static Future<_RealBoundaryFixture> create({
    EntryMetadataRepository? repository,
    EntryDatabaseFactory? databaseFactory,
    Future<void> Function(Directory support)? prepareSupport,
  }) async {
    final roots = await _TestRoots.create('keepers-real-boundary-');
    if (prepareSupport != null) {
      await prepareSupport(roots.support);
    }
    final database = await _openEntryDatabase();
    final plaintext = File(p.join(roots.capture.path, 'capture-source.tmp'));
    await plaintext.writeAsString('owned plaintext', flush: true);
    final store = testEncryptedBlobStore(roots.support, roots.capture);
    final keys = _MemorySecureValueStore()
      ..values['member-key'] = base64UrlEncode(List<int>.filled(32, 9))
      ..values['family-key'] = base64UrlEncode(List<int>.filled(32, 7));
    final service = EntryPersistenceService(
      codec: const EntryPayloadCodec(),
      keyResolver: EntryKeyResolver(IdentityKeyService(keys)),
      cipher: EntryCipher(
        nonceFactory: () =>
            Uint8List.fromList(List<int>.generate(12, (index) => index)),
      ),
      blobStore: store,
      repository: repository ?? EntryRepository(),
      database: databaseFactory ?? () async => database,
    );
    return _RealBoundaryFixture._(
      roots: roots,
      database: database,
      plaintext: plaintext,
      service: service,
    );
  }

  Future<EntrySaveFailure> saveFailure() async {
    try {
      await service.save(
        _saveRequest(
          plaintextRefs: const [CapturePlaintextRef('capture-source.tmp')],
        ),
      );
    } on EntrySaveFailure catch (failure) {
      return failure;
    }
    fail('Expected save to fail');
  }

  Future<List<FileSystemEntity>> stagingEntities() async {
    final staging = Directory(p.join(roots.support.path, 'entries', 'staging'));
    if (!staging.existsSync()) {
      return const [];
    }
    return staging.list(recursive: true).toList();
  }

  Future<void> close() async {
    if (database.isOpen) {
      await database.close();
    }
    await closeFilesOnly();
  }

  Future<void> closeFilesOnly() => roots.close();
}

final class _WriteThenThrowRepository implements EntryMetadataRepository {
  const _WriteThenThrowRepository(this.delegate);

  final EntryMetadataRepository delegate;

  @override
  Future<void> insert(
    DatabaseExecutor db,
    EntryMetadata metadata,
    String blobRef,
  ) async {
    await delegate.insert(db, metadata, blobRef);
    throw StateError('write then throw');
  }
}

final class _SwapPublishedBlobThenThrowRepository
    implements EntryMetadataRepository {
  _SwapPublishedBlobThenThrowRepository(this.delegate, this.supportDirectory);

  final EntryMetadataRepository delegate;
  final Directory supportDirectory;
  File? movedPublication;
  File? replacement;

  @override
  Future<void> insert(
    DatabaseExecutor db,
    EntryMetadata metadata,
    String blobRef,
  ) async {
    await delegate.insert(db, metadata, blobRef);
    final published = File(p.join(supportDirectory.path, blobRef));
    movedPublication = File('${published.path}.retained');
    published.renameSync(movedPublication!.path);
    replacement = File(published.path)
      ..writeAsBytesSync([8, 8, 8], flush: true);
    throw StateError('repository swapped publication before failure');
  }
}

final class _AliasPublishedBlobThenThrowRepository
    implements EntryMetadataRepository {
  _AliasPublishedBlobThenThrowRepository(this.delegate, this.supportDirectory);

  final EntryMetadataRepository delegate;
  final Directory supportDirectory;
  File? alias;

  @override
  Future<void> insert(
    DatabaseExecutor db,
    EntryMetadata metadata,
    String blobRef,
  ) async {
    await delegate.insert(db, metadata, blobRef);
    final published = File(p.join(supportDirectory.path, blobRef));
    alias = File('${published.path}.alias');
    final link = Process.runSync('ln', [published.path, alias!.path]);
    if (link.exitCode != 0) {
      throw StateError('ln failed: ${link.stderr}');
    }
    throw StateError('repository retained a hard-link alias before failure');
  }
}

final class _FailureFixture {
  _FailureFixture._({
    required this.roots,
    required this.database,
    required this.plaintext,
    required this.service,
  });

  final _TestRoots roots;
  final Database database;
  final File plaintext;
  final EntryPersistenceService service;

  File get finalBlob =>
      File(p.join(roots.support.path, 'entries', 'blobs', 'entry-1.keeper'));

  static Future<_FailureFixture> create({
    bool failInsert = false,
    bool failRollback = false,
    bool failPlaintextCleanup = false,
    bool failFinalize = false,
    bool finalBlobMayRemain = false,
    List<EntrySaveCause> finalizeAdditionalFailures = const [],
  }) async {
    final roots = await _TestRoots.create('keepers-failure-');
    final database = await _openEntryDatabase();
    final plaintext = File(p.join(roots.capture.path, 'capture-source.tmp'));
    await plaintext.writeAsString('owned plaintext', flush: true);
    final realStore = testEncryptedBlobStore(
      roots.support,
      roots.capture,
      finalizeError: failFinalize ? StateError('finalize failed') : null,
      finalBlobMayRemain: finalBlobMayRemain,
      finalizeAdditionalFailures: finalizeAdditionalFailures,
    );
    final store = _FaultingBlobStore(
      realStore,
      failRollback: failRollback,
      failPlaintextCleanup: failPlaintextCleanup,
    );
    final keys = _MemorySecureValueStore()
      ..values['member-key'] = base64UrlEncode(List<int>.filled(32, 9))
      ..values['family-key'] = base64UrlEncode(List<int>.filled(32, 7));
    final service = EntryPersistenceService(
      codec: const EntryPayloadCodec(),
      keyResolver: EntryKeyResolver(IdentityKeyService(keys)),
      cipher: EntryCipher(
        nonceFactory: () =>
            Uint8List.fromList(List<int>.generate(12, (index) => index)),
      ),
      blobStore: store,
      repository: _RecordingRepository([], failInsert: failInsert),
      database: () async => database,
    );
    return _FailureFixture._(
      roots: roots,
      database: database,
      plaintext: plaintext,
      service: service,
    );
  }

  Future<EntrySaveFailure> saveFailure() async {
    try {
      await service.save(
        _saveRequest(
          plaintextRefs: const [CapturePlaintextRef('capture-source.tmp')],
        ),
      );
    } on EntrySaveFailure catch (failure) {
      return failure;
    }
    fail('Expected save to fail');
  }

  Future<void> close() async {
    await database.close();
    await roots.close();
  }
}

final class _FaultingBlobStore implements EntryBlobStore {
  _FaultingBlobStore(
    this.delegate, {
    required this.failRollback,
    required this.failPlaintextCleanup,
  });

  final EncryptedBlobStore delegate;
  final bool failRollback;
  final bool failPlaintextCleanup;

  @override
  Future<CapturePlaintextCleanup> validatePlaintextRefs(
    Iterable<CapturePlaintextRef> refs,
  ) => delegate.validatePlaintextRefs(refs);

  @override
  Future<StagedEncryptedBlob> stage(String entryId, Uint8List encryptedBytes) =>
      delegate.stage(entryId, encryptedBytes);

  @override
  Future<FinalizedEncryptedBlob> finalize(StagedEncryptedBlob staged) =>
      delegate.finalize(staged);

  @override
  Future<void> rollback(FinalizedEncryptedBlob finalized) {
    if (failRollback) {
      throw StateError('rollback failed');
    }
    return delegate.rollback(finalized);
  }

  @override
  Future<void> deletePlaintext(CapturePlaintextCleanup cleanup) {
    if (failPlaintextCleanup) {
      throw StateError('plaintext cleanup failed');
    }
    return delegate.deletePlaintext(cleanup);
  }
}

final class _PersistenceHarness {
  _PersistenceHarness._({
    required this.sandbox,
    required this.support,
    required this.capture,
    required this.database,
    required this.codec,
    required this.cipher,
    required this.blobStore,
    required this.service,
  });

  final Directory sandbox;
  final Directory support;
  final Directory capture;
  final Database database;
  final EntryPayloadCodec codec;
  final EntryCipher cipher;
  final EncryptedBlobStore blobStore;
  final EntryPersistenceService service;

  static Future<_PersistenceHarness> create({
    required List<String> events,
    bool failInsert = false,
    bool omitMemberKey = false,
  }) async {
    final roots = await _TestRoots.create('keepers-save-');
    final support = roots.support;
    final capture = roots.capture;
    final database = await _openEntryDatabase();
    final keyStore = _MemorySecureValueStore();
    if (!omitMemberKey) {
      keyStore.values['member-key'] = base64UrlEncode(List<int>.filled(32, 9));
    }
    keyStore.values['family-key'] = base64UrlEncode(List<int>.filled(32, 7));
    final codec = _RecordingCodec(events);
    final cipher = _RecordingCipher(events);
    final blobStore = _RecordingBlobStore(support, capture, events);
    final service = EntryPersistenceService(
      codec: codec,
      keyResolver: _RecordingKeyResolver(IdentityKeyService(keyStore), events),
      cipher: cipher,
      blobStore: blobStore,
      repository: _RecordingRepository(events, failInsert: failInsert),
      database: () async => database,
    );
    return _PersistenceHarness._(
      sandbox: roots.sandbox,
      support: support,
      capture: capture,
      database: database,
      codec: codec,
      cipher: cipher,
      blobStore: blobStore,
      service: service,
    );
  }

  Future<File> writePlaintext(String contents) async {
    final file = File(p.join(capture.path, 'capture-source.tmp'));
    await file.writeAsString(contents, flush: true);
    return file;
  }

  CapturePlaintextRef plaintextRef(File file) =>
      CapturePlaintextRef(p.relative(file.path, from: capture.path));

  Future<void> close() async {
    await database.close();
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  }
}

class _RecordingCodec extends EntryPayloadCodec {
  _RecordingCodec(this.events);

  final List<String> events;

  @override
  Uint8List encode(EntryPayload payload) {
    events.add('encode');
    return super.encode(payload);
  }
}

class _RecordingCipher extends EntryCipher {
  _RecordingCipher(this.events)
    : super(
        nonceFactory: () =>
            Uint8List.fromList(List<int>.generate(12, (i) => i)),
      );

  final List<String> events;

  @override
  Future<Uint8List> encrypt({
    required Uint8List plaintext,
    required List<int> keyBytes,
    required EntryMetadata metadata,
    required EntryKeyScope keyScope,
  }) {
    events.add('encrypt');
    return super.encrypt(
      plaintext: plaintext,
      keyBytes: keyBytes,
      metadata: metadata,
      keyScope: keyScope,
    );
  }
}

class _RecordingKeyResolver extends EntryKeyResolver {
  _RecordingKeyResolver(super.identityKeys, this.events);

  final List<String> events;

  @override
  Future<ResolvedEntryKey> resolve(
    PrivacyTier privacy,
    LocalIdentity identity,
  ) {
    events.add('resolve-key');
    return super.resolve(privacy, identity);
  }
}

class _RecordingBlobStore extends EncryptedBlobStore {
  // The support parameter is also needed to construct the injected test FS.
  // ignore: use_super_parameters
  _RecordingBlobStore(
    Directory supportDirectory,
    Directory captureTemporaryDirectory,
    this.events,
  ) : super(
        supportDirectory,
        captureTemporaryDirectory: captureTemporaryDirectory,
        fileSystem: TestSecureBlobFileSystem(
          supportDirectory: supportDirectory,
          captureTemporaryDirectory: captureTemporaryDirectory,
        ),
      );

  final List<String> events;

  @override
  Future<StagedEncryptedBlob> stage(String entryId, Uint8List encryptedBytes) {
    events.add('stage');
    return super.stage(entryId, encryptedBytes);
  }

  @override
  Future<FinalizedEncryptedBlob> finalize(StagedEncryptedBlob staged) {
    events.add('finalize');
    return super.finalize(staged);
  }

  @override
  Future<void> rollback(FinalizedEncryptedBlob finalized) {
    events.add('rollback-final');
    return super.rollback(finalized);
  }

  @override
  Future<void> deletePlaintext(CapturePlaintextCleanup cleanup) {
    events.add('delete-plaintext');
    return super.deletePlaintext(cleanup);
  }
}

class _RecordingRepository extends EntryRepository {
  _RecordingRepository(this.events, {required this.failInsert});

  final List<String> events;
  final bool failInsert;

  @override
  Future<void> insert(
    DatabaseExecutor db,
    EntryMetadata metadata,
    String blobRef,
  ) {
    events.add('insert');
    if (failInsert) {
      throw StateError('insert failed');
    }
    return super.insert(db, metadata, blobRef);
  }
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

EntryPersistenceService _realService({
  required Database database,
  required EncryptedBlobStore blobStore,
}) {
  final keys = _MemorySecureValueStore()
    ..values['member-key'] = base64UrlEncode(List<int>.filled(32, 9))
    ..values['family-key'] = base64UrlEncode(List<int>.filled(32, 7));
  return EntryPersistenceService(
    codec: const EntryPayloadCodec(),
    keyResolver: EntryKeyResolver(IdentityKeyService(keys)),
    cipher: EntryCipher(
      nonceFactory: () =>
          Uint8List.fromList(List<int>.generate(12, (index) => index)),
    ),
    blobStore: blobStore,
    repository: EntryRepository(),
    database: () async => database,
  );
}

Future<Database> _openEntryDatabase() async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
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
  state TEXT NOT NULL,
  expires_at INTEGER,
  revealed_at INTEGER,
  kept_at INTEGER
)
''');
  return database;
}

const _identity = LocalIdentity(
  familyId: 'family-1',
  familyName: 'Keepers',
  familyKeyRef: 'family-key',
  memberId: 'member-1',
  memberName: 'Chris',
  memberKeyRef: 'member-key',
  colorToken: 'ochre',
  avatar: AvatarConfig.defaults(seed: 'member-1'),
);

final _metadata = EntryMetadata(
  id: 'entry-1',
  familyId: 'family-1',
  authorId: 'member-1',
  createdAt: DateTime.utc(2026, 9, 1),
  format: MemoryFormat.text,
  privacy: PrivacyTier.journal,
);

EntrySaveRequest _saveRequest({
  EntryMetadata? metadata,
  CapsuleSaveOptions? capsuleOptions,
  required Iterable<CapturePlaintextRef> plaintextRefs,
}) => EntrySaveRequest(
  metadata: metadata ?? _metadata,
  payload: _textPayload,
  identity: _identity,
  capsuleOptions: capsuleOptions,
  plaintextRefs: plaintextRefs,
);

final class _WriteThenThrowCapsuleRepository extends CapsuleRepository {
  const _WriteThenThrowCapsuleRepository();

  @override
  Future<List<CapsuleAssignment>> insertAssignments(
    DatabaseExecutor db, {
    required EntryMetadata entry,
    required CapsuleSaveOptions options,
  }) async {
    await super.insertAssignments(db, entry: entry, options: options);
    throw StateError('assignment insert failed after writing');
  }
}

Future<Database> _openCapsuleDatabase() async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await database.execute('PRAGMA foreign_keys = ON');
  for (final statement in KeepersSchema.statementsForUpgrade(
    0,
    KeepersSchema.version,
  )) {
    await database.execute(statement);
  }
  return database;
}

Future<void> _seedCapsuleFamily(Database database) async {
  await database.insert('families', {
    'id': 'family-1',
    'name': 'Keepers',
    'family_key_ref': 'family-key',
    'quorum': 1,
    'created_at': 1,
  });
  for (final memberId in ['member-1', 'member-2']) {
    await database.insert('members', {
      'id': memberId,
      'family_id': 'family-1',
      'name': memberId,
      'role': 'adult',
      'member_key_ref': '$memberId-key',
      'color_token': 'ochre',
      'avatar_config_json': '{}',
      'created_at': memberId == 'member-1' ? 1 : 2,
    });
  }
}

const _textPayload = EntryPayload(
  format: MemoryFormat.text,
  primaryBytes: null,
  text: 'Only encrypted',
  caption: 'private caption',
  mediaExtension: null,
  mediaDurationMs: null,
);

final class _TestRoots {
  _TestRoots._(this.sandbox, this.support, this.capture);

  final Directory sandbox;
  final Directory support;
  final Directory capture;

  static Future<_TestRoots> create(String prefix) async {
    final sandbox = await Directory.systemTemp.createTemp(prefix);
    final support = Directory(p.join(sandbox.path, 'support'));
    final capture = Directory(p.join(sandbox.path, 'capture'));
    await support.create();
    await capture.create();
    return _TestRoots._(sandbox, support, capture);
  }

  Future<void> close() async {
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  }
}
