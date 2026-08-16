import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';
import 'package:path/path.dart' as p;

const _safeScreenshotNames = <String>{
  'family-invitation-flow-success',
  'setup-choice-390x844-text-1_4',
  'setup-manual-join-390x844-text-1_4',
  'wheel-local-only-390x844-text-1_4',
  'invite-unconfigured-390x844-text-1_4',
  'invite-owner-email-390x844-text-1_4',
  'invite-owner-otp-390x844-text-1_4',
  'invite-owner-ready-recipient-entry-390x844-text-1_4',
  'invite-creating-390x844-text-1_4',
  'invite-pending-390x844-text-1_4',
  'invite-sharing-390x844-text-1_4',
  'invite-revoke-failure-390x844-text-1_4',
  'join-loading-390x844-text-1_4',
  'join-email-390x844-text-1_4',
  'join-otp-390x844-text-1_4',
  'join-preview-390x844-text-1_4',
  'join-joining-390x844-text-1_4',
  'join-keyboard-open-390x844-text-1_4',
  'join-recoverable-failure-390x844-text-1_4',
  'join-protected-failure-390x844-text-1_4',
  'join-long-content-reduced-motion-390x844-text-1_4',
  'wheel-post-acceptance-reduced-motion-390x844-text-1_4',
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
