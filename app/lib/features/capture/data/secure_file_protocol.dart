import 'dart:ffi';
import 'dart:typed_data';

enum SecureFileKind { regular, directory }

final class SecureFileIdentity {
  const SecureFileIdentity({required this.device, required this.inode});

  final int device;
  final int inode;

  @override
  bool operator ==(Object other) =>
      other is SecureFileIdentity &&
      other.device == device &&
      other.inode == inode;

  @override
  int get hashCode => Object.hash(device, inode);
}

/// Signals an anchored lookup failure without exposing platform errno values to
/// the portable quarantine state machine.
final class AnchoredEntryMissing implements Exception {
  const AnchoredEntryMissing();
}

/// Signals that a no-replace rename found an occupied destination.
final class AnchoredDestinationExists implements Exception {
  const AnchoredDestinationExists();
}

abstract interface class AnchoredQuarantineOperations {
  void beginPrivateMutation();

  void releasePrivateMutation();

  String createQuarantineName();

  void moveToQuarantineNoReplace(String sourceName, String quarantineName);

  void restoreFromQuarantineNoReplace(
    String quarantineName,
    String destinationName,
  );

  SecureFileIdentity openIdentity(String name, SecureFileKind kind);

  int unlinkPrivateCandidate(
    String name,
    SecureFileKind kind,
    SecureFileIdentity expectedIdentity,
  );
}

enum QuarantineRemovalState {
  removed,
  missing,
  mismatchRestored,
  unverifiedRestored,
  mismatchQuarantined,
  unverifiedQuarantined,
  removalFailed,
  quarantineFailed,
}

final class QuarantineRemovalResult {
  const QuarantineRemovalResult({
    required this.state,
    this.quarantineName,
    this.error,
    this.stackTrace,
    this.postRemovalLinkCount,
    this.releaseError,
    this.releaseStackTrace,
  });

  final QuarantineRemovalState state;
  final String? quarantineName;
  final Object? error;
  final StackTrace? stackTrace;
  final int? postRemovalLinkCount;
  final Object? releaseError;
  final StackTrace? releaseStackTrace;

  bool get removedOrMissing =>
      state == QuarantineRemovalState.removed ||
      state == QuarantineRemovalState.missing;

  bool get artifactMayRemain => !removedOrMissing || releaseError != null;

  QuarantineRemovalResult withReleaseFailure(
    Object error,
    StackTrace stackTrace,
  ) => QuarantineRemovalResult(
    state: state,
    quarantineName: quarantineName,
    error: this.error,
    stackTrace: this.stackTrace,
    postRemovalLinkCount: postRemovalLinkCount,
    releaseError: error,
    releaseStackTrace: stackTrace,
  );
}

/// Removes a leaf only after atomically moving it into a freshly created,
/// operation-private directory and checking the moved identity twice.
///
/// A mismatch is restored with no-replace semantics. If the original name has
/// been occupied meanwhile, the quarantined entry is conservatively retained.
/// This protocol coordinates trusted app writers. POSIX cannot prevent a
/// hostile, non-cooperating same-euid process from mutating a 0700 directory.
final class AnchoredQuarantineRemovalProtocol {
  const AnchoredQuarantineRemovalProtocol();

  QuarantineRemovalResult removeExpected({
    required AnchoredQuarantineOperations operations,
    required String originalName,
    required SecureFileIdentity expectedIdentity,
    required SecureFileKind kind,
  }) {
    try {
      operations.beginPrivateMutation();
    } on Object catch (error, stackTrace) {
      return QuarantineRemovalResult(
        state: QuarantineRemovalState.quarantineFailed,
        error: error,
        stackTrace: stackTrace,
      );
    }
    QuarantineRemovalResult result;
    try {
      result = _removeUnderPrivateAuthority(
        operations: operations,
        originalName: originalName,
        expectedIdentity: expectedIdentity,
        kind: kind,
      );
    } on Object catch (error, stackTrace) {
      result = QuarantineRemovalResult(
        state: QuarantineRemovalState.removalFailed,
        error: error,
        stackTrace: stackTrace,
      );
    }
    try {
      operations.releasePrivateMutation();
    } on Object catch (error, stackTrace) {
      return result.withReleaseFailure(error, stackTrace);
    }
    return result;
  }

  QuarantineRemovalResult _removeUnderPrivateAuthority({
    required AnchoredQuarantineOperations operations,
    required String originalName,
    required SecureFileIdentity expectedIdentity,
    required SecureFileKind kind,
  }) {
    String? quarantineName;
    Object? quarantineError;
    StackTrace? quarantineStack;
    for (var attempt = 0; attempt < 128; attempt += 1) {
      try {
        quarantineName = operations.createQuarantineName();
        operations.moveToQuarantineNoReplace(originalName, quarantineName);
        quarantineError = null;
        quarantineStack = null;
        break;
      } on AnchoredDestinationExists catch (error, stackTrace) {
        quarantineError = error;
        quarantineStack = stackTrace;
      } on AnchoredEntryMissing {
        return const QuarantineRemovalResult(
          state: QuarantineRemovalState.missing,
        );
      } on Object catch (error, stackTrace) {
        return QuarantineRemovalResult(
          state: QuarantineRemovalState.quarantineFailed,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (quarantineError != null || quarantineName == null) {
      return QuarantineRemovalResult(
        state: QuarantineRemovalState.quarantineFailed,
        error: quarantineError ?? StateError('Unable to reserve quarantine'),
        stackTrace: quarantineStack,
      );
    }

    SecureFileIdentity firstIdentity;
    try {
      firstIdentity = operations.openIdentity(quarantineName, kind);
    } on Object catch (error, stackTrace) {
      return _restore(
        operations: operations,
        originalName: originalName,
        quarantineName: quarantineName,
        restoredState: QuarantineRemovalState.unverifiedRestored,
        quarantinedState: QuarantineRemovalState.unverifiedQuarantined,
        originalError: error,
        originalStackTrace: stackTrace,
      );
    }
    if (firstIdentity != expectedIdentity) {
      return _restore(
        operations: operations,
        originalName: originalName,
        quarantineName: quarantineName,
        restoredState: QuarantineRemovalState.mismatchRestored,
        quarantinedState: QuarantineRemovalState.mismatchQuarantined,
      );
    }

    try {
      final secondIdentity = operations.openIdentity(quarantineName, kind);
      if (secondIdentity != expectedIdentity) {
        return _restore(
          operations: operations,
          originalName: originalName,
          quarantineName: quarantineName,
          restoredState: QuarantineRemovalState.mismatchRestored,
          quarantinedState: QuarantineRemovalState.mismatchQuarantined,
        );
      }
      final postRemovalLinkCount = operations.unlinkPrivateCandidate(
        quarantineName,
        kind,
        expectedIdentity,
      );
      return QuarantineRemovalResult(
        state: QuarantineRemovalState.removed,
        quarantineName: quarantineName,
        postRemovalLinkCount: postRemovalLinkCount,
      );
    } on Object catch (error, stackTrace) {
      return _restore(
        operations: operations,
        originalName: originalName,
        quarantineName: quarantineName,
        restoredState: QuarantineRemovalState.unverifiedRestored,
        quarantinedState: QuarantineRemovalState.unverifiedQuarantined,
        originalError: error,
        originalStackTrace: stackTrace,
      );
    }
  }

  QuarantineRemovalResult _restore({
    required AnchoredQuarantineOperations operations,
    required String originalName,
    required String quarantineName,
    required QuarantineRemovalState restoredState,
    required QuarantineRemovalState quarantinedState,
    Object? originalError,
    StackTrace? originalStackTrace,
  }) {
    try {
      operations.restoreFromQuarantineNoReplace(quarantineName, originalName);
      return QuarantineRemovalResult(
        state: restoredState,
        error: originalError,
        stackTrace: originalStackTrace,
      );
    } on Object catch (restoreError, restoreStackTrace) {
      return QuarantineRemovalResult(
        state: quarantinedState,
        quarantineName: quarantineName,
        error: _QuarantineRestoreFailure(originalError, restoreError),
        stackTrace: restoreStackTrace,
      );
    }
  }
}

final class PrivateMutationReleaseCause {
  const PrivateMutationReleaseCause({required this.error, required this.stack});

  final Object error;
  final StackTrace stack;
}

final class PrivateMutationReleaseFailure implements Exception {
  PrivateMutationReleaseFailure(Iterable<PrivateMutationReleaseCause> causes)
    : causes = List<PrivateMutationReleaseCause>.unmodifiable(causes);

  final List<PrivateMutationReleaseCause> causes;
}

final class _QuarantineRestoreFailure implements Exception {
  const _QuarantineRestoreFailure(this.originalError, this.restoreError);

  final Object? originalError;
  final Object restoreError;
}

enum PosixCleanupOperation {
  fstat,
  unlinkat,
  fsync,
  boundaryHook,
  closeSource,
  closeAttempt,
  closeBlobs,
  closeQuarantine,
  closeStaging,
  closeEntries,
  closeRoot,
  closeLayout,
}

enum PosixSyscallOperation { fstat, unlinkat, fsync, close }

typedef PosixSyscallFaultHook = void Function(PosixSyscallOperation operation);

/// Narrow test seam invoked only after the underlying syscall has succeeded.
/// Throwing models a syscall boundary whose result cannot be trusted while
/// still allowing the real kernel operation to release resources in tests.
final class PosixSyscallFaultInjector {
  const PosixSyscallFaultInjector(this.hook);

  final PosixSyscallFaultHook hook;

  void afterSuccess(PosixSyscallOperation operation) => hook(operation);
}

final class PosixCleanupAction {
  const PosixCleanupAction(this.operation, this.action);

  final PosixCleanupOperation operation;
  final void Function() action;
}

final class PosixCleanupFailure {
  const PosixCleanupFailure({
    required this.operation,
    required this.error,
    required this.stackTrace,
  });

  final PosixCleanupOperation operation;
  final Object error;
  final StackTrace stackTrace;
}

final class FailureTotalCleanupResult {
  FailureTotalCleanupResult(List<PosixCleanupFailure> failures)
    : failures = List.unmodifiable(failures);

  final List<PosixCleanupFailure> failures;
}

final class FailureTotalCleanupRunner {
  const FailureTotalCleanupRunner();

  FailureTotalCleanupResult run(Iterable<PosixCleanupAction> actions) {
    final failures = <PosixCleanupFailure>[];
    for (final action in actions) {
      try {
        action.action();
      } on Object catch (error, stackTrace) {
        failures.add(
          PosixCleanupFailure(
            operation: action.operation,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }
    return FailureTotalCleanupResult(failures);
  }
}

enum PosixNativeAbi {
  linuxX64,
  androidX64,
  androidArm64,
  macosX64,
  macosArm64,
  iosArm64,
}

/// Android SELinux blocks app-data hard links, even between two files owned by
/// the same app. Android therefore publishes with the equally atomic
/// `renameat2(RENAME_NOREPLACE)` path; other maintained targets retain the
/// hard-link publication protocol.
enum PosixPublicationStrategy { hardLink, atomicMove }

PosixPublicationStrategy publicationStrategyForAbi(PosixNativeAbi abi) =>
    switch (abi) {
      PosixNativeAbi.androidX64 ||
      PosixNativeAbi.androidArm64 => PosixPublicationStrategy.atomicMove,
      PosixNativeAbi.linuxX64 ||
      PosixNativeAbi.macosX64 ||
      PosixNativeAbi.macosArm64 ||
      PosixNativeAbi.iosArm64 => PosixPublicationStrategy.hardLink,
    };

extension PosixNativeAbiProfile on PosixNativeAbi {
  bool get usesDarwinRename =>
      this == PosixNativeAbi.macosX64 ||
      this == PosixNativeAbi.macosArm64 ||
      this == PosixNativeAbi.iosArm64;

  String get errnoSymbol => switch (this) {
    PosixNativeAbi.androidX64 || PosixNativeAbi.androidArm64 => '__errno',
    PosixNativeAbi.macosX64 ||
    PosixNativeAbi.macosArm64 ||
    PosixNativeAbi.iosArm64 => '__error',
    PosixNativeAbi.linuxX64 => '__errno_location',
  };

  int? get renameAt2SyscallNumber => switch (this) {
    PosixNativeAbi.linuxX64 || PosixNativeAbi.androidX64 => 316,
    PosixNativeAbi.androidArm64 => 276,
    PosixNativeAbi.macosX64 ||
    PosixNativeAbi.macosArm64 ||
    PosixNativeAbi.iosArm64 => null,
  };
}

PosixNativeAbi selectPosixNativeAbi(Abi abi) {
  if (abi == Abi.linuxX64) return PosixNativeAbi.linuxX64;
  if (abi == Abi.androidX64) return PosixNativeAbi.androidX64;
  if (abi == Abi.androidArm64) return PosixNativeAbi.androidArm64;
  if (abi == Abi.macosX64) return PosixNativeAbi.macosX64;
  if (abi == Abi.macosArm64) return PosixNativeAbi.macosArm64;
  if (abi == Abi.iosArm64) return PosixNativeAbi.iosArm64;
  throw UnsupportedError(
    'Encrypted blob persistence has no maintained native gate for $abi',
  );
}

final class PosixFileStat {
  const PosixFileStat({
    required this.device,
    required this.inode,
    required this.mode,
    required this.linkCount,
    required this.ownerId,
  });

  final int device;
  final int inode;
  final int mode;
  final int linkCount;
  final int ownerId;
}

final class PosixStatLayout {
  const PosixStatLayout._({
    required this.fstatSymbol,
    required this.deviceOffset,
    required this.deviceBytes,
    required this.inodeOffset,
    required this.modeOffset,
    required this.modeBytes,
    required this.linkCountOffset,
    required this.linkCountBytes,
    required this.ownerIdOffset,
  });

  factory PosixStatLayout.forAbi(PosixNativeAbi abi) {
    return switch (abi) {
      PosixNativeAbi.macosX64 => const PosixStatLayout._(
        fstatSymbol: r'fstat$INODE64',
        deviceOffset: 0,
        deviceBytes: 4,
        modeOffset: 4,
        modeBytes: 2,
        linkCountOffset: 6,
        linkCountBytes: 2,
        inodeOffset: 8,
        ownerIdOffset: 16,
      ),
      PosixNativeAbi.macosArm64 => const PosixStatLayout._(
        fstatSymbol: 'fstat',
        deviceOffset: 0,
        deviceBytes: 4,
        modeOffset: 4,
        modeBytes: 2,
        linkCountOffset: 6,
        linkCountBytes: 2,
        inodeOffset: 8,
        ownerIdOffset: 16,
      ),
      PosixNativeAbi.iosArm64 => const PosixStatLayout._(
        fstatSymbol: 'fstat',
        deviceOffset: 0,
        deviceBytes: 4,
        modeOffset: 4,
        modeBytes: 2,
        linkCountOffset: 6,
        linkCountBytes: 2,
        inodeOffset: 8,
        ownerIdOffset: 16,
      ),
      PosixNativeAbi.linuxX64 => const PosixStatLayout._(
        fstatSymbol: 'fstat',
        deviceOffset: 0,
        deviceBytes: 8,
        inodeOffset: 8,
        modeOffset: 24,
        modeBytes: 4,
        linkCountOffset: 16,
        linkCountBytes: 8,
        ownerIdOffset: 28,
      ),
      PosixNativeAbi.androidX64 => const PosixStatLayout._(
        fstatSymbol: 'fstat',
        deviceOffset: 0,
        deviceBytes: 8,
        inodeOffset: 8,
        modeOffset: 24,
        modeBytes: 4,
        linkCountOffset: 16,
        linkCountBytes: 8,
        ownerIdOffset: 28,
      ),
      PosixNativeAbi.androidArm64 => const PosixStatLayout._(
        fstatSymbol: 'fstat',
        deviceOffset: 0,
        deviceBytes: 8,
        inodeOffset: 8,
        modeOffset: 16,
        modeBytes: 4,
        linkCountOffset: 20,
        linkCountBytes: 4,
        ownerIdOffset: 24,
      ),
    };
  }

  final String fstatSymbol;
  final int deviceOffset;
  final int deviceBytes;
  final int inodeOffset;
  final int modeOffset;
  final int modeBytes;
  final int linkCountOffset;
  final int linkCountBytes;
  final int ownerIdOffset;

  PosixFileStat decode(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    return PosixFileStat(
      device: _unsigned(data, deviceOffset, deviceBytes),
      inode: data.getUint64(inodeOffset, Endian.little),
      mode: _unsigned(data, modeOffset, modeBytes),
      linkCount: _unsigned(data, linkCountOffset, linkCountBytes),
      ownerId: data.getUint32(ownerIdOffset, Endian.little),
    );
  }

  int _unsigned(ByteData data, int offset, int byteCount) =>
      switch (byteCount) {
        2 => data.getUint16(offset, Endian.little),
        4 => data.getUint32(offset, Endian.little),
        8 => data.getUint64(offset, Endian.little),
        _ => throw StateError('Unsupported native integer width: $byteCount'),
      };
}
