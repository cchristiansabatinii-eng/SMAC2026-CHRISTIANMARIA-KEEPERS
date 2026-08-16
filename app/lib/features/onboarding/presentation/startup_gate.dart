import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/application/family_join_controller.dart';
import 'package:keepers/features/family/application/pending_invite_completion_controller.dart';
import 'package:keepers/features/family/application/pending_join_completion_controller.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/features/family/presentation/family_join_screen.dart';
import 'package:keepers/features/onboarding/application/onboarding_providers.dart';
import 'package:keepers/features/onboarding/domain/local_identity.dart';
import 'package:keepers/features/onboarding/presentation/setup_screen.dart';
import 'package:keepers/features/vault/presentation/observatory_screen.dart';
import 'package:keepers/storage/database_providers.dart';
import 'package:keepers/theme/keepers_theme.dart';

enum StartupDestination { setup, resumeJoin, observatory }

final class StartupResolution {
  const StartupResolution._({
    required this.destination,
    this.identity,
    this.statusMessage,
  });

  const StartupResolution.setup({String? statusMessage})
    : this._(
        destination: StartupDestination.setup,
        statusMessage: statusMessage,
      );

  const StartupResolution.resumeJoin()
    : this._(destination: StartupDestination.resumeJoin);

  const StartupResolution.observatory(LocalIdentity identity)
    : this._(destination: StartupDestination.observatory, identity: identity);

  final StartupDestination destination;
  final LocalIdentity? identity;
  final String? statusMessage;
}

final class StartupGate extends ConsumerStatefulWidget {
  const StartupGate({super.key});

  @override
  ConsumerState<StartupGate> createState() => _StartupGateState();
}

final class _StartupGateState extends ConsumerState<StartupGate> {
  LocalIdentity? _establishedIdentity;
  StartupResolution? _resolution;
  Object? _startupError;
  ProviderSubscription<FamilyJoinCompletionRecovery>? _joinRecoveryListener;
  ProviderSubscription<AsyncValue<LocalIdentity?>>? _identityListener;
  ProviderSubscription<PendingInviteCompletionState>? _legacyRecoveryListener;
  var _legacyRecoveryScheduled = false;
  var _bootGeneration = 0;

  @override
  void initState() {
    super.initState();
    // A manual subscription keeps Task 3 recovery and its auto-dispose
    // notifier alive for the full awaited operation.
    _joinRecoveryListener = ref.listenManual(
      familyJoinCompletionRecoveryProvider,
      (_, _) {},
    );
    // Keep legacy completion recovery available for identities installed by
    // older capability invitations. New join recovery is awaited above.
    _legacyRecoveryListener = ref.listenManual(
      pendingInviteCompletionControllerProvider,
      (_, _) {},
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  @override
  void dispose() {
    _bootGeneration += 1;
    _joinRecoveryListener?.close();
    _identityListener?.close();
    _legacyRecoveryListener?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final established = _establishedIdentity;
    if (established != null) return ObservatoryScreen(identity: established);
    if (_startupError != null) {
      return StartupError(
        message: 'Keepers could not open local storage.',
        onRetry: _retry,
      );
    }
    final resolution = _resolution;
    if (resolution == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return switch (resolution.destination) {
      StartupDestination.observatory => _observatory(resolution.identity!),
      StartupDestination.resumeJoin => FamilyJoinScreen.manual(
        resumePendingRequest: true,
        onCompleted: _refreshAfterJoin,
      ),
      StartupDestination.setup => SetupScreen(
        statusMessage: resolution.statusMessage,
      ),
    };
  }

  Future<void> _bootstrap() async {
    final generation = ++_bootGeneration;
    if (mounted) {
      setState(() {
        _resolution = null;
        _startupError = null;
      });
    }
    try {
      await _joinRecoveryListener!.read()();
      if (!mounted || generation != _bootGeneration) return;

      _identityListener ??= ref.listenManual(localIdentityProvider, (_, next) {
        if (!mounted) return;
        next.when(
          data: (identity) {
            if (identity != null) {
              setState(() {
                _establishedIdentity = identity;
                _resolution = StartupResolution.observatory(identity);
                _startupError = null;
              });
            }
          },
          error: (error, _) {
            if (_establishedIdentity == null) {
              setState(() => _startupError = error);
            }
          },
          loading: () {},
        );
      });
      final identity = await ref.read(localIdentityProvider.future);
      if (!mounted || generation != _bootGeneration) return;
      if (identity != null) {
        setState(() {
          _establishedIdentity = identity;
          _resolution = StartupResolution.observatory(identity);
          _startupError = null;
        });
        return;
      }

      final gateway = ref.read(familyCodeJoinGatewayProvider);
      StartupResolution resolution;
      if (!gateway.isConfigured || gateway.authenticatedAccountId == null) {
        resolution = const StartupResolution.setup();
      } else {
        final own = await gateway.getOwnJoinRequest();
        if (!mounted || generation != _bootGeneration) return;
        resolution = _resolutionFor(own);
      }
      setState(() {
        _resolution = resolution;
        _startupError = null;
      });
    } on Object catch (error) {
      if (mounted && generation == _bootGeneration) {
        setState(() => _startupError = error);
      }
    }
  }

  static StartupResolution _resolutionFor(OwnFamilyJoinRequest? own) {
    if (own == null) return const StartupResolution.setup();
    return switch (own.state) {
      FamilyJoinRequestState.pending ||
      FamilyJoinRequestState.approved => const StartupResolution.resumeJoin(),
      FamilyJoinRequestState.declined => const StartupResolution.setup(
        statusMessage: "Your request wasn't accepted",
      ),
      FamilyJoinRequestState.cancelled => const StartupResolution.setup(
        statusMessage: 'Your request was cancelled',
      ),
      FamilyJoinRequestState.expired => const StartupResolution.setup(
        statusMessage: 'Your request has expired',
      ),
      FamilyJoinRequestState.installed => throw const FamilyJoinFailure(
        FamilyJoinFailureCode.localPersistenceFailed,
      ),
    };
  }

  Widget _observatory(LocalIdentity identity) {
    _establishedIdentity = identity;
    _scheduleLegacyRecovery();
    return ObservatoryScreen(identity: identity);
  }

  void _refreshAfterJoin() {
    ref.invalidate(localIdentityProvider);
    _bootstrap();
  }

  void _retry() {
    ref.invalidate(databaseProvider);
    ref.invalidate(localIdentityProvider);
    ref.invalidate(pendingJoinCompletionControllerProvider);
    _bootstrap();
  }

  void _scheduleLegacyRecovery() {
    if (_legacyRecoveryScheduled) return;
    _legacyRecoveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(pendingInviteCompletionControllerProvider.notifier).recover();
      }
    });
  }
}

final class StartupError extends StatelessWidget {
  const StartupError({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  KeepersText(
                    message,
                    textAlign: TextAlign.center,
                    style: KeepersType.heading.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(120, 48),
                    ),
                    onPressed: onRetry,
                    child: const KeepersText('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
