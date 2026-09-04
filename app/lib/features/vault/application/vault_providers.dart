import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/capture/application/capture_providers.dart';
import 'package:keepers/features/capture/data/encrypted_blob_store.dart';
import 'package:keepers/features/capture/data/entry_cipher.dart';
import 'package:keepers/features/capture/data/entry_key_resolver.dart';
import 'package:keepers/features/capture/data/entry_payload_codec.dart';
import 'package:keepers/features/capture/data/entry_repository.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_roster_provider.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/vault/application/vault_controller.dart';
import 'package:keepers/features/vault/data/vault_repository.dart';
import 'package:keepers/features/vault/data/weekly_reveal_cloud_gateway.dart';
import 'package:keepers/features/vault/data/weekly_reveal_sync_service.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

final vaultRepositoryProvider = Provider<VaultRepository>(
  (ref) => VaultRepository(),
);

final _weeklyRevealLifecycleProvider = NotifierProvider.autoDispose
    .family<_WeeklyRevealLifecycle, int, _WeeklyRevealScope>(
      _WeeklyRevealLifecycle.new,
    );

final vaultEntriesProvider = FutureProvider<List<VaultEntryMetadata>>((
  ref,
) async {
  final identity = await ref.watch(localIdentityProvider.future);
  if (identity == null) return const [];
  // A roster refresh can make a newly joined author's foreign-key row
  // available, so it is also a reason to retry a previously deferred import.
  ref.watch(familyRosterProvider(identity.familyId));
  final database = await ref.watch(databaseProvider.future);
  final repository = ref.watch(vaultRepositoryProvider);
  final localEntries = await repository.listForFamily(
    database,
    identity.familyId,
  );
  final cloudFamily = ref.watch(cloudFamilyGatewayProvider);
  if (cloudFamily case WeeklyRevealCloudGateway cloud) {
    final authenticatedAccountId = cloudFamily.authenticatedAccountId;
    final identityAccountId = identity.accountId;
    if (authenticatedAccountId == null ||
        identityAccountId == null ||
        authenticatedAccountId != identityAccountId) {
      return localEntries;
    }
    final scope = _WeeklyRevealScope(
      gateway: cloud,
      authenticatedAccountId: authenticatedAccountId,
      identityAccountId: identityAccountId,
      familyId: identity.familyId,
      memberId: identity.memberId,
    );
    final revision = ref.watch(_weeklyRevealLifecycleProvider(scope));
    final lifecycle = ref.read(_weeklyRevealLifecycleProvider(scope).notifier);
    var providerActive = true;
    ref.onDispose(() => providerActive = false);
    final blobStore = ref.watch(entryBlobStoreProvider.future);
    lifecycle.runSync(revision: revision, (lifecycleIsCurrent) async {
      bool isCurrent() => providerActive && lifecycleIsCurrent();

      final resolvedBlobStore = await blobStore;
      if (!isCurrent()) return false;
      final before = await repository.listForFamily(
        database,
        identity.familyId,
      );
      if (!isCurrent()) return false;
      final service = WeeklyRevealSyncService(
        cloud: cloud,
        listLocal: (familyId) => repository.listForFamily(database, familyId),
        readLocalBlob: (blobRef, {required maxBytes}) =>
            resolvedBlobStore.read(blobRef, maxBytes: maxBytes),
        importRemote: (entry, bytes) => _importRemoteWeeklyReveal(
          database: database,
          repository: repository,
          blobStore: resolvedBlobStore,
          remote: entry,
          bytes: bytes,
          isCurrent: isCurrent,
        ),
        isCurrent: isCurrent,
      );
      await service.synchronize(identity);
      if (!isCurrent()) return false;
      final after = await repository.listForFamily(database, identity.familyId);
      if (!isCurrent()) return false;
      return !_sameEntryIds(before, after);
    });
  }
  return localEntries;
});

final vaultControllerProvider = FutureProvider<VaultController>((ref) async {
  final identity = await ref.watch(localIdentityProvider.future);
  if (identity == null) {
    throw StateError('A local identity is required to open the vault');
  }
  final blobStore = await ref.watch(entryBlobStoreProvider.future);
  return VaultController(
    identity: identity,
    keyResolver: EntryKeyResolver(ref.watch(identityKeyServiceProvider)),
    cipher: EntryCipher(),
    codec: const EntryPayloadCodec(),
    readEncryptedBlob: blobStore.read,
    readEncryptedBlobBounded: (relativeRef, {required maxBytes}) =>
        blobStore.read(relativeRef, maxBytes: maxBytes),
  );
});

Future<void> _importRemoteWeeklyReveal({
  required Database database,
  required VaultRepository repository,
  required EncryptedBlobStore blobStore,
  required RemoteWeeklyRevealEntry remote,
  required Uint8List bytes,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return;
  final metadata = remote.metadata;
  final existing = await repository.findByIdForFamily(
    database,
    entryId: metadata.id,
    familyId: metadata.familyId,
  );
  if (!isCurrent()) return;
  if (existing != null) return;

  final relativeRef = p.join('entries', 'blobs', '${metadata.id}.keeper');
  final blobExists = await blobStore.exists(relativeRef);
  if (!isCurrent()) return;
  if (blobExists) {
    final existingBytes = await blobStore.read(
      relativeRef,
      maxBytes: remote.blobBytes,
    );
    if (!isCurrent()) return;
    if (!_sameBytes(existingBytes, bytes)) {
      throw StateError(
        'A different encrypted blob already uses this entry ID.',
      );
    }
    await database.transaction<void>((transaction) async {
      if (!isCurrent()) return;
      await EntryRepository().insert(transaction, metadata, relativeRef);
      if (!isCurrent()) throw const _StaleWeeklyRevealSync();
    });
    return;
  }

  if (!isCurrent()) return;
  final staged = await blobStore.stage(metadata.id, bytes);
  if (!isCurrent()) {
    final staleFinalized = await blobStore.finalize(staged);
    await blobStore.rollback(staleFinalized);
    return;
  }
  final finalized = await blobStore.finalize(staged);
  if (!isCurrent()) {
    await blobStore.rollback(finalized);
    return;
  }
  try {
    await database.transaction<void>((transaction) async {
      if (!isCurrent()) throw const _StaleWeeklyRevealSync();
      await EntryRepository().insert(
        transaction,
        metadata,
        finalized.relativeRef,
      );
      if (!isCurrent()) throw const _StaleWeeklyRevealSync();
    });
  } on Object {
    await blobStore.rollback(finalized);
    rethrow;
  }
}

final class _StaleWeeklyRevealSync implements Exception {
  const _StaleWeeklyRevealSync();
}

bool _sameBytes(Uint8List left, Uint8List right) {
  if (left.lengthInBytes != right.lengthInBytes) return false;
  var difference = 0;
  for (var index = 0; index < left.lengthInBytes; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

bool _sameEntryIds(
  List<VaultEntryMetadata> before,
  List<VaultEntryMetadata> after,
) {
  if (before.length != after.length) return false;
  final beforeIds = before.map((entry) => entry.id).toSet();
  return after.every((entry) => beforeIds.contains(entry.id));
}

final class _WeeklyRevealLifecycle extends Notifier<int> {
  _WeeklyRevealLifecycle(this.scope);

  static const _watchRetryDelays = <Duration>[
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];

  final _WeeklyRevealScope scope;
  Future<void>? _inFlight;
  _WeeklyRevealSyncRequest? _queued;
  StreamSubscription<void>? _watchSubscription;
  Timer? _watchRetryTimer;
  int? _skipSyncRevision;
  var _watchRetryAttempt = 0;
  var _watchGeneration = 0;
  var _operationGeneration = 0;
  var _active = true;
  var _disposed = false;

  @override
  int build() {
    _active = true;
    scheduleMicrotask(() => _bindWatch(requestSync: false));
    ref.onDispose(() {
      _disposed = true;
      _deactivate();
      _queued = null;
    });
    return 0;
  }

  void runSync(
    Future<bool> Function(bool Function() isCurrent) operation, {
    required int revision,
  }) {
    if (!_isScopeCurrent()) return;
    if (_skipSyncRevision == revision) {
      _skipSyncRevision = null;
      return;
    }
    final request = _WeeklyRevealSyncRequest(
      generation: _operationGeneration,
      operation: operation,
    );
    if (_inFlight != null) {
      _queued = request;
      return;
    }
    _start(request);
  }

  void _start(_WeeklyRevealSyncRequest request) {
    late final Future<void> future;
    future = _execute(request).whenComplete(() {
      if (!identical(_inFlight, future)) return;
      _inFlight = null;
      final trailing = _queued;
      _queued = null;
      if (trailing != null && _active && !_disposed && ref.mounted) {
        _start(trailing);
      }
    });
    _inFlight = future;
  }

  Future<void> _execute(_WeeklyRevealSyncRequest request) async {
    bool isCurrent() =>
        _isScopeCurrent() && request.generation == _operationGeneration;

    try {
      if (await request.operation(isCurrent) && isCurrent()) {
        _publishRefresh(skipNextSync: true);
      }
    } on Object {
      // Cloud reconciliation is best-effort. Cached encrypted rows remain the
      // authoritative view until a later refresh can converge successfully.
    }
  }

  void _bindWatch({required bool requestSync}) {
    if (!_isScopeCurrent()) return;
    final generation = ++_watchGeneration;
    final previous = _watchSubscription;
    _watchSubscription = null;
    if (previous != null) unawaited(previous.cancel());

    var terminated = false;
    late final StreamSubscription<void> subscription;
    void terminate() {
      if (terminated || generation != _watchGeneration) return;
      terminated = true;
      _watchSubscription = null;
      _scheduleWatchRecovery();
    }

    try {
      subscription = scope.gateway
          .watch(scope.familyId)
          .listen(
            (_) {
              if (generation != _watchGeneration || !_isScopeCurrent()) {
                return;
              }
              _watchRetryAttempt = 0;
              _watchRetryTimer?.cancel();
              _watchRetryTimer = null;
              _publishRefresh();
            },
            onError: (Object _, StackTrace _) => terminate(),
            onDone: terminate,
            cancelOnError: true,
          );
      if (generation != _watchGeneration || !_isScopeCurrent()) {
        unawaited(subscription.cancel());
        return;
      }
      _watchSubscription = subscription;
      if (requestSync) _publishRefresh();
    } on Object {
      if (generation == _watchGeneration) _scheduleWatchRecovery();
    }
  }

  void _scheduleWatchRecovery() {
    if (!_isScopeCurrent() || _watchRetryTimer != null) {
      return;
    }
    final delayIndex = _watchRetryAttempt < _watchRetryDelays.length
        ? _watchRetryAttempt
        : _watchRetryDelays.length - 1;
    _watchRetryAttempt += 1;
    _watchRetryTimer = Timer(_watchRetryDelays[delayIndex], () {
      _watchRetryTimer = null;
      _bindWatch(requestSync: true);
    });
  }

  void _deactivate() {
    if (!_active) return;
    _active = false;
    _operationGeneration += 1;
    _watchGeneration += 1;
    _watchRetryTimer?.cancel();
    _watchRetryTimer = null;
    final subscription = _watchSubscription;
    _watchSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _publishRefresh({bool skipNextSync = false}) {
    if (!_isScopeCurrent()) return;
    final nextRevision = state + 1;
    if (skipNextSync) _skipSyncRevision = nextRevision;
    state = nextRevision;
  }

  bool _isScopeCurrent() {
    if (!_active || _disposed || !ref.mounted) return false;
    final activeGateway = ref.read(cloudFamilyGatewayProvider);
    final authenticatedAccountId = activeGateway.authenticatedAccountId;
    if (!identical(activeGateway, scope.gateway) ||
        authenticatedAccountId == null ||
        authenticatedAccountId != scope.authenticatedAccountId ||
        authenticatedAccountId != scope.identityAccountId) {
      return false;
    }
    final identity = switch (ref.read(localIdentityProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };
    return identity?.accountId != null &&
        identity?.accountId == scope.identityAccountId &&
        identity?.familyId == scope.familyId &&
        identity?.memberId == scope.memberId;
  }
}

final class _WeeklyRevealSyncRequest {
  const _WeeklyRevealSyncRequest({
    required this.generation,
    required this.operation,
  });

  final int generation;
  final Future<bool> Function(bool Function() isCurrent) operation;
}

final class _WeeklyRevealScope {
  const _WeeklyRevealScope({
    required this.gateway,
    required this.authenticatedAccountId,
    required this.identityAccountId,
    required this.familyId,
    required this.memberId,
  });

  final WeeklyRevealCloudGateway gateway;
  final String authenticatedAccountId;
  final String identityAccountId;
  final String familyId;
  final String memberId;

  @override
  bool operator ==(Object other) =>
      other is _WeeklyRevealScope &&
      identical(other.gateway, gateway) &&
      other.authenticatedAccountId == authenticatedAccountId &&
      other.identityAccountId == identityAccountId &&
      other.familyId == familyId &&
      other.memberId == memberId;

  @override
  int get hashCode => Object.hash(
    identityHashCode(gateway),
    authenticatedAccountId,
    identityAccountId,
    familyId,
    memberId,
  );
}
