import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BLE dependencies are exactly pinned for native API stability', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('flutter_ble_peripheral: 3.1.0'));
    expect(pubspec, contains('flutter_blue_plus: 2.3.12'));
    expect(
      pubspec,
      contains('path: packages/flutter_ble_peripheral'),
      reason: 'the audited 3.1.0 native runtime is patched in-repo',
    );
  });

  test('vendored Android advertiser is resolved safely for every use', () {
    final manager = File(
      'packages/flutter_ble_peripheral/android/src/main/kotlin/'
      'dev/steenbakker/flutter_ble_peripheral/'
      'FlutterBlePeripheralManager.kt',
    ).readAsStringSync();
    final plugin = File(
      'packages/flutter_ble_peripheral/android/src/main/kotlin/'
      'dev/steenbakker/flutter_ble_peripheral/'
      'FlutterBlePeripheralPlugin.kt',
    ).readAsStringSync();

    expect(
      manager,
      matches(
        RegExp(
          r'private val bluetoothLeAdvertiser:[\s\S]{0,240}?get\(\)'
          r'[\s\S]{0,240}?mBluetoothManager\?\.adapter\?\.'
          r'bluetoothLeAdvertiser',
        ),
      ),
    );
    expect(manager, contains('ADVERTISE_FAILED_FEATURE_UNSUPPORTED'));
    expect(manager, isNot(contains('mBluetoothLeAdvertiser!!')));
    expect(manager, isNot(contains('bluetoothLeAdvertiser!!')));
    expect(plugin, contains('PackageManager.FEATURE_BLUETOOTH_LE'));
  });

  test('vendored Darwin peripheral is lazy and does not log beacon data', () {
    final root =
        'packages/flutter_ble_peripheral/darwin/flutter_ble_peripheral/'
        'Sources/flutter_ble_peripheral';
    final plugin = File('$root/FlutterBlePeripheralPlugin.swift')
        .readAsStringSync();
    final manager = File('$root/FlutterBlePeripheralManager.swift')
        .readAsStringSync();
    final delegate = File('$root/Delegates/PeripheralManagerDelegate.swift')
        .readAsStringSync();

    expect(plugin, contains('private lazy var flutterBlePeripheralManager'));
    expect(
      plugin,
      isNot(
        contains(
          'self.flutterBlePeripheralManager = FlutterBlePeripheralManager(',
        ),
      ),
    );
    expect(RegExp(r'print\([^\n]*advertisementData').hasMatch(plugin), isFalse);
    expect(
      RegExp(r'print\([^\n]*advertisementData').hasMatch(manager),
      isFalse,
    );
    expect(
      delegate,
      matches(
        RegExp(
          r'guard error == nil else \{[\s\S]{0,500}?'
          r'publishPeripheralState\(state: \.idle\)',
        ),
      ),
    );
  });

  test('Android declares optional foreground BLE capabilities safely', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final proguard = File('android/app/proguard-rules.pro').readAsStringSync();

    expect(
      manifest,
      matches(
        RegExp(
          r'android\.hardware\.bluetooth_le"\s+android:required="false"',
          multiLine: true,
        ),
      ),
    );
    for (final permission in const [
      'BLUETOOTH_SCAN',
      'BLUETOOTH_ADVERTISE',
      'BLUETOOTH_CONNECT',
      'BLUETOOTH',
      'BLUETOOTH_ADMIN',
      'ACCESS_FINE_LOCATION',
      'ACCESS_COARSE_LOCATION',
    ]) {
      expect(manifest, contains('android.permission.$permission'));
    }
    expect(
      manifest,
      matches(
        RegExp(
          r'android\.permission\.BLUETOOTH_SCAN"\s+'
          r'android:usesPermissionFlags="neverForLocation"',
          multiLine: true,
        ),
      ),
    );
    expect(proguard, contains('com.jmx.flutter_blue_plus.**'));
    expect(proguard, contains('com.lib.flutter_blue_plus.**'));
  });

  test('iOS explains Bluetooth without enabling background presence', () {
    final info = File('ios/Runner/Info.plist').readAsStringSync();

    expect(info, contains('<key>NSBluetoothAlwaysUsageDescription</key>'));
    expect(info, isNot(contains('<key>UIBackgroundModes</key>')));
    expect(info, isNot(contains('<string>bluetooth-central</string>')));
    expect(info, isNot(contains('<string>bluetooth-peripheral</string>')));
  });

  test('third-party notice records BLE licenses and release constraint', () {
    final notices = File('THIRD_PARTY_NOTICES.md').readAsStringSync();

    expect(notices, contains('flutter_ble_peripheral'));
    expect(notices, contains('BSD 3-Clause License'));
    expect(notices, contains('flutter_blue_plus'));
    expect(notices, contains('paid commercial license'));
  });
}
