import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/data/encrypted_blob_store.dart';
import 'package:path/path.dart' as p;

void main() {
  final requiresPosix = Platform.isWindows
      ? 'The production encrypted-blob filesystem intentionally does not '
            'support Windows.'
      : false;

  group('POSIX handle-anchored encrypted blob filesystem', () {
    test(
      'native ABI smoke opens fstats publishes and removes a real file',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-native-smoke-');
        addTearDown(roots.close);
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
        );

        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));
        final finalized = await fileSystem.finalize(
          staged,
          destinationName: 'entry-1.keeper',
          publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
        );

        expect(finalized.identity.device, greaterThanOrEqualTo(0));
        expect(finalized.identity.inode, greaterThan(0));
        expect(await fileSystem.readBlob(finalized.destinationName), [1, 2, 3]);
        await fileSystem.rollbackBlob(finalized);
        expect(await fileSystem.blobExists(finalized.destinationName), isFalse);
      },
      skip: requiresPosix,
    );

    test(
      'atomic-move publication saves reads and rolls back a real file',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-atomic-move-');
        addTearDown(roots.close);
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          publicationStrategy: PosixPublicationStrategy.atomicMove,
        );

        final staged = await fileSystem.stage(Uint8List.fromList([4, 5, 6]));
        final finalized = await fileSystem.finalize(
          staged,
          destinationName: 'entry-atomic.keeper',
          publishedRef: p.join('entries', 'blobs', 'entry-atomic.keeper'),
        );

        expect(await fileSystem.readBlob(finalized.destinationName), [4, 5, 6]);
        await fileSystem.rollbackBlob(finalized);
        expect(await fileSystem.blobExists(finalized.destinationName), isFalse);
      },
      skip: requiresPosix,
    );

    test('linked roots and linked owned components fail closed', () async {
      final roots = await _PosixRoots.create('keepers-posix-links-');
      addTearDown(roots.close);
      final outside = Directory(p.join(roots.sandbox.path, 'outside'))
        ..createSync();
      final supportLink = Link(p.join(roots.sandbox.path, 'support-link'))
        ..createSync(roots.support.path);
      final linkedRootFileSystem = PosixSecureBlobFileSystem(
        supportDirectory: Directory(supportLink.path),
        captureTemporaryDirectory: roots.capture,
      );
      await expectLater(
        linkedRootFileSystem.stage(Uint8List.fromList([1])),
        throwsA(isA<SecureBlobFileSystemFailure>()),
      );

      final entries = Directory(p.join(roots.support.path, 'entries'))
        ..createSync();
      Link(p.join(entries.path, 'staging')).createSync(outside.path);
      final linkedComponentFileSystem = PosixSecureBlobFileSystem(
        supportDirectory: roots.support,
        captureTemporaryDirectory: roots.capture,
      );
      await expectLater(
        linkedComponentFileSystem.stage(Uint8List.fromList([1])),
        throwsA(isA<SecureBlobFileSystemFailure>()),
      );
      expect(await outside.list().toList(), isEmpty);
    }, skip: requiresPosix);

    test(
      'capture parent links and support aliases are rejected before cleanup',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-capture-link-');
        addTearDown(roots.close);
        final outside = Directory(p.join(roots.sandbox.path, 'outside'))
          ..createSync();
        final protected = File(p.join(outside.path, 'capture.tmp'))
          ..writeAsStringSync('protected', flush: true);
        Link(p.join(roots.capture.path, 'linked')).createSync(outside.path);
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
        );
        await expectLater(
          fileSystem.validatePlaintextRefs(const [
            ['linked', 'capture.tmp'],
          ]),
          throwsA(isA<FileSystemException>()),
        );

        final aliasFileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: Directory(
            p.join(roots.support.path, 'entries'),
          )..createSync(),
        );
        await expectLater(
          aliasFileSystem.validatePlaintextRefs(const []),
          throwsArgumentError,
        );
        expect(await protected.readAsString(), 'protected');
      },
      skip: requiresPosix,
    );

    test(
      'staging leaf open remains anchored when the support path is swapped',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-stage-parent-');
        addTearDown(roots.close);
        final outside = Directory(p.join(roots.sandbox.path, 'outside'))
          ..createSync();
        Directory? retained;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (boundary != PosixFileBoundary.beforeStageLeafOpen ||
                retained != null) {
              return;
            }
            retained = Directory('${roots.support.path}.retained');
            roots.support.renameSync(retained!.path);
            Link(roots.support.path).createSync(outside.path);
          },
        );

        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));
        await fileSystem.finalize(
          staged,
          destinationName: 'entry-1.keeper',
          publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
        );

        expect(await outside.list().toList(), isEmpty);
        _restoreLinkedDirectory(roots.support.path, retained!);
        expect(await fileSystem.readBlob('entry-1.keeper'), [1, 2, 3]);
      },
      skip: requiresPosix,
    );

    test(
      'one opened staging descriptor owns create, write, fsync, and identity',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-stage-fd-');
        addTearDown(roots.close);
        final outside = File(p.join(roots.sandbox.path, 'outside.bin'));
        await outside.writeAsBytes([9, 9, 9], flush: true);
        var interposed = false;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (boundary != PosixFileBoundary.afterStageLeafOpenBeforeWrite ||
                interposed) {
              return;
            }
            interposed = true;
            final source = File(
              p.join(
                roots.support.path,
                'entries',
                'staging',
                context.attemptName!,
                'payload.part',
              ),
            );
            source.deleteSync();
            Link(source.path).createSync(outside.path);
          },
        );

        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));
        expect(interposed, isTrue);
        expect(await outside.readAsBytes(), [9, 9, 9]);

        await expectLater(
          fileSystem.finalize(
            staged,
            destinationName: 'entry-1.keeper',
            publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
          ),
          throwsA(isA<SecureBlobFileSystemFailure>()),
        );
        expect(
          Link(p.join(roots.support.path, 'entries', 'blobs', 'entry-1.keeper'))
              .existsSync(),
          isTrue,
        );
        expect(await outside.readAsBytes(), [9, 9, 9]);
      },
      skip: requiresPosix,
    );

    test(
      'publication preserves a swapped regular source and reports failure',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-source-id-');
        addTearDown(roots.close);
        var interposed = false;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (boundary != PosixFileBoundary.beforeFinalLink || interposed) {
              return;
            }
            interposed = true;
            final source = File(
              p.join(
                roots.support.path,
                'entries',
                'staging',
                context.attemptName!,
                'payload.part',
              ),
            );
            source.deleteSync();
            source.writeAsBytesSync([7, 7, 7], flush: true);
          },
        );
        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));

        SecureBlobFileSystemFailure? failure;
        try {
          await fileSystem.finalize(
            staged,
            destinationName: 'entry-1.keeper',
            publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
          );
        } on SecureBlobFileSystemFailure catch (error) {
          failure = error;
        }

        expect(interposed, isTrue);
        expect(failure, isNotNull);
        expect(failure!.publishedBlobRef, isNull);
        expect(failure.finalBlobMayRemain, isFalse);
        final blobs = p.join(roots.support.path, 'entries', 'blobs');
        expect(await File(p.join(blobs, 'entry-1.keeper')).readAsBytes(), [
          7,
          7,
          7,
        ]);
      },
      skip: requiresPosix,
    );

    test(
      'linkat no-replace keeps the first published bytes unchanged',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-no-replace-');
        addTearDown(roots.close);
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
        );
        final first = await fileSystem.stage(Uint8List.fromList([1]));
        final second = await fileSystem.stage(Uint8List.fromList([2]));
        await fileSystem.finalize(
          first,
          destinationName: 'entry-1.keeper',
          publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
        );

        await expectLater(
          fileSystem.finalize(
            second,
            destinationName: 'entry-1.keeper',
            publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
          ),
          throwsA(isA<SecureBlobFileSystemFailure>()),
        );

        expect(await fileSystem.readBlob('entry-1.keeper'), [1]);
      },
      skip: requiresPosix,
    );

    test(
      'publication verifies destination identity through its retained parent',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-dest-id-');
        addTearDown(roots.close);
        var interposed = false;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (boundary !=
                    PosixFileBoundary.afterFinalLinkBeforeIdentityCheck ||
                interposed) {
              return;
            }
            interposed = true;
            final destination = File(
              p.join(
                roots.support.path,
                'entries',
                'blobs',
                context.destinationName!,
              ),
            );
            destination.renameSync('${destination.path}.interposed');
            destination.writeAsBytesSync([6, 6, 6], flush: true);
          },
        );
        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));

        SecureBlobFileSystemFailure? failure;
        try {
          await fileSystem.finalize(
            staged,
            destinationName: 'entry-1.keeper',
            publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
          );
        } on SecureBlobFileSystemFailure catch (error) {
          failure = error;
        }

        expect(interposed, isTrue);
        expect(failure, isNotNull);
        expect(failure!.publishedBlobRef, isNull);
        expect(failure.finalBlobMayRemain, isTrue);
        final blobs = p.join(roots.support.path, 'entries', 'blobs');
        expect(await File(p.join(blobs, 'entry-1.keeper')).readAsBytes(), [
          6,
          6,
          6,
        ]);
        expect(
          await File(p.join(blobs, 'entry-1.keeper.interposed')).readAsBytes(),
          [1, 2, 3],
        );
      },
      skip: requiresPosix,
    );

    test(
      'private-authority release failure preserves finalize primary and state',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-release-');
        addTearDown(roots.close);
        var interposed = false;
        var releaseFailed = false;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (boundary ==
                    PosixFileBoundary.afterFinalLinkBeforeIdentityCheck &&
                !interposed) {
              interposed = true;
              final destination = File(
                p.join(
                  roots.support.path,
                  'entries',
                  'blobs',
                  context.destinationName!,
                ),
              );
              destination.renameSync('${destination.path}.interposed');
              destination.writeAsBytesSync([6, 6, 6], flush: true);
            }
            if (boundary == PosixFileBoundary.beforePrivateMutationRelease &&
                context.destinationName == 'entry-1.keeper' &&
                !releaseFailed) {
              releaseFailed = true;
              throw StateError('private authority release failed');
            }
          },
        );
        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));

        SecureBlobFileSystemFailure? failure;
        try {
          await fileSystem.finalize(
            staged,
            destinationName: 'entry-1.keeper',
            publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
          );
        } on SecureBlobFileSystemFailure catch (error) {
          failure = error;
        }

        expect(interposed, isTrue);
        expect(releaseFailed, isTrue);
        expect(failure, isNotNull);
        expect(failure!.primary.phase, EntrySavePhase.finalizeBlob);
        expect(failure.finalBlobMayRemain, isTrue);
        expect(
          failure.additionalFailures.map((cause) => cause.phase),
          contains(EntrySavePhase.finalBlobRollback),
        );
        expect(
          failure.additionalFailures.map((cause) => cause.error),
          contains(isA<PrivateMutationReleaseFailure>()),
        );
        expect(
          failure.additionalFailures.last.error,
          isA<PrivateMutationReleaseFailure>(),
        );
        final blobs = p.join(roots.support.path, 'entries', 'blobs');
        expect(await File(p.join(blobs, 'entry-1.keeper')).readAsBytes(), [
          6,
          6,
          6,
        ]);
        expect(
          await File(p.join(blobs, 'entry-1.keeper.interposed')).readAsBytes(),
          [1, 2, 3],
        );
      },
      skip: requiresPosix,
    );

    test(
      'read and rollback remain bound to the opened blobs directory',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-blob-parent-');
        addTearDown(roots.close);
        final outside = Directory(p.join(roots.sandbox.path, 'outside'))
          ..createSync();
        final outsideBlob = File(p.join(outside.path, 'entry-1.keeper'))
          ..writeAsBytesSync([8, 8, 8], flush: true);
        PosixFileBoundary? targetBoundary;
        Directory? retained;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (boundary != targetBoundary || retained != null) {
              return;
            }
            final blobs = Directory(
              p.join(roots.support.path, 'entries', 'blobs'),
            );
            retained = Directory('${blobs.path}.retained');
            blobs.renameSync(retained!.path);
            Link(blobs.path).createSync(outside.path);
          },
        );
        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));
        final finalized = await fileSystem.finalize(
          staged,
          destinationName: 'entry-1.keeper',
          publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
        );

        targetBoundary = PosixFileBoundary.afterBlobLeafOpenBeforeRead;
        expect(await fileSystem.readBlob('entry-1.keeper'), [1, 2, 3]);
        _restoreLinkedDirectory(
          p.join(roots.support.path, 'entries', 'blobs'),
          retained!,
        );
        retained = null;

        targetBoundary = PosixFileBoundary.beforeBlobUnlink;
        await fileSystem.rollbackBlob(finalized);
        expect(await outsideBlob.readAsBytes(), [8, 8, 8]);
        expect(
          File(p.join(retained!.path, 'entry-1.keeper')).existsSync(),
          isFalse,
        );
      },
      skip: requiresPosix,
    );

    test(
      'rollback detects a post-open blob replacement and protects its target',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-rollback-leaf-');
        addTearDown(roots.close);
        final protected = File(p.join(roots.sandbox.path, 'protected.bin'))
          ..writeAsBytesSync([9, 9, 9], flush: true);
        var interposed = false;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (boundary != PosixFileBoundary.beforeBlobUnlink || interposed) {
              return;
            }
            interposed = true;
            final destination = File(
              p.join(
                roots.support.path,
                'entries',
                'blobs',
                context.destinationName!,
              ),
            );
            destination.renameSync('${destination.path}.retained');
            Link(destination.path).createSync(protected.path);
          },
        );
        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));
        final finalized = await fileSystem.finalize(
          staged,
          destinationName: 'entry-1.keeper',
          publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
        );

        await expectLater(
          fileSystem.rollbackBlob(finalized),
          throwsA(isA<FileSystemException>()),
        );

        expect(interposed, isTrue);
        expect(await protected.readAsBytes(), [9, 9, 9]);
        expect(
          Link(p.join(roots.support.path, 'entries', 'blobs', 'entry-1.keeper'))
              .existsSync(),
          isTrue,
        );
        expect(
          File(
            p.join(
              roots.support.path,
              'entries',
              'blobs',
              'entry-1.keeper.retained',
            ),
          ).existsSync(),
          isTrue,
        );
      },
      skip: requiresPosix,
    );

    test(
      'rollback restores a regular-file replacement without unlinking it',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-rollback-file-');
        addTearDown(roots.close);
        var interposed = false;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (boundary != PosixFileBoundary.beforeBlobUnlink || interposed) {
              return;
            }
            interposed = true;
            final destination = File(
              p.join(
                roots.support.path,
                'entries',
                'blobs',
                context.destinationName!,
              ),
            );
            destination.renameSync('${destination.path}.retained');
            destination.writeAsBytesSync([8, 8, 8], flush: true);
          },
        );
        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));
        final finalized = await fileSystem.finalize(
          staged,
          destinationName: 'entry-1.keeper',
          publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
        );

        await expectLater(
          fileSystem.rollbackBlob(finalized),
          throwsA(isA<FileSystemException>()),
        );

        final destination = File(
          p.join(roots.support.path, 'entries', 'blobs', 'entry-1.keeper'),
        );
        expect(await destination.readAsBytes(), [8, 8, 8]);
        expect(await File('${destination.path}.retained').readAsBytes(), [
          1,
          2,
          3,
        ]);
      },
      skip: requiresPosix,
    );

    test(
      'pre-existing operation-like directory is never adopted or mutated',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-private-op-');
        addTearDown(roots.close);
        var rollbackStarted = false;
        var observedFreshAuthority = false;
        final quarantine = Directory(
          p.join(roots.support.path, 'entries', 'quarantine'),
        );
        late final Directory preexisting;
        late final File protected;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, _) {
            if (!rollbackStarted ||
                boundary !=
                    PosixFileBoundary
                        .afterQuarantineIdentityCheckBeforeUnlink) {
              return;
            }
            final operationDirectories = quarantine
                .listSync(followLinks: false)
                .whereType<Directory>()
                .toList();
            expect(operationDirectories, hasLength(2));
            expect(protected.existsSync(), isTrue);
            observedFreshAuthority = operationDirectories.any(
              (directory) =>
                  directory.path != preexisting.path &&
                  directory.listSync(followLinks: false).length == 1,
            );
          },
        );
        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));
        final finalized = await fileSystem.finalize(
          staged,
          destinationName: 'entry-1.keeper',
          publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
        );
        preexisting = Directory(p.join(quarantine.path, 'operation-existing'))
          ..createSync();
        final chmod = Process.runSync('chmod', ['0700', preexisting.path]);
        expect(chmod.exitCode, 0);
        protected = File(p.join(preexisting.path, 'unrelated.bin'))
          ..writeAsBytesSync([9, 9, 9], flush: true);

        rollbackStarted = true;
        await fileSystem.rollbackBlob(finalized);

        expect(observedFreshAuthority, isTrue);
        expect(await protected.readAsBytes(), [9, 9, 9]);
      },
      skip: requiresPosix,
    );

    test(
      'public-name replacement during private removal is never deleted',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-final-file-');
        addTearDown(roots.close);
        var rollbackStarted = false;
        var interposed = false;
        final destination = File(
          p.join(roots.support.path, 'entries', 'blobs', 'entry-1.keeper'),
        );
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (!rollbackStarted ||
                interposed ||
                boundary !=
                    PosixFileBoundary
                        .afterQuarantineIdentityCheckBeforeUnlink ||
                context.destinationName != 'entry-1.keeper') {
              return;
            }
            interposed = true;
            _expectFreshPrivateRemovalBoundary(roots.support);
            destination.writeAsBytesSync([8, 8, 8], flush: true);
          },
        );
        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));
        final finalized = await fileSystem.finalize(
          staged,
          destinationName: 'entry-1.keeper',
          publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
        );

        rollbackStarted = true;
        await fileSystem.rollbackBlob(finalized);

        expect(interposed, isTrue);
        expect(await destination.readAsBytes(), [8, 8, 8]);
      },
      skip: requiresPosix,
    );

    test(
      'rollback retains publication when private-authority root loses 0700',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-quarantine-');
        addTearDown(roots.close);
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
        );
        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));
        final finalized = await fileSystem.finalize(
          staged,
          destinationName: 'entry-1.keeper',
          publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
        );
        final quarantine = Directory(
          p.join(roots.support.path, 'entries', 'quarantine'),
        );
        final chmod = Process.runSync('chmod', ['0777', quarantine.path]);
        expect(chmod.exitCode, 0);

        await expectLater(
          fileSystem.rollbackBlob(finalized),
          throwsA(isA<FileSystemException>()),
        );

        expect(await fileSystem.readBlob('entry-1.keeper'), [1, 2, 3]);
      },
      skip: requiresPosix,
    );

    test(
      'public-name symlink during private removal is never deleted',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-final-link-');
        addTearDown(roots.close);
        final protected = File(p.join(roots.sandbox.path, 'protected.bin'))
          ..writeAsBytesSync([9, 9, 9], flush: true);
        final destination = p.join(
          roots.support.path,
          'entries',
          'blobs',
          'entry-1.keeper',
        );
        var rollbackStarted = false;
        var interposed = false;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (!rollbackStarted ||
                interposed ||
                boundary !=
                    PosixFileBoundary
                        .afterQuarantineIdentityCheckBeforeUnlink ||
                context.destinationName != 'entry-1.keeper') {
              return;
            }
            interposed = true;
            _expectFreshPrivateRemovalBoundary(roots.support);
            Link(destination).createSync(protected.path);
          },
        );
        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));
        final finalized = await fileSystem.finalize(
          staged,
          destinationName: 'entry-1.keeper',
          publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
        );

        rollbackStarted = true;
        await fileSystem.rollbackBlob(finalized);

        expect(interposed, isTrue);
        expect(Link(destination).existsSync(), isTrue);
        expect(await protected.readAsBytes(), [9, 9, 9]);
      },
      skip: requiresPosix,
    );

    test(
      'plaintext cleanup unlinks through its retained capture-root handle',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-plaintext-');
        addTearDown(roots.close);
        final owned = File(p.join(roots.capture.path, 'capture.tmp'))
          ..writeAsStringSync('owned', flush: true);
        final outside = Directory(p.join(roots.sandbox.path, 'outside'))
          ..createSync();
        final outsideFile = File(p.join(outside.path, 'capture.tmp'))
          ..writeAsStringSync('protected', flush: true);
        Directory? retained;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (boundary != PosixFileBoundary.beforePlaintextUnlink ||
                retained != null) {
              return;
            }
            retained = Directory('${roots.capture.path}.retained');
            roots.capture.renameSync(retained!.path);
            Link(roots.capture.path).createSync(outside.path);
          },
        );
        final cleanup = await fileSystem.validatePlaintextRefs(const [
          ['capture.tmp'],
        ]);

        await fileSystem.deletePlaintext(cleanup);

        expect(
          File(p.join(retained!.path, p.basename(owned.path))).existsSync(),
          isFalse,
        );
        expect(await outsideFile.readAsString(), 'protected');
      },
      skip: requiresPosix,
    );

    test(
      'plaintext leaf replacement is detected without touching its target',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-plain-leaf-');
        addTearDown(roots.close);
        final owned = File(p.join(roots.capture.path, 'capture.tmp'))
          ..writeAsStringSync('owned', flush: true);
        final protected = File(p.join(roots.sandbox.path, 'protected.tmp'))
          ..writeAsStringSync('protected', flush: true);
        var interposed = false;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (boundary != PosixFileBoundary.beforePlaintextUnlink ||
                interposed) {
              return;
            }
            interposed = true;
            owned.renameSync('${owned.path}.retained');
            Link(owned.path).createSync(protected.path);
          },
        );
        final cleanup = await fileSystem.validatePlaintextRefs(const [
          ['capture.tmp'],
        ]);

        await expectLater(
          fileSystem.deletePlaintext(cleanup),
          throwsA(isA<SecureBlobFileSystemFailure>()),
        );

        expect(interposed, isTrue);
        expect(await protected.readAsString(), 'protected');
        expect(Link(owned.path).existsSync(), isTrue);
        expect(File('${owned.path}.retained').existsSync(), isTrue);
      },
      skip: requiresPosix,
    );

    test(
      'plaintext cleanup restores a regular replacement without deleting it',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-plain-file-');
        addTearDown(roots.close);
        final owned = File(p.join(roots.capture.path, 'capture.tmp'))
          ..writeAsStringSync('owned', flush: true);
        var interposed = false;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (boundary != PosixFileBoundary.beforePlaintextUnlink ||
                interposed) {
              return;
            }
            interposed = true;
            owned.renameSync('${owned.path}.retained');
            owned.writeAsStringSync('unrelated', flush: true);
          },
        );
        final cleanup = await fileSystem.validatePlaintextRefs(const [
          ['capture.tmp'],
        ]);

        await expectLater(
          fileSystem.deletePlaintext(cleanup),
          throwsA(isA<SecureBlobFileSystemFailure>()),
        );

        expect(await owned.readAsString(), 'unrelated');
        expect(await File('${owned.path}.retained').readAsString(), 'owned');
      },
      skip: requiresPosix,
    );

    test(
      'attempt cleanup remains bound when the staging pathname is swapped',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-attempt-');
        addTearDown(roots.close);
        final outside = Directory(p.join(roots.sandbox.path, 'outside'))
          ..createSync();
        Directory? retained;
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          boundaryHook: (boundary, context) {
            if (boundary != PosixFileBoundary.beforeAttemptCleanup ||
                retained != null) {
              return;
            }
            final staging = Directory(
              p.join(roots.support.path, 'entries', 'staging'),
            );
            retained = Directory('${staging.path}.retained');
            staging.renameSync(retained!.path);
            Link(staging.path).createSync(outside.path);
          },
        );
        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));

        await fileSystem.finalize(
          staged,
          destinationName: 'entry-1.keeper',
          publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
        );

        expect(await outside.list().toList(), isEmpty);
        expect(await retained!.list().toList(), isEmpty);
      },
      skip: requiresPosix,
    );

    test(
      'syscall cleanup faults preserve finalize primary and close every fd',
      () async {
        final roots = await _PosixRoots.create('keepers-posix-syscall-fault-');
        addTearDown(roots.close);
        var injectCleanupFailures = false;
        final observed = <PosixSyscallOperation>[];
        final fileSystem = PosixSecureBlobFileSystem(
          supportDirectory: roots.support,
          captureTemporaryDirectory: roots.capture,
          syscallFaultInjector: PosixSyscallFaultInjector((operation) {
            if (!injectCleanupFailures) {
              return;
            }
            observed.add(operation);
            if (operation != PosixSyscallOperation.fstat) {
              throw StateError('injected ${operation.name}');
            }
          }),
          boundaryHook: (boundary, context) {
            if (boundary == PosixFileBoundary.beforeFinalLink) {
              injectCleanupFailures = true;
              throw StateError('finalize primary');
            }
          },
        );
        final staged = await fileSystem.stage(Uint8List.fromList([1, 2, 3]));

        SecureBlobFileSystemFailure? failure;
        try {
          await fileSystem.finalize(
            staged,
            destinationName: 'entry-1.keeper',
            publishedRef: p.join('entries', 'blobs', 'entry-1.keeper'),
          );
        } on SecureBlobFileSystemFailure catch (error) {
          failure = error;
        }

        expect(failure, isNotNull);
        expect(
          (failure!.primary.error as StateError).message,
          'finalize primary',
        );
        expect(
          failure.additionalFailures.map((cause) => cause.phase),
          everyElement(EntrySavePhase.stagingCleanup),
        );
        expect(observed, contains(PosixSyscallOperation.fstat));
        expect(observed, contains(PosixSyscallOperation.unlinkat));
        expect(observed, contains(PosixSyscallOperation.fsync));
        expect(
          observed.where((item) => item == PosixSyscallOperation.close),
          hasLength(7),
        );
      },
      skip: requiresPosix,
    );
  });

  test(
    'Windows is explicitly unsupported by the production filesystem',
    () async {
      final roots = await _PosixRoots.create('keepers-windows-unsupported-');
      addTearDown(roots.close);
      final store = EncryptedBlobStore(
        roots.support,
        captureTemporaryDirectory: roots.capture,
      );

      await expectLater(
        store.stage('entry-1', Uint8List.fromList([1])),
        throwsUnsupportedError,
      );
    },
    skip: Platform.isWindows
        ? false
        : 'Windows-only fail-closed contract check.',
  );
}

void _restoreLinkedDirectory(String linkPath, Directory retained) {
  Link(linkPath).deleteSync();
  retained.renameSync(linkPath);
}

void _expectFreshPrivateRemovalBoundary(Directory support) {
  final entries = Directory(p.join(support.path, 'entries'));
  final blobs = Directory(p.join(entries.path, 'blobs'));
  final quarantine = Directory(p.join(entries.path, 'quarantine'));
  expect(
    blobs
        .listSync(followLinks: false)
        .map((entity) => p.basename(entity.path))
        .where((name) => name.startsWith('quarantine-')),
    isEmpty,
  );
  expect(quarantine.existsSync(), isTrue);
  expect(quarantine.statSync().mode & 0x1ff, 0x1c0);
  final operationAuthorities = quarantine
      .listSync(followLinks: false)
      .whereType<Directory>()
      .where((directory) => p.basename(directory.path).startsWith('operation-'))
      .toList();
  expect(operationAuthorities, hasLength(1));
  final authority = operationAuthorities.single;
  expect(authority.statSync().mode & 0x1ff, 0x1c0);
  expect(authority.listSync(followLinks: false), hasLength(1));
}

final class _PosixRoots {
  const _PosixRoots(this.sandbox, this.support, this.capture);

  final Directory sandbox;
  final Directory support;
  final Directory capture;

  static Future<_PosixRoots> create(String prefix) async {
    final sandbox = await Directory.systemTemp.createTemp(prefix);
    final support = Directory(p.join(sandbox.path, 'support'));
    final capture = Directory(p.join(sandbox.path, 'capture'));
    await support.create();
    await capture.create();
    return _PosixRoots(sandbox, support, capture);
  }

  Future<void> close() async {
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  }
}
