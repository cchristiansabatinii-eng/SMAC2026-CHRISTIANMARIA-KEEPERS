import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('launcher icons use an edge-to-edge black field and compact white key', () async {
    const expectedSizes = <String, int>{
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
      'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
      'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
      'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png': 20,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png': 40,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png': 60,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png': 29,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png': 58,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png': 87,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png': 40,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png': 80,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png':
          120,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png':
          120,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png':
          180,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png': 76,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png':
          152,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png':
          167,
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png':
          1024,
    };

    for (final entry in expectedSizes.entries) {
      final icon = await _decodeIcon(entry.key);
      expect(icon.width, entry.value, reason: entry.key);
      expect(icon.height, entry.value, reason: entry.key);

      for (final point in [
        (x: 0, y: 0),
        (x: icon.width - 1, y: 0),
        (x: 0, y: icon.height - 1),
        (x: icon.width - 1, y: icon.height - 1),
      ]) {
        final pixel = _pixel(icon, point.x, point.y);
        expect(pixel.alpha, 255, reason: '${entry.key} $point');
        expect(pixel.maxChannel, 0, reason: entry.key);
      }
    }

    final master = await _decodeIcon(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
      'Icon-App-1024x1024@1x.png',
    );
    final center = _pixel(master, master.width ~/ 2, master.height ~/ 2);
    final shaft = _pixel(master, master.width * 42 ~/ 100, master.height ~/ 2);
    final keyhole = _pixel(
      master,
      master.width ~/ 2,
      master.height * 35 ~/ 100,
    );
    expect(center.maxChannel, lessThanOrEqualTo(8));
    expect(shaft.minChannel, greaterThanOrEqualTo(245));
    expect(keyhole.maxChannel, lessThanOrEqualTo(8));

    var darkPixels = 0;
    var whitePixels = 0;
    var nonGrayscalePixels = 0;
    var brightLeft = master.width;
    var brightTop = master.height;
    var brightRight = -1;
    var brightBottom = -1;
    for (var y = 0; y < master.height; y++) {
      for (var x = 0; x < master.width; x++) {
        final pixel = _pixel(master, x, y);
        if (pixel.maxChannel <= 8) darkPixels++;
        if (pixel.minChannel >= 245) {
          whitePixels++;
          brightLeft = brightLeft < x ? brightLeft : x;
          brightTop = brightTop < y ? brightTop : y;
          brightRight = brightRight > x ? brightRight : x;
          brightBottom = brightBottom > y ? brightBottom : y;
        }
        if (pixel.maxChannel - pixel.minChannel > 2) nonGrayscalePixels++;
      }
    }

    final pixelCount = master.width * master.height;
    expect(darkPixels / pixelCount, greaterThan(.90));
    expect(whitePixels / pixelCount, inInclusiveRange(.045, .075));
    expect(nonGrayscalePixels / pixelCount, lessThan(.001));
    expect(brightLeft / master.width, inInclusiveRange(.35, .40));
    expect(brightRight / master.width, inInclusiveRange(.60, .65));
    expect(brightTop / master.height, inInclusiveRange(.25, .31));
    expect(brightBottom / master.height, inInclusiveRange(.70, .76));
  });

  test(
    'Android adaptive icon owns its black mask without a white badge',
    () async {
      final adaptiveIcon = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      );
      final background = File(
        'android/app/src/main/res/values/ic_launcher_background.xml',
      );
      expect(adaptiveIcon.existsSync(), isTrue);
      expect(background.existsSync(), isTrue);
      expect(
        adaptiveIcon.readAsStringSync(),
        allOf(
          contains('@color/ic_launcher_background'),
          contains('@drawable/ic_launcher_foreground'),
        ),
      );
      expect(background.readAsStringSync(), contains('#000000'));

      const foregroundSizes = <String, int>{
        'android/app/src/main/res/drawable-mdpi/ic_launcher_foreground.png':
            108,
        'android/app/src/main/res/drawable-hdpi/ic_launcher_foreground.png':
            162,
        'android/app/src/main/res/drawable-xhdpi/ic_launcher_foreground.png':
            216,
        'android/app/src/main/res/drawable-xxhdpi/ic_launcher_foreground.png':
            324,
        'android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png':
            432,
      };
      for (final entry in foregroundSizes.entries) {
        final foreground = await _decodeIcon(entry.key);
        expect(foreground.width, entry.value, reason: entry.key);
        expect(foreground.height, entry.value, reason: entry.key);
        expect(_pixel(foreground, 0, 0).alpha, 0, reason: entry.key);
        final keyStroke = _pixel(
          foreground,
          foreground.width * 42 ~/ 100,
          foreground.height ~/ 2,
        );
        expect(keyStroke.alpha, greaterThanOrEqualTo(245), reason: entry.key);
        expect(
          keyStroke.minChannel,
          greaterThanOrEqualTo(245),
          reason: entry.key,
        );

        final center = _pixel(
          foreground,
          foreground.width ~/ 2,
          foreground.height ~/ 2,
        );
        expect(center.alpha, lessThanOrEqualTo(8), reason: entry.key);

        final keyhole = _pixel(
          foreground,
          foreground.width ~/ 2,
          foreground.height * 42 ~/ 100,
        );
        expect(
          keyhole.alpha,
          lessThanOrEqualTo(8),
          reason: '${entry.key} keyhole',
        );

        var visiblePixels = 0;
        var maxRadiusSquared = 0.0;
        var visibleLeft = foreground.width;
        var visibleTop = foreground.height;
        var visibleRight = -1;
        var visibleBottom = -1;
        for (var y = 0; y < foreground.height; y++) {
          for (var x = 0; x < foreground.width; x++) {
            if (_pixel(foreground, x, y).alpha < 128) continue;
            visiblePixels++;
            visibleLeft = visibleLeft < x ? visibleLeft : x;
            visibleTop = visibleTop < y ? visibleTop : y;
            visibleRight = visibleRight > x ? visibleRight : x;
            visibleBottom = visibleBottom > y ? visibleBottom : y;
            final dx = x + .5 - foreground.width / 2;
            final dy = y + .5 - foreground.height / 2;
            final radiusSquared = dx * dx + dy * dy;
            if (radiusSquared > maxRadiusSquared) {
              maxRadiusSquared = radiusSquared;
            }
          }
        }
        final pixelCount = foreground.width * foreground.height;
        expect(
          visiblePixels / pixelCount,
          inInclusiveRange(.020, .040),
          reason: '${entry.key} alpha coverage',
        );
        expect(
          visibleLeft / foreground.width,
          inInclusiveRange(.39, .44),
          reason: '${entry.key} left bound',
        );
        expect(
          visibleRight / foreground.width,
          inInclusiveRange(.56, .61),
          reason: '${entry.key} right bound',
        );
        expect(
          visibleTop / foreground.height,
          inInclusiveRange(.33, .38),
          reason: '${entry.key} top bound',
        );
        expect(
          visibleBottom / foreground.height,
          inInclusiveRange(.63, .68),
          reason: '${entry.key} bottom bound',
        );
        final safeRadius = foreground.width * 33 / 108;
        expect(
          maxRadiusSquared,
          lessThanOrEqualTo(safeRadius * safeRadius),
          reason: '${entry.key} adaptive safe zone',
        );
      }
    },
  );
}

Future<({int width, int height, Uint8List rgba})> _decodeIcon(
  String path,
) async {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: path);
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = (
    width: frame.image.width,
    height: frame.image.height,
    rgba: data!.buffer.asUint8List(),
  );
  frame.image.dispose();
  codec.dispose();
  return result;
}

({int red, int green, int blue, int alpha, int minChannel, int maxChannel})
_pixel(({int width, int height, Uint8List rgba}) image, int x, int y) {
  final offset = (y * image.width + x) * 4;
  final red = image.rgba[offset];
  final green = image.rgba[offset + 1];
  final blue = image.rgba[offset + 2];
  return (
    red: red,
    green: green,
    blue: blue,
    alpha: image.rgba[offset + 3],
    minChannel: [
      red,
      green,
      blue,
    ].reduce((left, right) => left < right ? left : right),
    maxChannel: [
      red,
      green,
      blue,
    ].reduce((left, right) => left > right ? left : right),
  );
}
