import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:share_plus/share_plus.dart';

typedef ShareInvocation = Future<ShareResult> Function(ShareParams params);

final inviteShareServiceProvider = Provider<InviteShareService>(
  (ref) => InviteShareService(),
);

class InviteShareService {
  InviteShareService({ShareInvocation? share})
    : _share = share ?? SharePlus.instance.share;

  final ShareInvocation _share;

  Future<void> shareInvitation(
    Uri invitationUri, {
    Rect? sharePositionOrigin,
  }) async {
    await _share(
      ShareParams(
        text: 'Join my family on Keepers.\n$invitationUri',
        sharePositionOrigin: _usableOrigin(sharePositionOrigin),
      ),
    );
  }

  Future<void> shareFamilyLink(FamilyCode code, {Rect? sharePositionOrigin}) =>
      shareInvitation(code.joinUri, sharePositionOrigin: sharePositionOrigin);

  Future<void> shareGatheringNudge({Rect? sharePositionOrigin}) async {
    await _share(
      ShareParams(
        text: 'Come open this week with us in Keepers.',
        sharePositionOrigin: _usableOrigin(sharePositionOrigin),
      ),
    );
  }

  Rect? _usableOrigin(Rect? origin) {
    if (origin == null || origin.isEmpty || !origin.isFinite) return null;
    return origin;
  }

  @override
  String toString() => 'InviteShareService()';
}
