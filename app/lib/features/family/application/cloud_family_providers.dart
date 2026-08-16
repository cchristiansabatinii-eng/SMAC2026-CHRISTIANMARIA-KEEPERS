import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/data/cloud_family_gateway.dart';
import 'package:keepers/features/family/data/unavailable_cloud_family_gateway.dart';

final cloudFamilyGatewayProvider = Provider<CloudFamilyGateway>(
  (ref) => const UnavailableCloudFamilyGateway(),
);

final familyCodeJoinGatewayProvider = Provider<FamilyCodeJoinGateway>((ref) {
  final gateway = ref.watch(cloudFamilyGatewayProvider);
  return switch (gateway) {
    FamilyCodeJoinGateway capability => capability,
    _ => const UnavailableFamilyCodeJoinGateway(),
  };
});
