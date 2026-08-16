import 'dart:convert';

import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_member.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';

export 'family_join_failure.dart';

enum FamilyJoinRequestState {
  pending,
  approved,
  installed,
  declined,
  cancelled,
  expired,
}

enum FamilyJoinRequestCancelReason { requester, codeRegenerated }

final class FamilyJoinPreview {
  FamilyJoinPreview({
    required this.familyId,
    required this.familyName,
    required this.codeVersion,
    required List<FamilyMember> members,
  }) : members = List<FamilyMember>.unmodifiable(members);

  final String familyId;
  final String familyName;
  final int codeVersion;
  final List<FamilyMember> members;

  factory FamilyJoinPreview.validated({
    required String familyId,
    required String familyName,
    required int codeVersion,
    required List<FamilyMember> members,
  }) {
    _requireUuid(familyId, 'familyId');
    _requireNonEmpty(familyName, 'familyName');
    _requirePositive(codeVersion, 'codeVersion');
    _requireRoster(members, familyId: familyId);
    return FamilyJoinPreview(
      familyId: familyId,
      familyName: familyName,
      codeVersion: codeVersion,
      members: members,
    );
  }
}

final class FamilyJoinProfileDraft {
  const FamilyJoinProfileDraft({
    required this.memberId,
    required this.displayName,
    required this.demographicRole,
    required this.colorToken,
    required this.avatar,
    required this.joiningPublicKey,
  });

  final String memberId;
  final String displayName;
  final FamilyDemographicRole demographicRole;
  final String colorToken;
  final AvatarConfig avatar;
  final String joiningPublicKey;

  factory FamilyJoinProfileDraft.validated({
    required String memberId,
    required String displayName,
    required FamilyDemographicRole demographicRole,
    required String colorToken,
    required AvatarConfig avatar,
    required String joiningPublicKey,
  }) {
    _requireProfile(
      memberId: memberId,
      displayName: displayName,
      colorToken: colorToken,
      avatar: avatar,
      joiningPublicKey: joiningPublicKey,
    );
    return FamilyJoinProfileDraft(
      memberId: memberId,
      displayName: displayName,
      demographicRole: demographicRole,
      colorToken: colorToken,
      avatar: avatar,
      joiningPublicKey: joiningPublicKey,
    );
  }
}

final class FamilyJoinRequestDraft {
  const FamilyJoinRequestDraft({required this.code, required this.profile});

  final FamilyCode code;
  final FamilyJoinProfileDraft profile;

  factory FamilyJoinRequestDraft.validated({
    required FamilyCode code,
    required FamilyJoinProfileDraft profile,
  }) {
    _requireProfile(
      memberId: profile.memberId,
      displayName: profile.displayName,
      colorToken: profile.colorToken,
      avatar: profile.avatar,
      joiningPublicKey: profile.joiningPublicKey,
    );
    return FamilyJoinRequestDraft(code: code, profile: profile);
  }
}

final class PendingFamilyJoinRequest {
  PendingFamilyJoinRequest({
    required this.requestId,
    required this.familyId,
    required this.requesterAccountId,
    required this.memberId,
    required this.displayName,
    required this.demographicRole,
    required this.colorToken,
    required this.avatar,
    required this.joiningPublicKey,
    required this.codeVersion,
    required this.state,
    required DateTime createdAt,
    required DateTime expiresAt,
  }) : createdAt = createdAt.toUtc(),
       expiresAt = expiresAt.toUtc();

  final String requestId;
  final String familyId;
  final String requesterAccountId;
  final String memberId;
  final String displayName;
  final FamilyDemographicRole demographicRole;
  final String colorToken;
  final AvatarConfig avatar;
  final String joiningPublicKey;
  final int codeVersion;
  final FamilyJoinRequestState state;
  final DateTime createdAt;
  final DateTime expiresAt;

  factory PendingFamilyJoinRequest.validated({
    required String requestId,
    required String familyId,
    required String requesterAccountId,
    required String memberId,
    required String displayName,
    required FamilyDemographicRole demographicRole,
    required String colorToken,
    required AvatarConfig avatar,
    required String joiningPublicKey,
    required int codeVersion,
    required FamilyJoinRequestState state,
    required DateTime createdAt,
    required DateTime expiresAt,
  }) {
    _requireRequestFields(
      requestId: requestId,
      familyId: familyId,
      requesterAccountId: requesterAccountId,
      memberId: memberId,
      displayName: displayName,
      colorToken: colorToken,
      avatar: avatar,
      joiningPublicKey: joiningPublicKey,
      codeVersion: codeVersion,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
    return PendingFamilyJoinRequest(
      requestId: requestId,
      familyId: familyId,
      requesterAccountId: requesterAccountId,
      memberId: memberId,
      displayName: displayName,
      demographicRole: demographicRole,
      colorToken: colorToken,
      avatar: avatar,
      joiningPublicKey: joiningPublicKey,
      codeVersion: codeVersion,
      state: state,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}

final class JoinEnvelopeContext {
  const JoinEnvelopeContext({
    required this.requestId,
    required this.familyId,
    required this.requesterAccountId,
    required this.codeVersion,
  });

  final String requestId;
  final String familyId;
  final String requesterAccountId;
  final int codeVersion;

  factory JoinEnvelopeContext.validated({
    required String requestId,
    required String familyId,
    required String requesterAccountId,
    required int codeVersion,
  }) {
    _requireUuid(requestId, 'requestId');
    _requireUuid(familyId, 'familyId');
    _requireUuid(requesterAccountId, 'requesterAccountId');
    _requirePositive(codeVersion, 'codeVersion');
    return JoinEnvelopeContext(
      requestId: requestId,
      familyId: familyId,
      requesterAccountId: requesterAccountId,
      codeVersion: codeVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JoinEnvelopeContext &&
          other.requestId == requestId &&
          other.familyId == familyId &&
          other.requesterAccountId == requesterAccountId &&
          other.codeVersion == codeVersion;

  @override
  int get hashCode =>
      Object.hash(requestId, familyId, requesterAccountId, codeVersion);
}

final class FamilyJoinApprovalEnvelope {
  static const currentVersion = 1;

  const FamilyJoinApprovalEnvelope({
    required this.version,
    required this.context,
    required this.ephemeralPublicKey,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  final int version;
  final JoinEnvelopeContext context;
  final String ephemeralPublicKey;
  final String nonce;
  final String ciphertext;
  final String mac;

  factory FamilyJoinApprovalEnvelope.validated({
    required int version,
    required JoinEnvelopeContext context,
    required String ephemeralPublicKey,
    required String nonce,
    required String ciphertext,
    required String mac,
  }) {
    _requireEnvelopeFields(
      version: version,
      context: context,
      ephemeralPublicKey: ephemeralPublicKey,
      nonce: nonce,
      ciphertext: ciphertext,
      mac: mac,
    );
    return FamilyJoinApprovalEnvelope(
      version: version,
      context: context,
      ephemeralPublicKey: ephemeralPublicKey,
      nonce: nonce,
      ciphertext: ciphertext,
      mac: mac,
    );
  }

  factory FamilyJoinApprovalEnvelope.fromJson(Map<String, Object?> json) {
    const fields = {
      'version',
      'requestId',
      'familyId',
      'requesterAccountId',
      'codeVersion',
      'ephemeralPublicKey',
      'nonce',
      'ciphertext',
      'mac',
    };
    if (json.length != fields.length || !fields.every(json.containsKey)) {
      throw const FormatException('Invalid family join envelope fields');
    }
    final version = json['version'];
    final requestId = json['requestId'];
    final familyId = json['familyId'];
    final requesterAccountId = json['requesterAccountId'];
    final codeVersion = json['codeVersion'];
    final ephemeralPublicKey = json['ephemeralPublicKey'];
    final nonce = json['nonce'];
    final ciphertext = json['ciphertext'];
    final mac = json['mac'];
    if (version is! int ||
        requestId is! String ||
        familyId is! String ||
        requesterAccountId is! String ||
        codeVersion is! int ||
        ephemeralPublicKey is! String ||
        nonce is! String ||
        ciphertext is! String ||
        mac is! String) {
      throw const FormatException('Invalid family join envelope values');
    }
    try {
      return FamilyJoinApprovalEnvelope.validated(
        version: version,
        context: JoinEnvelopeContext(
          requestId: requestId,
          familyId: familyId,
          requesterAccountId: requesterAccountId,
          codeVersion: codeVersion,
        ),
        ephemeralPublicKey: ephemeralPublicKey,
        nonce: nonce,
        ciphertext: ciphertext,
        mac: mac,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid family join envelope values', error);
    }
  }

  Map<String, Object> toJson() => {
    'version': version,
    'requestId': context.requestId,
    'familyId': context.familyId,
    'requesterAccountId': context.requesterAccountId,
    'codeVersion': context.codeVersion,
    'ephemeralPublicKey': ephemeralPublicKey,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'mac': mac,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyJoinApprovalEnvelope &&
          other.version == version &&
          other.context == context &&
          other.ephemeralPublicKey == ephemeralPublicKey &&
          other.nonce == nonce &&
          other.ciphertext == ciphertext &&
          other.mac == mac;

  @override
  int get hashCode =>
      Object.hash(version, context, ephemeralPublicKey, nonce, ciphertext, mac);

  @override
  String toString() => 'FamilyJoinApprovalEnvelope(<redacted>)';
}

final class OwnFamilyJoinRequest {
  OwnFamilyJoinRequest({
    required this.requestId,
    required this.familyId,
    required this.familyName,
    required this.requesterAccountId,
    required this.memberId,
    required this.displayName,
    required this.demographicRole,
    required this.colorToken,
    required this.avatar,
    required this.joiningPublicKey,
    required this.codeVersion,
    required this.state,
    required DateTime createdAt,
    required DateTime expiresAt,
    this.cancelReason,
    this.approvalEnvelope,
    List<FamilyMember> roster = const [],
  }) : createdAt = createdAt.toUtc(),
       expiresAt = expiresAt.toUtc(),
       roster = List<FamilyMember>.unmodifiable(roster);

  final String requestId;
  final String familyId;
  final String familyName;
  final String requesterAccountId;
  final String memberId;
  final String displayName;
  final FamilyDemographicRole demographicRole;
  final String colorToken;
  final AvatarConfig avatar;
  final String joiningPublicKey;
  final int codeVersion;
  final FamilyJoinRequestState state;
  final DateTime createdAt;
  final DateTime expiresAt;
  final FamilyJoinRequestCancelReason? cancelReason;
  final FamilyJoinApprovalEnvelope? approvalEnvelope;
  final List<FamilyMember> roster;

  factory OwnFamilyJoinRequest.validated({
    required String requestId,
    required String familyId,
    required String familyName,
    required String requesterAccountId,
    required String memberId,
    required String displayName,
    required FamilyDemographicRole demographicRole,
    required String colorToken,
    required AvatarConfig avatar,
    required String joiningPublicKey,
    required int codeVersion,
    required FamilyJoinRequestState state,
    required DateTime createdAt,
    required DateTime expiresAt,
    FamilyJoinRequestCancelReason? cancelReason,
    FamilyJoinApprovalEnvelope? approvalEnvelope,
    List<FamilyMember> roster = const [],
  }) {
    _requireRequestFields(
      requestId: requestId,
      familyId: familyId,
      requesterAccountId: requesterAccountId,
      memberId: memberId,
      displayName: displayName,
      colorToken: colorToken,
      avatar: avatar,
      joiningPublicKey: joiningPublicKey,
      codeVersion: codeVersion,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
    _requireNonEmpty(familyName, 'familyName');
    _requireRoster(roster, familyId: familyId);
    if (state == FamilyJoinRequestState.approved && approvalEnvelope == null) {
      throw ArgumentError.value(
        approvalEnvelope,
        'approvalEnvelope',
        'Required when approved',
      );
    }
    if ((state == FamilyJoinRequestState.cancelled) != (cancelReason != null)) {
      throw ArgumentError.value(
        cancelReason,
        'cancelReason',
        'Required only when cancelled',
      );
    }
    if (approvalEnvelope != null) {
      _requireEnvelopeMatches(
        approvalEnvelope,
        requestId: requestId,
        familyId: familyId,
        requesterAccountId: requesterAccountId,
        codeVersion: codeVersion,
      );
    }
    return OwnFamilyJoinRequest(
      requestId: requestId,
      familyId: familyId,
      familyName: familyName,
      requesterAccountId: requesterAccountId,
      memberId: memberId,
      displayName: displayName,
      demographicRole: demographicRole,
      colorToken: colorToken,
      avatar: avatar,
      joiningPublicKey: joiningPublicKey,
      codeVersion: codeVersion,
      state: state,
      createdAt: createdAt,
      expiresAt: expiresAt,
      cancelReason: cancelReason,
      approvalEnvelope: approvalEnvelope,
      roster: roster,
    );
  }
}

final class FamilyJoinDecision {
  FamilyJoinDecision({
    required this.requestId,
    required this.familyId,
    required this.state,
    required DateTime updatedAt,
  }) : updatedAt = updatedAt.toUtc();

  final String requestId;
  final String familyId;
  final FamilyJoinRequestState state;
  final DateTime updatedAt;

  factory FamilyJoinDecision.validated({
    required String requestId,
    required String familyId,
    required FamilyJoinRequestState state,
    required DateTime updatedAt,
  }) {
    _requireUuid(requestId, 'requestId');
    _requireUuid(familyId, 'familyId');
    return FamilyJoinDecision(
      requestId: requestId,
      familyId: familyId,
      state: state,
      updatedAt: updatedAt,
    );
  }
}

final class ApprovedFamilyJoin {
  ApprovedFamilyJoin({
    required this.requestId,
    required this.familyId,
    required this.familyName,
    required this.localMemberId,
    required this.joiningPublicKey,
    required this.approvalEnvelope,
    required List<FamilyMember> roster,
  }) : roster = List<FamilyMember>.unmodifiable(roster);

  final String requestId;
  final String familyId;
  final String familyName;
  final String localMemberId;
  final String joiningPublicKey;
  final FamilyJoinApprovalEnvelope approvalEnvelope;
  final List<FamilyMember> roster;

  factory ApprovedFamilyJoin.validated({
    required String requestId,
    required String familyId,
    required String familyName,
    required String localMemberId,
    required String joiningPublicKey,
    required FamilyJoinApprovalEnvelope approvalEnvelope,
    required List<FamilyMember> roster,
  }) {
    _requireUuid(requestId, 'requestId');
    _requireUuid(familyId, 'familyId');
    _requireNonEmpty(familyName, 'familyName');
    _requireUuid(localMemberId, 'localMemberId');
    _requirePublicKey(joiningPublicKey);
    _requireRoster(roster, familyId: familyId);
    if (!roster.any((member) => member.id == localMemberId)) {
      throw ArgumentError.value(
        localMemberId,
        'localMemberId',
        'Must be in roster',
      );
    }
    _requireEnvelopeMatches(
      approvalEnvelope,
      requestId: requestId,
      familyId: familyId,
      requesterAccountId: approvalEnvelope.context.requesterAccountId,
      codeVersion: approvalEnvelope.context.codeVersion,
    );
    return ApprovedFamilyJoin(
      requestId: requestId,
      familyId: familyId,
      familyName: familyName,
      localMemberId: localMemberId,
      joiningPublicKey: joiningPublicKey,
      approvalEnvelope: approvalEnvelope,
      roster: roster,
    );
  }
}

bool isCanonicalFamilyJoinUuid(String value) =>
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(value);

List<int> decodeCanonicalFamilyJoinBase64Url(
  String value, {
  required int expectedLength,
  required String field,
}) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value) || value.length % 4 == 1) {
    throw FormatException('Invalid family join $field');
  }
  try {
    final decoded = base64Url.decode(base64Url.normalize(value));
    if (decoded.length != expectedLength ||
        unpaddedFamilyJoinBase64Url(decoded) != value) {
      throw FormatException('Invalid family join $field');
    }
    return decoded;
  } on FormatException {
    rethrow;
  } on Object catch (error) {
    throw FormatException('Invalid family join $field', error);
  }
}

String unpaddedFamilyJoinBase64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

void _requireRequestFields({
  required String requestId,
  required String familyId,
  required String requesterAccountId,
  required String memberId,
  required String displayName,
  required String colorToken,
  required AvatarConfig avatar,
  required String joiningPublicKey,
  required int codeVersion,
  required DateTime createdAt,
  required DateTime expiresAt,
}) {
  _requireUuid(requestId, 'requestId');
  _requireUuid(familyId, 'familyId');
  _requireUuid(requesterAccountId, 'requesterAccountId');
  _requireProfile(
    memberId: memberId,
    displayName: displayName,
    colorToken: colorToken,
    avatar: avatar,
    joiningPublicKey: joiningPublicKey,
  );
  _requirePositive(codeVersion, 'codeVersion');
  if (!expiresAt.toUtc().isAfter(createdAt.toUtc())) {
    throw ArgumentError.value(
      expiresAt,
      'expiresAt',
      'Must be after createdAt',
    );
  }
}

void _requireProfile({
  required String memberId,
  required String displayName,
  required String colorToken,
  required AvatarConfig avatar,
  required String joiningPublicKey,
}) {
  _requireUuid(memberId, 'memberId');
  _requireNonEmpty(displayName, 'displayName');
  _requireNonEmpty(colorToken, 'colorToken');
  _requireAvatar(avatar);
  _requirePublicKey(joiningPublicKey);
}

void _requireEnvelopeFields({
  required int version,
  required JoinEnvelopeContext context,
  required String ephemeralPublicKey,
  required String nonce,
  required String ciphertext,
  required String mac,
}) {
  if (version != FamilyJoinApprovalEnvelope.currentVersion) {
    throw ArgumentError.value(
      version,
      'version',
      'Unsupported envelope version',
    );
  }
  _requireUuid(context.requestId, 'requestId');
  _requireUuid(context.familyId, 'familyId');
  _requireUuid(context.requesterAccountId, 'requesterAccountId');
  _requirePositive(context.codeVersion, 'codeVersion');
  _requireBytes(
    ephemeralPublicKey,
    expectedLength: 32,
    field: 'ephemeralPublicKey',
  );
  _requireBytes(nonce, expectedLength: 12, field: 'nonce');
  _requireBytes(ciphertext, expectedLength: 32, field: 'ciphertext');
  _requireBytes(mac, expectedLength: 16, field: 'mac');
}

void _requireEnvelopeMatches(
  FamilyJoinApprovalEnvelope envelope, {
  required String requestId,
  required String familyId,
  required String requesterAccountId,
  required int codeVersion,
}) {
  _requireEnvelopeFields(
    version: envelope.version,
    context: envelope.context,
    ephemeralPublicKey: envelope.ephemeralPublicKey,
    nonce: envelope.nonce,
    ciphertext: envelope.ciphertext,
    mac: envelope.mac,
  );
  if (envelope.context.requestId != requestId ||
      envelope.context.familyId != familyId ||
      envelope.context.requesterAccountId != requesterAccountId ||
      envelope.context.codeVersion != codeVersion) {
    throw ArgumentError.value(envelope, 'approvalEnvelope', 'Context mismatch');
  }
}

void _requireRoster(List<FamilyMember> roster, {required String familyId}) {
  for (final member in roster) {
    _requireUuid(member.id, 'roster member id');
    if (member.familyId != familyId) {
      throw ArgumentError.value(
        member.familyId,
        'roster familyId',
        'Must match familyId',
      );
    }
    _requireAvatar(member.avatar);
  }
}

void _requireAvatar(AvatarConfig avatar) {
  if (avatar.schemaVersion != AvatarConfig.currentSchemaVersion ||
      avatar.styleId != AvatarConfig.currentStyleId ||
      avatar.styleRevision != AvatarConfig.currentStyleRevision ||
      avatar.seed.isEmpty ||
      AvatarConfig.decode(avatar.encode(), fallbackSeed: '__invalid__') !=
          avatar) {
    throw ArgumentError.value(avatar, 'avatar', 'Must be strictly decodable');
  }
}

void _requirePublicKey(String value) =>
    _requireBytes(value, expectedLength: 32, field: 'joiningPublicKey');

void _requireBytes(
  String value, {
  required int expectedLength,
  required String field,
}) {
  try {
    decodeCanonicalFamilyJoinBase64Url(
      value,
      expectedLength: expectedLength,
      field: field,
    );
  } on FormatException {
    throw ArgumentError.value(value, field, 'Must be canonical base64url');
  }
}

void _requireUuid(String value, String field) {
  if (!isCanonicalFamilyJoinUuid(value)) {
    throw ArgumentError.value(value, field, 'Must be a canonical UUID');
  }
}

void _requirePositive(int value, String field) {
  if (value <= 0) {
    throw ArgumentError.value(value, field, 'Must be positive');
  }
}

void _requireNonEmpty(String value, String field) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, field, 'Must not be empty');
  }
}
