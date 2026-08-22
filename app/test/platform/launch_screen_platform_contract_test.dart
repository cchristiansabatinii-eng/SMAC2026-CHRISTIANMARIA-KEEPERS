import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native launch surfaces match the black Keepers opening frame', () {
    final androidBase = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    final androidV21 = File(
      'android/app/src/main/res/drawable-v21/launch_background.xml',
    ).readAsStringSync();
    final androidColorsFile = File(
      'android/app/src/main/res/values/colors.xml',
    );
    final androidV31File = File(
      'android/app/src/main/res/values-v31/styles.xml',
    );
    expect(androidColorsFile.existsSync(), isTrue);
    expect(androidV31File.existsSync(), isTrue);
    if (!androidColorsFile.existsSync() || !androidV31File.existsSync()) return;
    final androidColors = androidColorsFile.readAsStringSync();
    final androidV31 = androidV31File.readAsStringSync();
    final ios = File('ios/Runner/Base.lproj/LaunchScreen.storyboard')
        .readAsStringSync();
    final androidWordmark = File(
      'android/app/src/main/res/drawable-mdpi/keepers_launch_wordmark.png',
    );
    final iosWordmarks = <File>[
      File('ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png'),
      File(
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png',
      ),
      File(
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png',
      ),
    ];

    expect(androidBase, contains('@color/keepers_launch_ground'));
    expect(androidV21, contains('@color/keepers_launch_ground'));
    expect(androidBase, contains('@drawable/keepers_launch_wordmark'));
    expect(androidV21, contains('@drawable/keepers_launch_wordmark'));
    expect(androidColors, contains('#0B0A08'));
    expect(
      androidV31,
      contains(
        '<item name="android:windowSplashScreenBackground">@color/keepers_launch_ground</item>',
      ),
    );
    expect(
      androidV31,
      contains(
        '<item name="android:windowSplashScreenAnimatedIcon">@drawable/keepers_launch_wordmark</item>',
      ),
    );
    expect(androidWordmark.existsSync(), isTrue);
    expect(androidWordmark.lengthSync(), greaterThan(1000));
    expect(
      File(
        'android/app/src/main/res/drawable-nodpi/keepers_launch_wordmark.png',
      ).existsSync(),
      isFalse,
      reason: 'nodpi makes the pre-Android 12 logo too small on dense screens',
    );
    for (final wordmark in iosWordmarks) {
      expect(wordmark.lengthSync(), greaterThan(1000));
    }
    expect(ios, contains('image="LaunchImage"'));
    expect(ios, contains('red="0.0431372549"'));
    expect(ios, contains('green="0.0392156863"'));
    expect(ios, contains('blue="0.0313725490"'));
    expect(androidBase, isNot(contains('@android:color/white')));
  });
}
