import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:cryptography/dart.dart';
import 'package:keepers/features/family/domain/family_code.dart';

/// The small boundary around app_links keeps platform delivery testable.
abstract interface class InviteUriSource {
  Stream<Uri> get uriLinkStream;

  Future<Uri?> getInitialUri();
}

final class AppLinksInviteUriSource implements InviteUriSource {
  AppLinksInviteUriSource(AppLinks appLinks) : _appLinks = appLinks;

  final AppLinks _appLinks;

  @override
  Stream<Uri> get uriLinkStream => _appLinks.uriLinkStream;

  @override
  Future<Uri?> getInitialUri() => _appLinks.getInitialLink();
}

sealed class InviteLinkEvent {
  const InviteLinkEvent();
}

/// A parsed link is deliberately never converted back into a URI for UI use.
final class ValidFamilyJoinLinkEvent extends InviteLinkEvent {
  const ValidFamilyJoinLinkEvent(this.link);

  final FamilyJoinLink link;

  @override
  String toString() => 'ValidFamilyJoinLinkEvent(<redacted>)';
}

final class MalformedFamilyJoinLinkEvent extends InviteLinkEvent {
  const MalformedFamilyJoinLinkEvent();

  @override
  String toString() => 'MalformedFamilyJoinLinkEvent()';
}

/// Resolves cold links without missing the stream-first delivery used by
/// app_links 7.2, then emits later warm links after root navigation is ready.
final class InviteLinkCoordinator {
  InviteLinkCoordinator(this._source);

  static const _maxBufferedEvents = 8;

  final InviteUriSource _source;
  late final _events = StreamController<InviteLinkEvent>.broadcast(
    onListen: _flushUndelivered,
  );
  final _pending = <_BufferedInviteEvent>[];
  final _undelivered = <InviteLinkEvent>[];
  StreamSubscription<Uri>? _subscription;
  Future<InviteLinkEvent?>? _initial;
  var _initialTaken = false;
  var _initialResolved = false;
  List<int>? _coldDeliveryDigest;
  var _disposed = false;

  Stream<InviteLinkEvent> get events => _events.stream;

  Future<InviteLinkEvent?> resolveInitialLink() {
    if (_initialTaken) return Future<InviteLinkEvent?>.value();
    return _initial ??= _resolveInitialLink();
  }

  /// Delivers the cold result once, then drops the future retaining its parsed
  /// link. Startup calls this after main has begun resolution before cloud
  /// initialization.
  Future<InviteLinkEvent?> takeInitialLink() async {
    if (_initialTaken) return null;
    final resolution = _initial ??= _resolveInitialLink();
    _initialTaken = true;
    final result = await resolution;
    _initial = null;
    return result;
  }

  Future<InviteLinkEvent?> _resolveInitialLink() async {
    _subscription = _source.uriLinkStream.listen(_onUri, onError: (_, _) {});
    Uri? initialUri;
    try {
      initialUri = await _source.getInitialUri();
    } on Object {
      // A platform read failure is not a Join target and must not block startup.
    }
    if (_disposed) return null;
    final initialEvent = _parseUri(initialUri);
    InviteLinkEvent? first;
    if (initialEvent != null && initialUri != null) {
      final initialDigest = _digest(initialUri);
      final matching = _pending.indexWhere(
        (entry) => _sameDigest(entry.uriDigest, initialDigest),
      );
      if (matching >= 0) {
        first = _pending.removeAt(matching).event;
        _pending.removeWhere(
          (entry) => _sameDigest(entry.uriDigest, initialDigest),
        );
      } else {
        first = initialEvent;
        _coldDeliveryDigest = initialDigest;
      }
    } else if (_pending.isNotEmpty) {
      first = _pending.removeAt(0).event;
    }
    _initialResolved = true;
    for (final entry in List<_BufferedInviteEvent>.of(_pending)) {
      _deliver(entry.event);
    }
    _pending.clear();
    return first;
  }

  void _onUri(Uri uri) {
    if (_disposed) return;
    final event = _parseUri(uri);
    if (event == null) return;
    final digest = _digest(uri);
    if (_initialResolved) {
      final coldDigest = _coldDeliveryDigest;
      if (coldDigest != null) {
        _coldDeliveryDigest = null;
        if (_sameDigest(coldDigest, digest)) return;
      }
      _deliver(event);
    } else {
      if (_pending.any((entry) => _sameDigest(entry.uriDigest, digest))) {
        return;
      }
      if (_pending.length >= _maxBufferedEvents) _pending.removeAt(0);
      _pending.add(_BufferedInviteEvent(event, digest));
    }
  }

  InviteLinkEvent? _parseUri(Uri? uri) {
    if (uri == null || !_isFamilyJoinNamespace(uri)) {
      return null;
    }
    try {
      final link = FamilyJoinLink.parse(uri);
      return ValidFamilyJoinLinkEvent(link);
    } on FormatException {
      return const MalformedFamilyJoinLinkEvent();
    }
  }

  /// Drops the one-shot cold OS delivery guard when its route is no longer
  /// active. This prevents the digest from suppressing a later deliberate
  /// reopen on platforms that delivered the cold URI through only one channel.
  void releaseColdDeliveryGuard() {
    _coldDeliveryDigest = null;
  }

  void _deliver(InviteLinkEvent event) {
    if (_events.hasListener) {
      _events.add(event);
    } else {
      _appendBounded(_undelivered, event);
    }
  }

  void _appendBounded(List<InviteLinkEvent> target, InviteLinkEvent event) {
    if (target.length >= _maxBufferedEvents) target.removeAt(0);
    target.add(event);
  }

  void _flushUndelivered() {
    for (final event in List<InviteLinkEvent>.of(_undelivered)) {
      _events.add(event);
    }
    _undelivered.clear();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    _pending.clear();
    _undelivered.clear();
    _coldDeliveryDigest = null;
    await _events.close();
  }

  static List<int> _digest(Uri uri) =>
      const DartSha256().hashSync(utf8.encode(uri.toString())).bytes;

  static bool _sameDigest(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    var difference = 0;
    for (var index = 0; index < first.length; index += 1) {
      difference |= first[index] ^ second[index];
    }
    return difference == 0;
  }
}

bool _isFamilyJoinNamespace(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host == 'join.keepers.app' &&
    uri.pathSegments.isNotEmpty &&
    uri.pathSegments.first == 'f';

final class _BufferedInviteEvent {
  const _BufferedInviteEvent(this.event, this.uriDigest);

  final InviteLinkEvent event;
  final List<int> uriDigest;
}
