import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/data/encrypted_blob_store.dart';

void main() {
  group('cooperative private-authority removal', () {
    test('regular-file replacement is restored and never unlinked', () {
      const intended = SecureFileIdentity(device: 1, inode: 10);
      const unrelated = SecureFileIdentity(device: 1, inode: 20);
      final operations = _MemoryQuarantineOperations({
        'entry.keeper': unrelated,
        'entry.keeper.retained': intended,
      });

      final result = const AnchoredQuarantineRemovalProtocol().removeExpected(
        operations: operations,
        originalName: 'entry.keeper',
        expectedIdentity: intended,
        kind: SecureFileKind.regular,
      );

      expect(result.state, QuarantineRemovalState.mismatchRestored);
      expect(operations.entries['entry.keeper'], unrelated);
      expect(operations.entries['entry.keeper.retained'], intended);
      expect(operations.unlinked, isEmpty);
    });

    test('symlink replacement is restored without touching its target', () {
      const intended = SecureFileIdentity(device: 1, inode: 10);
      const link = SecureFileIdentity(device: 1, inode: 30);
      final operations = _MemoryQuarantineOperations(
        {'capture.tmp': link, 'capture.tmp.retained': intended},
        links: {'capture.tmp'},
      );

      final result = const AnchoredQuarantineRemovalProtocol().removeExpected(
        operations: operations,
        originalName: 'capture.tmp',
        expectedIdentity: intended,
        kind: SecureFileKind.regular,
      );

      expect(result.state, QuarantineRemovalState.unverifiedRestored);
      expect(operations.entries['capture.tmp'], link);
      expect(operations.unlinked, isEmpty);
    });

    test('restore collision retains the mismatched entry in quarantine', () {
      const intended = SecureFileIdentity(device: 1, inode: 10);
      const unrelated = SecureFileIdentity(device: 1, inode: 20);
      const racing = SecureFileIdentity(device: 1, inode: 40);
      final operations = _MemoryQuarantineOperations({
        'entry.keeper': unrelated,
        'entry.keeper.retained': intended,
      }, beforeRestore: (entries) => entries['entry.keeper'] = racing);

      final result = const AnchoredQuarantineRemovalProtocol().removeExpected(
        operations: operations,
        originalName: 'entry.keeper',
        expectedIdentity: intended,
        kind: SecureFileKind.regular,
      );

      expect(result.state, QuarantineRemovalState.mismatchQuarantined);
      expect(operations.entries['entry.keeper'], racing);
      expect(operations.entries[result.quarantineName], unrelated);
      expect(operations.unlinked, isEmpty);
    });

    test('removal exposes the verified post-unlink link count', () {
      const intended = SecureFileIdentity(device: 1, inode: 10);
      final operations = _MemoryQuarantineOperations({
        'capture.tmp': intended,
      }, postUnlinkLinkCount: 1);

      final result = const AnchoredQuarantineRemovalProtocol().removeExpected(
        operations: operations,
        originalName: 'capture.tmp',
        expectedIdentity: intended,
        kind: SecureFileKind.regular,
      );

      expect(result.state, QuarantineRemovalState.removed);
      expect(result.postRemovalLinkCount, 1);
      expect(operations.entries, isEmpty);
      expect(operations.unlinked, [intended]);
      expect(operations.opened, [intended, intended]);
    });

    test('release failure preserves the completed removal result', () {
      const intended = SecureFileIdentity(device: 1, inode: 10);
      final releaseError = StateError('private authority release failed');
      final operations = _MemoryQuarantineOperations({
        'capture.tmp': intended,
      }, releaseError: releaseError);

      final result = const AnchoredQuarantineRemovalProtocol().removeExpected(
        operations: operations,
        originalName: 'capture.tmp',
        expectedIdentity: intended,
        kind: SecureFileKind.regular,
      );

      expect(result.state, QuarantineRemovalState.removed);
      expect(result.postRemovalLinkCount, 0);
      expect(result.error, isNull);
      expect(result.releaseError, same(releaseError));
      expect(result.releaseStackTrace, isNotNull);
      expect(result.artifactMayRemain, isTrue);
      expect(operations.entries, isEmpty);
    });

    test('release failure is appended after the operation failure', () {
      const intended = SecureFileIdentity(device: 1, inode: 10);
      final operationError = StateError('candidate could not be opened');
      final releaseError = StateError('private authority release failed');
      final operations = _MemoryQuarantineOperations(
        {'capture.tmp': intended},
        openError: operationError,
        releaseError: releaseError,
      );

      final result = const AnchoredQuarantineRemovalProtocol().removeExpected(
        operations: operations,
        originalName: 'capture.tmp',
        expectedIdentity: intended,
        kind: SecureFileKind.regular,
      );

      expect(result.state, QuarantineRemovalState.unverifiedRestored);
      expect(result.error, same(operationError));
      expect(result.releaseError, same(releaseError));
      expect(operations.entries['capture.tmp'], intended);
      expect(operations.unlinked, isEmpty);
    });

    test('unavailable private authority preserves the original entry', () {
      const intended = SecureFileIdentity(device: 1, inode: 10);
      final operations = _MemoryQuarantineOperations({
        'capture.tmp': intended,
      }, beginError: StateError('authority unavailable'));

      final result = const AnchoredQuarantineRemovalProtocol().removeExpected(
        operations: operations,
        originalName: 'capture.tmp',
        expectedIdentity: intended,
        kind: SecureFileKind.regular,
      );

      expect(result.state, QuarantineRemovalState.quarantineFailed);
      expect(operations.entries['capture.tmp'], intended);
      expect(operations.unlinked, isEmpty);
      expect(operations.privateBegins, 1);
      expect(operations.privateReleases, 0);
    });
  });

  group('failure-total cleanup sequencing', () {
    test('syscall injector preserves fstat unlink fsync close order', () {
      final visited = <PosixSyscallOperation>[];
      final injector = PosixSyscallFaultInjector((operation) {
        visited.add(operation);
        throw StateError('injected ${operation.name}');
      });
      final result = const FailureTotalCleanupRunner().run([
        for (final operation in PosixSyscallOperation.values)
          PosixCleanupAction(switch (operation) {
            PosixSyscallOperation.fstat => PosixCleanupOperation.fstat,
            PosixSyscallOperation.unlinkat => PosixCleanupOperation.unlinkat,
            PosixSyscallOperation.fsync => PosixCleanupOperation.fsync,
            PosixSyscallOperation.close => PosixCleanupOperation.closeSource,
          }, () => injector.afterSuccess(operation)),
      ]);

      expect(visited, PosixSyscallOperation.values);
      expect(result.failures, hasLength(PosixSyscallOperation.values.length));
      expect(result.failures.map((failure) => failure.operation), [
        PosixCleanupOperation.fstat,
        PosixCleanupOperation.unlinkat,
        PosixCleanupOperation.fsync,
        PosixCleanupOperation.closeSource,
      ]);
    });

    test('fstat unlink fsync and every close failure retain their order', () {
      final visited = <PosixCleanupOperation>[];
      final result = const FailureTotalCleanupRunner().run([
        for (final operation in PosixCleanupOperation.values)
          PosixCleanupAction(operation, () {
            visited.add(operation);
            throw StateError(operation.name);
          }),
      ]);

      expect(visited, PosixCleanupOperation.values);
      expect(
        result.failures.map((failure) => failure.operation),
        PosixCleanupOperation.values,
      );
      expect(
        result.failures.map((failure) => (failure.error as StateError).message),
        PosixCleanupOperation.values.map((operation) => operation.name),
      );
    });

    test('later closes still run after successful and failed operations', () {
      final visited = <PosixCleanupOperation>[];
      final result = const FailureTotalCleanupRunner().run([
        PosixCleanupAction(PosixCleanupOperation.fstat, () {
          visited.add(PosixCleanupOperation.fstat);
          throw StateError('primary cleanup failure');
        }),
        PosixCleanupAction(PosixCleanupOperation.unlinkat, () {
          visited.add(PosixCleanupOperation.unlinkat);
        }),
        PosixCleanupAction(PosixCleanupOperation.closeSource, () {
          visited.add(PosixCleanupOperation.closeSource);
          throw StateError('source close');
        }),
        PosixCleanupAction(PosixCleanupOperation.closeAttempt, () {
          visited.add(PosixCleanupOperation.closeAttempt);
        }),
        PosixCleanupAction(PosixCleanupOperation.closeLayout, () {
          visited.add(PosixCleanupOperation.closeLayout);
        }),
      ]);

      expect(visited, [
        PosixCleanupOperation.fstat,
        PosixCleanupOperation.unlinkat,
        PosixCleanupOperation.closeSource,
        PosixCleanupOperation.closeAttempt,
        PosixCleanupOperation.closeLayout,
      ]);
      expect(result.failures.map((failure) => failure.operation), [
        PosixCleanupOperation.fstat,
        PosixCleanupOperation.closeSource,
      ]);
    });
  });

  group('native stat ABI fixtures', () {
    test('macOS x64 selects INODE64 and decodes its checked fixture', () {
      final layout = PosixStatLayout.forAbi(PosixNativeAbi.macosX64);
      final bytes = Uint8List(32)
        ..setAll(0, const [1, 2, 3, 4, 0, 128, 3, 0])
        ..setAll(8, const [8, 7, 6, 5, 4, 3, 2, 1]);

      final stat = layout.decode(bytes);

      expect(layout.fstatSymbol, r'fstat$INODE64');
      expect(stat.device, 0x04030201);
      expect(stat.inode, 0x0102030405060708);
      expect(stat.mode, 0x8000);
      expect(stat.linkCount, 3);
    });

    test('Darwin arm64 selects the only-64-bit fstat ABI', () {
      final layout = PosixStatLayout.forAbi(PosixNativeAbi.macosArm64);
      expect(layout.fstatSymbol, 'fstat');
      expect(layout.modeOffset, 4);
      expect(layout.linkCountOffset, 6);
      expect(layout.inodeOffset, 8);
    });

    test('iOS arm64 uses the Darwin 64-bit stat and symbol profile', () {
      final layout = PosixStatLayout.forAbi(PosixNativeAbi.iosArm64);

      expect(selectPosixNativeAbi(Abi.iosArm64), PosixNativeAbi.iosArm64);
      expect(layout.fstatSymbol, 'fstat');
      expect(layout.modeOffset, 4);
      expect(layout.linkCountOffset, 6);
      expect(layout.ownerIdOffset, 16);
      expect(PosixNativeAbi.iosArm64.errnoSymbol, '__error');
      expect(PosixNativeAbi.iosArm64.usesDarwinRename, isTrue);
    });

    test('Linux x64 fixture decodes gated native ownership offsets', () {
      final layout = PosixStatLayout.forAbi(PosixNativeAbi.linuxX64);
      final bytes = Uint8List(40)
        ..setAll(0, const [9, 0, 0, 0, 0, 0, 0, 0])
        ..setAll(8, const [21, 0, 0, 0, 0, 0, 0, 0])
        ..setAll(16, const [2, 0, 0, 0, 0, 0, 0, 0])
        ..setAll(24, const [0, 128, 0, 0, 42, 0, 0, 0]);

      final stat = layout.decode(bytes);

      expect(layout.fstatSymbol, 'fstat');
      expect(stat.device, 9);
      expect(stat.inode, 21);
      expect(stat.mode, 0x8000);
      expect(stat.linkCount, 2);
      expect(stat.ownerId, 42);
    });

    test('Android x64 uses the Bionic x64 stat and syscall profile', () {
      final layout = PosixStatLayout.forAbi(PosixNativeAbi.androidX64);

      expect(selectPosixNativeAbi(Abi.androidX64), PosixNativeAbi.androidX64);
      expect(layout.deviceOffset, 0);
      expect(layout.inodeOffset, 8);
      expect(layout.linkCountOffset, 16);
      expect(layout.modeOffset, 24);
      expect(layout.ownerIdOffset, 28);
      expect(PosixNativeAbi.androidX64.errnoSymbol, '__errno');
      expect(PosixNativeAbi.androidX64.renameAt2SyscallNumber, 316);
      expect(
        publicationStrategyForAbi(PosixNativeAbi.androidX64),
        PosixPublicationStrategy.atomicMove,
      );
    });

    test('Android arm64 fixture decodes Bionic LP64 ownership offsets', () {
      final layout = PosixStatLayout.forAbi(PosixNativeAbi.androidArm64);
      final bytes = Uint8List(32)
        ..setAll(0, const [9, 0, 0, 0, 0, 0, 0, 0])
        ..setAll(8, const [21, 0, 0, 0, 0, 0, 0, 0])
        ..setAll(16, const [0, 128, 0, 0, 2, 0, 0, 0])
        ..setAll(24, const [42, 0, 0, 0]);

      final stat = layout.decode(bytes);

      expect(
        selectPosixNativeAbi(Abi.androidArm64),
        PosixNativeAbi.androidArm64,
      );
      expect(stat.device, 9);
      expect(stat.inode, 21);
      expect(stat.mode, 0x8000);
      expect(stat.linkCount, 2);
      expect(stat.ownerId, 42);
      expect(PosixNativeAbi.androidArm64.errnoSymbol, '__errno');
      expect(PosixNativeAbi.androidArm64.renameAt2SyscallNumber, 276);
      expect(
        publicationStrategyForAbi(PosixNativeAbi.androidArm64),
        PosixPublicationStrategy.atomicMove,
      );
    });

    test('desktop and Apple targets retain hard-link publication', () {
      for (final abi in const [
        PosixNativeAbi.linuxX64,
        PosixNativeAbi.macosX64,
        PosixNativeAbi.macosArm64,
        PosixNativeAbi.iosArm64,
      ]) {
        expect(
          publicationStrategyForAbi(abi),
          PosixPublicationStrategy.hardLink,
        );
      }
    });

    test('ungated ABIs fail closed in the production selector', () {
      expect(
        () => selectPosixNativeAbi(Abi.androidArm),
        throwsUnsupportedError,
      );
      expect(() => selectPosixNativeAbi(Abi.iosX64), throwsUnsupportedError);
      expect(
        () => selectPosixNativeAbi(Abi.linuxArm64),
        throwsUnsupportedError,
      );
    });
  });
}

final class _MemoryQuarantineOperations
    implements AnchoredQuarantineOperations {
  _MemoryQuarantineOperations(
    Map<String, SecureFileIdentity> entries, {
    Set<String>? links,
    this.beforeRestore,
    this.beginError,
    this.releaseError,
    this.openError,
    this.postUnlinkLinkCount = 0,
  }) : entries = Map.of(entries),
       links = Set.of(links ?? const {});

  final Map<String, SecureFileIdentity> entries;
  final Set<String> links;
  final void Function(Map<String, SecureFileIdentity> entries)? beforeRestore;
  final Object? beginError;
  final Object? releaseError;
  final Object? openError;
  final int postUnlinkLinkCount;
  int privateBegins = 0;
  int privateReleases = 0;
  final List<SecureFileIdentity> opened = [];
  final List<SecureFileIdentity> unlinked = [];

  @override
  void beginPrivateMutation() {
    privateBegins += 1;
    if (beginError != null) {
      throw beginError!;
    }
  }

  @override
  void releasePrivateMutation() {
    privateReleases += 1;
    if (releaseError != null) {
      throw releaseError!;
    }
  }

  @override
  String createQuarantineName() => '.quarantine-fixed';

  @override
  SecureFileIdentity openIdentity(String name, SecureFileKind kind) {
    if (openError != null) {
      throw openError!;
    }
    final identity = entries[name];
    if (identity == null) {
      throw const AnchoredEntryMissing();
    }
    if (links.contains(name)) {
      throw StateError('O_NOFOLLOW rejected link');
    }
    opened.add(identity);
    return identity;
  }

  @override
  void moveToQuarantineNoReplace(String sourceName, String quarantineName) {
    _renameNoReplace(sourceName, quarantineName);
  }

  @override
  void restoreFromQuarantineNoReplace(
    String quarantineName,
    String destinationName,
  ) {
    if (quarantineName == '.quarantine-fixed') {
      beforeRestore?.call(entries);
    }
    _renameNoReplace(quarantineName, destinationName);
  }

  void _renameNoReplace(String sourceName, String destinationName) {
    if (entries.containsKey(destinationName)) {
      throw const AnchoredDestinationExists();
    }
    final identity = entries.remove(sourceName);
    if (identity == null) {
      throw const AnchoredEntryMissing();
    }
    if (links.remove(sourceName)) {
      links.add(destinationName);
    }
    entries[destinationName] = identity;
  }

  @override
  int unlinkPrivateCandidate(
    String name,
    SecureFileKind kind,
    SecureFileIdentity expectedIdentity,
  ) {
    final identity = entries[name];
    if (identity == null) {
      throw const AnchoredEntryMissing();
    }
    if (identity != expectedIdentity || links.contains(name)) {
      throw StateError('Current quarantine name is not the verified entry');
    }
    entries.remove(name);
    links.remove(name);
    unlinked.add(identity);
    return postUnlinkLinkCount;
  }
}
