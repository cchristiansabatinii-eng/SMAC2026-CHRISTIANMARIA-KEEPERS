import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/family_key_envelope_codec.dart';
import 'package:keepers/features/family/data/invite_share_service.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/storage/database_providers.dart';

enum FamilyInvitePhase {
  checking,
  needsAuthentication,
  awaitingOtp,
  ready,
  creating,
  created,
  revoking,
  failed,
}

enum FamilyInviteRetryPoint {
  initialize,
  requestOtp,
  verifyOtp,
  bootstrap,
  create,
  revoke,
}

final class FamilyInviteState {
  const FamilyInviteState({
    this.phase = FamilyInvitePhase.checking,
    this.authenticationEmail = '',
    this.recipientEmail = '',
    this.createdInvitation,
    this.failure,
    this.retryPoint,
    this.isSharing = false,
    this.shareFailure,
    this.isRecipientLocked = false,
  });

  final FamilyInvitePhase phase;
  final String authenticationEmail;
  final String recipientEmail;
  final CreatedInvitation? createdInvitation;
  final InvitationFailure? failure;
  final FamilyInviteRetryPoint? retryPoint;
  final bool isSharing;
  final InvitationFailure? shareFailure;
  final bool isRecipientLocked;

  bool get isBusy =>
      phase == FamilyInvitePhase.checking ||
      phase == FamilyInvitePhase.creating ||
      phase == FamilyInvitePhase.revoking;

  @override
  String toString() => 'FamilyInviteState(${phase.name})';
}

final familyKeyEnvelopeCodecProvider = Provider<FamilyKeyEnvelopeCodec>(
  (ref) => CryptographicFamilyKeyEnvelopeCodec(),
);

final familyInviteControllerProvider =
    NotifierProvider.autoDispose<FamilyInviteController, FamilyInviteState>(
      FamilyInviteController.new,
    );

base class FamilyInviteController extends Notifier<FamilyInviteState> {
  Future<void>? _inFlight;
  Future<void>? _shareInFlight;
  LocalIdentity? _identity;
  String? _bootstrappedAccountId;
  String? _authenticationEmailNormalized;
  InvitationDraft? _draft;
  CloudInvitationDraft? _cloudDraft;
  String? _draftAccountId;
  CreatedInvitation? _createdInvitation;
  FamilyInviteRetryPoint? _resumeAfterAuthentication;
  var _generation = 0;

  @override
  FamilyInviteState build() {
    final gateway = ref.read(cloudFamilyGatewayProvider);
    if (gateway case CloudFamilyAuthEvents(:final signedInEvents)) {
      final subscription = signedInEvents.listen(
        (_) => unawaited(_resumeAfterExternalSignIn()),
        // Supabase reports recoverable refresh and callback failures through
        // this stream. The invitation state already owns user-facing recovery.
        onError: (Object _, StackTrace _) {},
      );
      ref.onDispose(subscription.cancel);
    }
    ref.onDispose(() {
      _generation += 1;
      _clearInvitationMaterial();
    });
    return const FamilyInviteState();
  }

  Future<void> _resumeAfterExternalSignIn() async {
    final running = _inFlight;
    if (running != null) await running;
    final canResumeAuthentication =
        state.phase == FamilyInvitePhase.awaitingOtp ||
        state.phase == FamilyInvitePhase.needsAuthentication ||
        (state.phase == FamilyInvitePhase.failed &&
            (state.retryPoint == FamilyInviteRetryPoint.requestOtp ||
                state.retryPoint == FamilyInviteRetryPoint.verifyOtp));
    if (!ref.mounted ||
        !canResumeAuthentication ||
        ref.read(cloudFamilyGatewayProvider).authenticatedAccountId == null) {
      return;
    }
    await initialize();
  }

  Future<void> initialize() => _deduplicate(_initialize);

  Future<void> _initialize() async {
    final generation = ++_generation;
    final gateway = ref.read(cloudFamilyGatewayProvider);
    state = FamilyInviteState(
      phase: FamilyInvitePhase.checking,
      authenticationEmail: state.authenticationEmail,
      recipientEmail: state.recipientEmail,
      createdInvitation: state.createdInvitation,
    );
    if (!gateway.isConfigured) {
      _setFailure(
        const InvitationFailure(InvitationFailureCode.notConfigured),
        retryPoint: FamilyInviteRetryPoint.initialize,
      );
      return;
    }

    final startingAccount = gateway.authenticatedAccountId;
    final identity = await ref.read(localIdentityProvider.future);
    if (!_isCurrentGeneration(generation)) return;
    if (gateway.authenticatedAccountId != startingAccount) {
      _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.initialize);
      return;
    }
    if (identity == null) {
      _setFailure(
        const InvitationFailure(InvitationFailureCode.unknown),
        retryPoint: FamilyInviteRetryPoint.initialize,
      );
      return;
    }
    _identity = identity;
    if (startingAccount == null) {
      state = FamilyInviteState(
        phase: FamilyInvitePhase.needsAuthentication,
        authenticationEmail: state.authenticationEmail,
        recipientEmail: state.recipientEmail,
      );
      return;
    }
    await _bootstrap(identity, startingAccount, generation);
  }

  Future<void> requestEmailOtp(String email) => _deduplicate(() async {
    final normalized = _normalizeEmail(email);
    if (normalized == null) {
      state = FamilyInviteState(
        phase: FamilyInvitePhase.failed,
        authenticationEmail: email,
        recipientEmail: state.recipientEmail,
        failure: const InvitationFailure(InvitationFailureCode.invalidEmail),
        retryPoint: FamilyInviteRetryPoint.requestOtp,
      );
      return;
    }
    final generation = ++_generation;
    final startingAccount = ref
        .read(cloudFamilyGatewayProvider)
        .authenticatedAccountId;
    state = FamilyInviteState(
      phase: FamilyInvitePhase.checking,
      authenticationEmail: email,
      recipientEmail: state.recipientEmail,
      retryPoint: FamilyInviteRetryPoint.requestOtp,
    );
    try {
      await ref.read(cloudFamilyGatewayProvider).requestEmailOtp(normalized);
      if (!_isCurrentGeneration(generation)) return;
      if (ref.read(cloudFamilyGatewayProvider).authenticatedAccountId !=
          startingAccount) {
        _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.requestOtp);
        return;
      }
      _authenticationEmailNormalized = normalized;
      state = FamilyInviteState(
        phase: FamilyInvitePhase.awaitingOtp,
        authenticationEmail: email,
        recipientEmail: state.recipientEmail,
      );
    } on InvitationFailure catch (failure) {
      if (_isCurrentGeneration(generation)) {
        _setFailure(failure, retryPoint: FamilyInviteRetryPoint.requestOtp);
      }
    } on Object {
      if (_isCurrentGeneration(generation)) {
        _setFailure(
          const InvitationFailure(InvitationFailureCode.unknown),
          retryPoint: FamilyInviteRetryPoint.requestOtp,
        );
      }
    }
  });

  Future<void> verifyEmailOtp(String token) => _deduplicate(() async {
    final email =
        _authenticationEmailNormalized ??
        _normalizeEmail(state.authenticationEmail);
    if (email == null) {
      _setFailure(
        const InvitationFailure(InvitationFailureCode.invalidEmail),
        retryPoint: FamilyInviteRetryPoint.verifyOtp,
      );
      return;
    }
    final generation = ++_generation;
    state = FamilyInviteState(
      phase: FamilyInvitePhase.checking,
      authenticationEmail: state.authenticationEmail,
      recipientEmail: state.recipientEmail,
      retryPoint: FamilyInviteRetryPoint.verifyOtp,
    );
    final gateway = ref.read(cloudFamilyGatewayProvider);
    try {
      await gateway.verifyEmailOtp(email: email, token: token);
      if (!_isCurrentGeneration(generation)) return;
      final accountId = gateway.authenticatedAccountId;
      if (accountId == null) {
        _setFailure(
          const InvitationFailure(InvitationFailureCode.signedOut),
          retryPoint: FamilyInviteRetryPoint.verifyOtp,
        );
        return;
      }
      final identity =
          _identity ?? await ref.read(localIdentityProvider.future);
      if (!_isCurrentGeneration(generation)) return;
      if (gateway.authenticatedAccountId != accountId) {
        _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.verifyOtp);
        return;
      }
      if (identity == null) {
        _setFailure(
          const InvitationFailure(InvitationFailureCode.unknown),
          retryPoint: FamilyInviteRetryPoint.verifyOtp,
        );
        return;
      }
      _identity = identity;
      await _bootstrap(identity, accountId, generation);
    } on InvitationFailure catch (failure) {
      if (_isCurrentGeneration(generation)) {
        _setFailure(failure, retryPoint: FamilyInviteRetryPoint.verifyOtp);
      }
    } on Object {
      if (_isCurrentGeneration(generation)) {
        _setFailure(
          const InvitationFailure(InvitationFailureCode.unknown),
          retryPoint: FamilyInviteRetryPoint.verifyOtp,
        );
      }
    }
  });

  Future<void> _bootstrap(
    LocalIdentity identity,
    String accountId,
    int generation,
  ) async {
    if (identity.accountId != null && identity.accountId != accountId) {
      _setFailure(
        const InvitationFailure(InvitationFailureCode.differentFamily),
        retryPoint: FamilyInviteRetryPoint.bootstrap,
      );
      return;
    }
    if (_bootstrappedAccountId == accountId) {
      _setReady();
      return;
    }
    final gateway = ref.read(cloudFamilyGatewayProvider);
    try {
      if (identity.accountId == accountId) {
        final database = await ref.read(databaseProvider.future);
        if (!_accountIsCurrent(generation, accountId)) {
          _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.bootstrap);
          return;
        }
        final roster = await ref
            .read(familyRosterRepositoryProvider)
            .listLocal(database, familyId: identity.familyId);
        if (!_accountIsCurrent(generation, accountId)) {
          _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.bootstrap);
          return;
        }
        // The owner is created before an invitation can add later members;
        // both cloud and local roster persistence retain that join order.
        if (roster.isEmpty || roster.first.id != identity.memberId) {
          _setFailure(
            const InvitationFailure(InvitationFailureCode.notOwner),
            retryPoint: FamilyInviteRetryPoint.bootstrap,
          );
          return;
        }
        _bootstrappedAccountId = accountId;
        _setReady();
        return;
      }
      final owner = LocalOwnerFamily(
        familyId: identity.familyId,
        familyName: identity.familyName,
        memberId: identity.memberId,
        displayName: identity.memberName,
        demographicRole: FamilyDemographicRole.adult,
        colorToken: identity.colorToken,
        avatar: identity.avatar,
      );
      await gateway.bootstrapOwner(owner);
      if (!_accountIsCurrent(generation, accountId)) {
        _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.bootstrap);
        return;
      }
      final database = await ref.read(databaseProvider.future);
      if (!_accountIsCurrent(generation, accountId)) {
        _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.bootstrap);
        return;
      }
      await database.transaction((transaction) async {
        await ref
            .read(memberRepositoryProvider)
            .bindLocalIdentity(
              transaction,
              familyId: identity.familyId,
              memberId: identity.memberId,
              accountId: accountId,
            );
      });
      if (!_accountIsCurrent(generation, accountId)) {
        _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.bootstrap);
        return;
      }
      _bootstrappedAccountId = accountId;
      _identity = LocalIdentity(
        familyId: identity.familyId,
        familyName: identity.familyName,
        familyKeyRef: identity.familyKeyRef,
        memberId: identity.memberId,
        memberName: identity.memberName,
        memberKeyRef: identity.memberKeyRef,
        colorToken: identity.colorToken,
        avatar: identity.avatar,
        accountId: accountId,
      );
      ref.invalidate(localIdentityProvider);
      _setReady();
    } on InvitationFailure catch (failure) {
      if (_isCurrentGeneration(generation)) {
        _setFailure(failure, retryPoint: FamilyInviteRetryPoint.bootstrap);
      }
    } on Object {
      if (_isCurrentGeneration(generation)) {
        _setFailure(
          const InvitationFailure(InvitationFailureCode.localPersistenceFailed),
          retryPoint: FamilyInviteRetryPoint.bootstrap,
        );
      }
    }
  }

  Future<void> createInvite(
    String recipientEmail, {
    Rect? sharePositionOrigin,
  }) => _deduplicate(() async {
    final gateway = ref.read(cloudFamilyGatewayProvider);
    final identity = _identity;
    final accountId = gateway.authenticatedAccountId;
    if (identity == null ||
        accountId == null ||
        _bootstrappedAccountId != accountId) {
      _setFailure(
        const InvitationFailure(InvitationFailureCode.signedOut),
        retryPoint: FamilyInviteRetryPoint.create,
      );
      return;
    }

    final generation = ++_generation;
    if (_cloudDraft == null) {
      final normalizedRecipient = _normalizeEmail(recipientEmail);
      if (normalizedRecipient == null) {
        state = FamilyInviteState(
          phase: FamilyInvitePhase.failed,
          authenticationEmail: state.authenticationEmail,
          recipientEmail: recipientEmail,
          failure: const InvitationFailure(InvitationFailureCode.invalidEmail),
          retryPoint: FamilyInviteRetryPoint.create,
        );
        return;
      }
      state = FamilyInviteState(
        phase: FamilyInvitePhase.creating,
        authenticationEmail: state.authenticationEmail,
        recipientEmail: recipientEmail,
      );
      List<int>? familyKey;
      List<int>? resolvedFamilyKey;
      try {
        resolvedFamilyKey = await ref
            .read(identityKeyServiceProvider)
            .resolve(identity.familyKeyRef);
        familyKey = List<int>.of(resolvedFamilyKey, growable: false);
        if (!_accountIsCurrent(generation, accountId)) {
          _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.create);
          return;
        }
        final draft = await ref
            .read(familyKeyEnvelopeCodecProvider)
            .createDraft(
              familyId: identity.familyId,
              familyKey: familyKey,
              inviteId: ref.read(idFactoryProvider)(),
              expiresAt: ref
                  .read(utcNowProvider)()
                  .add(const Duration(hours: 24)),
            );
        if (!_accountIsCurrent(generation, accountId)) {
          _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.create);
          return;
        }
        _draft = draft;
        _cloudDraft = CloudInvitationDraft(
          inviteId: draft.link.inviteId,
          familyId: identity.familyId,
          recipientEmail: normalizedRecipient,
          tokenHash: draft.tokenHash,
          envelope: draft.envelope,
        );
        _draftAccountId = accountId;
      } on InvitationFailure catch (failure) {
        if (_isCurrentGeneration(generation)) {
          _setFailure(failure, retryPoint: FamilyInviteRetryPoint.create);
        }
        return;
      } on Object {
        if (_isCurrentGeneration(generation)) {
          _setFailure(
            const InvitationFailure(InvitationFailureCode.unknown),
            retryPoint: FamilyInviteRetryPoint.create,
          );
        }
        return;
      } finally {
        if (familyKey != null) _zeroize(familyKey);
        if (resolvedFamilyKey != null) _zeroizeIfMutable(resolvedFamilyKey);
      }
    } else {
      state = FamilyInviteState(
        phase: FamilyInvitePhase.creating,
        authenticationEmail: state.authenticationEmail,
        recipientEmail: state.recipientEmail,
        createdInvitation: state.createdInvitation,
        isRecipientLocked: true,
      );
    }

    final cloudDraft = _cloudDraft!;
    if (_draftAccountId != accountId ||
        cloudDraft.familyId != identity.familyId) {
      _clearInvitationMaterial();
      _setFailure(
        const InvitationFailure(InvitationFailureCode.signedOut),
        retryPoint: FamilyInviteRetryPoint.create,
      );
      return;
    }
    try {
      final created = await gateway.createInvitation(cloudDraft);
      if (!_accountIsCurrent(generation, accountId)) {
        _clearInvitationMaterial();
        _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.create);
        return;
      }
      if (created.inviteId != cloudDraft.inviteId ||
          created.familyId != cloudDraft.familyId ||
          created.state != CloudInvitationState.pending ||
          !created.expiresAt.isAfter(created.createdAt)) {
        _setFailure(
          const InvitationFailure(InvitationFailureCode.unknown),
          retryPoint: FamilyInviteRetryPoint.create,
        );
        return;
      }
      _createdInvitation = created;
      state = FamilyInviteState(
        phase: FamilyInvitePhase.created,
        authenticationEmail: state.authenticationEmail,
        recipientEmail: state.recipientEmail,
        createdInvitation: created,
      );
      await _shareInvitation(sharePositionOrigin: sharePositionOrigin);
    } on InvitationFailure catch (failure) {
      if (_isCurrentGeneration(generation)) {
        _setFailure(failure, retryPoint: FamilyInviteRetryPoint.create);
      }
    } on Object {
      if (_isCurrentGeneration(generation)) {
        _setFailure(
          const InvitationFailure(InvitationFailureCode.unknown),
          retryPoint: FamilyInviteRetryPoint.create,
        );
      }
    }
  });

  Future<void> revokeInvite() => _deduplicate(() async {
    final created = _createdInvitation ?? state.createdInvitation;
    final accountId = ref
        .read(cloudFamilyGatewayProvider)
        .authenticatedAccountId;
    if (created == null || accountId == null) {
      _setFailure(
        const InvitationFailure(InvitationFailureCode.signedOut),
        retryPoint: FamilyInviteRetryPoint.revoke,
      );
      return;
    }
    final generation = ++_generation;
    state = FamilyInviteState(
      phase: FamilyInvitePhase.revoking,
      authenticationEmail: state.authenticationEmail,
      recipientEmail: state.recipientEmail,
      createdInvitation: created,
    );
    try {
      await ref
          .read(cloudFamilyGatewayProvider)
          .revokeInvitation(created.inviteId);
      if (!_accountIsCurrent(generation, accountId)) {
        _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.revoke);
        return;
      }
      _clearInvitationMaterial();
      _setReady();
    } on InvitationFailure catch (failure) {
      if (_isCurrentGeneration(generation)) {
        _setFailure(failure, retryPoint: FamilyInviteRetryPoint.revoke);
      }
    } on Object {
      if (_isCurrentGeneration(generation)) {
        _setFailure(
          const InvitationFailure(InvitationFailureCode.unknown),
          retryPoint: FamilyInviteRetryPoint.revoke,
        );
      }
    }
  });

  Future<void> shareAgain({Rect? sharePositionOrigin}) {
    final running = _inFlight;
    if (running != null) return running;
    return _shareInvitation(sharePositionOrigin: sharePositionOrigin);
  }

  Future<void> _shareInvitation({Rect? sharePositionOrigin}) {
    final running = _shareInFlight;
    if (running != null) return running;
    final created = _createdInvitation ?? state.createdInvitation;
    final draft = _draft;
    final identity = _identity;
    final gateway = ref.read(cloudFamilyGatewayProvider);
    final accountId = gateway.authenticatedAccountId;
    if (created == null ||
        draft == null ||
        identity == null ||
        accountId == null ||
        _draftAccountId != accountId ||
        created.inviteId != draft.link.inviteId ||
        created.familyId != identity.familyId ||
        draft.envelope.familyId != identity.familyId) {
      if (accountId == null || _draftAccountId != accountId) {
        _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.create);
      } else if (created != null) {
        state = FamilyInviteState(
          phase: FamilyInvitePhase.created,
          authenticationEmail: state.authenticationEmail,
          recipientEmail: state.recipientEmail,
          createdInvitation: created,
          shareFailure: const InvitationFailure(InvitationFailureCode.unknown),
        );
      }
      return Future<void>.value();
    }

    late final Future<void> future;
    future =
        () async {
          state = FamilyInviteState(
            phase: FamilyInvitePhase.created,
            authenticationEmail: state.authenticationEmail,
            recipientEmail: state.recipientEmail,
            createdInvitation: created,
            isSharing: true,
          );
          try {
            await ref
                .read(inviteShareServiceProvider)
                .shareInvitation(
                  draft.link.toUri(),
                  sharePositionOrigin: sharePositionOrigin,
                );
            if (!ref.mounted || gateway.authenticatedAccountId != accountId) {
              _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.create);
              return;
            }
            state = FamilyInviteState(
              phase: FamilyInvitePhase.created,
              authenticationEmail: state.authenticationEmail,
              recipientEmail: state.recipientEmail,
              createdInvitation: created,
            );
          } on Object {
            if (ref.mounted && gateway.authenticatedAccountId != accountId) {
              _handleStaleAccount(retryPoint: FamilyInviteRetryPoint.create);
            } else if (ref.mounted) {
              state = FamilyInviteState(
                phase: FamilyInvitePhase.created,
                authenticationEmail: state.authenticationEmail,
                recipientEmail: state.recipientEmail,
                createdInvitation: created,
                shareFailure: const InvitationFailure(
                  InvitationFailureCode.unknown,
                ),
              );
            }
          }
        }().whenComplete(() {
          if (identical(_shareInFlight, future)) _shareInFlight = null;
        });
    _shareInFlight = future;
    return future;
  }

  Future<void> _deduplicate(Future<void> Function() operation) {
    final sharing = _shareInFlight;
    if (sharing != null) return sharing;
    final running = _inFlight;
    if (running != null) return running;
    late final Future<void> future;
    future = operation().whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  bool _isCurrentGeneration(int generation) =>
      ref.mounted && generation == _generation;

  bool _accountIsCurrent(int generation, String accountId) =>
      _isCurrentGeneration(generation) &&
      ref.read(cloudFamilyGatewayProvider).authenticatedAccountId == accountId;

  void _handleStaleAccount({FamilyInviteRetryPoint? retryPoint}) {
    if (!ref.mounted) return;
    _bootstrappedAccountId = null;
    _clearInvitationMaterial();
    if (retryPoint == FamilyInviteRetryPoint.create ||
        retryPoint == FamilyInviteRetryPoint.revoke) {
      _resumeAfterAuthentication = retryPoint;
    }
    state = FamilyInviteState(
      phase: FamilyInvitePhase.failed,
      authenticationEmail: state.authenticationEmail,
      recipientEmail: state.recipientEmail,
      failure: const InvitationFailure(InvitationFailureCode.signedOut),
      retryPoint: retryPoint,
    );
  }

  void _setReady() {
    if (!ref.mounted) return;
    final resume = _resumeAfterAuthentication;
    _resumeAfterAuthentication = null;
    if (resume == FamilyInviteRetryPoint.revoke && _createdInvitation != null) {
      state = FamilyInviteState(
        phase: FamilyInvitePhase.created,
        authenticationEmail: state.authenticationEmail,
        recipientEmail: state.recipientEmail,
        createdInvitation: _createdInvitation,
      );
      return;
    }
    state = FamilyInviteState(
      phase: FamilyInvitePhase.ready,
      authenticationEmail: state.authenticationEmail,
      recipientEmail: state.recipientEmail,
      retryPoint: resume == FamilyInviteRetryPoint.create ? resume : null,
      isRecipientLocked: _cloudDraft != null,
    );
  }

  void _setFailure(
    InvitationFailure failure, {
    FamilyInviteRetryPoint? retryPoint,
  }) {
    if (!ref.mounted) return;
    if (failure.code == InvitationFailureCode.signedOut &&
        (retryPoint == FamilyInviteRetryPoint.create ||
            retryPoint == FamilyInviteRetryPoint.revoke)) {
      _bootstrappedAccountId = null;
      _resumeAfterAuthentication = retryPoint;
    }
    state = FamilyInviteState(
      phase: FamilyInvitePhase.failed,
      authenticationEmail: state.authenticationEmail,
      recipientEmail: state.recipientEmail,
      createdInvitation: _createdInvitation ?? state.createdInvitation,
      failure: failure,
      retryPoint: retryPoint,
      shareFailure: state.shareFailure,
      isRecipientLocked: _cloudDraft != null,
    );
  }

  void _clearInvitationMaterial() {
    _draft = null;
    _cloudDraft = null;
    _draftAccountId = null;
    _createdInvitation = null;
    _resumeAfterAuthentication = null;
  }
}

String? _normalizeEmail(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.length > 254 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

void _zeroize(List<int> bytes) {
  for (var index = 0; index < bytes.length; index += 1) {
    bytes[index] = 0;
  }
}

void _zeroizeIfMutable(List<int> bytes) {
  try {
    _zeroize(bytes);
  } on UnsupportedError {
    // IdentityKeyService intentionally returns an immutable source list. The
    // controller-owned mutable copy is still overwritten unconditionally.
  }
}
