import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/supabase_cloud_gateway_bootstrap.dart';
import 'package:keepers/features/family/data/unavailable_cloud_family_gateway.dart';

typedef CloudFamilyGatewayLoader = Future<CloudFamilyGateway?> Function();

final cloudFamilyGatewayLoaderProvider = Provider<CloudFamilyGatewayLoader>(
  (ref) => configuredCloudFamilyGateway,
);

final initialCloudFamilyGatewayProvider = Provider<CloudFamilyGateway?>(
  (ref) => null,
);

final cloudFamilyGatewayStateProvider =
    NotifierProvider<CloudFamilyGatewayController, CloudFamilyGateway>(
      CloudFamilyGatewayController.new,
    );

final cloudFamilyGatewayProvider = Provider<CloudFamilyGateway>(
  (ref) => ref.watch(cloudFamilyGatewayStateProvider),
);

final class CloudFamilyGatewayController extends Notifier<CloudFamilyGateway> {
  Future<CloudFamilyGateway>? _inFlight;

  @override
  CloudFamilyGateway build() =>
      ref.watch(initialCloudFamilyGatewayProvider) ??
      const UnavailableCloudFamilyGateway();

  Future<CloudFamilyGateway> reload() {
    final running = _inFlight;
    if (running != null) return running;
    late final Future<CloudFamilyGateway> future;
    future = _reload().whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  Future<CloudFamilyGateway> _reload() async {
    CloudFamilyGateway? loaded;
    try {
      loaded = await ref.read(cloudFamilyGatewayLoaderProvider)();
    } on Object {
      loaded = null;
    }
    final next = loaded ?? const UnavailableCloudFamilyGateway();
    if (ref.mounted) state = next;
    return next;
  }
}

final familyCodeJoinGatewayProvider = Provider<FamilyCodeJoinGateway>((ref) {
  final gateway = ref.watch(cloudFamilyGatewayProvider);
  return switch (gateway) {
    FamilyCodeJoinGateway capability => capability,
    _ => const UnavailableFamilyCodeJoinGateway(),
  };
});
