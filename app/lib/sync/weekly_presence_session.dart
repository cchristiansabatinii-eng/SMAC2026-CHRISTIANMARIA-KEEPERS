import 'dart:async';
import 'dart:typed_data';

import 'package:keepers/sync/weekly_presence_token_codec.dart';

const weeklyPresenceFreshness = Duration(seconds: 15);
const weeklyPresenceTickerInterval = Duration(seconds: 1);

enum WeeklyPresenceRadioStatus {
  ready,
  bluetoothOff,
  permissionDenied,
  unsupported,
  failed,
}

final class WeeklyPresenceAdvertisement {
  WeeklyPresenceAdvertisement({required Iterable<String> serviceUuids})
    : serviceUuids = Set.unmodifiable({
        for (final uuid in serviceUuids)
          if (uuid.trim().isNotEmpty) uuid.trim().toLowerCase(),
      });

  final Set<String> serviceUuids;
}

abstract interface class WeeklyPresenceRadio {
  Future<WeeklyPresenceRadioHandle> open({required String serviceUuid});
}

abstract interface class WeeklyPresenceRadioHandle {
  WeeklyPresenceRadioStatus get initialStatus;

  Stream<WeeklyPresenceAdvertisement> get advertisements;

  Stream<WeeklyPresenceRadioStatus> get statuses;

  Future<WeeklyPresenceRadioStatus> updateAdvertisement({
    required String serviceUuid,
  });

  Future<void> stop();
}

abstract interface class WeeklyPresenceTicker {
  bool get isActive;

  void cancel();
}

typedef WeeklyPresenceTickerFactory = WeeklyPresenceTicker Function(
  Duration interval,
  void Function() callback,
);
typedef WeeklyPresenceFamilyKeyResolver = Future<List<int>> Function(
  String familyKeyRef,
);

final class WeeklyPresenceSessionRequest {
  const WeeklyPresenceSessionRequest({
    required this.familyId,
    required this.memberId,
    required this.familyKeyRef,
    required this.rosterMemberIds,
  });

  final String familyId;
  final String memberId;
  final String familyKeyRef;
  final Set<String> rosterMemberIds;
}

final class WeeklyPresenceReading {
  const WeeklyPresenceReading.unavailable()
    : isAvailable = false,
      memberLastSeenAt = const {};

  WeeklyPresenceReading.available(Map<String, DateTime> memberLastSeenAt)
    : isAvailable = true,
      memberLastSeenAt = Map.unmodifiable({
        for (final entry in memberLastSeenAt.entries)
          entry.key: entry.value.toUtc(),
      });

  final bool isAvailable;
  final Map<String, DateTime> memberLastSeenAt;
}

/// Owns one foreground-only BLE presence session.
///
/// Each [start] replaces the prior session. Every callback is tied to the
/// generation and handle that created it, so a late scan, status, or radio
/// completion can never revive attendance from an earlier identity.
final class WeeklyPresenceSession {
  factory WeeklyPresenceSession({
    required WeeklyPresenceRadio radio,
    required WeeklyPresenceTokenEncoder tokenEncoder,
    required WeeklyPresenceFamilyKeyResolver resolveFamilyKey,
    DateTime Function()? now,
    WeeklyPresenceTickerFactory? tickerFactory,
  }) => WeeklyPresenceSession._(
    radio,
    tokenEncoder,
    resolveFamilyKey,
    now ?? DateTime.now,
    tickerFactory ?? _timerTicker,
  );

  WeeklyPresenceSession._(
    this._radio,
    this._tokenEncoder,
    this._resolveFamilyKey,
    this._now,
    this._tickerFactory,
  );

  final WeeklyPresenceRadio _radio;
  final WeeklyPresenceTokenEncoder _tokenEncoder;
  final WeeklyPresenceFamilyKeyResolver _resolveFamilyKey;
  final DateTime Function() _now;
  final WeeklyPresenceTickerFactory _tickerFactory;

  final StreamController<WeeklyPresenceReading> _readings =
      StreamController<WeeklyPresenceReading>.broadcast(sync: true);
  WeeklyPresenceReading _currentReading =
      const WeeklyPresenceReading.unavailable();
  Future<void> _operationTail = Future<void>.value();
  _ActiveWeeklyPresence? _active;
  var _generation = 0;
  var _disposed = false;
  Future<void>? _disposeFuture;

  WeeklyPresenceReading get currentReading => _currentReading;

  Stream<WeeklyPresenceReading> get readings => _readings.stream;

  Future<void> start(WeeklyPresenceSessionRequest request) {
    if (_disposed) {
      return Future<void>.error(
        StateError('WeeklyPresenceSession has been disposed'),
      );
    }
    final generation = ++_generation;
    _publishUnavailable();
    _requestActiveRadioStop();
    return _enqueue(() => _replace(request, generation));
  }

  Future<void> updateRoster(Set<String> memberIds) {
    if (_disposed) return Future<void>.value();
    final normalized = _normalizedIds(memberIds);
    return _enqueue(() async {
      final active = _active;
      if (active == null || !_isCurrent(active)) return;

      if (!normalized.contains(active.memberId)) {
        _generation += 1;
        _publishUnavailable();
        await _tearDownActive();
        return;
      }

      active.rosterMemberIds = normalized;
      active.memberLastSeenAt.removeWhere(
        (memberId, _) =>
            memberId == active.memberId || !normalized.contains(memberId),
      );
      _refreshExpectedMembers(active, _utcNow(), force: true);
      _publishActive(active);
    });
  }

  Future<void> stop() {
    if (_disposed) return _disposeFuture ?? Future<void>.value();
    _generation += 1;
    _publishUnavailable();
    _requestActiveRadioStop();
    return _enqueue(_tearDownActive);
  }

  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;

    _generation += 1;
    _publishUnavailable();
    _disposed = true;
    _requestActiveRadioStop();
    late final Future<void> disposing;
    disposing = _enqueue(() async {
      await _tearDownActive();
      await _readings.close();
    });
    _disposeFuture = disposing;
    return disposing;
  }

  Future<void> _replace(
    WeeklyPresenceSessionRequest rawRequest,
    int generation,
  ) async {
    await _tearDownActive();
    if (!_accepts(generation)) return;

    final request = _normalizedRequest(rawRequest);
    if (request == null ||
        !request.rosterMemberIds.contains(request.memberId)) {
      _publishUnavailable();
      return;
    }

    Uint8List? familyKey;
    WeeklyPresenceRadioHandle? unopenedHandle;
    try {
      final resolved = await _resolveFamilyKey(request.familyKeyRef);
      familyKey = Uint8List.fromList(resolved);
      if (!_accepts(generation)) {
        _zero(familyKey);
        return;
      }

      final now = _utcNow();
      final slot = _tokenEncoder.slotFor(now);
      final ownUuid = _tokenEncoder.serviceUuid(
        familyKey: familyKey,
        familyId: request.familyId,
        memberId: request.memberId,
        slot: slot,
      );
      final expected = _expectedMembers(
        familyKey: familyKey,
        familyId: request.familyId,
        memberId: request.memberId,
        rosterMemberIds: request.rosterMemberIds,
        at: now,
      );

      unopenedHandle = await _radio.open(serviceUuid: ownUuid);
      if (!_accepts(generation)) {
        await _stopHandle(unopenedHandle);
        _zero(familyKey);
        return;
      }

      final active = _ActiveWeeklyPresence(
        generation: generation,
        familyId: request.familyId,
        memberId: request.memberId,
        familyKey: familyKey,
        rosterMemberIds: request.rosterMemberIds,
        handle: unopenedHandle,
        advertisedSlot: slot,
        expectedSlot: slot,
        expectedMembersByUuid: expected,
      );
      unopenedHandle = null;
      familyKey = null;
      _active = active;
      active.advertisementSubscription = active.handle.advertisements.listen(
        (advertisement) => _onAdvertisement(active, advertisement),
      );
      active.statusSubscription = active.handle.statuses.listen(
        (status) => _onRadioStatus(active, status),
      );
      active.ticker = _tickerFactory(
        weeklyPresenceTickerInterval,
        () => _onTick(active),
      );
      _applyRadioStatus(active, active.handle.initialStatus);
    } on Object {
      if (unopenedHandle != null) await _stopHandle(unopenedHandle);
      if (familyKey != null) _zero(familyKey);
      final active = _active;
      if (active != null && active.generation == generation) {
        await _tearDownActive();
      }
      if (_accepts(generation)) _publishUnavailable();
    }
  }

  void _onAdvertisement(
    _ActiveWeeklyPresence active,
    WeeklyPresenceAdvertisement advertisement,
  ) {
    if (!_isCurrent(active) || !active.radioReady) return;
    try {
      final now = _utcNow();
      var shouldPublish = _pruneExpired(active, now);
      _refreshExpectedMembers(active, now);
      for (final serviceUuid in advertisement.serviceUuids) {
        final memberId =
            active.expectedMembersByUuid[serviceUuid.trim().toLowerCase()];
        if (memberId == null ||
            memberId == active.memberId ||
            !active.rosterMemberIds.contains(memberId)) {
          continue;
        }
        final publishedAt = _currentReading.memberLastSeenAt[memberId];
        if (publishedAt == null) {
          shouldPublish = true;
        } else {
          final sincePublication = now.difference(publishedAt);
          if (sincePublication.isNegative ||
              sincePublication >= weeklyPresenceTickerInterval) {
            shouldPublish = true;
          }
        }
        // Every authentic sighting refreshes expiry even when the public
        // snapshot is throttled to keep scan bursts from rebuilding the UI.
        active.memberLastSeenAt[memberId] = now;
      }
      if (shouldPublish) _publishActive(active);
    } on Object {
      _failClosed(active);
    }
  }

  void _onRadioStatus(
    _ActiveWeeklyPresence active,
    WeeklyPresenceRadioStatus status,
  ) {
    if (!_isCurrent(active)) return;
    _applyRadioStatus(active, status);
  }

  void _applyRadioStatus(
    _ActiveWeeklyPresence active,
    WeeklyPresenceRadioStatus status,
  ) {
    if (!_isCurrent(active)) return;
    if (status != WeeklyPresenceRadioStatus.ready) {
      _failClosed(active);
      return;
    }

    active.radioReady = true;
    try {
      final now = _utcNow();
      _pruneExpired(active, now);
      _refreshExpectedMembers(active, now);
      _publishActive(active);
      _queueMaintenance(active);
    } on Object {
      _failClosed(active);
    }
  }

  void _onTick(_ActiveWeeklyPresence active) {
    if (!_isCurrent(active) || !active.radioReady) return;
    try {
      final now = _utcNow();
      _pruneExpired(active, now);
      _refreshExpectedMembers(active, now);
      _publishActive(active);
      _queueMaintenance(active);
    } on Object {
      _failClosed(active);
    }
  }

  void _queueMaintenance(_ActiveWeeklyPresence active) {
    unawaited(
      _enqueue(() async {
        if (!_isCurrent(active) || !active.radioReady) return;
        try {
          final now = _utcNow();
          final slot = _tokenEncoder.slotFor(now);
          _refreshExpectedMembers(active, now);
          if (slot == active.advertisedSlot) return;

          final uuid = _tokenEncoder.serviceUuid(
            familyKey: active.familyKey,
            familyId: active.familyId,
            memberId: active.memberId,
            slot: slot,
          );
          final status = await active.handle.updateAdvertisement(
            serviceUuid: uuid,
          );
          if (!_isCurrent(active)) return;
          if (status == WeeklyPresenceRadioStatus.ready) {
            active.advertisedSlot = slot;
          } else {
            _failClosed(active);
          }
        } on Object {
          if (_isCurrent(active)) _failClosed(active);
        }
      }),
    );
  }

  bool _refreshExpectedMembers(
    _ActiveWeeklyPresence active,
    DateTime now, {
    bool force = false,
  }) {
    final slot = _tokenEncoder.slotFor(now);
    if (!force && slot == active.expectedSlot) return false;
    active.expectedMembersByUuid = _expectedMembers(
      familyKey: active.familyKey,
      familyId: active.familyId,
      memberId: active.memberId,
      rosterMemberIds: active.rosterMemberIds,
      at: now,
    );
    active.expectedSlot = slot;
    return true;
  }

  Map<String, String> _expectedMembers({
    required List<int> familyKey,
    required String familyId,
    required String memberId,
    required Set<String> rosterMemberIds,
    required DateTime at,
  }) {
    final expected = _tokenEncoder.expectedMembersByServiceUuid(
      familyKey: familyKey,
      familyId: familyId,
      memberIds: rosterMemberIds.where((id) => id != memberId),
      at: at,
      skewSlots: 1,
    );
    return Map.unmodifiable({
      for (final entry in expected.entries)
        if (entry.key.trim().isNotEmpty &&
            entry.value != memberId &&
            rosterMemberIds.contains(entry.value))
          entry.key.trim().toLowerCase(): entry.value,
    });
  }

  bool _pruneExpired(_ActiveWeeklyPresence active, DateTime now) {
    final previousLength = active.memberLastSeenAt.length;
    active.memberLastSeenAt.removeWhere((memberId, lastSeenAt) {
      if (!active.rosterMemberIds.contains(memberId) ||
          memberId == active.memberId) {
        return true;
      }
      final age = now.difference(lastSeenAt);
      return age.isNegative || age > weeklyPresenceFreshness;
    });
    return active.memberLastSeenAt.length != previousLength;
  }

  void _failClosed(_ActiveWeeklyPresence active) {
    if (!_isCurrent(active)) return;
    active.radioReady = false;
    active.memberLastSeenAt.clear();
    _publishUnavailable();
  }

  void _publishActive(_ActiveWeeklyPresence active) {
    if (!_isCurrent(active) || !active.radioReady) {
      _publishUnavailable();
      return;
    }
    _publish(WeeklyPresenceReading.available(active.memberLastSeenAt));
  }

  void _publishUnavailable() {
    _publish(const WeeklyPresenceReading.unavailable());
  }

  void _publish(WeeklyPresenceReading reading) {
    if (_sameReading(_currentReading, reading)) return;
    _currentReading = reading;
    if (!_readings.isClosed) _readings.add(reading);
  }

  Future<void> _tearDownActive() async {
    final active = _active;
    if (active == null) return;
    final radioStop = active.radioStopFuture ??= _stopHandle(active.handle);
    _active = null;
    active.ticker?.cancel();
    await _cancel(active.advertisementSubscription);
    await _cancel(active.statusSubscription);
    try {
      await radioStop;
    } finally {
      _zero(active.familyKey);
      active.memberLastSeenAt.clear();
      active.expectedMembersByUuid = const {};
    }
  }

  void _requestActiveRadioStop() {
    final active = _active;
    if (active == null) return;
    active.radioStopFuture ??= _stopHandle(active.handle);
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final running = _operationTail.then<void>((_) => operation());
    _operationTail = running.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return running;
  }

  bool _accepts(int generation) => !_disposed && generation == _generation;

  bool _isCurrent(_ActiveWeeklyPresence active) =>
      !_disposed &&
      identical(_active, active) &&
      active.generation == _generation;

  DateTime _utcNow() => _now().toUtc();

  static WeeklyPresenceSessionRequest? _normalizedRequest(
    WeeklyPresenceSessionRequest request,
  ) {
    final familyId = request.familyId.trim();
    final memberId = request.memberId.trim();
    final familyKeyRef = request.familyKeyRef.trim();
    if (familyId.isEmpty || memberId.isEmpty || familyKeyRef.isEmpty) {
      return null;
    }
    return WeeklyPresenceSessionRequest(
      familyId: familyId,
      memberId: memberId,
      familyKeyRef: familyKeyRef,
      rosterMemberIds: _normalizedIds(request.rosterMemberIds),
    );
  }

  static Set<String> _normalizedIds(Iterable<String> ids) => Set.unmodifiable({
    for (final id in ids)
      if (id.trim().isNotEmpty) id.trim(),
  });

  static bool _sameReading(
    WeeklyPresenceReading left,
    WeeklyPresenceReading right,
  ) {
    if (left.isAvailable != right.isAvailable ||
        left.memberLastSeenAt.length != right.memberLastSeenAt.length) {
      return false;
    }
    for (final entry in left.memberLastSeenAt.entries) {
      if (right.memberLastSeenAt[entry.key] != entry.value) return false;
    }
    return true;
  }

  static Future<void> _cancel(StreamSubscription<Object?>? subscription) async {
    if (subscription == null) return;
    try {
      await subscription.cancel();
    } on Object {
      // The generation guard already makes a failed cancellation harmless.
    }
  }

  static Future<void> _stopHandle(WeeklyPresenceRadioHandle handle) async {
    try {
      await handle.stop();
    } on Object {
      // Stopping is best-effort; local attendance has already failed closed.
    }
  }

  static void _zero(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

  static WeeklyPresenceTicker _timerTicker(
    Duration interval,
    void Function() callback,
  ) => _TimerWeeklyPresenceTicker(interval, callback);
}

final class _ActiveWeeklyPresence {
  _ActiveWeeklyPresence({
    required this.generation,
    required this.familyId,
    required this.memberId,
    required this.familyKey,
    required this.rosterMemberIds,
    required this.handle,
    required this.advertisedSlot,
    required this.expectedSlot,
    required this.expectedMembersByUuid,
  });

  final int generation;
  final String familyId;
  final String memberId;
  final Uint8List familyKey;
  final WeeklyPresenceRadioHandle handle;
  Set<String> rosterMemberIds;
  int advertisedSlot;
  int expectedSlot;
  Map<String, String> expectedMembersByUuid;
  final Map<String, DateTime> memberLastSeenAt = {};
  var radioReady = false;
  StreamSubscription<WeeklyPresenceAdvertisement>? advertisementSubscription;
  StreamSubscription<WeeklyPresenceRadioStatus>? statusSubscription;
  WeeklyPresenceTicker? ticker;
  Future<void>? radioStopFuture;
}

final class _TimerWeeklyPresenceTicker implements WeeklyPresenceTicker {
  _TimerWeeklyPresenceTicker(Duration interval, void Function() callback)
    : _timer = Timer.periodic(interval, (_) => callback());

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}
