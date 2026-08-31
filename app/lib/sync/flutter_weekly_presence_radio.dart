import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:keepers/sync/weekly_presence_session.dart';

/// Minimum pause between automatic scan restarts on one waiting-room handle.
///
/// Android rate-limits apps that start scanning too frequently. Seven seconds
/// keeps even repeated one-shot recoveries to at most five starts per 30
/// seconds.
const weeklyPresenceRadioRecoveryBackoff = Duration(seconds: 7);

typedef WeeklyPresenceRecoveryDelay = Future<void> Function(Duration delay);

/// Narrow native-BLE boundary used by the foreground radio owner.
///
/// The production implementation deliberately strips scan results down to
/// service UUIDs before they enter the waiting-room domain.
abstract interface class WeeklyPresenceBlePlatform {
  bool get requiresAdvertisingConfirmation;

  Future<bool> get isScannerSupported;

  Future<bool> get isPeripheralSupported;

  Future<PeripheralBluetoothState> hasPermission();

  Future<PeripheralBluetoothState> requestPermission();

  Stream<WeeklyPresenceAdvertisement> get advertisements;

  Stream<BluetoothAdapterState> get adapterStates;

  Stream<PeripheralState>? get peripheralStates;

  Future<PeripheralBluetoothState> startAdvertising({
    required String serviceUuid,
  });

  Future<void> stopAdvertising();

  Future<void> startScanning();

  Future<void> stopScanning();
}

final class _FlutterWeeklyPresenceBlePlatform
    implements WeeklyPresenceBlePlatform {
  _FlutterWeeklyPresenceBlePlatform({FlutterBlePeripheral? peripheral})
    : _peripheral = peripheral ?? FlutterBlePeripheral();

  final FlutterBlePeripheral _peripheral;

  @override
  bool get requiresAdvertisingConfirmation =>
      Platform.isIOS || Platform.isMacOS;

  @override
  Future<bool> get isScannerSupported => FlutterBluePlus.isSupported;

  @override
  Future<bool> get isPeripheralSupported => _peripheral.isSupported;

  @override
  Future<PeripheralBluetoothState> hasPermission() =>
      _peripheral.hasPermission();

  @override
  Future<PeripheralBluetoothState> requestPermission() =>
      _peripheral.requestPermission();

  @override
  Stream<WeeklyPresenceAdvertisement> get advertisements => FlutterBluePlus
      .onScanResults
      .expand<WeeklyPresenceAdvertisement>((results) sync* {
        for (final result in results) {
          final serviceUuids = {
            for (final uuid in result.advertisementData.serviceUuids)
              uuid.str128.toLowerCase(),
          };
          if (serviceUuids.isNotEmpty) {
            yield WeeklyPresenceAdvertisement(serviceUuids: serviceUuids);
          }
        }
      });

  @override
  Stream<BluetoothAdapterState> get adapterStates =>
      FlutterBluePlus.adapterState;

  @override
  Stream<PeripheralState>? get peripheralStates =>
      _peripheral.onPeripheralStateChanged;

  @override
  Future<PeripheralBluetoothState> startAdvertising({
    required String serviceUuid,
  }) {
    return _peripheral.start(
      advertiseData: AdvertiseDataCore(serviceUuid: serviceUuid),
      androidSettings: const AndroidAdvertiseSettings(
        advertiseSettings: AdvertiseSettings(
          advertiseMode: AdvertiseMode.advertiseModeLowLatency,
          txPowerLevel: AdvertiseTxPower.advertiseTxPowerMedium,
          connectable: false,
          timeout: 0,
        ),
      ),
    );
  }

  @override
  Future<void> stopAdvertising() => _peripheral.stop();

  @override
  Future<void> startScanning() => FlutterBluePlus.startScan(
    continuousUpdates: true,
    oneByOne: true,
    androidScanMode: AndroidScanMode.lowLatency,
    androidUsesFineLocation: false,
  );

  @override
  Future<void> stopScanning() => FlutterBluePlus.stopScan();
}

/// The foreground mobile BLE bridge for the Weekly waiting room.
///
/// Native BLE APIs are process-global. This owner creates scoped handles so a
/// delayed callback or stop from an old waiting room cannot affect its
/// replacement.
final class FlutterWeeklyPresenceRadio implements WeeklyPresenceRadio {
  FlutterWeeklyPresenceRadio({
    FlutterBlePeripheral? peripheral,
    WeeklyPresenceBlePlatform? platform,
    WeeklyPresenceRecoveryDelay? recoveryDelay,
  }) : assert(peripheral == null || platform == null),
       _platform =
           platform ??
           _FlutterWeeklyPresenceBlePlatform(peripheral: peripheral),
       _recoveryDelay =
           recoveryDelay ?? ((delay) => Future<void>.delayed(delay));

  final WeeklyPresenceBlePlatform _platform;
  final WeeklyPresenceRecoveryDelay _recoveryDelay;
  Future<void> _operationTail = Future<void>.value();
  _FlutterWeeklyPresenceRadioHandle? _activeHandle;

  @override
  Future<WeeklyPresenceRadioHandle> open({required String serviceUuid}) {
    return _serialize(() async {
      final previous = _activeHandle;
      if (previous != null) await previous._stopInsideOperation();

      final handle = _FlutterWeeklyPresenceRadioHandle(this, _platform);
      _activeHandle = handle;
      await handle._open(serviceUuid);
      return handle;
    });
  }

  bool _owns(_FlutterWeeklyPresenceRadioHandle handle) =>
      identical(_activeHandle, handle);

  void _release(_FlutterWeeklyPresenceRadioHandle handle) {
    if (_owns(handle)) _activeHandle = null;
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

final class _FlutterWeeklyPresenceRadioHandle
    implements WeeklyPresenceRadioHandle {
  _FlutterWeeklyPresenceRadioHandle(this._owner, this._platform);

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  final FlutterWeeklyPresenceRadio _owner;
  final WeeklyPresenceBlePlatform _platform;
  final StreamController<WeeklyPresenceAdvertisement> _advertisementController =
      StreamController<WeeklyPresenceAdvertisement>.broadcast(sync: true);
  final StreamController<WeeklyPresenceRadioStatus> _statusController =
      StreamController<WeeklyPresenceRadioStatus>.broadcast(sync: true);

  StreamSubscription<WeeklyPresenceAdvertisement>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<PeripheralState>? _peripheralSubscription;
  WeeklyPresenceRadioStatus _initialStatus = WeeklyPresenceRadioStatus.failed;
  String? _serviceUuid;
  var _advertising = false;
  var _scanning = false;
  var _opening = false;
  var _updating = false;
  var _canRecover = false;
  var _recoveryQueued = false;
  var _stopped = false;
  var _expectedStopIdleEvents = 0;
  Completer<WeeklyPresenceRadioStatus>? _advertisingConfirmation;
  Future<void>? _cleanupFuture;
  Future<void>? _publicStopFuture;

  bool get _acceptsCallbacks => !_stopped && _owner._owns(this);

  @override
  WeeklyPresenceRadioStatus get initialStatus => _initialStatus;

  @override
  Stream<WeeklyPresenceAdvertisement> get advertisements =>
      _advertisementController.stream;

  @override
  Stream<WeeklyPresenceRadioStatus> get statuses => _statusController.stream;

  Future<void> _open(String rawServiceUuid) async {
    _opening = true;
    _serviceUuid = _normalizedUuid(rawServiceUuid);
    _listenForAdvertisements();

    final uuid = _serviceUuid;
    var status = uuid == null
        ? WeeklyPresenceRadioStatus.failed
        : await _startRadios(uuid);
    if (uuid != null &&
        status == WeeklyPresenceRadioStatus.failed &&
        _acceptsCallbacks) {
      // A transport/startup fault has no guaranteed native state event. Make
      // one bounded retry while opening; persistent failure remains terminal
      // until the user re-enters, and permission/radio states are never spun.
      status = await _startRadios(uuid);
    }
    if (_acceptsCallbacks) {
      _initialStatus = status;
      _canRecover = true;
    }
    _opening = false;
  }

  void _listenForAdvertisements() {
    _scanSubscription = _platform.advertisements.listen(
      (advertisement) {
        if (!_acceptsCallbacks || !_scanning) return;
        _advertisementController.add(advertisement);
      },
      onError: (Object error, StackTrace stackTrace) {
        final status = _statusForError(error);
        _completeAdvertisingConfirmation(status);
        if (!_acceptsCallbacks) return;
        _scanning = false;
        _emitStatus(status);
        if (status == WeeklyPresenceRadioStatus.failed) _queueRecovery();
      },
    );
  }

  void _listenForRadioState() {
    _adapterSubscription ??= _platform.adapterStates.listen(
      _onAdapterState,
      onError: (Object error, StackTrace stackTrace) {
        final status = _statusForError(error);
        if (!_acceptsCallbacks) return;
        _advertising = false;
        _scanning = false;
        _emitStatus(status);
        if (status == WeeklyPresenceRadioStatus.failed) _queueRecovery();
      },
    );
    final peripheralStates = _platform.peripheralStates;
    if (peripheralStates != null) {
      _peripheralSubscription ??= peripheralStates.listen(
        _onPeripheralState,
        onError: (Object error, StackTrace stackTrace) {
          final status = _statusForError(error);
          _completeAdvertisingConfirmation(status);
          if (!_acceptsCallbacks) return;
          _advertising = false;
          _emitStatus(status);
          if (status == WeeklyPresenceRadioStatus.failed) _queueRecovery();
        },
      );
    }
  }

  Future<WeeklyPresenceRadioStatus> _startRadios(String serviceUuid) async {
    if (!_acceptsCallbacks) return WeeklyPresenceRadioStatus.failed;
    try {
      if (!await _platform.isScannerSupported ||
          !await _platform.isPeripheralSupported) {
        return WeeklyPresenceRadioStatus.unsupported;
      }

      // Subscribe before requesting permission. On Darwin the system prompt may
      // outlive the plugin's immediate permission result; the later powered-on
      // delegate event must still be able to recover this same room session.
      _listenForRadioState();
      var permission = await _platform.hasPermission();
      if (permission != PeripheralBluetoothState.granted &&
          permission != PeripheralBluetoothState.ready) {
        permission = await _platform.requestPermission();
      }
      final permissionStatus = _statusForPeripheralBluetooth(permission);
      if (permissionStatus != WeeklyPresenceRadioStatus.ready) {
        return permissionStatus;
      }
      if (!_acceptsCallbacks) return WeeklyPresenceRadioStatus.failed;

      final advertiseStatus = await _startAdvertising(serviceUuid);
      if (advertiseStatus != WeeklyPresenceRadioStatus.ready) {
        await _stopNativeRadios();
        return advertiseStatus;
      }
      if (!_acceptsCallbacks) {
        await _stopNativeRadios();
        return WeeklyPresenceRadioStatus.failed;
      }

      await _platform.startScanning();
      if (!_acceptsCallbacks) {
        await _stopNativeRadios();
        return WeeklyPresenceRadioStatus.failed;
      }
      _scanning = true;
      return WeeklyPresenceRadioStatus.ready;
    } on Object catch (error) {
      await _stopNativeRadios();
      return _statusForError(error);
    }
  }

  Future<WeeklyPresenceRadioStatus> _startAdvertising(
    String serviceUuid,
  ) async {
    final confirmation = _platform.requiresAdvertisingConfirmation
        ? Completer<WeeklyPresenceRadioStatus>()
        : null;
    if (confirmation != null) {
      if (_peripheralSubscription == null) {
        return WeeklyPresenceRadioStatus.failed;
      }
      _advertisingConfirmation = confirmation;
    }
    try {
      final state = await _platform.startAdvertising(serviceUuid: serviceUuid);
      // `start` documents only `ready` as confirmation that the native request
      // was accepted. Darwin additionally confirms the asynchronous
      // CoreBluetooth result through PeripheralState.advertising.
      final status = _statusForAdvertisementStart(state);
      if (status != WeeklyPresenceRadioStatus.ready || confirmation == null) {
        _advertising = state == PeripheralBluetoothState.ready;
        return status;
      }

      final confirmed = await confirmation.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => WeeklyPresenceRadioStatus.failed,
      );
      _advertising = confirmed == WeeklyPresenceRadioStatus.ready;
      return confirmed;
    } finally {
      if (identical(_advertisingConfirmation, confirmation)) {
        _advertisingConfirmation = null;
      }
    }
  }

  @override
  Future<WeeklyPresenceRadioStatus> updateAdvertisement({
    required String serviceUuid,
  }) {
    return _owner._serialize(() async {
      if (!_acceptsCallbacks) return WeeklyPresenceRadioStatus.failed;
      final normalized = _normalizedUuid(serviceUuid);
      if (normalized == null) {
        _emitStatus(WeeklyPresenceRadioStatus.failed);
        return WeeklyPresenceRadioStatus.failed;
      }

      _updating = true;
      var recoverAfterUpdate = false;
      try {
        // Android's legacy advertiser rejects start-while-started. An explicit
        // stop also ensures an iOS advertisement queued while powered off can
        // never surface with an obsolete token.
        await _stopAdvertising();
        if (!_acceptsCallbacks) return WeeklyPresenceRadioStatus.failed;

        final status = await _startAdvertising(normalized);
        if (status != WeeklyPresenceRadioStatus.ready) {
          await _stopAdvertising();
          recoverAfterUpdate = status == WeeklyPresenceRadioStatus.failed;
          _emitStatus(status);
          return status;
        }
        _serviceUuid = normalized;

        if (!_scanning) {
          await _platform.startScanning();
          _scanning = true;
        }
        if (!_acceptsCallbacks) return WeeklyPresenceRadioStatus.failed;
        _emitStatus(WeeklyPresenceRadioStatus.ready);
        return WeeklyPresenceRadioStatus.ready;
      } on Object catch (error) {
        await _stopAdvertising();
        final status = _statusForError(error);
        recoverAfterUpdate = status == WeeklyPresenceRadioStatus.failed;
        _emitStatus(status);
        return status;
      } finally {
        _updating = false;
        if (recoverAfterUpdate) _queueRecovery();
      }
    });
  }

  void _onAdapterState(BluetoothAdapterState state) {
    if (!_acceptsCallbacks || _opening) return;
    switch (state) {
      case BluetoothAdapterState.on:
        if (!_advertising || !_scanning) _queueRecovery();
      case BluetoothAdapterState.off:
      case BluetoothAdapterState.turningOff:
        _advertising = false;
        _scanning = false;
        _emitStatus(WeeklyPresenceRadioStatus.bluetoothOff);
      case BluetoothAdapterState.unauthorized:
        _advertising = false;
        _scanning = false;
        _emitStatus(WeeklyPresenceRadioStatus.permissionDenied);
      case BluetoothAdapterState.unavailable:
        _advertising = false;
        _scanning = false;
        _emitStatus(WeeklyPresenceRadioStatus.unsupported);
      case BluetoothAdapterState.unknown:
        _advertising = false;
        _scanning = false;
        _emitStatus(WeeklyPresenceRadioStatus.failed);
      case BluetoothAdapterState.turningOn:
        _advertising = false;
        _scanning = false;
    }
  }

  void _onPeripheralState(PeripheralState state) {
    final expectedStopIdle =
        state == PeripheralState.idle && _expectedStopIdleEvents > 0;
    if (expectedStopIdle) {
      _expectedStopIdleEvents -= 1;
    } else {
      _completeAdvertisingConfirmation(_statusForPeripheralState(state));
    }
    if (!_acceptsCallbacks || _opening) return;
    switch (state) {
      case PeripheralState.advertising:
      case PeripheralState.connected:
        _advertising = true;
        if (_updating) return;
        if (_scanning) _emitStatus(WeeklyPresenceRadioStatus.ready);
      case PeripheralState.poweredOff:
        _advertising = false;
        _emitStatus(WeeklyPresenceRadioStatus.bluetoothOff);
      case PeripheralState.unauthorized:
      case PeripheralState.shouldShowRequestPermissionRationale:
        _advertising = false;
        _emitStatus(WeeklyPresenceRadioStatus.permissionDenied);
      case PeripheralState.unsupported:
        _advertising = false;
        _emitStatus(WeeklyPresenceRadioStatus.unsupported);
      case PeripheralState.locationServicesDisabled:
      case PeripheralState.unknown:
        _advertising = false;
        _emitStatus(WeeklyPresenceRadioStatus.failed);
      case PeripheralState.idle:
        if (_updating || expectedStopIdle) return;
        _advertising = false;
        _emitStatus(WeeklyPresenceRadioStatus.failed);
        _queueRecovery();
    }
  }

  void _queueRecovery() {
    if (!_acceptsCallbacks ||
        !_canRecover ||
        _opening ||
        _updating ||
        _recoveryQueued) {
      return;
    }
    final serviceUuid = _serviceUuid;
    if (serviceUuid == null) return;

    _recoveryQueued = true;
    unawaited(_recoverAfterBackoff(serviceUuid));
  }

  Future<void> _recoverAfterBackoff(String serviceUuid) async {
    try {
      await _owner._recoveryDelay(weeklyPresenceRadioRecoveryBackoff);
      if (!_acceptsCallbacks || (_advertising && _scanning)) return;
      await _owner._serialize(() async {
        if (!_acceptsCallbacks || (_advertising && _scanning)) return;
        _updating = true;
        try {
          await _stopNativeRadios();
          if (!_acceptsCallbacks) return;
          final status = await _startRadios(serviceUuid);
          if (_acceptsCallbacks) _emitStatus(status);
        } finally {
          _updating = false;
        }
      });
    } on Object {
      if (_acceptsCallbacks) _emitStatus(WeeklyPresenceRadioStatus.failed);
    } finally {
      _recoveryQueued = false;
    }
  }

  void _emitStatus(WeeklyPresenceRadioStatus status) {
    if (!_acceptsCallbacks || _statusController.isClosed) return;
    _statusController.add(status);
  }

  @override
  Future<void> stop() {
    final existing = _publicStopFuture;
    if (existing != null) return existing;

    // Revoke callback ownership before waiting behind any in-flight native
    // operation. Cleanup remains serialized, but a recovery can no longer
    // restart either radio after the room requests stop.
    final ownedNativeRadios = _revoke();
    final stopping = _owner._serialize<void>(
      () => _cleanupAfterRevocation(ownedNativeRadios),
    );
    _publicStopFuture = stopping;
    return stopping;
  }

  Future<void> _stopInsideOperation() {
    final ownedNativeRadios = _revoke();
    return _cleanupAfterRevocation(ownedNativeRadios);
  }

  bool _revoke() {
    if (_stopped) return false;
    final ownedNativeRadios = _owner._owns(this);
    _stopped = true;
    _canRecover = false;
    _completeAdvertisingConfirmation(WeeklyPresenceRadioStatus.failed);
    _owner._release(this);
    return ownedNativeRadios;
  }

  Future<void> _cleanupAfterRevocation(bool ownedNativeRadios) {
    return _cleanupFuture ??= _performCleanup(ownedNativeRadios);
  }

  Future<void> _performCleanup(bool ownedNativeRadios) async {
    await _cancel(_scanSubscription);
    await _cancel(_adapterSubscription);
    await _cancel(_peripheralSubscription);
    if (ownedNativeRadios) await _stopNativeRadios();

    await _advertisementController.close();
    await _statusController.close();
  }

  Future<void> _stopNativeRadios() async {
    _scanning = false;
    _advertising = false;
    try {
      await _platform.stopScanning();
    } on Object {
      // The scoped handle is already unavailable locally.
    }
    await _stopAdvertising();
  }

  Future<void> _stopAdvertising() async {
    _advertising = false;
    // Darwin reports stop on its event channel separately from the method
    // result. Remember that one expected idle so a delayed stop notification
    // cannot reject the next asynchronous start confirmation.
    final expectedBefore = _expectedStopIdleEvents;
    final expectsIdle =
        _platform.requiresAdvertisingConfirmation &&
        _acceptsCallbacks &&
        _peripheralSubscription != null;
    if (expectsIdle) _expectedStopIdleEvents += 1;
    try {
      await _platform.stopAdvertising();
    } on Object {
      if (expectsIdle && _expectedStopIdleEvents > expectedBefore) {
        _expectedStopIdleEvents -= 1;
      }
      // This also covers devices that expose Bluetooth but cannot advertise.
    }
  }

  static Future<void> _cancel(StreamSubscription<Object?>? subscription) async {
    if (subscription == null) return;
    try {
      await subscription.cancel();
    } on Object {
      // Callback ownership is revoked before cancellation starts.
    }
  }

  static String? _normalizedUuid(String value) {
    final normalized = value.trim().toLowerCase();
    return _uuidPattern.hasMatch(normalized) ? normalized : null;
  }

  static WeeklyPresenceRadioStatus _statusForPeripheralBluetooth(
    PeripheralBluetoothState state,
  ) {
    return switch (state) {
      PeripheralBluetoothState.granted ||
      PeripheralBluetoothState.ready => WeeklyPresenceRadioStatus.ready,
      PeripheralBluetoothState.turnedOff =>
        WeeklyPresenceRadioStatus.bluetoothOff,
      PeripheralBluetoothState.denied ||
      PeripheralBluetoothState.permanentlyDenied ||
      PeripheralBluetoothState.restricted ||
      PeripheralBluetoothState.limited =>
        WeeklyPresenceRadioStatus.permissionDenied,
      PeripheralBluetoothState.unsupported =>
        WeeklyPresenceRadioStatus.unsupported,
      PeripheralBluetoothState.unknown => WeeklyPresenceRadioStatus.failed,
    };
  }

  static WeeklyPresenceRadioStatus _statusForAdvertisementStart(
    PeripheralBluetoothState state,
  ) {
    if (state == PeripheralBluetoothState.granted) {
      return WeeklyPresenceRadioStatus.failed;
    }
    return _statusForPeripheralBluetooth(state);
  }

  static WeeklyPresenceRadioStatus _statusForPeripheralState(
    PeripheralState state,
  ) {
    return switch (state) {
      PeripheralState.advertising ||
      PeripheralState.connected => WeeklyPresenceRadioStatus.ready,
      PeripheralState.poweredOff => WeeklyPresenceRadioStatus.bluetoothOff,
      PeripheralState.unauthorized ||
      PeripheralState.shouldShowRequestPermissionRationale =>
        WeeklyPresenceRadioStatus.permissionDenied,
      PeripheralState.unsupported => WeeklyPresenceRadioStatus.unsupported,
      PeripheralState.locationServicesDisabled ||
      PeripheralState.unknown ||
      PeripheralState.idle => WeeklyPresenceRadioStatus.failed,
    };
  }

  void _completeAdvertisingConfirmation(WeeklyPresenceRadioStatus status) {
    final confirmation = _advertisingConfirmation;
    if (confirmation == null || confirmation.isCompleted) return;
    confirmation.complete(status);
  }

  static WeeklyPresenceRadioStatus _statusForError(Object error) {
    if (error is MissingPluginException) {
      return WeeklyPresenceRadioStatus.unsupported;
    }
    final message = switch (error) {
      PlatformException(:final code, :final message, :final details) =>
        '$code ${message ?? ''} ${details ?? ''}',
      _ => error.toString(),
    }.toLowerCase();
    if (message.contains('permission') ||
        message.contains('unauthor') ||
        message.contains('denied')) {
      return WeeklyPresenceRadioStatus.permissionDenied;
    }
    if ((message.contains('bluetooth') || message.contains('powered')) &&
        (message.contains('off') || message.contains('turned'))) {
      return WeeklyPresenceRadioStatus.bluetoothOff;
    }
    if (message.contains('unsupported') ||
        message.contains('not supported') ||
        message.contains('unavailable')) {
      return WeeklyPresenceRadioStatus.unsupported;
    }
    return WeeklyPresenceRadioStatus.failed;
  }
}
