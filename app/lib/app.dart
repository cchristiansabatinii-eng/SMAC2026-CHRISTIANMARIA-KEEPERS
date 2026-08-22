import 'dart:async';

import 'package:flutter/material.dart';
import 'package:keepers/design_system/observatory/observatory_theme.dart';
import 'package:keepers/features/family/data/invite_link_coordinator.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/presentation/family_join_screen.dart';
import 'package:keepers/features/launch/presentation/keepers_launch_sequence.dart';
import 'package:keepers/features/onboarding/presentation/startup_gate.dart';
import 'package:keepers/ui/keepers_app_background.dart';

class KeepersApp extends StatefulWidget {
  const KeepersApp({
    super.key,
    this.inviteUriSource,
    this.inviteLinkCoordinator,
    this.playLaunchSequence = false,
    this.onLaunchReady,
  });

  static const joinRouteName = '/family/join';

  final InviteUriSource? inviteUriSource;
  final InviteLinkCoordinator? inviteLinkCoordinator;
  final bool playLaunchSequence;
  final VoidCallback? onLaunchReady;

  @override
  State<KeepersApp> createState() => _KeepersAppState();
}

class _KeepersAppState extends State<KeepersApp> {
  static const _maxQueuedWarmEvents = 8;
  late final InviteLinkCoordinator _coordinator;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _warmEvents = <InviteLinkEvent>[];
  StreamSubscription<InviteLinkEvent>? _subscription;
  InviteLinkEvent? _initialEvent;
  FamilyCode? _activeJoinCode;
  var _initialResolved = false;
  var _presentingWarmJoin = false;
  var _coldJoinActive = false;
  var _malformedJoinActive = false;
  var _warmFlushScheduled = false;
  var _hasRetriedWarmFlush = false;
  late var _launchSequenceVisible = widget.playLaunchSequence;

  @override
  void initState() {
    super.initState();
    _coordinator =
        widget.inviteLinkCoordinator ??
        InviteLinkCoordinator(
          widget.inviteUriSource ?? const _NoInviteUriSource(),
        );
    _subscription = _coordinator.events.listen(_queueWarm);
    _resolveInitial();
  }

  Future<void> _resolveInitial() async {
    final event = await _coordinator.takeInitialLink();
    if (!mounted) return;
    setState(() {
      _initialEvent = event;
      _initialResolved = true;
      _coldJoinActive = event != null;
      _setActiveJoin(event);
      _removeQueuedDuplicateOf(event);
    });
    _flushWarm();
  }

  void _queueWarm(InviteLinkEvent event) {
    if (_isActiveOrQueued(event)) return;
    if (_warmEvents.length >= _maxQueuedWarmEvents) _warmEvents.removeAt(0);
    _warmEvents.add(event);
    _flushWarm();
  }

  void _flushWarm() {
    if (!_initialResolved || _coldJoinActive) {
      return;
    }
    if (_navigatorKey.currentState == null) {
      _scheduleWarmFlush();
      return;
    }
    if (_presentingWarmJoin || _warmEvents.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _presentingWarmJoin || _warmEvents.isEmpty) {
        return;
      }
      _presentingWarmJoin = true;
      final event = _warmEvents.removeAt(0);
      _setActiveJoin(event);
      _navigatorKey.currentState!.push<void>(_joinRoute(event)).whenComplete(
        () {
          if (!mounted) return;
          _clearActiveJoin(event);
          _presentingWarmJoin = false;
          _flushWarm();
        },
      );
    });
    // Warm links often arrive while the app is idle. Registering a post-frame
    // callback alone does not request a frame, so make the queued route
    // observable without waiting for an unrelated repaint or user gesture.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _scheduleWarmFlush() {
    if (_warmFlushScheduled) return;
    _warmFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmFlushScheduled = false;
      if (!mounted) return;
      if (_navigatorKey.currentState != null) {
        _flushWarm();
      } else if (!_hasRetriedWarmFlush) {
        _hasRetriedWarmFlush = true;
        _scheduleWarmFlush();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Route<void> _joinRoute(InviteLinkEvent event) => MaterialPageRoute<void>(
    settings: const RouteSettings(name: KeepersApp.joinRouteName),
    builder: (_) => switch (event) {
      ValidFamilyJoinLinkEvent(:final link) => FamilyJoinScreen.forCode(
        link.code,
      ),
      MalformedFamilyJoinLinkEvent() => const FamilyJoinScreen.malformed(),
    },
  );

  bool _isActiveOrQueued(InviteLinkEvent event) => switch (event) {
    ValidFamilyJoinLinkEvent(:final link) =>
      _activeJoinCode == link.code ||
          _warmEvents.any(
            (queued) =>
                queued is ValidFamilyJoinLinkEvent &&
                queued.link.code == link.code,
          ),
    MalformedFamilyJoinLinkEvent() =>
      _malformedJoinActive ||
          _warmEvents.any((queued) => queued is MalformedFamilyJoinLinkEvent),
  };

  void _setActiveJoin(InviteLinkEvent? event) {
    switch (event) {
      case ValidFamilyJoinLinkEvent(:final link):
        _activeJoinCode = link.code;
        _malformedJoinActive = false;
      case MalformedFamilyJoinLinkEvent():
        _activeJoinCode = null;
        _malformedJoinActive = true;
      case null:
        _activeJoinCode = null;
        _malformedJoinActive = false;
    }
  }

  void _clearActiveJoin(InviteLinkEvent? event) {
    switch (event) {
      case ValidFamilyJoinLinkEvent(:final link)
          when _activeJoinCode == link.code:
        _activeJoinCode = null;
      case MalformedFamilyJoinLinkEvent() when _malformedJoinActive:
        _malformedJoinActive = false;
      case ValidFamilyJoinLinkEvent() || MalformedFamilyJoinLinkEvent() || null:
        break;
    }
  }

  void _removeQueuedDuplicateOf(InviteLinkEvent? event) {
    switch (event) {
      case ValidFamilyJoinLinkEvent(:final link):
        _warmEvents.removeWhere(
          (queued) =>
              queued is ValidFamilyJoinLinkEvent &&
              queued.link.code == link.code,
        );
      case MalformedFamilyJoinLinkEvent():
        _warmEvents.removeWhere(
          (queued) => queued is MalformedFamilyJoinLinkEvent,
        );
      case null:
        break;
    }
  }

  void _releaseColdJoin() {
    if (!mounted || !_coldJoinActive) return;
    setState(() {
      _clearActiveJoin(_initialEvent);
      _initialEvent = null;
      _coldJoinActive = false;
    });
    _coordinator.releaseColdDeliveryGuard();
    _flushWarm();
  }

  void _abandonColdJoin() {
    if (!mounted) return;
    setState(() {
      _clearActiveJoin(_initialEvent);
      _initialEvent = null;
      _coldJoinActive = false;
    });
    _coordinator.releaseColdDeliveryGuard();
    _navigatorKey.currentState?.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/'),
        builder: (_) => const StartupGate(),
      ),
      (_) => false,
    );
    _flushWarm();
  }

  void _completeLaunchSequence() {
    if (!mounted || !_launchSequenceVisible) return;
    setState(() => _launchSequenceVisible = false);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_coordinator.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Keepers',
      navigatorKey: _navigatorKey,
      theme: KeepersTheme.daylight(),
      darkTheme: KeepersTheme.daylight(),
      builder: (context, child) {
        if (_initialResolved && !_coldJoinActive && _warmEvents.isNotEmpty) {
          _scheduleWarmFlush();
        }
        return KeepersAppBackground(
          key: const ValueKey('keepers-global-background'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child ?? const SizedBox.shrink(),
              if (_launchSequenceVisible)
                BlockSemantics(
                  child: KeepersLaunchSequence(
                    onCompleted: _completeLaunchSequence,
                    onReady: widget.onLaunchReady,
                  ),
                ),
            ],
          ),
        );
      },
      home: !_initialResolved
          ? const Scaffold(
              backgroundColor: Colors.transparent,
              body: Center(child: CircularProgressIndicator()),
            )
          : switch (_initialEvent) {
              ValidFamilyJoinLinkEvent(:final link) => FamilyJoinScreen.forCode(
                link.code,
                onCompleted: _releaseColdJoin,
                onAbandoned: _abandonColdJoin,
              ),
              MalformedFamilyJoinLinkEvent() => FamilyJoinScreen.malformed(
                onAbandoned: _abandonColdJoin,
              ),
              null => const StartupGate(),
            },
    );
  }
}

final class _NoInviteUriSource implements InviteUriSource {
  const _NoInviteUriSource();
  @override
  Stream<Uri> get uriLinkStream => const Stream<Uri>.empty();
  @override
  Future<Uri?> getInitialUri() async => null;
}
