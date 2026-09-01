import 'dart:math' as math;
import 'dart:ui';

final class OrbitPositions {
  OrbitPositions({
    required this.memberCenter,
    required Iterable<Offset> memoryCenters,
  }) : memoryCenters = List<Offset>.unmodifiable(memoryCenters);

  final Offset memberCenter;
  final List<Offset> memoryCenters;
}

final class OrbitLayout {
  const OrbitLayout._();

  static OrbitPositions positions({
    required Size size,
    required int memoryCount,
    required double phase,
    required double drift,
  }) {
    if (memoryCount < 0) {
      throw ArgumentError.value(memoryCount, 'memoryCount');
    }
    final memberCenter = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .34;
    final clampedPhase = phase.clamp(-1.0, 1.0).toDouble();
    final centers = List<Offset>.generate(memoryCount, (index) {
      final angle =
          -math.pi / 2 + index * 2 * math.pi / math.max(memoryCount, 1);
      final radial = Offset(math.cos(angle), math.sin(angle)) * radius;
      final tangent = Offset(-math.sin(angle), math.cos(angle));
      return memberCenter + radial + tangent * drift * clampedPhase;
    }, growable: false);
    return OrbitPositions(memberCenter: memberCenter, memoryCenters: centers);
  }
}
