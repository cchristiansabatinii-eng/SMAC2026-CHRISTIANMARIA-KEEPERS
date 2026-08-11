import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/design_system/observatory/motion_policy.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/design_system/observatory/observatory_view.dart';
import 'package:keepers/design_system/observatory/orbit_scene.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';

const _memoryId = 'memory-1';
final _scene = OrbitSceneModel(
  member: const OrbitMemberNode(
    id: 'member-1',
    name: 'Chris',
    colorToken: 'ochre',
  ),
  memories: [
    OrbitMemoryMark(
      id: _memoryId,
      format: MemoryFormat.text,
      privacy: PrivacyTier.reveal,
      createdAt: DateTime.utc(2026, 9, 1),
      colorToken: 'ochre',
    ),
  ],
);

void main() {
  testWidgets('normal seal moves the format object before landing brass', (
    tester,
  ) async {
    const policy = MotionPolicy(
      idleDrift: 0,
      parallax: 0,
      useSealTravel: true,
      sealDuration: Duration(seconds: 1),
    );

    await tester.pumpWidget(_view(policy: policy, sealProgress: 0));
    final member = find.byKey(const ValueKey('orbit-member-node'));
    final actor = find.byKey(const ValueKey('seal-actor-$_memoryId'));
    final mark = find.byKey(const ValueKey('orbit-memory-$_memoryId'));
    final badge = find.byKey(const ValueKey('seal-badge-$_memoryId'));
    expect(actor, findsOneWidget);
    expect(
      find.descendant(of: actor, matching: find.byIcon(Icons.notes_rounded)),
      findsOneWidget,
    );
    expect(tester.getCenter(actor), tester.getCenter(member));
    expect(mark, findsNothing);
    expect(badge, findsNothing);

    await tester.pumpWidget(_view(policy: policy, sealProgress: .5));
    final midway = tester.getCenter(actor);
    expect(midway, isNot(tester.getCenter(member)));
    expect(mark, findsNothing);
    expect(badge, findsNothing);

    await tester.pumpWidget(_view(policy: policy, sealProgress: .75));
    final landed = tester.getCenter(actor);
    expect(mark, findsNothing);
    expect(badge, findsOneWidget);
    expect(tester.getCenter(badge), landed);

    await tester.pumpWidget(_view(policy: policy, sealProgress: 1));
    expect(actor, findsNothing);
    expect(mark, findsOneWidget);
    expect(badge, findsOneWidget);
    expect(tester.getCenter(mark), landed);
    expect(tester.getCenter(badge), landed);
  });

  testWidgets('reduced motion keeps the format object at its target', (
    tester,
  ) async {
    const policy = MotionPolicy(
      idleDrift: 0,
      parallax: 0,
      useSealTravel: false,
      sealDuration: Duration(milliseconds: 168),
    );

    await tester.pumpWidget(_view(policy: policy, sealProgress: .25));
    final actor = find.byKey(const ValueKey('seal-actor-$_memoryId'));
    expect(actor, findsOneWidget);
    final target = tester.getCenter(actor);
    expect(target.dx, closeTo(400, .001));
    expect(target.dy, closeTo(96, .001));
    expect(find.byKey(const ValueKey('orbit-memory-$_memoryId')), findsNothing);

    await tester.pumpWidget(_view(policy: policy, sealProgress: 1));
    expect(actor, findsNothing);
    expect(
      find.byKey(const ValueKey('orbit-memory-$_memoryId')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('seal-badge-$_memoryId')), findsOneWidget);
  });

  testWidgets('idle drift continues and stops immediately for reduced motion', (
    tester,
  ) async {
    const normal = MotionPolicy(
      idleDrift: 7,
      parallax: 0,
      useSealTravel: true,
      sealDuration: Duration(milliseconds: 100),
    );
    const reduced = MotionPolicy(
      idleDrift: 0,
      parallax: 0,
      useSealTravel: false,
      sealDuration: Duration(milliseconds: 40),
    );
    final mark = find.byKey(const ValueKey('orbit-memory-$_memoryId'));

    await tester.pumpWidget(_view(policy: normal, sealing: false));
    await tester.pump(const Duration(seconds: 8));
    final before = tester.getCenter(mark);
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.getCenter(mark), isNot(before));

    await tester.pumpWidget(_view(policy: reduced, sealing: false));
    await tester.pump();
    final stopped = tester.getCenter(mark);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getCenter(mark), stopped);

    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

Widget _view({
  required MotionPolicy policy,
  double sealProgress = 0,
  bool sealing = true,
}) => MaterialApp(
  theme: KeepersTheme.dark(),
  home: Center(
    child: SizedBox.square(
      dimension: 600,
      child: ObservatoryView(
        scene: _scene,
        policy: policy,
        onAddMemory: null,
        onOpenMemory: (_) {},
        sealedMemoryId: sealing ? _memoryId : null,
        sealProgress: sealProgress,
      ),
    ),
  ),
);
