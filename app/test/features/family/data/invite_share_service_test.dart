import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/invite_share_service.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test(
    'shares one text payload with message, URI, and usable origin',
    () async {
      final calls = <ShareParams>[];
      final service = InviteShareService(
        share: (params) async {
          calls.add(params);
          return const ShareResult('ignored', ShareResultStatus.dismissed);
        },
      );
      final link = Uri.parse(
        'keepers://join?v=1&i=11111111-1111-4111-8111-111111111111&t=token&s=secret',
      );
      const origin = Rect.fromLTWH(12, 24, 48, 48);

      await service.shareInvitation(link, sharePositionOrigin: origin);

      expect(calls, hasLength(1));
      expect(calls.single.text, contains('Join my family on Keepers'));
      expect(calls.single.text, contains(link.toString()));
      expect(calls.single.uri, isNull);
      expect(calls.single.sharePositionOrigin, origin);
    },
  );

  test('dismissed and unavailable results are deliberately ignored', () async {
    for (final status in [
      ShareResultStatus.dismissed,
      ShareResultStatus.unavailable,
    ]) {
      final service = InviteShareService(
        share: (_) async => ShareResult('private result', status),
      );

      await expectLater(
        service.shareInvitation(Uri.parse('keepers://join')),
        completes,
      );
    }
  });

  test('nudge copy contains no invitation capability', () async {
    late ShareParams call;
    final service = InviteShareService(
      share: (params) async {
        call = params;
        return const ShareResult('', ShareResultStatus.unavailable);
      },
    );

    await service.shareGatheringNudge();

    expect(call.text, contains('Come open this week with us in Keepers'));
    expect(call.text, isNot(contains('keepers://join')));
    expect(call.uri, isNull);
  });
}
