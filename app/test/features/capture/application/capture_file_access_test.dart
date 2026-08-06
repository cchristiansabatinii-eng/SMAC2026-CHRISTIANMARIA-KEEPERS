import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/application/capture_providers.dart';
import 'package:keepers/features/capture/data/encrypted_blob_store.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:path/path.dart' as p;

import '../data/test_secure_blob_file_system.dart';

void main() {
  late Directory root;
  late Directory support;
  late Directory capture;
  late EncryptedBlobStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('capture-access-');
    capture = Directory('${root.path}${Platform.pathSeparator}keepers-capture')
      ..createSync();
    support = await Directory.systemTemp.createTemp('capture-support-');
    store = testEncryptedBlobStore(support, root);
  });
  tearDown(() async {
    await root.delete(recursive: true);
    await support.delete(recursive: true);
  });

  OwnedCaptureFileAccess access({
    PosixFileBoundaryHook? hook,
    String Function()? idFactory,
    bool failSourceClose = false,
    int failCaptureSnapshotDeletes = 0,
  }) {
    if (hook != null || failSourceClose || failCaptureSnapshotDeletes > 0) {
      store = testEncryptedBlobStore(
        support,
        root,
        failCaptureSnapshotDeletes: failCaptureSnapshotDeletes,
        captureBoundaryHook: hook,
        failCaptureSourceClose: failSourceClose,
      );
    }
    return OwnedCaptureFileAccess(
      temporaryDirectory: () async => root,
      idFactory: idFactory ?? () => 'fixed',
      blobStore: () async => store,
    );
  }

  test('rejects traversal and sibling-prefix paths', () async {
    final outside = File('${root.path}${Platform.pathSeparator}outside.jpg')
      ..writeAsBytesSync([1]);
    final sibling = Directory('${capture.path}-sibling')..createSync();
    final siblingFile = File('${sibling.path}${Platform.pathSeparator}x.jpg')
      ..writeAsBytesSync([2]);
    await expectLater(access().read(outside.path), throwsArgumentError);
    await expectLater(access().read(siblingFile.path), throwsArgumentError);
  });

  test('rejects a symlink source without reading its target', () async {
    final outside = File('${root.path}${Platform.pathSeparator}secret.jpg')
      ..writeAsBytesSync([9]);
    final link = Link('${capture.path}${Platform.pathSeparator}link.jpg');
    await link.create(outside.path);
    await expectLater(
      access().read(link.path),
      throwsA(isA<FileSystemException>()),
    );
  }, skip: Platform.isWindows ? 'Requires POSIX symlink creation' : false);

  test('exclusive random snapshots do not collide', () async {
    final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    final first = await access().read(source.path);
    final second = await access().read(source.path);
    expect(first.plaintextRef, isNot(second.plaintextRef));
    await first.release();
    await second.release();
  });

  test('snapshot release removes the identity-bound real file', () async {
    final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    final media = await access().read(source.path);
    final snapshot = File(
      '${root.path}${Platform.pathSeparator}${media.plaintextRef}',
    );
    expect(snapshot.existsSync(), isTrue);
    final attempt = snapshot.parent;
    await media.release();
    expect(snapshot.existsSync(), isFalse);
    expect(attempt.existsSync(), isFalse);
  });

  test(
    'snapshot owner does not expose raw secure authority dynamically',
    () async {
      File('${capture.path}${Platform.pathSeparator}photo.jpg')
          .writeAsBytesSync([1, 2, 3]);
      final owner = await store.createCaptureSnapshot(
        relativeSource: 'keepers-capture/photo.jpg',
        snapshotId: 'opaque',
        extension: 'jpg',
      );

      expect(owner.relativePath, isNotEmpty);
      expect(owner.bytes, [1, 2, 3]);
      expect(
        () => (owner as dynamic).secure,
        throwsA(isA<NoSuchMethodError>()),
      );
      expect(
        () => (owner as dynamic).storeToken,
        throwsA(isA<NoSuchMethodError>()),
      );
      await store.deleteCaptureSnapshot(owner);
    },
  );

  test('snapshot cleanup rejects cross-store and forged owners', () async {
    File('${capture.path}${Platform.pathSeparator}photo.jpg')
        .writeAsBytesSync([1, 2, 3]);
    final owner = await store.createCaptureSnapshot(
      relativeSource: 'keepers-capture/photo.jpg',
      snapshotId: 'bound',
      extension: 'jpg',
    );
    final otherSupport = await Directory.systemTemp.createTemp(
      'capture-other-support-',
    );
    addTearDown(() async {
      if (await otherSupport.exists()) {
        await otherSupport.delete(recursive: true);
      }
    });
    final otherStore = testEncryptedBlobStore(otherSupport, root);

    await expectLater(
      otherStore.deleteCaptureSnapshot(owner),
      throwsArgumentError,
    );
    expect(
      () => store.deleteCaptureSnapshot(Object() as dynamic),
      throwsA(anyOf(isA<ArgumentError>(), isA<TypeError>())),
    );
    await store.deleteCaptureSnapshot(owner);
  });

  test('snapshot cleanup is idempotent for the same consumed owner', () async {
    final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    final owner = await store.createCaptureSnapshot(
      relativeSource: 'keepers-capture/photo.jpg',
      snapshotId: 'consumed',
      extension: 'jpg',
    );

    await store.deleteCaptureSnapshot(owner);
    await store.deleteCaptureSnapshot(owner);

    expect(
      capture
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.path),
      [source.path],
    );
  });

  test(
    'ambiguous snapshot close consumes authority without a descriptor retry',
    () async {
      final secure = TestSecureBlobFileSystem(
        supportDirectory: support,
        captureTemporaryDirectory: root,
        failCaptureSnapshotCloseAfterCleanup: 1,
      );
      store = EncryptedBlobStore(
        support,
        captureTemporaryDirectory: root,
        fileSystem: secure,
      );
      final fileAccess = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'ambiguous',
        blobStore: () async => store,
      );
      final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final media = await fileAccess.read(source.path);

      await expectLater(media.release(), throwsA(anything));
      await media.release();
      await fileAccess.retryPendingCleanup();

      expect(secure.captureSnapshotCleanupCalls, 1);
      expect(
        capture
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => file.path),
        [source.path],
      );
    },
  );

  test(
    'snapshot release revalidates fresh authority after a failed delete',
    () async {
      store = testEncryptedBlobStore(
        support,
        root,
        failCaptureSnapshotDeletes: 1,
      );
      final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final media = await access().read(source.path);
      final snapshot = File(
        '${root.path}${Platform.pathSeparator}${media.plaintextRef}',
      );

      await expectLater(media.release(), throwsA(anything));
      expect(snapshot.existsSync(), isTrue);
      await media.release();

      expect(snapshot.existsSync(), isFalse);
    },
  );

  test('rejects generated identifiers that contain path segments', () async {
    final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    await expectLater(
      access(idFactory: () => '..${Platform.pathSeparator}escape')
          .read(source.path),
      throwsArgumentError,
    );
  });

  test(
    'source swap after open reads the retained file identity',
    () async {
      final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final replacement = File(
        '${capture.path}${Platform.pathSeparator}new.jpg',
      )..writeAsBytesSync([8, 8]);
      final media = await access(
        hook: (boundary, _) {
          if (boundary == PosixFileBoundary.afterCaptureSourceOpen) {
            source.renameSync(
              '${capture.path}${Platform.pathSeparator}old.jpg',
            );
            replacement.renameSync(source.path);
          }
        },
      ).read(source.path);
      expect(media.bytes, [1, 2, 3]);
      await media.release();
    },
    skip: Platform.isWindows ? 'Requires POSIX rename of an open file' : false,
  );

  test('partial snapshot failure removes every created artifact', () async {
    final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    await expectLater(
      access(
        hook: (boundary, _) {
          if (boundary == PosixFileBoundary.afterCaptureSnapshotCreate) {
            throw StateError('injected write failure');
          }
        },
      ).read(source.path),
      throwsA(isA<StateError>()),
    );
    final names = capture.listSync().map((entity) => entity.path).join('\n');
    expect(names, isNot(contains('snapshot-')));
  });

  test('attempt-only construction failure retains cleanup ownership', () async {
    final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    final fileAccess = access(
      hook: (boundary, _) {
        if (boundary == PosixFileBoundary.beforeCaptureSnapshotCreate) {
          throw StateError('injected snapshot-open failure');
        }
      },
    );

    await expectLater(fileAccess.read(source.path), throwsA(anything));
    await fileAccess.retryPendingCleanup();

    expect(
      capture
          .listSync(recursive: true)
          .whereType<FileSystemEntity>()
          .map((entity) => entity.path),
      [source.path],
    );
  });

  test(
    'post-mkdir attempt-open failure retains exact cleanup ownership',
    () async {
      final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final fileAccess = access(
        hook: (boundary, _) {
          if (boundary ==
              PosixFileBoundary.afterCaptureAttemptCreateBeforeOpen) {
            throw StateError('injected capture attempt open failure');
          }
        },
      );

      await expectLater(fileAccess.read(source.path), throwsA(anything));
      await fileAccess.retryPendingCleanup();

      expect(
        capture
            .listSync(recursive: true)
            .whereType<FileSystemEntity>()
            .map((entity) => entity.path),
        [source.path],
      );
    },
  );

  test(
    'post-open attempt-stat failure retains exact cleanup ownership',
    () async {
      final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final fileAccess = access(
        hook: (boundary, _) {
          if (boundary ==
              PosixFileBoundary.afterCaptureAttemptOpenBeforeIdentity) {
            throw StateError('injected capture attempt stat failure');
          }
        },
      );

      await expectLater(fileAccess.read(source.path), throwsA(anything));
      await fileAccess.retryPendingCleanup();

      expect(
        capture
            .listSync(recursive: true)
            .whereType<FileSystemEntity>()
            .map((entity) => entity.path),
        [source.path],
      );
    },
  );

  for (final boundary in <PosixFileBoundary>[
    PosixFileBoundary.afterCaptureAttemptCreateBeforeOpen,
    PosixFileBoundary.afterCaptureAttemptOpenBeforeIdentity,
  ]) {
    test(
      'production POSIX retains post-mkdir authority at ${boundary.name}',
      () async {
        final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
          ..writeAsBytesSync([1, 2, 3]);
        final productionStore = EncryptedBlobStore(
          support,
          captureTemporaryDirectory: root,
          fileSystem: PosixSecureBlobFileSystem(
            supportDirectory: support,
            captureTemporaryDirectory: root,
            boundaryHook: (observed, _) {
              if (observed == boundary) {
                throw StateError('injected ${boundary.name} failure');
              }
            },
          ),
        );
        final fileAccess = OwnedCaptureFileAccess(
          temporaryDirectory: () async => root,
          idFactory: () => 'native-attempt',
          blobStore: () async => productionStore,
        );

        await expectLater(fileAccess.read(source.path), throwsA(anything));
        await fileAccess.retryPendingCleanup();

        expect(
          capture
              .listSync(recursive: true)
              .whereType<FileSystemEntity>()
              .map((entity) => entity.path),
          [source.path],
        );
      },
      skip: Platform.isWindows
          ? 'Production SecureBlobFileSystem intentionally requires POSIX'
          : false,
    );
  }

  test('construction failure registers residual cleanup for retry', () async {
    final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    final fileAccess = access(
      failCaptureSnapshotDeletes: 1,
      hook: (boundary, _) {
        if (boundary == PosixFileBoundary.afterCaptureSnapshotCreate) {
          throw StateError('construction failed');
        }
      },
    );
    await expectLater(fileAccess.read(source.path), throwsA(anything));
    expect(capture.listSync(recursive: true).whereType<File>(), isNotEmpty);

    await fileAccess.retryPendingCleanup();

    expect(
      capture
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.path),
      [source.path],
    );
  });

  test(
    'source close failure is accounted before snapshot ownership transfer',
    () async {
      final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final fileAccess = access(failSourceClose: true);

      await expectLater(
        fileAccess.read(source.path),
        throwsA(isA<StateError>()),
      );

      expect(
        capture
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => file.path),
        [source.path],
      );
    },
  );

  test(
    'production POSIX authority removes a constructed snapshot',
    () async {
      final productionStore = EncryptedBlobStore(
        support,
        captureTemporaryDirectory: root,
      );
      final fileAccess = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'native',
        blobStore: () async => productionStore,
      );
      final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final media = await fileAccess.read(source.path);
      final snapshot = File(
        '${root.path}${Platform.pathSeparator}${media.plaintextRef}',
      );
      expect(snapshot.existsSync(), isTrue);
      await media.release();
      expect(snapshot.existsSync(), isFalse);
    },
    skip: Platform.isWindows
        ? 'Production SecureBlobFileSystem intentionally requires POSIX'
        : false,
  );

  test(
    'production POSIX never retries a descriptor after ambiguous close',
    () async {
      var descriptorReleaseStarted = false;
      var closeInjected = false;
      final productionStore = EncryptedBlobStore(
        support,
        captureTemporaryDirectory: root,
        fileSystem: PosixSecureBlobFileSystem(
          supportDirectory: support,
          captureTemporaryDirectory: root,
          boundaryHook: (boundary, _) {
            if (boundary ==
                PosixFileBoundary.beforeCaptureSnapshotDescriptorRelease) {
              descriptorReleaseStarted = true;
            }
          },
          syscallFaultInjector: PosixSyscallFaultInjector((operation) {
            if (descriptorReleaseStarted &&
                operation == PosixSyscallOperation.close &&
                !closeInjected) {
              closeInjected = true;
              throw StateError('injected close-success ambiguity');
            }
          }),
        ),
      );
      final fileAccess = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'native-close',
        blobStore: () async => productionStore,
      );
      final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final media = await fileAccess.read(source.path);

      await expectLater(media.release(), throwsA(anything));
      expect(closeInjected, isTrue);
      final sentinels = <RandomAccessFile>[];
      addTearDown(() {
        for (final sentinel in sentinels) {
          try {
            sentinel.closeSync();
          } on FileSystemException {
            // A failing implementation may already have closed one sentinel.
          }
        }
      });
      for (var index = 0; index < 32; index++) {
        sentinels.add(
          File(p.join(root.path, 'sentinel-$index.bin'))
              .openSync(mode: FileMode.write),
        );
      }

      await media.release();
      await fileAccess.retryPendingCleanup();

      for (var index = 0; index < sentinels.length; index++) {
        expect(
          () => sentinels[index].writeByteSync(index),
          returnsNormally,
          reason: 'sentinel descriptor $index was closed by a stale retry',
        );
      }
    },
    skip: Platform.isWindows
        ? 'Production SecureBlobFileSystem intentionally requires POSIX'
        : false,
  );

  test(
    'production POSIX rejects a source swap before operational open',
    () async {
      final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final replacement = File(
        '${capture.path}${Platform.pathSeparator}replacement.jpg',
      )..writeAsBytesSync([9, 9, 9]);
      final moved = File('${capture.path}${Platform.pathSeparator}moved.jpg');
      final productionStore = EncryptedBlobStore(
        support,
        captureTemporaryDirectory: root,
        fileSystem: PosixSecureBlobFileSystem(
          supportDirectory: support,
          captureTemporaryDirectory: root,
          boundaryHook: (boundary, context) {
            if (boundary == PosixFileBoundary.beforeCaptureSourceOpen) {
              source.renameSync(moved.path);
              replacement.renameSync(source.path);
            }
          },
        ),
      );
      final fileAccess = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'native',
        blobStore: () async => productionStore,
      );

      await expectLater(
        fileAccess.read(source.path),
        throwsA(isA<FileSystemException>()),
      );

      expect(moved.readAsBytesSync(), [1, 2, 3]);
      expect(source.readAsBytesSync(), [9, 9, 9]);
    },
    skip: Platform.isWindows
        ? 'Production SecureBlobFileSystem intentionally requires POSIX'
        : false,
  );

  test(
    'production POSIX retains a swapped snapshot identity as unresolved',
    () async {
      final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      late File moved;
      late File replacement;
      final productionStore = EncryptedBlobStore(
        support,
        captureTemporaryDirectory: root,
        fileSystem: PosixSecureBlobFileSystem(
          supportDirectory: support,
          captureTemporaryDirectory: root,
          boundaryHook: (boundary, context) {
            if (boundary == PosixFileBoundary.afterCaptureSnapshotCreate) {
              final snapshot = File(
                '${root.path}${Platform.pathSeparator}${context.plaintextSegments!.join(Platform.pathSeparator)}',
              );
              moved = File(
                '${snapshot.parent.path}${Platform.pathSeparator}moved.jpg',
              );
              replacement = File(snapshot.path);
              snapshot.renameSync(moved.path);
              replacement.writeAsBytesSync([8, 8, 8]);
            }
          },
        ),
      );
      final fileAccess = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'native',
        blobStore: () async => productionStore,
      );

      await expectLater(fileAccess.read(source.path), throwsA(anything));
      await expectLater(fileAccess.retryPendingCleanup(), throwsA(anything));

      expect(moved.existsSync(), isTrue);
      expect(replacement.existsSync(), isTrue);
      expect(replacement.readAsBytesSync(), [8, 8, 8]);
    },
    skip: Platform.isWindows
        ? 'Production SecureBlobFileSystem intentionally requires POSIX'
        : false,
  );

  test(
    'production POSIX cleanup retry never adopts a regular replacement',
    () async {
      final source = File('${capture.path}${Platform.pathSeparator}photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      var failFirstCleanup = true;
      final productionStore = EncryptedBlobStore(
        support,
        captureTemporaryDirectory: root,
        fileSystem: PosixSecureBlobFileSystem(
          supportDirectory: support,
          captureTemporaryDirectory: root,
          boundaryHook: (boundary, context) {
            if (boundary == PosixFileBoundary.beforeCaptureSnapshotCleanup &&
                failFirstCleanup) {
              failFirstCleanup = false;
              throw StateError('injected first cleanup failure');
            }
          },
        ),
      );
      final fileAccess = OwnedCaptureFileAccess(
        temporaryDirectory: () async => root,
        idFactory: () => 'native',
        blobStore: () async => productionStore,
      );
      final media = await fileAccess.read(source.path);
      final snapshot = File(
        '${root.path}${Platform.pathSeparator}${media.plaintextRef}',
      );
      final moved = File(
        '${snapshot.parent.path}${Platform.pathSeparator}moved.jpg',
      );

      await expectLater(media.release(), throwsA(anything));
      snapshot.renameSync(moved.path);
      final replacement = File(snapshot.path)..writeAsBytesSync([8, 8, 8]);
      await expectLater(media.release(), throwsA(anything));
      await expectLater(fileAccess.retryPendingCleanup(), throwsA(anything));

      expect(moved.existsSync(), isTrue);
      expect(replacement.existsSync(), isTrue);
      expect(replacement.readAsBytesSync(), [8, 8, 8]);
    },
    skip: Platform.isWindows
        ? 'Production SecureBlobFileSystem intentionally requires POSIX'
        : false,
  );

  test('production provider wires the hardened capture authority', () {
    final container = ProviderContainer(
      overrides: [
        temporaryDirectoryProvider.overrideWithValue(AsyncData(capture)),
        entryBlobStoreProvider.overrideWithValue(AsyncData(store)),
        idFactoryProvider.overrideWithValue(() => 'fixed'),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(captureFileAccessProvider),
      isA<OwnedCaptureFileAccess>(),
    );
  });
}
