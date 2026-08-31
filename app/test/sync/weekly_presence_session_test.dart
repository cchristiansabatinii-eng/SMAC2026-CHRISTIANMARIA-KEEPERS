import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/sync/weekly_presence_session.dart';
import 'package:keepers/sync/weekly_presence_token_codec.dart';

void main() {
  const familyId = 'family-1';
  const currentMemberId = 'member-a';
  final familyKey = List<int>.generate(32, (index) => index + 1);
  final initialNow = DateTime.utc(2026, 9, 8, 12);

  test(
    'starts a private beacon and recognizes only active roster members',
    () async {
      final clock = _FakeClock(initialNow);
      final radio = _FakeRadio();
      final session = _session(
        radio: radio,
        clock: clock,
        familyKey: familyKey,
      );
      final codec = WeeklyPresenceTokenCodec();

      await session.start(
        const WeeklyPresenceSessionRequest(
          familyId: familyId,
          memberId: currentMemberId,
          familyKeyRef: 'family-key',
          rosterMemberIds: {'member-a', 'member-b'},
        ),
      );

      final expectedOwnUuid = codec.serviceUuid(
        familyKey: familyKey,
        familyId: familyId,
        memberId: currentMemberId,
        slot: codec.slotFor(initialNow),
      );
      expect(radio.handles, hasLength(1));
      expect(radio.handles.single.openedWith, expectedOwnUuid);

      final memberBUuid = codec.serviceUuid(
        familyKey: familyKey,
        familyId: familyId,
        memberId: 'member-b',
        slot: codec.slotFor(initialNow),
      );
      final outsiderUuid = codec.serviceUuid(
        familyKey: familyKey,
        familyId: familyId,
        memberId: 'member-outsider',
        slot: codec.slotFor(initialNow),
      );
      radio.handles.single.emitAdvertisement({outsiderUuid, memberBUuid});
      await _flush();

      expect(session.currentReading.memberLastSeenAt.keys, {'member-b'});
      expect(session.currentReading.memberLastSeenAt['member-b'], initialNow);
      await session.dispose();
    },
  );

  test('duplicate sightings refresh only that member and members expire independently', () async {
    final clock = _FakeClock(initialNow);
    final radio = _FakeRadio();
    final tickers = _FakeTickerFactory();
    final codec = WeeklyPresenceTokenCodec();
    final session = _session(
      radio: radio,
      clock: clock,
      familyKey: familyKey,
      tickers: tickers,
    );

    await session.start(
      const WeeklyPresenceSessionRequest(
        familyId: familyId,
        memberId: currentMemberId,
        familyKeyRef: 'family-key',
        rosterMemberIds: {'member-a', 'member-b', 'member-c'},
      ),
    );
    final handle = radio.handles.single;
    final memberBUuid = codec.serviceUuid(
      familyKey: familyKey,
      familyId: familyId,
      memberId: 'member-b',
      slot: codec.slotFor(initialNow),
    );
    final memberCUuid = codec.serviceUuid(
      familyKey: familyKey,
      familyId: familyId,
      memberId: 'member-c',
      slot: codec.slotFor(initialNow),
    );

    handle.emitAdvertisement({memberBUuid});
    await _flush();
    clock.advance(const Duration(seconds: 8));
    handle.emitAdvertisement({memberBUuid, memberCUuid});
    await _flush();
    clock.advance(const Duration(seconds: 8));
    tickers.fireActive();
    await _flush();

    expect(session.currentReading.memberLastSeenAt.keys, {
      'member-b',
      'member-c',
    });
    clock.advance(const Duration(seconds: 8));
    tickers.fireActive();
    await _flush();
    expect(session.currentReading.memberLastSeenAt, isEmpty);
    await session.dispose();
  });

  test(
    'duplicate sightings publish at most once per second and still refresh TTL',
    () async {
      final clock = _FakeClock(initialNow);
      final radio = _FakeRadio();
      final tickers = _FakeTickerFactory();
      final codec = WeeklyPresenceTokenCodec();
      final session = _session(
        radio: radio,
        clock: clock,
        familyKey: familyKey,
        tickers: tickers,
      );
      await session.start(
        const WeeklyPresenceSessionRequest(
          familyId: familyId,
          memberId: currentMemberId,
          familyKeyRef: 'family-key',
          rosterMemberIds: {'member-a', 'member-b'},
        ),
      );
      final memberBUuid = codec.serviceUuid(
        familyKey: familyKey,
        familyId: familyId,
        memberId: 'member-b',
        slot: codec.slotFor(initialNow),
      );
      final readings = <WeeklyPresenceReading>[];
      final subscription = session.readings.listen(readings.add);
      addTearDown(subscription.cancel);

      radio.handles.single.emitAdvertisement({memberBUuid});
      await _flush();
      for (var index = 0; index < 5; index += 1) {
        clock.advance(const Duration(milliseconds: 100));
        radio.handles.single.emitAdvertisement({memberBUuid});
        await _flush();
      }
      expect(readings, hasLength(1));

      clock.advance(const Duration(milliseconds: 500));
      radio.handles.single.emitAdvertisement({memberBUuid});
      await _flush();
      expect(readings, hasLength(2));

      clock.advance(const Duration(seconds: 14));
      tickers.fireActive();
      await _flush();
      expect(session.currentReading.memberLastSeenAt.keys, {'member-b'});

      clock.advance(const Duration(milliseconds: 1001));
      tickers.fireActive();
      await _flush();
      expect(session.currentReading.memberLastSeenAt, isEmpty);
      await session.dispose();
    },
  );

  test('rotates the advertised UUID when the time slot changes', () async {
    final clock = _FakeClock(initialNow);
    final radio = _FakeRadio();
    final tickers = _FakeTickerFactory();
    final codec = WeeklyPresenceTokenCodec();
    final session = _session(
      radio: radio,
      clock: clock,
      familyKey: familyKey,
      tickers: tickers,
    );

    await session.start(
      const WeeklyPresenceSessionRequest(
        familyId: familyId,
        memberId: currentMemberId,
        familyKeyRef: 'family-key',
        rosterMemberIds: {'member-a', 'member-b'},
      ),
    );
    clock.advance(const Duration(seconds: 10));
    tickers.fireActive();
    await _flush();

    final expected = codec.serviceUuid(
      familyKey: familyKey,
      familyId: familyId,
      memberId: currentMemberId,
      slot: codec.slotFor(clock.now()),
    );
    expect(radio.handles.single.updatedUuids, [expected]);
    await session.dispose();
  });

  test(
    'radio loss fails closed and late events after stop are ignored',
    () async {
      final clock = _FakeClock(initialNow);
      final radio = _FakeRadio();
      final codec = WeeklyPresenceTokenCodec();
      final session = _session(
        radio: radio,
        clock: clock,
        familyKey: familyKey,
      );

      await session.start(
        const WeeklyPresenceSessionRequest(
          familyId: familyId,
          memberId: currentMemberId,
          familyKeyRef: 'family-key',
          rosterMemberIds: {'member-a', 'member-b'},
        ),
      );
      final handle = radio.handles.single;
      final memberBUuid = codec.serviceUuid(
        familyKey: familyKey,
        familyId: familyId,
        memberId: 'member-b',
        slot: codec.slotFor(initialNow),
      );
      handle.emitAdvertisement({memberBUuid});
      await _flush();
      expect(session.currentReading.memberLastSeenAt, isNotEmpty);

      handle.emitStatus(WeeklyPresenceRadioStatus.bluetoothOff);
      await _flush();
      expect(session.currentReading.isAvailable, isFalse);
      expect(session.currentReading.memberLastSeenAt, isEmpty);

      handle.emitStatus(WeeklyPresenceRadioStatus.ready);
      handle.emitAdvertisement({memberBUuid});
      await _flush();
      expect(session.currentReading.memberLastSeenAt.keys, {'member-b'});

      await session.stop();
      expect(handle.stopCalls, 1);
      handle.emitAdvertisement({memberBUuid});
      await _flush();
      expect(session.currentReading.isAvailable, isFalse);
      expect(session.currentReading.memberLastSeenAt, isEmpty);
      await session.dispose();
    },
  );

  test('unsupported startup and roster removal fail closed', () async {
    final clock = _FakeClock(initialNow);
    final unsupportedRadio = _FakeRadio(
      initialStatus: WeeklyPresenceRadioStatus.unsupported,
    );
    final unsupported = _session(
      radio: unsupportedRadio,
      clock: clock,
      familyKey: familyKey,
    );
    await unsupported.start(
      const WeeklyPresenceSessionRequest(
        familyId: familyId,
        memberId: currentMemberId,
        familyKeyRef: 'family-key',
        rosterMemberIds: {'member-a', 'member-b'},
      ),
    );
    expect(unsupported.currentReading.isAvailable, isFalse);
    await unsupported.dispose();

    final radio = _FakeRadio();
    final session = _session(radio: radio, clock: clock, familyKey: familyKey);
    final codec = WeeklyPresenceTokenCodec();
    await session.start(
      const WeeklyPresenceSessionRequest(
        familyId: familyId,
        memberId: currentMemberId,
        familyKeyRef: 'family-key',
        rosterMemberIds: {'member-a', 'member-b'},
      ),
    );
    final memberBUuid = codec.serviceUuid(
      familyKey: familyKey,
      familyId: familyId,
      memberId: 'member-b',
      slot: codec.slotFor(initialNow),
    );
    radio.handles.single.emitAdvertisement({memberBUuid});
    await _flush();
    expect(session.currentReading.memberLastSeenAt.keys, {'member-b'});

    await session.updateRoster({'member-a'});
    expect(session.currentReading.memberLastSeenAt, isEmpty);
    radio.handles.single.emitAdvertisement({memberBUuid});
    await _flush();
    expect(session.currentReading.memberLastSeenAt, isEmpty);
    await session.dispose();
  });

  test('recognizes a member added to the roster in the current slot', () async {
    final clock = _FakeClock(initialNow);
    final radio = _FakeRadio();
    final session = _session(radio: radio, clock: clock, familyKey: familyKey);
    final codec = WeeklyPresenceTokenCodec();
    await session.start(
      const WeeklyPresenceSessionRequest(
        familyId: familyId,
        memberId: currentMemberId,
        familyKeyRef: 'family-key',
        rosterMemberIds: {'member-a'},
      ),
    );
    final memberBUuid = codec.serviceUuid(
      familyKey: familyKey,
      familyId: familyId,
      memberId: 'member-b',
      slot: codec.slotFor(initialNow),
    );

    radio.handles.single.emitAdvertisement({memberBUuid});
    await _flush();
    expect(session.currentReading.memberLastSeenAt, isEmpty);

    await session.updateRoster({'member-a', 'member-b'});
    radio.handles.single.emitAdvertisement({memberBUuid});
    await _flush();
    expect(session.currentReading.memberLastSeenAt.keys, {'member-b'});
    await session.dispose();
  });

  test(
    'identity replacement clears old attendance and zeroes owned keys',
    () async {
      final clock = _FakeClock(initialNow);
      final radio = _FakeRadio();
      final encoder = _KeyCapturingEncoder();
      final session = WeeklyPresenceSession(
        radio: radio,
        tokenEncoder: encoder,
        resolveFamilyKey: (_) async => List<int>.from(familyKey),
        now: clock.now,
        tickerFactory: _FakeTickerFactory().call,
      );

      await session.start(
        const WeeklyPresenceSessionRequest(
          familyId: familyId,
          memberId: currentMemberId,
          familyKeyRef: 'family-key',
          rosterMemberIds: {'member-a', 'member-b'},
        ),
      );
      final oldHandle = radio.handles.single;
      oldHandle.emitAdvertisement({'member-b-token'});
      await _flush();
      expect(session.currentReading.memberLastSeenAt.keys, {'member-b'});

      await session.start(
        const WeeklyPresenceSessionRequest(
          familyId: 'family-2',
          memberId: 'member-z',
          familyKeyRef: 'family-key-2',
          rosterMemberIds: {'member-z'},
        ),
      );
      expect(oldHandle.stopCalls, 1);
      expect(session.currentReading.memberLastSeenAt, isEmpty);
      expect(encoder.capturedKeys.first, everyElement(0));

      await session.stop();
      expect(encoder.capturedKeys, everyElement(everyElement(0)));
      await session.dispose();
    },
  );

  final promptStopScenarios =
      <
        ({
          String name,
          Future<void> Function(WeeklyPresenceSession session) act,
        })
      >[
        (name: 'stop', act: (session) => session.stop()),
        (name: 'dispose', act: (session) => session.dispose()),
        (
          name: 'replacement',
          act: (session) => session.start(
            const WeeklyPresenceSessionRequest(
              familyId: 'family-2',
              memberId: 'member-z',
              familyKeyRef: 'family-key-2',
              rosterMemberIds: {'member-z'},
            ),
          ),
        ),
      ];
  for (final scenario in promptStopScenarios) {
    test(
      '${scenario.name} requests radio revocation while rotation is blocked',
      () => _expectPromptRadioStop(
        initialNow: initialNow,
        familyKey: familyKey,
        act: scenario.act,
      ),
    );
  }
}

Future<void> _expectPromptRadioStop({
  required DateTime initialNow,
  required List<int> familyKey,
  required Future<void> Function(WeeklyPresenceSession session) act,
}) async {
  final clock = _FakeClock(initialNow);
  final radio = _FakeRadio();
  final tickers = _FakeTickerFactory();
  final encoder = _KeyCapturingEncoder();
  final session = WeeklyPresenceSession(
    radio: radio,
    tokenEncoder: encoder,
    resolveFamilyKey: (_) async => List<int>.from(familyKey),
    now: clock.now,
    tickerFactory: tickers.call,
  );
  final rotation = Completer<WeeklyPresenceRadioStatus>();

  try {
    await session.start(
      const WeeklyPresenceSessionRequest(
        familyId: 'family-1',
        memberId: 'member-a',
        familyKeyRef: 'family-key',
        rosterMemberIds: {'member-a', 'member-b'},
      ),
    );
    final handle = radio.handles.single;
    handle.updateBlocker = rotation;
    clock.advance(const Duration(seconds: 10));
    tickers.fireActive();
    await handle.updateStarted.future.timeout(const Duration(seconds: 1));

    final shutdown = act(session);
    try {
      expect(handle.stopCalls, 1);
      expect(encoder.capturedKeys.first, isNot(everyElement(0)));
    } finally {
      if (!rotation.isCompleted) {
        rotation.complete(WeeklyPresenceRadioStatus.ready);
      }
      await shutdown.timeout(const Duration(seconds: 1));
    }
    expect(encoder.capturedKeys.first, everyElement(0));
  } finally {
    if (!rotation.isCompleted) {
      rotation.complete(WeeklyPresenceRadioStatus.ready);
    }
    await session.dispose();
  }
}

WeeklyPresenceSession _session({
  required _FakeRadio radio,
  required _FakeClock clock,
  required List<int> familyKey,
  _FakeTickerFactory? tickers,
}) => WeeklyPresenceSession(
  radio: radio,
  tokenEncoder: WeeklyPresenceTokenCodec(),
  resolveFamilyKey: (_) async => List<int>.from(familyKey),
  now: clock.now,
  tickerFactory: (tickers ?? _FakeTickerFactory()).call,
);

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _FakeClock {
  _FakeClock(this.value);

  DateTime value;

  DateTime now() => value;

  void advance(Duration duration) => value = value.add(duration);
}

final class _FakeTickerFactory {
  final List<_FakeTicker> tickers = [];

  WeeklyPresenceTicker call(Duration interval, void Function() callback) {
    final ticker = _FakeTicker(callback);
    tickers.add(ticker);
    return ticker;
  }

  void fireActive() {
    for (final ticker in List<_FakeTicker>.from(tickers)) {
      if (ticker.isActive) ticker.fire();
    }
  }
}

final class _FakeTicker implements WeeklyPresenceTicker {
  _FakeTicker(this._callback);

  final void Function() _callback;
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() => _active = false;

  void fire() => _callback();
}

final class _FakeRadio implements WeeklyPresenceRadio {
  _FakeRadio({this.initialStatus = WeeklyPresenceRadioStatus.ready});

  final WeeklyPresenceRadioStatus initialStatus;
  final List<_FakeRadioHandle> handles = [];

  @override
  Future<WeeklyPresenceRadioHandle> open({required String serviceUuid}) async {
    final handle = _FakeRadioHandle(
      openedWith: serviceUuid,
      initialStatus: initialStatus,
    );
    handles.add(handle);
    return handle;
  }
}

final class _FakeRadioHandle implements WeeklyPresenceRadioHandle {
  _FakeRadioHandle({required this.openedWith, required this.initialStatus});

  final String openedWith;

  @override
  final WeeklyPresenceRadioStatus initialStatus;

  final _advertisements =
      StreamController<WeeklyPresenceAdvertisement>.broadcast();
  final _statuses = StreamController<WeeklyPresenceRadioStatus>.broadcast();
  final List<String> updatedUuids = [];
  final updateStarted = Completer<void>();
  Completer<WeeklyPresenceRadioStatus>? updateBlocker;
  var stopCalls = 0;

  @override
  Stream<WeeklyPresenceAdvertisement> get advertisements =>
      _advertisements.stream;

  @override
  Stream<WeeklyPresenceRadioStatus> get statuses => _statuses.stream;

  @override
  Future<WeeklyPresenceRadioStatus> updateAdvertisement({
    required String serviceUuid,
  }) async {
    updatedUuids.add(serviceUuid);
    final blocker = updateBlocker;
    if (blocker != null) {
      if (!updateStarted.isCompleted) updateStarted.complete();
      return blocker.future;
    }
    return WeeklyPresenceRadioStatus.ready;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  void emitAdvertisement(Set<String> serviceUuids) {
    _advertisements.add(
      WeeklyPresenceAdvertisement(serviceUuids: serviceUuids),
    );
  }

  void emitStatus(WeeklyPresenceRadioStatus status) => _statuses.add(status);
}

final class _KeyCapturingEncoder implements WeeklyPresenceTokenEncoder {
  final List<List<int>> capturedKeys = [];

  @override
  int slotFor(DateTime at) => at.toUtc().millisecondsSinceEpoch ~/ 10000;

  @override
  String serviceUuid({
    required List<int> familyKey,
    required String familyId,
    required String memberId,
    required int slot,
  }) {
    capturedKeys.add(familyKey);
    return '$memberId-token';
  }

  @override
  Map<String, String> expectedMembersByServiceUuid({
    required List<int> familyKey,
    required String familyId,
    required Iterable<String> memberIds,
    required DateTime at,
    int skewSlots = 1,
  }) {
    capturedKeys.add(familyKey);
    return {for (final memberId in memberIds) '$memberId-token': memberId};
  }
}
