import 'package:keepers/features/capture/domain/capture_models.dart';

final class OrbitSceneModel {
  const OrbitSceneModel({required this.member, required this.memories});

  final OrbitMemberNode member;
  final List<OrbitMemoryMark> memories;
}

final class OrbitMemberNode {
  const OrbitMemberNode({
    required this.id,
    required this.name,
    required this.colorToken,
  });

  final String id;
  final String name;
  final String colorToken;
}

final class OrbitMemoryMark {
  const OrbitMemoryMark({
    required this.id,
    required this.format,
    required this.privacy,
    required this.createdAt,
    required this.colorToken,
  });

  final String id;
  final MemoryFormat format;
  final PrivacyTier privacy;
  final DateTime createdAt;
  final String colorToken;
}
