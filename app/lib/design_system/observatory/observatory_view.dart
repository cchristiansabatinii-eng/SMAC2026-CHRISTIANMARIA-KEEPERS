import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:keepers/design_system/observatory/motion_policy.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/design_system/observatory/orbit_layout.dart';
import 'package:keepers/design_system/observatory/orbit_scene.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';
import 'package:keepers/features/vault/domain/vault_models.dart';

final class ObservatoryView extends StatefulWidget {
  const ObservatoryView({
    required this.scene,
    required this.policy,
    required this.onAddMemory,
    required this.onOpenMemory,
    this.sealedMemoryId,
    this.sealProgress = 0,
    super.key,
  });

  final OrbitSceneModel scene;
  final MotionPolicy policy;
  final VoidCallback? onAddMemory;
  final ValueChanged<String> onOpenMemory;
  final String? sealedMemoryId;
  final double sealProgress;

  @override
  State<ObservatoryView> createState() => _ObservatoryViewState();
}

final class _ObservatoryViewState extends State<ObservatoryView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idleController;

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(vsync: this, value: .5);
    _syncIdleMotion();
  }

  @override
  void didUpdateWidget(covariant ObservatoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.policy.idleDrift != widget.policy.idleDrift ||
        oldWidget.policy.useSealTravel != widget.policy.useSealTravel ||
        oldWidget.policy.sealDuration != widget.policy.sealDuration) {
      _syncIdleMotion();
    }
  }

  void _syncIdleMotion() {
    _idleController.stop();
    if (widget.policy.isReduced || widget.policy.idleDrift == 0) {
      _idleController.value = .5;
      return;
    }
    _idleController.repeat(reverse: true, period: widget.policy.idlePeriod);
  }

  @override
  void dispose() {
    _idleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ObservatoryTokens>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.ground,
        image: const DecorationImage(
          image: AssetImage('assets/textures/observatory-grain.png'),
          repeat: ImageRepeat.repeat,
          opacity: .04,
        ),
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: AnimatedBuilder(
          animation: _idleController,
          builder: (context, _) => _OrbitField(
            scene: widget.scene,
            phase:
                Curves.easeInOutBack.transform(_idleController.value) * 2 - 1,
            policy: widget.policy,
            tokens: tokens,
            onAddMemory: widget.onAddMemory,
            onOpenMemory: widget.onOpenMemory,
            sealedMemoryId: widget.sealedMemoryId,
            sealProgress: widget.sealProgress,
          ),
        ),
      ),
    );
  }
}

final class _OrbitField extends StatelessWidget {
  const _OrbitField({
    required this.scene,
    required this.phase,
    required this.policy,
    required this.tokens,
    required this.onAddMemory,
    required this.onOpenMemory,
    required this.sealedMemoryId,
    required this.sealProgress,
  });

  final OrbitSceneModel scene;
  final double phase;
  final MotionPolicy policy;
  final ObservatoryTokens tokens;
  final VoidCallback? onAddMemory;
  final ValueChanged<String> onOpenMemory;
  final String? sealedMemoryId;
  final double sealProgress;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final layout = OrbitLayout.positions(
        size: size,
        memoryCount: scene.memories.length,
        phase: phase,
        drift: policy.idleDrift,
      );
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _OrbitPainter(
                ringColor: Theme.of(context).colorScheme.outlineVariant,
                memberColor: tokens.memberColor(scene.member.colorToken),
              ),
            ),
          ),
          for (var index = 0; index < scene.memories.length; index += 1)
            if (scene.memories[index].id != sealedMemoryId || sealProgress >= 1)
              _memoryMark(
                context,
                scene.memories[index],
                layout.memoryCenters[index],
              ),
          _memberNode(context, layout.memberCenter),
          ..._sealSequence(layout),
        ],
      );
    },
  );

  Widget _memberNode(BuildContext context, Offset center) => Positioned(
    left: center.dx - 88,
    top: center.dy - 28,
    width: 176,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          key: const ValueKey('orbit-member-node'),
          container: true,
          explicitChildNodes: true,
          label: 'Current member ${scene.member.name}',
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: tokens.memberColor(scene.member.colorToken),
              shape: BoxShape.circle,
              border: Border.all(color: tokens.brass, width: 2),
              boxShadow: [
                BoxShadow(
                  color: tokens
                      .memberColor(scene.member.colorToken)
                      .withValues(alpha: .3),
                  blurRadius: 16,
                ),
              ],
            ),
            child: const Icon(
              Icons.person_rounded,
              semanticLabel: 'Family member',
            ),
          ),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
          onPressed: onAddMemory,
          icon: Icon(Icons.add_rounded, color: tokens.brass),
          label: const Text('Add a memory'),
        ),
      ],
    ),
  );

  Widget _memoryMark(
    BuildContext context,
    OrbitMemoryMark memory,
    Offset center,
  ) => Positioned(
    key: ValueKey('orbit-memory-${memory.id}'),
    left: center.dx - 22,
    top: center.dy - 22,
    width: 44,
    height: 44,
    child: Semantics(
      label: '${memory.format.vaultLabel}, ${memory.privacy.vaultLabel}',
      button: true,
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed: () => onOpenMemory(memory.id),
        icon: _memoryObject(memory),
      ),
    ),
  );

  Widget _memoryObject(OrbitMemoryMark memory) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: tokens.memorySurface,
      shape: BoxShape.circle,
      border: Border.all(
        color: tokens.memberColor(memory.colorToken),
        width: 2,
      ),
    ),
    child: Icon(_formatIcon(memory.format), size: 17),
  );

  List<Widget> _sealSequence(OrbitPositions layout) {
    final index = scene.memories.indexWhere(
      (memory) => memory.id == sealedMemoryId,
    );
    if (index < 0) return const [];
    final memory = scene.memories[index];
    final target = layout.memoryCenters[index];
    final progress = sealProgress.clamp(0, 1).toDouble();
    const travelEnd = .7;
    final travelProgress = Curves.easeOutCubic.transform(
      (progress / travelEnd).clamp(0, 1).toDouble(),
    );
    final position = policy.useSealTravel
        ? Offset.lerp(layout.memberCenter, target, travelProgress)!
        : target;
    final actorProgress = policy.useSealTravel ? travelProgress : progress;
    final actor = progress < 1
        ? Positioned(
            key: ValueKey('seal-actor-${memory.id}'),
            left: position.dx - 22,
            top: position.dy - 22,
            width: 44,
            height: 44,
            child: Center(
              child: Opacity(
                opacity: policy.useSealTravel ? 1 : actorProgress,
                child: Transform.scale(
                  scale: 1 - .18 * actorProgress,
                  child: _memoryObject(memory),
                ),
              ),
            ),
          )
        : null;
    final badgeProgress = ((progress - travelEnd) / (1 - travelEnd))
        .clamp(0, 1)
        .toDouble();
    final badge = badgeProgress > 0
        ? Positioned(
            key: ValueKey('seal-badge-${memory.id}'),
            left: target.dx - 16,
            top: target.dy - 16,
            width: 32,
            height: 32,
            child: Semantics(
              container: true,
              label: 'Memory sealed',
              liveRegion: true,
              child: Opacity(
                opacity: badgeProgress,
                child: Transform.scale(
                  scale: .82 + .18 * badgeProgress,
                  child: Icon(
                    Icons.verified_rounded,
                    color: tokens.brass,
                    size: 32,
                  ),
                ),
              ),
            ),
          )
        : null;
    return [?actor, ?badge];
  }
}

IconData _formatIcon(MemoryFormat format) => switch (format) {
  MemoryFormat.photo => Icons.photo_rounded,
  MemoryFormat.voice => Icons.graphic_eq_rounded,
  MemoryFormat.text => Icons.notes_rounded,
};

final class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({required this.ringColor, required this.memberColor});

  final Color ringColor;
  final Color memberColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .34;
    final ring = Paint()
      ..color = ringColor.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius, ring);
    canvas.drawCircle(
      center,
      radius * .72,
      ring..color = memberColor.withValues(alpha: .15),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.ringColor != ringColor ||
      oldDelegate.memberColor != memberColor;
}
