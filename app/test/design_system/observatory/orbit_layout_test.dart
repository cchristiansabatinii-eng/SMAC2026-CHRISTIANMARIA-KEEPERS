import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/orbit_layout.dart';

void main() {
  test('one member stays centered and memories remain in orbit bounds', () {
    final layout = OrbitLayout.positions(
      size: const Size(320, 320),
      memoryCount: 6,
      phase: 0,
      drift: 4,
    );

    expect(layout.memberCenter, const Offset(160, 160));
    expect(layout.memoryCenters, hasLength(6));
    expect(layout.memoryCenters.first.dx, closeTo(160, .001));
    expect(layout.memoryCenters.first.dy, closeTo(51.2, .001));
    expect(
      layout.memoryCenters.every(const Rect.fromLTWH(0, 0, 320, 320).contains),
      isTrue,
    );
  });

  test('phase adds at most four pixels of tangential drift', () {
    final neutral = OrbitLayout.positions(
      size: const Size(320, 240),
      memoryCount: 4,
      phase: 0,
      drift: 4,
    );
    final drifted = OrbitLayout.positions(
      size: const Size(320, 240),
      memoryCount: 4,
      phase: 1,
      drift: 4,
    );
    final clamped = OrbitLayout.positions(
      size: const Size(320, 240),
      memoryCount: 4,
      phase: 99,
      drift: 4,
    );

    for (var index = 0; index < neutral.memoryCenters.length; index += 1) {
      expect(
        (drifted.memoryCenters[index] - neutral.memoryCenters[index]).distance,
        closeTo(4, .001),
      );
    }
    expect(clamped.memoryCenters, drifted.memoryCenters);
  });

  test('an empty orbit has no memory centers', () {
    final layout = OrbitLayout.positions(
      size: const Size(320, 320),
      memoryCount: 0,
      phase: 0,
      drift: 4,
    );

    expect(layout.memberCenter, const Offset(160, 160));
    expect(layout.memoryCenters, isEmpty);
  });

  test('caller-owned drift token controls the bounded offset', () {
    final neutral = OrbitLayout.positions(
      size: const Size(320, 320),
      memoryCount: 1,
      phase: 0,
      drift: 9,
    );
    final drifted = OrbitLayout.positions(
      size: const Size(320, 320),
      memoryCount: 1,
      phase: 1,
      drift: 9,
    );

    expect(
      (drifted.memoryCenters.single - neutral.memoryCenters.single).distance,
      closeTo(9, .001),
    );
  });
}
