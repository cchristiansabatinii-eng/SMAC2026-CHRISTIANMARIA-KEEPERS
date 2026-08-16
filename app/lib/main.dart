import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humation_flutter/humation_flutter.dart';
import 'package:keepers/app.dart';
import 'package:keepers/features/family/application/cloud_family_providers.dart';
import 'package:keepers/features/family/data/invite_link_coordinator.dart';
import 'package:keepers/features/family/data/supabase_cloud_gateway_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Humation.prewarm();
  // Construct this before optional cloud startup so cold links are observed
  // before Supabase has a chance to delay the root app.
  final inviteUriSource = AppLinksInviteUriSource(AppLinks());
  final inviteLinkCoordinator = InviteLinkCoordinator(inviteUriSource);
  unawaited(inviteLinkCoordinator.resolveInitialLink());
  final configuredGateway = await configuredCloudFamilyGateway();
  runApp(
    ProviderScope(
      overrides: [
        if (configuredGateway != null)
          cloudFamilyGatewayProvider.overrideWithValue(configuredGateway),
      ],
      child: KeepersApp(inviteLinkCoordinator: inviteLinkCoordinator),
    ),
  );
}
