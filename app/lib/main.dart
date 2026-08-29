import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humation_flutter/humation_flutter.dart';
import 'package:keepers/app.dart';
import 'package:keepers/features/capture/data/audio_playback_adapter.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/data/invite_link_coordinator.dart';
import 'package:keepers/features/family/data/supabase_cloud_gateway_bootstrap.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  Humation.prewarm();
  try {
    await purgeAbandonedAudioPlaybackPlaintext(getTemporaryDirectory);
  } on Object {
    // Cleanup is best-effort: a temporary-storage failure must not prevent
    // access to encrypted memories or family invitations.
  }
  // Supabase must attach the first AppLinks listener so a cold auth callback
  // reaches its non-replaying mobile stream. Invite routing starts afterward
  // and still recovers a cold Join target through getInitialLink.
  final CloudFamilyGatewayLoader cloudGatewayLoader =
      configuredCloudFamilyGateway;
  final configuredGateway = await cloudGatewayLoader();
  final inviteUriSource = AppLinksInviteUriSource(AppLinks());
  final inviteLinkCoordinator = InviteLinkCoordinator(inviteUriSource);
  unawaited(inviteLinkCoordinator.resolveInitialLink());
  // Keep the native black-and-cream wordmark on screen until Flutter has
  // decoded its exact launch counterpart. This prevents a blank handoff on
  // cold or resource-constrained devices.
  binding.deferFirstFrame();
  runApp(
    ProviderScope(
      overrides: [
        cloudFamilyGatewayLoaderProvider.overrideWithValue(cloudGatewayLoader),
        initialCloudFamilyGatewayProvider.overrideWithValue(configuredGateway),
      ],
      child: KeepersApp(
        inviteLinkCoordinator: inviteLinkCoordinator,
        playLaunchSequence: true,
        onLaunchReady: binding.allowFirstFrame,
      ),
    ),
  );
}
