import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cloud auth begins observing before invitation routing consumes cold links',
    () {
      final startup = File('lib/main.dart').readAsStringSync();
      final cloudBootstrap = startup.indexOf(
        'final configuredGateway = await cloudGatewayLoader()',
      );
      final inviteSource = startup.indexOf(
        'AppLinksInviteUriSource(AppLinks())',
      );
      final inviteResolution = startup.indexOf(
        'inviteLinkCoordinator.resolveInitialLink()',
      );

      expect(cloudBootstrap, greaterThanOrEqualTo(0));
      expect(inviteSource, greaterThan(cloudBootstrap));
      expect(inviteResolution, greaterThan(inviteSource));
    },
  );

  test(
    'Android routes verified family links and auth callbacks separately',
    () {
      final android = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();

      final familyLinkFilter = RegExp(
        r'<intent-filter android:autoVerify="true">\s*<action android:name="android.intent.action.VIEW"/>\s*<category android:name="android.intent.category.DEFAULT"/>\s*<category android:name="android.intent.category.BROWSABLE"/>\s*<data android:scheme="https" android:host="join\.keepers\.app" android:pathPrefix="/f/"/>\s*</intent-filter>',
        multiLine: true,
      );
      final authCallbackFilter = RegExp(
        r'<intent-filter>\s*<action android:name="android.intent.action.VIEW"/>\s*<category android:name="android.intent.category.DEFAULT"/>\s*<category android:name="android.intent.category.BROWSABLE"/>\s*<data android:scheme="keepers" android:host="auth-callback"/>\s*</intent-filter>',
        multiLine: true,
      );

      expect(familyLinkFilter.allMatches(android), hasLength(1));
      expect(authCallbackFilter.allMatches(android), hasLength(1));
      expect(
        RegExp(r'android:autoVerify="true"').allMatches(android),
        hasLength(1),
      );
      expect(
        RegExp(r'android:host="join\.keepers\.app"').allMatches(android),
        hasLength(1),
      );
      expect(
        RegExp(r'android:pathPrefix="/f/"').allMatches(android),
        hasLength(1),
      );
      expect(RegExp(r'android:host="join"').allMatches(android), isEmpty);
      expect(
        RegExp(r'android:scheme="keepers"').allMatches(android),
        hasLength(1),
      );
      expect(
        android,
        contains(
          'android:name="flutter_deeplinking_enabled" android:value="false"',
        ),
      );
      expect(android, contains('android.permission.INTERNET'));
      final permissions = RegExp(r'<uses-permission android:name="([^"]+)"')
          .allMatches(android)
          .map((match) => match.group(1))
          .toSet();
      expect(permissions, {
        'android.permission.CAMERA',
        'android.permission.RECORD_AUDIO',
        'android.permission.INTERNET',
      });
    },
  );

  test(
    'iOS retains auth routing and signs both universal-link entitlements',
    () {
      final info = File('ios/Runner/Info.plist').readAsStringSync();
      final debugEntitlements = File('ios/Runner/DebugProfile.entitlements')
          .readAsStringSync();
      final releaseEntitlements = File('ios/Runner/Release.entitlements')
          .readAsStringSync();
      final project = File('ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();

      expect(
        RegExp(
          r'<key>CFBundleURLSchemes</key>\s*<array>\s*<string>keepers</string>\s*</array>',
          multiLine: true,
        ).allMatches(info),
        hasLength(1),
      );
      expect(
        RegExp(
          r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>',
          multiLine: true,
        ).hasMatch(info),
        isTrue,
      );
      expect(info, isNot(contains('CFBundleURLQuerySchemes')));

      for (final entitlements in [debugEntitlements, releaseEntitlements]) {
        expect(
          RegExp(
            r'<key>com\.apple\.developer\.associated-domains</key>\s*<array>\s*<string>applinks:join\.keepers\.app</string>\s*</array>',
            multiLine: true,
          ).allMatches(entitlements),
          hasLength(1),
        );
        expect(
          RegExp(r'applinks:join\.keepers\.app').allMatches(entitlements),
          hasLength(1),
        );
        expect(entitlements, contains('<key>keychain-access-groups</key>'));
      }
      expect(
        RegExp(r'CODE_SIGN_ENTITLEMENTS = Runner/DebugProfile\.entitlements;')
            .allMatches(project),
        hasLength(1),
      );
      expect(
        RegExp(r'CODE_SIGN_ENTITLEMENTS = Runner/Release\.entitlements;')
            .allMatches(project),
        hasLength(2),
      );
      expect(project, isNot(contains('Runner/Runner.entitlements')));
      expect(File('ios/Runner/Runner.entitlements').existsSync(), isFalse);
    },
  );
}
