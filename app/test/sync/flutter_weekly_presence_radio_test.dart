import 'dart:async';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/sync/flutter_weekly_presence_radio.dart';
import 'package:keepers/sync/weekly_presence_session.dart';

void main() {
  const serviceUuid = '12345678-1234-4234-8234-123456789abc';

  test('initial generic failure retries once and opens ready', () async {
    final platform = _FakeWeeklyPresenceBlePlatform();
    addTearDown(platform.dispose);
    platform.startAdvertisingOutcomes.add(
      StateError('transient advertisement transport error'),
    );

    final handle = await _radio(platform).open(serviceUuid: serviceUuid);
    addTearDown(handle.stop);

    expect(handle.initialStatus, WeeklyPresenceRadioStatus.ready);
    expect(platform.startAdvertisingCalls, 2);
    expect(platform.startScanningCalls, 1);
  });

  test('initial generic recovery is bounded to one retry', () async {
    final platform = _FakeWeeklyPresenceBlePlatform();
    addTearDown(platform.dispose);
    platform.startAdvertisingOutcomes.addAll(<Object>[
      StateError('first advertisement transport error'),
      StateError('second advertisement transport error'),
      StateError('must not be consumed'),
    ]);

    final handle = await _radio(platform).open(serviceUuid: serviceUuid);
    addTearDown(handle.stop);

    expect(handle.initialStatus, WeeklyPresenceRadioStatus.failed);
    expect(platform.startAdvertisingCalls, 2);
    expect(platform.startScanningCalls, 0);
    expect(platform.startAdvertisingOutcomes, hasLength(1));
  });

  test('permission granted after initial prompt recovers in place', () async {
    final platform = _FakeWeeklyPresenceBlePlatform()
      ..permissionState = PeripheralBluetoothState.denied
      ..requestedPermissionState = PeripheralBluetoothState.denied;
    addTearDown(platform.dispose);

    final handle = await _radio(platform).open(serviceUuid: serviceUuid);
    addTearDown(handle.stop);
    expect(handle.initialStatus, WeeklyPresenceRadioStatus.permissionDenied);
    expect(platform.startScanningCalls, 0);
    final ready = handle.statuses.firstWhere(
      (status) => status == WeeklyPresenceRadioStatus.ready,
    );

    platform.permissionState = PeripheralBluetoothState.granted;
    platform.peripheralStateController.add(PeripheralState.idle);
    await ready.timeout(const Duration(seconds: 1));

    expect(platform.startAdvertisingCalls, 1);
    expect(platform.startScanningCalls, 1);
  });

  test('Darwin-style open waits for advertising confirmation', () async {
    final platform = _FakeWeeklyPresenceBlePlatform(
      requiresAdvertisingConfirmation: true,
    );
    addTearDown(platform.dispose);
    var openCompleted = false;

    final openFuture = _radio(platform).open(serviceUuid: serviceUuid);
    unawaited(openFuture.whenComplete(() => openCompleted = true));
    await platform.firstAdvertisingStarted.future.timeout(
      const Duration(seconds: 1),
    );
    await Future<void>.delayed(Duration.zero);

    expect(openCompleted, isFalse);
    expect(platform.startScanningCalls, 0);
    platform.peripheralStateController.add(PeripheralState.advertising);
    final handle = await openFuture.timeout(const Duration(seconds: 1));
    addTearDown(handle.stop);

    expect(handle.initialStatus, WeeklyPresenceRadioStatus.ready);
    expect(platform.startScanningCalls, 1);
  });

  test('Darwin-style advertising failure does not report ready', () async {
    final platform = _FakeWeeklyPresenceBlePlatform(
      requiresAdvertisingConfirmation: true,
    );
    addTearDown(platform.dispose);
    platform.startAdvertisingOutcomes.addAll(<Object>[
      PeripheralBluetoothState.ready,
      PeripheralBluetoothState.unsupported,
    ]);

    final openFuture = _radio(platform).open(serviceUuid: serviceUuid);
    await platform.firstAdvertisingStarted.future.timeout(
      const Duration(seconds: 1),
    );
    platform.peripheralStateController.add(PeripheralState.idle);
    await platform.secondAdvertisingStarted.future.timeout(
      const Duration(seconds: 1),
    );
    final handle = await openFuture.timeout(const Duration(seconds: 1));
    addTearDown(handle.stop);

    expect(handle.initialStatus, WeeklyPresenceRadioStatus.unsupported);
    expect(platform.startAdvertisingCalls, 2);
    expect(platform.startScanningCalls, 0);
  });

  test('Darwin-style rotation ignores the delayed stop-idle event', () async {
    final platform = _FakeWeeklyPresenceBlePlatform(
      requiresAdvertisingConfirmation: true,
    );
    addTearDown(platform.dispose);

    final openFuture = _radio(platform).open(serviceUuid: serviceUuid);
    await platform.firstAdvertisingStarted.future.timeout(
      const Duration(seconds: 1),
    );
    platform.peripheralStateController.add(PeripheralState.advertising);
    final handle = await openFuture.timeout(const Duration(seconds: 1));
    addTearDown(handle.stop);

    final updateFuture = handle.updateAdvertisement(
      serviceUuid: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
    );
    await platform.secondAdvertisingStarted.future.timeout(
      const Duration(seconds: 1),
    );
    // Darwin publishes this idle for the preceding stop on an event channel;
    // it can reach Dart after the new method-channel start has been invoked.
    platform.peripheralStateController.add(PeripheralState.idle);
    platform.peripheralStateController.add(PeripheralState.advertising);

    expect(
      await updateFuture.timeout(const Duration(seconds: 1)),
      WeeklyPresenceRadioStatus.ready,
    );
    expect(platform.startAdvertisingCalls, 2);
  });

  test('scan-stream error queues recovery and returns ready', () async {
    final platform = _FakeWeeklyPresenceBlePlatform();
    addTearDown(platform.dispose);
    final handle = await _radio(platform).open(serviceUuid: serviceUuid);
    addTearDown(handle.stop);

    expect(handle.initialStatus, WeeklyPresenceRadioStatus.ready);
    expect(platform.startScanningCalls, 1);
    final statuses = <WeeklyPresenceRadioStatus>[];
    final statusSubscription = handle.statuses.listen(statuses.add);
    addTearDown(statusSubscription.cancel);

    platform.advertisementController.addError(
      StateError('transient scan transport error'),
    );

    await platform.secondScanStarted.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);

    expect(platform.startScanningCalls, 2);
    expect(platform.startAdvertisingCalls, 2);
    expect(statuses, <WeeklyPresenceRadioStatus>[
      WeeklyPresenceRadioStatus.failed,
      WeeklyPresenceRadioStatus.ready,
    ]);
  });

  test('automatic recovery is paced and coalesces an error burst', () async {
    final platform = _FakeWeeklyPresenceBlePlatform();
    addTearDown(platform.dispose);
    final releaseRecovery = Completer<void>();
    addTearDown(() {
      if (!releaseRecovery.isCompleted) releaseRecovery.complete();
    });
    final delayObserved = Completer<Duration>();
    final handle = await FlutterWeeklyPresenceRadio(
      platform: platform,
      recoveryDelay: (duration) {
        if (!delayObserved.isCompleted) delayObserved.complete(duration);
        return releaseRecovery.future;
      },
    ).open(serviceUuid: serviceUuid);
    addTearDown(handle.stop);

    platform.advertisementController.addError(StateError('transport error 1'));
    platform.advertisementController.addError(StateError('transport error 2'));
    final delay = await delayObserved.future.timeout(
      const Duration(seconds: 1),
    );
    expect(delay, greaterThanOrEqualTo(const Duration(seconds: 7)));
    expect(platform.startScanningCalls, 1);
    expect(platform.startAdvertisingCalls, 1);

    releaseRecovery.complete();
    await platform.secondScanStarted.future.timeout(const Duration(seconds: 1));
    expect(platform.startScanningCalls, 2);
    expect(platform.startAdvertisingCalls, 2);
  });

  test(
    'permission-denied scan-stream error fails closed without retry',
    () async {
      final platform = _FakeWeeklyPresenceBlePlatform();
      addTearDown(platform.dispose);
      final handle = await _radio(platform).open(serviceUuid: serviceUuid);
      addTearDown(handle.stop);
      final statuses = <WeeklyPresenceRadioStatus>[];
      final statusSubscription = handle.statuses.listen(statuses.add);
      addTearDown(statusSubscription.cancel);

      platform.advertisementController.addError(
        StateError('Bluetooth scan permission denied'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(platform.startScanningCalls, 1);
      expect(platform.startAdvertisingCalls, 1);
      expect(platform.secondScanStarted.isCompleted, isFalse);
      expect(statuses, <WeeklyPresenceRadioStatus>[
        WeeklyPresenceRadioStatus.permissionDenied,
      ]);
    },
  );

  test(
    'adapter-state stream error queues recovery and returns ready',
    () async {
      final platform = _FakeWeeklyPresenceBlePlatform();
      addTearDown(platform.dispose);
      final handle = await _radio(platform).open(serviceUuid: serviceUuid);
      addTearDown(handle.stop);

      final statuses = <WeeklyPresenceRadioStatus>[];
      final statusSubscription = handle.statuses.listen(statuses.add);
      addTearDown(statusSubscription.cancel);

      platform.adapterStateController.addError(
        StateError('transient adapter-state transport error'),
      );

      await platform.secondScanStarted.future.timeout(
        const Duration(seconds: 1),
      );
      await Future<void>.delayed(Duration.zero);

      expect(platform.startScanningCalls, 2);
      expect(platform.startAdvertisingCalls, 2);
      expect(statuses, <WeeklyPresenceRadioStatus>[
        WeeklyPresenceRadioStatus.failed,
        WeeklyPresenceRadioStatus.ready,
      ]);
    },
  );

  test(
    'peripheral-state stream error queues recovery and returns ready',
    () async {
      final platform = _FakeWeeklyPresenceBlePlatform();
      addTearDown(platform.dispose);
      final handle = await _radio(platform).open(serviceUuid: serviceUuid);
      addTearDown(handle.stop);

      final statuses = <WeeklyPresenceRadioStatus>[];
      final statusSubscription = handle.statuses.listen(statuses.add);
      addTearDown(statusSubscription.cancel);

      platform.peripheralStateController.addError(
        StateError('transient peripheral-state transport error'),
      );

      await platform.secondScanStarted.future.timeout(
        const Duration(seconds: 1),
      );
      await Future<void>.delayed(Duration.zero);

      expect(platform.startScanningCalls, 2);
      expect(platform.startAdvertisingCalls, 2);
      expect(statuses, <WeeklyPresenceRadioStatus>[
        WeeklyPresenceRadioStatus.failed,
        WeeklyPresenceRadioStatus.ready,
      ]);
    },
  );

  test('rotation exception queues one recovery after the update', () async {
    final platform = _FakeWeeklyPresenceBlePlatform();
    addTearDown(platform.dispose);
    final handle = await _radio(platform).open(serviceUuid: serviceUuid);
    addTearDown(handle.stop);
    platform.startAdvertisingOutcomes.add(
      StateError('transient advertisement transport error'),
    );
    final statuses = <WeeklyPresenceRadioStatus>[];
    final statusSubscription = handle.statuses.listen(statuses.add);
    addTearDown(statusSubscription.cancel);

    final result = await handle.updateAdvertisement(
      serviceUuid: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
    );

    expect(result, WeeklyPresenceRadioStatus.failed);
    expect(statuses, <WeeklyPresenceRadioStatus>[
      WeeklyPresenceRadioStatus.failed,
    ]);
    expect(platform.startScanningCalls, 1);
    await platform.secondScanStarted.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);

    expect(platform.startScanningCalls, 2);
    expect(platform.startAdvertisingCalls, 3);
    expect(platform.advertisedServiceUuids, <String>[
      serviceUuid,
      'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      serviceUuid,
    ]);
    expect(statuses, <WeeklyPresenceRadioStatus>[
      WeeklyPresenceRadioStatus.failed,
      WeeklyPresenceRadioStatus.ready,
    ]);
  });

  test('non-ready rotation fails closed without retry', () async {
    final platform = _FakeWeeklyPresenceBlePlatform();
    addTearDown(platform.dispose);
    final handle = await _radio(platform).open(serviceUuid: serviceUuid);
    addTearDown(handle.stop);
    platform.startAdvertisingOutcomes.add(PeripheralBluetoothState.turnedOff);
    final statuses = <WeeklyPresenceRadioStatus>[];
    final statusSubscription = handle.statuses.listen(statuses.add);
    addTearDown(statusSubscription.cancel);

    final result = await handle.updateAdvertisement(
      serviceUuid: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
    );

    expect(result, WeeklyPresenceRadioStatus.bluetoothOff);
    expect(statuses, <WeeklyPresenceRadioStatus>[
      WeeklyPresenceRadioStatus.bluetoothOff,
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(platform.startScanningCalls, 1);
    expect(platform.startAdvertisingCalls, 2);
    expect(platform.secondScanStarted.isCompleted, isFalse);
    expect(statuses, <WeeklyPresenceRadioStatus>[
      WeeklyPresenceRadioStatus.bluetoothOff,
    ]);
  });

  test('stop revokes a blocked recovery before radios can restart', () async {
    final platform = _FakeWeeklyPresenceBlePlatform();
    addTearDown(platform.dispose);
    final handle = await _radio(platform).open(serviceUuid: serviceUuid);
    addTearDown(handle.stop);
    final stopScanningBlocker = Completer<void>();
    platform.stopScanningBlocker = stopScanningBlocker;
    addTearDown(() {
      if (!stopScanningBlocker.isCompleted) stopScanningBlocker.complete();
    });
    final statuses = <WeeklyPresenceRadioStatus>[];
    final statusSubscription = handle.statuses.listen(statuses.add);
    addTearDown(statusSubscription.cancel);

    platform.advertisementController.addError(
      StateError('transient scan transport error'),
    );
    await platform.stopScanningEntered.future.timeout(
      const Duration(seconds: 1),
    );

    final stopFuture = handle.stop();
    stopScanningBlocker.complete();
    await stopFuture.timeout(const Duration(seconds: 1));

    expect(platform.startScanningCalls, 1);
    expect(platform.startAdvertisingCalls, 1);
    expect(statuses, <WeeklyPresenceRadioStatus>[
      WeeklyPresenceRadioStatus.failed,
    ]);
  });
}

FlutterWeeklyPresenceRadio _radio(_FakeWeeklyPresenceBlePlatform platform) =>
    FlutterWeeklyPresenceRadio(platform: platform, recoveryDelay: (_) async {});

final class _FakeWeeklyPresenceBlePlatform
    implements WeeklyPresenceBlePlatform {
  _FakeWeeklyPresenceBlePlatform({
    this.requiresAdvertisingConfirmation = false,
  });

  @override
  final bool requiresAdvertisingConfirmation;

  final advertisementController =
      StreamController<WeeklyPresenceAdvertisement>.broadcast(sync: true);
  final adapterStateController =
      StreamController<BluetoothAdapterState>.broadcast(sync: true);
  final peripheralStateController = StreamController<PeripheralState>.broadcast(
    sync: true,
  );
  final secondScanStarted = Completer<void>();
  final startAdvertisingOutcomes = <Object>[];
  final advertisedServiceUuids = <String>[];
  final stopScanningEntered = Completer<void>();
  final firstAdvertisingStarted = Completer<void>();
  final secondAdvertisingStarted = Completer<void>();
  Completer<void>? stopScanningBlocker;

  int startAdvertisingCalls = 0;
  int startScanningCalls = 0;
  PeripheralBluetoothState permissionState = PeripheralBluetoothState.granted;
  PeripheralBluetoothState requestedPermissionState =
      PeripheralBluetoothState.granted;

  @override
  Stream<WeeklyPresenceAdvertisement> get advertisements =>
      advertisementController.stream;

  @override
  Stream<BluetoothAdapterState> get adapterStates =>
      adapterStateController.stream;

  @override
  Stream<PeripheralState>? get peripheralStates =>
      peripheralStateController.stream;

  @override
  Future<bool> get isPeripheralSupported async => true;

  @override
  Future<bool> get isScannerSupported async => true;

  @override
  Future<PeripheralBluetoothState> hasPermission() async => permissionState;

  @override
  Future<PeripheralBluetoothState> requestPermission() async =>
      requestedPermissionState;

  @override
  Future<PeripheralBluetoothState> startAdvertising({
    required String serviceUuid,
  }) async {
    startAdvertisingCalls += 1;
    if (startAdvertisingCalls == 1 && !firstAdvertisingStarted.isCompleted) {
      firstAdvertisingStarted.complete();
    }
    if (startAdvertisingCalls == 2 && !secondAdvertisingStarted.isCompleted) {
      secondAdvertisingStarted.complete();
    }
    advertisedServiceUuids.add(serviceUuid);
    if (startAdvertisingOutcomes.isNotEmpty) {
      final outcome = startAdvertisingOutcomes.removeAt(0);
      if (outcome is PeripheralBluetoothState) return outcome;
      throw outcome;
    }
    return PeripheralBluetoothState.ready;
  }

  @override
  Future<void> startScanning() async {
    startScanningCalls += 1;
    if (startScanningCalls == 2 && !secondScanStarted.isCompleted) {
      secondScanStarted.complete();
    }
  }

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<void> stopScanning() async {
    final blocker = stopScanningBlocker;
    if (blocker == null) return;
    stopScanningBlocker = null;
    if (!stopScanningEntered.isCompleted) stopScanningEntered.complete();
    await blocker.future;
  }

  Future<void> dispose() async {
    await advertisementController.close();
    await adapterStateController.close();
    await peripheralStateController.close();
  }
}
