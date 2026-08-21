import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';
import 'package:path/path.dart' as p;

const _qaStates = <String>{
  'main-code-loaded',
  'main-code-offline',
  'noncreator-code-sheet',
  'creator-regeneration-confirmation',
  'manual-code-entry',
  'family-preview',
  'pending-cancel',
  'join-request-notice',
  'approval-sheet',
  'decline',
  'expiry',
  'invitation-changed',
  'network-failure-retry',
  'installed-avatar-arrival',
};

const _qaSizes = <String>{'390x844', '430x932'};

final _safeScreenshotNames = <String>{
  'family-code-flow-success',
  for (final size in _qaSizes)
    for (final state in _qaStates) '$state-$size-text-1_4-reduced-motion',
};

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: null,
    onScreenshot: (name, bytes, [args]) async {
      if (!_safeScreenshotNames.contains(name) || bytes.isEmpty) return false;
      final pass = Platform.environment['KEEPERS_INVITATION_SCREENSHOT_PASS'];
      if (pass != 'pass-1' && pass != 'pass-2') {
        throw StateError(
          'KEEPERS_INVITATION_SCREENSHOT_PASS must be pass-1 or pass-2',
        );
      }
      final directory = Directory(
        p.join('outputs', 'family-invitations', pass),
      );
      await directory.create(recursive: true);
      await File(p.join(directory.path, '$name.png'))
          .writeAsBytes(bytes, flush: true);
      return true;
    },
  );
}
