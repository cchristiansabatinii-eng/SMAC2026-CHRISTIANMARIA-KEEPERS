import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keepers/theme/keepers_theme.dart';

const keepersLaunchDuration = Duration(milliseconds: 3900);
const keepersLaunchWordmarkAsset = 'assets/brand/keepers-launch-wordmark.png';

final class KeepersLaunchSequence extends StatefulWidget {
  const KeepersLaunchSequence({
    required this.onCompleted,
    this.onReady,
    super.key,
  });

  final VoidCallback onCompleted;
  final VoidCallback? onReady;

  @override
  State<KeepersLaunchSequence> createState() => _KeepersLaunchSequenceState();
}

final class _KeepersLaunchSequenceState extends State<KeepersLaunchSequence>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _completed = false;
  var _reducedMotionBypassScheduled = false;
  var _precacheScheduled = false;
  var _readyNotified = false;
  var _startScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: keepersLaunchDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _finish();
          });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    final reducedMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false) ||
        View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;
    if (reducedMotion) {
      if (_reducedMotionBypassScheduled) return;
      _reducedMotionBypassScheduled = true;
      _controller.stop();
      _notifyReady();
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
      return;
    }
    _prepareLogo();
  }

  void _prepareLogo() {
    if (_precacheScheduled) return;
    _precacheScheduled = true;
    unawaited(_precacheLogo());
  }

  Future<void> _precacheLogo() async {
    try {
      await precacheImage(
        const AssetImage(keepersLaunchWordmarkAsset),
        context,
      );
    } on Object {
      // The native logo remains visible until this completes in production.
      // If the bundled image ever fails, still release the app rather than
      // trapping the user on the native launch screen.
    }
    if (!mounted || _completed || _reducedMotionBypassScheduled) return;
    _notifyReady();
    _scheduleStart();
  }

  void _notifyReady() {
    if (_readyNotified) return;
    _readyNotified = true;
    widget.onReady?.call();
  }

  void _scheduleStart() {
    if (_startScheduled || _reducedMotionBypassScheduled) return;
    _startScheduled = true;
    // Begin only after the logo has reached the screen. Starting in initState
    // lets a busy cold-start frame consume the logo hold before it is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _completed || _reducedMotionBypassScheduled) return;
      _controller.forward();
    });
  }

  void _finish() {
    if (_completed) return;
    _completed = true;
    _controller.stop();
    widget.onCompleted();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final milliseconds =
          _controller.value * keepersLaunchDuration.inMilliseconds;
      final phase = _LaunchPhase.at(milliseconds);
      final overlayOpacity = 1 - _interval(milliseconds, 3480, 3900);
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: KeepersColors.ground,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: KeepersColors.ground,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarDividerColor: KeepersColors.ground,
        ),
        child: Opacity(
          opacity: overlayOpacity,
          child: Semantics(
            label: 'Skip opening animation',
            button: true,
            onTap: _finish,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _finish,
              child: ColoredBox(
                key: const ValueKey('keepers-launch-sequence'),
                color: KeepersColors.ground,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (milliseconds >= 1180)
                      RepaintBoundary(
                        child: CustomPaint(
                          key: const ValueKey('keepers-launch-memory-field'),
                          painter: _LaunchMemoryPainter(milliseconds),
                        ),
                      ),
                    _LaunchMessage(phase: phase, milliseconds: milliseconds),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

enum _LaunchPhase {
  logo,
  present,
  authentic,
  bold,
  you;

  static _LaunchPhase at(double milliseconds) {
    if (milliseconds < 600) return logo;
    if (milliseconds < 1800) return present;
    if (milliseconds < 2360) return authentic;
    if (milliseconds < 2920) return bold;
    return you;
  }
}

final class _LaunchMessage extends StatelessWidget {
  const _LaunchMessage({required this.phase, required this.milliseconds});

  final _LaunchPhase phase;
  final double milliseconds;

  @override
  Widget build(BuildContext context) {
    if (phase == _LaunchPhase.logo) {
      return Center(
        child: Opacity(
          opacity: 1 - _interval(milliseconds, 420, 600),
          child: Image.asset(
            keepersLaunchWordmarkAsset,
            key: ValueKey('keepers-launch-logo'),
            width: 196,
            height: 78,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      );
    }

    final phrase = switch (phase) {
      _LaunchPhase.present => milliseconds < 820 ? 'Be' : 'Be present.',
      _LaunchPhase.authentic => 'Be authentic.',
      _LaunchPhase.bold => 'Be bold.',
      _LaunchPhase.you => 'Be you.',
      _LaunchPhase.logo => '',
    };
    final (start, end) = switch (phase) {
      _LaunchPhase.present => (600.0, 1800.0),
      _LaunchPhase.authentic => (1800.0, 2360.0),
      _LaunchPhase.bold => (2360.0, 2920.0),
      _LaunchPhase.you => (2920.0, 3900.0),
      _LaunchPhase.logo => (0.0, 600.0),
    };
    final opacity = Curves.easeOutCubic.transform(
      _stageOpacity(milliseconds, start, end),
    );
    final alignment = switch (phase) {
      _LaunchPhase.authentic => const Alignment(0, -.30),
      _LaunchPhase.bold => const Alignment(0, .14),
      _LaunchPhase.you => const Alignment(0, 0),
      _ => const Alignment(0, -.08),
    };
    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: Offset(0, 8 * (1 - opacity)),
        child: Opacity(
          opacity: opacity,
          child: Text(
            phrase,
            key: const ValueKey('keepers-launch-phrase'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: KeepersColors.cream,
              fontFamily: KeepersType.primary,
              fontSize: 28,
              fontWeight: phase == _LaunchPhase.bold
                  ? FontWeight.w700
                  : FontWeight.w600,
              height: 1,
              letterSpacing: .8,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

final class _LaunchMemoryPainter extends CustomPainter {
  const _LaunchMemoryPainter(this.milliseconds);

  final double milliseconds;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .53, size.height * .61);
    final gather = Curves.easeOutCubic.transform(
      _interval(milliseconds, 1240, 1800),
    );
    final authenticFade = _stageOpacity(milliseconds, 1240, 2500);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..color = KeepersColors.cream.withValues(alpha: .34 * authenticFade);

    const targetRings = <(double, double, double)>[
      (-.34, -.20, 13),
      (-.24, .20, 17),
      (.31, -.22, 21),
      (.37, .22, 15),
      (-.06, .33, 11),
      (.12, -.34, 10),
    ];
    for (var index = 0; index < targetRings.length; index += 1) {
      final (dx, dy, radius) = targetRings[index];
      final start = Offset(
        index.isEven ? -size.width * .58 : size.width * .58,
        (index - 2.5) * size.height * .13,
      );
      final target = center + Offset(dx * size.width, dy * size.height);
      canvas.drawCircle(
        Offset.lerp(start, target, gather)!,
        radius * (.7 + .3 * gather),
        ringPaint,
      );
    }

    if (milliseconds < 2520) {
      final orbScale = .76 + .24 * gather;
      canvas.drawCircle(
        center,
        60 * orbScale,
        Paint()
          ..color = KeepersColors.cream.withValues(alpha: .15 * authenticFade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34),
      );
      canvas.drawCircle(
        center,
        20 * orbScale,
        Paint()
          ..color = KeepersColors.auraIvory.withValues(
            alpha: .94 * authenticFade,
          ),
      );
    }

    final wipe = _stageOpacity(milliseconds, 1640, 2040);
    if (wipe > 0) {
      final frameWidth = size.width * (.08 + .70 * wipe);
      final rect = Rect.fromCenter(
        center: Offset(size.width * .5, size.height * .54),
        width: frameWidth,
        height: size.height * .48,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = KeepersColors.cream.withValues(alpha: .76 * wipe),
      );
    }

    final bold = _stageOpacity(milliseconds, 2280, 3000);
    if (bold > 0) {
      final morph = Curves.easeInOutCubic.transform(
        _interval(milliseconds, 2540, 2860),
      );
      final width = 34 + 76 * morph;
      final height = 34 - 20 * morph;
      final rect = Rect.fromCenter(
        center: Offset(size.width * .5, size.height * .43),
        width: width,
        height: height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(height / 2)),
        Paint()..color = KeepersColors.cream.withValues(alpha: .98 * bold),
      );
    }

    final you = _stageOpacity(milliseconds, 2860, 3560);
    if (you > 0) {
      final resolve = Curves.easeOutCubic.transform(
        _interval(milliseconds, 2920, 3340),
      );
      canvas.drawCircle(
        Offset(size.width * .5, size.height * (.42 + .03 * resolve)),
        13 - 8 * resolve,
        Paint()..color = KeepersColors.cream.withValues(alpha: .9 * you),
      );
    }
  }

  @override
  bool shouldRepaint(_LaunchMemoryPainter oldDelegate) =>
      oldDelegate.milliseconds != milliseconds;
}

double _interval(double value, double start, double end) =>
    ((value - start) / (end - start)).clamp(0.0, 1.0);

double _stageOpacity(double value, double start, double end) {
  const fade = 180.0;
  return (_interval(value, start, start + fade) *
          (1 - _interval(value, end - fade, end)))
      .clamp(0.0, 1.0);
}
