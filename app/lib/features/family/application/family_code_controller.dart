import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_join_crypto_providers.dart';
import 'package:keepers/features/family/data/family_code_cache_repository.dart';
import 'package:keepers/features/family/data/invite_share_service.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_join_failure.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

enum FamilyCodePhase { loading, ready, regenerating, failed }

final class FamilyCodeState {
  const FamilyCodeState({
    this.phase = FamilyCodePhase.loading,
    this.displayCode,
    this.codeVersion,
    this.isCreator = false,
    this.isOffline = false,
    this.feedback,
    this.failure,
  });

  final FamilyCodePhase phase;
  final String? displayCode;
  final int? codeVersion;
  final bool isCreator;
  final bool isOffline;
  final String? feedback;
  final FamilyJoinFailure? failure;

  bool get hasCode => displayCode != null && codeVersion != null;

  @override
  String toString() =>
      'FamilyCodeState(${phase.name}, version: $codeVersion, '
      'offline: $isOffline)';
}

abstract interface class FamilyClipboard {
  Future<void> writeText(String value);
}

final class PlatformFamilyClipboard implements FamilyClipboard {
  const PlatformFamilyClipboard();

  @override
  Future<void> writeText(String value) =>
      Clipboard.setData(ClipboardData(text: value));
}

final familyClipboardProvider = Provider<FamilyClipboard>(
  (ref) => const PlatformFamilyClipboard(),
);

final familyCodeControllerProvider = NotifierProvider.autoDispose
    .family<FamilyCodeController, FamilyCodeState, String>(
      FamilyCodeController.new,
    );

base class FamilyCodeController extends Notifier<FamilyCodeState> {
  FamilyCodeController(this._familyId);

  static const _maximumCandidateSubmissions = 5;

  final String _familyId;
  Future<void>? _inFlight;
  _PublishedCodeContext? _publishedContext;
  var _generation = 0;

  @override
  FamilyCodeState build() {
    ref.onDispose(() {
      _generation += 1;
      _publishedContext = null;
    });
    unawaited(Future<void>.microtask(load));
    return const FamilyCodeState();
  }

  Future<void> load() => _deduplicate(_load);

  Future<void> _load() async {
    final generation = ++_generation;
    final previous = state;
    state = FamilyCodeState(
      phase: FamilyCodePhase.loading,
      displayCode: previous.displayCode,
      codeVersion: previous.codeVersion,
      isCreator: previous.isCreator,
    );

    final gateway = ref.read(familyCodeJoinGatewayProvider);
    final expectedAccountId = gateway.authenticatedAccountId;
    late final Database database;
    LocalIdentity? identity;
    List<int>? familyKey;
    var cachePublished = false;

    try {
      database = await ref.read(databaseProvider.future);
      if (!_authIsCurrent(generation, expectedAccountId)) return;
      identity = await ref.read(localIdentityProvider.future);
      if (!_authIsCurrent(generation, expectedAccountId)) return;
      identity = _validateIdentity(
        identity,
        expectedAccountId: expectedAccountId,
        allowUnbound: true,
      );
      if (identity == null) return;

      final resolved = await ref
          .read(identityKeyServiceProvider)
          .resolve(identity.familyKeyRef);
      identity = await _revalidateIdentity(
        generation: generation,
        expectedAccountId: expectedAccountId,
        baseline: identity,
        allowUnbound: true,
      );
      if (identity == null) return;
      familyKey = List<int>.of(resolved, growable: false);

      final cached = await ref
          .read(familyCodeCacheRepositoryProvider)
          .find(database, familyId: _familyId);
      identity = await _revalidateIdentity(
        generation: generation,
        expectedAccountId: expectedAccountId,
        baseline: identity,
        allowUnbound: true,
      );
      if (identity == null) return;
      if (cached != null) {
        try {
          final cachedCode = await _openRecord(cached.material, familyKey);
          identity = await _revalidateIdentity(
            generation: generation,
            expectedAccountId: expectedAccountId,
            baseline: identity,
            allowUnbound: true,
          );
          if (identity == null) return;
          state = FamilyCodeState(
            phase: FamilyCodePhase.loading,
            displayCode: cachedCode.display,
            codeVersion: cached.material.codeVersion,
            isCreator:
                expectedAccountId != null &&
                cached.creatorAccountId == expectedAccountId,
          );
          _rememberPublishedCode(
            generation: generation,
            accountId: expectedAccountId,
            identity: identity,
          );
          cachePublished = true;
        } on Object {
          // A corrupted or unauthentic local envelope is never displayed.
          cachePublished = false;
        }
      }

      if (!gateway.isConfigured) {
        identity = await _revalidateIdentity(
          generation: generation,
          expectedAccountId: expectedAccountId,
          baseline: identity!,
          allowUnbound: true,
        );
        if (identity == null) return;
        if (cachePublished) {
          _markOffline();
        } else {
          _fail(
            const FamilyJoinFailure(FamilyJoinFailureCode.notConfigured),
            fallback: previous,
          );
        }
        return;
      }
      if (expectedAccountId == null) {
        identity = await _revalidateIdentity(
          generation: generation,
          expectedAccountId: expectedAccountId,
          baseline: identity!,
          allowUnbound: true,
        );
        if (identity == null) return;
        if (cachePublished) {
          _markOffline();
        } else {
          _fail(
            const FamilyJoinFailure(FamilyJoinFailureCode.signedOut),
            fallback: previous,
          );
        }
        return;
      }
      if (!_authIsCurrent(generation, expectedAccountId)) return;

      EncryptedFamilyCodeRecord record;
      try {
        record = await gateway.getFamilyCode(_familyId);
        identity = await _revalidateIdentity(
          generation: generation,
          expectedAccountId: expectedAccountId,
          baseline: identity!,
          allowUnbound: true,
        );
        if (identity == null) return;
      } on FamilyJoinFailure catch (failure) {
        if (failure.code != FamilyJoinFailureCode.familyNotFound &&
            failure.code != FamilyJoinFailureCode.forbidden) {
          rethrow;
        }
        identity = await _revalidateIdentity(
          generation: generation,
          expectedAccountId: expectedAccountId,
          baseline: identity!,
          allowUnbound: true,
        );
        if (identity == null) return;
        record = await _bootstrapOwner(
          database: database,
          identity: identity,
          accountId: expectedAccountId,
          familyKey: familyKey,
          generation: generation,
        );
      }
      identity = await _revalidateIdentity(
        generation: generation,
        expectedAccountId: expectedAccountId,
        baseline: identity,
        allowUnbound: true,
      );
      if (identity == null) return;
      identity = await _repairCreatorBinding(
        database: database,
        record: record,
        identity: identity,
        accountId: expectedAccountId,
        generation: generation,
      );
      if (identity == null) return;
      await _cacheAndPublish(
        database: database,
        record: record,
        familyKey: familyKey,
        accountId: expectedAccountId,
        identity: identity,
        generation: generation,
      );
    } on FamilyJoinFailure catch (failure) {
      if (!_isCurrent(generation)) return;
      if (identity != null) {
        identity = await _revalidateIdentity(
          generation: generation,
          expectedAccountId: expectedAccountId,
          baseline: identity,
          allowUnbound: true,
        );
        if (identity == null) return;
      } else if (!_authIsCurrent(generation, expectedAccountId)) {
        return;
      }
      if (cachePublished &&
          (failure.code == FamilyJoinFailureCode.networkUnavailable ||
              failure.code == FamilyJoinFailureCode.notConfigured)) {
        _markOffline();
      } else {
        _fail(failure, fallback: cachePublished ? state : previous);
      }
    } on Object {
      if (_isCurrent(generation)) {
        if (identity != null) {
          identity = await _revalidateIdentity(
            generation: generation,
            expectedAccountId: expectedAccountId,
            baseline: identity,
            allowUnbound: true,
          );
          if (identity == null) return;
        } else if (!_authIsCurrent(generation, expectedAccountId)) {
          return;
        }
        _fail(
          const FamilyJoinFailure(FamilyJoinFailureCode.localPersistenceFailed),
          fallback: cachePublished ? state : previous,
        );
      }
    } finally {
      if (familyKey != null) _zeroize(familyKey);
    }
  }

  Future<void> regenerate() => _deduplicate(() async {
    final previous = state;
    final currentVersion = previous.codeVersion;
    final gateway = ref.read(familyCodeJoinGatewayProvider);
    final expectedAccountId = gateway.authenticatedAccountId;
    if (!previous.isCreator || currentVersion == null) {
      _fail(
        const FamilyJoinFailure(FamilyJoinFailureCode.notCreator),
        fallback: previous,
      );
      return;
    }
    if (!gateway.isConfigured || expectedAccountId == null) {
      _fail(
        FamilyJoinFailure(
          gateway.isConfigured
              ? FamilyJoinFailureCode.signedOut
              : FamilyJoinFailureCode.notConfigured,
        ),
        fallback: previous,
      );
      return;
    }
    if (!_publishedForAccount(expectedAccountId)) {
      _securityFailure(FamilyJoinFailureCode.signedOut);
      return;
    }

    final generation = ++_generation;
    state = FamilyCodeState(
      phase: FamilyCodePhase.regenerating,
      displayCode: previous.displayCode,
      codeVersion: currentVersion,
      isCreator: true,
    );
    List<int>? familyKey;
    LocalIdentity? identity;
    try {
      final database = await ref.read(databaseProvider.future);
      if (!_authIsCurrent(generation, expectedAccountId)) return;
      identity = await ref.read(localIdentityProvider.future);
      if (!_authIsCurrent(generation, expectedAccountId)) return;
      identity = _validateIdentity(
        identity,
        expectedAccountId: expectedAccountId,
        allowUnbound: false,
        baseline: _publishedContext?.identity,
      );
      if (identity == null) return;
      final resolved = await ref
          .read(identityKeyServiceProvider)
          .resolve(identity.familyKeyRef);
      identity = await _revalidateIdentity(
        generation: generation,
        expectedAccountId: expectedAccountId,
        baseline: identity,
        allowUnbound: false,
      );
      if (identity == null) return;
      familyKey = List<int>.of(resolved, growable: false);

      final record = await _submitCandidates(
        codeVersion: currentVersion + 1,
        familyKey: familyKey,
        generation: generation,
        accountId: expectedAccountId,
        identity: identity,
        allowUnbound: false,
        submit: (draft) => gateway.regenerateFamilyCode(
          familyId: _familyId,
          expectedVersion: currentVersion,
          replacement: draft,
        ),
      );
      identity = await _revalidateIdentity(
        generation: generation,
        expectedAccountId: expectedAccountId,
        baseline: identity,
        allowUnbound: false,
      );
      if (identity == null) return;
      if (record.creatorAccountId != expectedAccountId ||
          record.material.codeVersion != currentVersion + 1) {
        throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
      }
      await _cacheAndPublish(
        database: database,
        record: record,
        familyKey: familyKey,
        accountId: expectedAccountId,
        identity: identity,
        generation: generation,
        feedback: 'Family code regenerated',
      );
    } on FamilyJoinFailure catch (failure) {
      if (!_isCurrent(generation)) return;
      if (identity != null) {
        identity = await _revalidateIdentity(
          generation: generation,
          expectedAccountId: expectedAccountId,
          baseline: identity,
          allowUnbound: false,
        );
        if (identity == null) return;
      } else if (!_authIsCurrent(generation, expectedAccountId)) {
        return;
      }
      if (_isCurrent(generation)) {
        _rememberPublishedCode(
          generation: generation,
          accountId: expectedAccountId,
          identity: identity ?? _publishedContext!.identity,
        );
        _fail(failure, fallback: previous);
      }
    } on Object {
      if (!_isCurrent(generation)) return;
      if (identity != null) {
        identity = await _revalidateIdentity(
          generation: generation,
          expectedAccountId: expectedAccountId,
          baseline: identity,
          allowUnbound: false,
        );
        if (identity == null) return;
      } else if (!_authIsCurrent(generation, expectedAccountId)) {
        return;
      }
      if (_isCurrent(generation)) {
        _rememberPublishedCode(
          generation: generation,
          accountId: expectedAccountId,
          identity: identity ?? _publishedContext!.identity,
        );
        _fail(
          const FamilyJoinFailure(FamilyJoinFailureCode.unknown),
          fallback: previous,
        );
      }
    } finally {
      if (familyKey != null) _zeroize(familyKey);
    }
  });

  Future<void> copyFamilyCode() async {
    final action = await _authorizeVisibleAction();
    if (action == null) return;
    try {
      await ref.read(familyClipboardProvider).writeText(action.code.display);
      if (_actionIsCurrent(action)) _setFeedback('Family code copied');
    } on Object {
      if (_actionIsCurrent(action)) _setActionFailure();
    }
  }

  Future<void> copyFamilyLink() async {
    final action = await _authorizeVisibleAction();
    if (action == null) return;
    try {
      await ref
          .read(familyClipboardProvider)
          .writeText(action.code.joinUri.toString());
      if (_actionIsCurrent(action)) _setFeedback('Family link copied');
    } on Object {
      if (_actionIsCurrent(action)) _setActionFailure();
    }
  }

  Future<void> shareFamilyLink({Rect? sharePositionOrigin}) async {
    final action = await _authorizeVisibleAction();
    if (action == null) return;
    try {
      await ref
          .read(inviteShareServiceProvider)
          .shareFamilyLink(
            action.code,
            sharePositionOrigin: sharePositionOrigin,
          );
      if (_actionIsCurrent(action)) _setFeedback('Share options opened');
    } on Object {
      if (_actionIsCurrent(action)) _setActionFailure();
    }
  }

  Future<EncryptedFamilyCodeRecord> _bootstrapOwner({
    required Database database,
    required LocalIdentity identity,
    required String accountId,
    required List<int> familyKey,
    required int generation,
  }) async {
    if (identity.accountId != null && identity.accountId != accountId) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.forbidden);
    }
    final roster = await ref
        .read(familyRosterRepositoryProvider)
        .listLocal(database, familyId: _familyId);
    final currentIdentity = await _revalidateIdentity(
      generation: generation,
      expectedAccountId: accountId,
      baseline: identity,
      allowUnbound: true,
    );
    if (currentIdentity == null) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut);
    }
    if (roster.isEmpty || roster.first.id != currentIdentity.memberId) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.notCreator);
    }

    final owner = LocalOwnerFamily(
      familyId: currentIdentity.familyId,
      familyName: currentIdentity.familyName,
      memberId: currentIdentity.memberId,
      displayName: currentIdentity.memberName,
      demographicRole: FamilyDemographicRole.adult,
      colorToken: currentIdentity.colorToken,
      avatar: currentIdentity.avatar,
    );
    final gateway = ref.read(familyCodeJoinGatewayProvider);
    final record = await _submitCandidates(
      codeVersion: 1,
      familyKey: familyKey,
      generation: generation,
      accountId: accountId,
      identity: currentIdentity,
      allowUnbound: true,
      submit: (draft) => gateway.bootstrapOwnerWithFamilyCode(owner, draft),
    );
    if (await _revalidateIdentity(
          generation: generation,
          expectedAccountId: accountId,
          baseline: currentIdentity,
          allowUnbound: true,
        ) ==
        null) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut);
    }
    if (record.creatorAccountId != accountId ||
        record.material.codeVersion != 1) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
    }
    return record;
  }

  Future<EncryptedFamilyCodeRecord> _submitCandidates({
    required int codeVersion,
    required List<int> familyKey,
    required int generation,
    required String accountId,
    required LocalIdentity identity,
    required bool allowUnbound,
    required Future<EncryptedFamilyCodeRecord> Function(FamilyCodeDraft draft)
    submit,
  }) async {
    for (
      var attempt = 0;
      attempt < _maximumCandidateSubmissions;
      attempt += 1
    ) {
      final draft = await ref
          .read(familyCodeCodecProvider)
          .createDraft(
            familyId: _familyId,
            codeVersion: codeVersion,
            familyKey: familyKey,
          );
      if (await _revalidateIdentity(
            generation: generation,
            expectedAccountId: accountId,
            baseline: identity,
            allowUnbound: allowUnbound,
          ) ==
          null) {
        throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut);
      }
      try {
        final record = await submit(draft);
        if (await _revalidateIdentity(
              generation: generation,
              expectedAccountId: accountId,
              baseline: identity,
              allowUnbound: allowUnbound,
            ) ==
            null) {
          throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut);
        }
        return record;
      } on FamilyJoinFailure catch (failure) {
        if (await _revalidateIdentity(
              generation: generation,
              expectedAccountId: accountId,
              baseline: identity,
              allowUnbound: allowUnbound,
            ) ==
            null) {
          throw const FamilyJoinFailure(FamilyJoinFailureCode.signedOut);
        }
        if (failure.code != FamilyJoinFailureCode.codeCollision ||
            attempt == _maximumCandidateSubmissions - 1) {
          rethrow;
        }
      }
    }
    throw const FamilyJoinFailure(FamilyJoinFailureCode.codeCollision);
  }

  Future<void> _cacheAndPublish({
    required Database database,
    required EncryptedFamilyCodeRecord record,
    required List<int> familyKey,
    required String accountId,
    required LocalIdentity identity,
    required int generation,
    String? feedback,
  }) async {
    LocalIdentity? currentIdentity = await _revalidateIdentity(
      generation: generation,
      expectedAccountId: accountId,
      baseline: identity,
      allowUnbound: false,
    );
    if (currentIdentity == null) return;
    final code = await _openRecord(record.material, familyKey);
    currentIdentity = await _revalidateIdentity(
      generation: generation,
      expectedAccountId: accountId,
      baseline: currentIdentity,
      allowUnbound: false,
    );
    if (currentIdentity == null) return;
    await ref
        .read(familyCodeCacheRepositoryProvider)
        .upsert(
          database,
          FamilyCodeCacheRecord(
            material: record.material,
            creatorAccountId: record.creatorAccountId,
            updatedAt: record.updatedAt,
            cachedAt: ref.read(utcNowProvider)(),
          ),
        );
    currentIdentity = await _revalidateIdentity(
      generation: generation,
      expectedAccountId: accountId,
      baseline: currentIdentity,
      allowUnbound: false,
    );
    if (currentIdentity == null) return;
    state = FamilyCodeState(
      phase: FamilyCodePhase.ready,
      displayCode: code.display,
      codeVersion: record.material.codeVersion,
      isCreator: record.creatorAccountId == accountId,
      feedback: feedback,
    );
    _rememberPublishedCode(
      generation: generation,
      accountId: accountId,
      identity: currentIdentity,
    );
  }

  Future<LocalIdentity?> _repairCreatorBinding({
    required Database database,
    required EncryptedFamilyCodeRecord record,
    required LocalIdentity identity,
    required String accountId,
    required int generation,
  }) async {
    if (record.creatorAccountId != accountId) {
      return _validateIdentity(
        identity,
        expectedAccountId: accountId,
        allowUnbound: false,
        baseline: identity,
      );
    }
    if (identity.accountId == accountId) return identity;
    if (identity.accountId != null) {
      _securityFailure(FamilyJoinFailureCode.forbidden);
      return null;
    }

    final roster = await ref
        .read(familyRosterRepositoryProvider)
        .listLocal(database, familyId: _familyId);
    LocalIdentity? currentIdentity = await _revalidateIdentity(
      generation: generation,
      expectedAccountId: accountId,
      baseline: identity,
      allowUnbound: true,
    );
    if (currentIdentity == null) return null;
    if (roster.isEmpty || roster.first.id != currentIdentity.memberId) {
      _securityFailure(FamilyJoinFailureCode.forbidden);
      return null;
    }

    final bindingIdentity = currentIdentity;
    await database.transaction((transaction) async {
      await ref
          .read(memberRepositoryProvider)
          .bindLocalIdentity(
            transaction,
            familyId: bindingIdentity.familyId,
            memberId: bindingIdentity.memberId,
            accountId: accountId,
          );
    });
    currentIdentity = await _revalidateIdentity(
      generation: generation,
      expectedAccountId: accountId,
      baseline: currentIdentity,
      allowUnbound: true,
    );
    if (currentIdentity == null) return null;

    ref.invalidate(localIdentityProvider);
    final rebound = await ref.read(localIdentityProvider.future);
    if (!_authIsCurrent(generation, accountId)) return null;
    return _validateIdentity(
      rebound,
      expectedAccountId: accountId,
      allowUnbound: false,
      baseline: currentIdentity,
    );
  }

  Future<FamilyCode> _openRecord(
    EncryptedFamilyCodeMaterial material,
    List<int> familyKey,
  ) {
    if (material.familyId != _familyId) {
      throw const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected);
    }
    return ref
        .read(familyCodeCodecProvider)
        .open(material: material, familyKey: familyKey);
  }

  bool _authIsCurrent(int generation, String? expectedAccountId) {
    if (!_isCurrent(generation)) return false;
    if (ref.read(familyCodeJoinGatewayProvider).authenticatedAccountId ==
        expectedAccountId) {
      return true;
    }
    _securityFailure(FamilyJoinFailureCode.signedOut);
    return false;
  }

  LocalIdentity? _validateIdentity(
    LocalIdentity? identity, {
    required String? expectedAccountId,
    required bool allowUnbound,
    LocalIdentity? baseline,
  }) {
    final identityChanged =
        identity == null ||
        identity.familyId != _familyId ||
        (baseline != null &&
            (identity.memberId != baseline.memberId ||
                identity.familyKeyRef != baseline.familyKeyRef ||
                identity.memberKeyRef != baseline.memberKeyRef ||
                (baseline.accountId != null &&
                    identity.accountId != baseline.accountId)));
    final accountMismatch =
        expectedAccountId != null &&
        identity != null &&
        identity.accountId != expectedAccountId &&
        !(allowUnbound && identity.accountId == null);
    final signedOutWithBoundIdentity =
        expectedAccountId == null && identity?.accountId != null;
    if (identityChanged || accountMismatch || signedOutWithBoundIdentity) {
      _securityFailure(
        signedOutWithBoundIdentity
            ? FamilyJoinFailureCode.signedOut
            : FamilyJoinFailureCode.forbidden,
      );
      return null;
    }
    return identity;
  }

  Future<LocalIdentity?> _revalidateIdentity({
    required int generation,
    required String? expectedAccountId,
    required LocalIdentity baseline,
    required bool allowUnbound,
  }) async {
    if (!_authIsCurrent(generation, expectedAccountId)) return null;
    final latest = await ref.read(localIdentityProvider.future);
    if (!_authIsCurrent(generation, expectedAccountId)) return null;
    return _validateIdentity(
      latest,
      expectedAccountId: expectedAccountId,
      allowUnbound: allowUnbound,
      baseline: baseline,
    );
  }

  void _rememberPublishedCode({
    required int generation,
    required String? accountId,
    required LocalIdentity identity,
  }) {
    if (!_isCurrent(generation)) return;
    _publishedContext = _PublishedCodeContext(
      generation: generation,
      accountId: accountId,
      identity: identity,
    );
  }

  bool _publishedForAccount(String accountId) {
    final context = _publishedContext;
    return state.hasCode &&
        context != null &&
        context.generation == _generation &&
        context.accountId == accountId;
  }

  Future<_VisibleCodeAction?> _authorizeVisibleAction() async {
    if (state.phase == FamilyCodePhase.loading ||
        state.phase == FamilyCodePhase.regenerating) {
      return null;
    }
    final generation = _generation;
    final context = _publishedContext;
    final code = _visibleCode();
    if (context == null ||
        context.generation != generation ||
        code == null ||
        !_authIsCurrent(generation, context.accountId)) {
      return null;
    }
    final identity = await _revalidateIdentity(
      generation: generation,
      expectedAccountId: context.accountId,
      baseline: context.identity,
      allowUnbound: context.accountId == null,
    );
    if (identity == null || !_isCurrent(generation)) return null;
    if (state.displayCode != code.display) return null;
    return _VisibleCodeAction(
      generation: generation,
      code: code,
      context: _PublishedCodeContext(
        generation: generation,
        accountId: context.accountId,
        identity: identity,
      ),
    );
  }

  bool _actionIsCurrent(_VisibleCodeAction action) {
    if (!_authIsCurrent(action.generation, action.context.accountId)) {
      return false;
    }
    final context = _publishedContext;
    return context != null &&
        context.generation == action.generation &&
        context.accountId == action.context.accountId &&
        context.identity.memberId == action.context.identity.memberId &&
        context.identity.familyKeyRef == action.context.identity.familyKeyRef &&
        state.displayCode == action.code.display;
  }

  FamilyCode? _visibleCode() {
    final display = state.displayCode;
    if (display == null) return null;
    try {
      return FamilyCode.parse(display);
    } on FormatException {
      return null;
    }
  }

  void _markOffline() {
    state = FamilyCodeState(
      phase: FamilyCodePhase.ready,
      displayCode: state.displayCode,
      codeVersion: state.codeVersion,
      isCreator: state.isCreator,
      isOffline: true,
    );
  }

  void _fail(FamilyJoinFailure failure, {required FamilyCodeState fallback}) {
    state = FamilyCodeState(
      phase: FamilyCodePhase.failed,
      displayCode: fallback.displayCode,
      codeVersion: fallback.codeVersion,
      isCreator: fallback.isCreator,
      isOffline: fallback.isOffline,
      failure: failure,
    );
  }

  void _setFeedback(String feedback) {
    state = FamilyCodeState(
      phase: state.phase,
      displayCode: state.displayCode,
      codeVersion: state.codeVersion,
      isCreator: state.isCreator,
      isOffline: state.isOffline,
      feedback: feedback,
    );
  }

  void _setActionFailure() {
    state = FamilyCodeState(
      phase: state.phase,
      displayCode: state.displayCode,
      codeVersion: state.codeVersion,
      isCreator: state.isCreator,
      isOffline: state.isOffline,
      failure: const FamilyJoinFailure(FamilyJoinFailureCode.unknown),
    );
  }

  Future<void> _deduplicate(Future<void> Function() operation) {
    final running = _inFlight;
    if (running != null) return running;
    late final Future<void> future;
    future = operation().whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  void _securityFailure(FamilyJoinFailureCode code) {
    _generation += 1;
    _publishedContext = null;
    state = FamilyCodeState(
      phase: FamilyCodePhase.failed,
      failure: FamilyJoinFailure(code),
    );
  }
}

final class _PublishedCodeContext {
  const _PublishedCodeContext({
    required this.generation,
    required this.accountId,
    required this.identity,
  });

  final int generation;
  final String? accountId;
  final LocalIdentity identity;
}

final class _VisibleCodeAction {
  const _VisibleCodeAction({
    required this.generation,
    required this.code,
    required this.context,
  });

  final int generation;
  final FamilyCode code;
  final _PublishedCodeContext context;
}

void _zeroize(List<int> bytes) {
  for (var index = 0; index < bytes.length; index += 1) {
    bytes[index] = 0;
  }
}
