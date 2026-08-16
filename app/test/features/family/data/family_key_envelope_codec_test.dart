import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/family_key_envelope_codec.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';

void main() {
  const inviteId = '11111111-1111-4111-8111-111111111111';
  const familyId = '22222222-2222-4222-8222-222222222222';
  final familyKey = List<int>.generate(32, (index) => 160 + index);
  final expiresAt = DateTime.parse('2026-09-06T12:00:00+04:00');

  test('family key survives a versioned envelope round-trip', () async {
    final codec = CryptographicFamilyKeyEnvelopeCodec();

    final draft = await codec.createDraft(
      familyId: familyId,
      familyKey: familyKey,
      inviteId: inviteId,
      expiresAt: expiresAt,
    );

    expect(
      await codec.open(link: draft.link, envelope: draft.envelope),
      familyKey,
    );
    expect(draft.tokenHash, hasLength(43));
    expect(draft.tokenHash, isNot(contains('=')));
    expect(draft.envelope.version, 1);
    expect(draft.envelope.inviteId, inviteId);
    expect(draft.envelope.familyId, familyId);
    expect(draft.expiresAt, DateTime.utc(2026, 9, 6, 8));
  });

  test('codec matches the specified HKDF and AES-GCM wire vector', () async {
    final randomValues = <List<int>>[
      List<int>.generate(32, (index) => index),
      List<int>.generate(32, (index) => 32 + index),
      List<int>.generate(12, (index) => 64 + index),
    ];
    var nextValue = 0;
    final codec = CryptographicFamilyKeyEnvelopeCodec(
      randomBytes: (length) {
        final value = randomValues[nextValue++];
        expect(value, hasLength(length));
        return value;
      },
    );

    final draft = await codec.createDraft(
      familyId: familyId,
      familyKey: familyKey,
      inviteId: inviteId,
      expiresAt: expiresAt,
    );

    expect(draft.link.token, 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8');
    expect(
      draft.link.wrappingSecret,
      'ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8',
    );
    expect(draft.tokenHash, 'Yw3NKWbEM2aRElRIu7JbT_QSpJxzLbLIq8G4WBvXEN0');
    expect(draft.envelope.nonce, 'QEFCQ0RFRkdISUpL');
    expect(
      draft.envelope.ciphertext,
      'dzxbydaKtny4utSm6emjHL1rdRA2FQNFq1XFdrvqnHE',
    );
    expect(draft.envelope.mac, 'lK7nv6RnbkniS7AiGiCIqA');
    expect(nextValue, 3);
  });

  test('envelope has an exact validated storage representation', () async {
    final draft = await CryptographicFamilyKeyEnvelopeCodec().createDraft(
      familyId: familyId,
      familyKey: familyKey,
      inviteId: inviteId,
      expiresAt: expiresAt,
    );

    expect(draft.envelope.toJson(), {
      'version': 1,
      'inviteId': inviteId,
      'familyId': familyId,
      'nonce': draft.envelope.nonce,
      'ciphertext': draft.envelope.ciphertext,
      'mac': draft.envelope.mac,
    });
    expect(
      InvitationEnvelope.fromJson(draft.envelope.toJson()),
      draft.envelope,
    );

    final invalid = <Map<String, Object?>>[
      {...draft.envelope.toJson()}..remove('mac'),
      {...draft.envelope.toJson(), 'extra': 'unexpected'},
      {...draft.envelope.toJson(), 'version': 2},
      {...draft.envelope.toJson(), 'nonce': '${draft.envelope.nonce}='},
      {...draft.envelope.toJson(), 'mac': 7},
    ];
    for (final json in invalid) {
      expect(() => InvitationEnvelope.fromJson(json), throwsFormatException);
    }
  });

  test(
    'wrong secret, family, invite and every tampered field fail closed',
    () async {
      final codec = CryptographicFamilyKeyEnvelopeCodec();
      final draft = await codec.createDraft(
        familyId: familyId,
        familyKey: familyKey,
        inviteId: inviteId,
        expiresAt: expiresAt,
      );
      const otherInviteId = '33333333-3333-4333-8333-333333333333';
      const otherFamilyId = '44444444-4444-4444-8444-444444444444';
      final mutations =
          <({FamilyInviteLink link, InvitationEnvelope envelope})>[
            (
              link: _copyLink(
                draft.link,
                wrappingSecret: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              ),
              envelope: draft.envelope,
            ),
            (
              link: draft.link,
              envelope: _copyEnvelope(draft.envelope, familyId: otherFamilyId),
            ),
            (
              link: _copyLink(draft.link, inviteId: otherInviteId),
              envelope: draft.envelope,
            ),
            (
              link: _copyLink(draft.link, inviteId: otherInviteId),
              envelope: _copyEnvelope(draft.envelope, inviteId: otherInviteId),
            ),
            (
              link: draft.link,
              envelope: _copyEnvelope(draft.envelope, version: 2),
            ),
            (
              link: draft.link,
              envelope: _copyEnvelope(
                draft.envelope,
                nonce: _flipFirstByte(draft.envelope.nonce),
              ),
            ),
            (
              link: draft.link,
              envelope: _copyEnvelope(
                draft.envelope,
                ciphertext: _flipFirstByte(draft.envelope.ciphertext),
              ),
            ),
            (
              link: draft.link,
              envelope: _copyEnvelope(
                draft.envelope,
                mac: _flipFirstByte(draft.envelope.mac),
              ),
            ),
          ];

      for (final mutation in mutations) {
        await expectLater(
          codec.open(link: mutation.link, envelope: mutation.envelope),
          throwsA(
            equals(
              const InvitationFailure(InvitationFailureCode.envelopeRejected),
            ),
          ),
        );
      }
    },
  );

  test('invalid key and envelope lengths are rejected before crypto', () async {
    final codec = CryptographicFamilyKeyEnvelopeCodec();
    await expectLater(
      codec.createDraft(
        familyId: familyId,
        familyKey: List<int>.filled(31, 1),
        inviteId: inviteId,
        expiresAt: expiresAt,
      ),
      throwsArgumentError,
    );
    final draft = await codec.createDraft(
      familyId: familyId,
      familyKey: familyKey,
      inviteId: inviteId,
      expiresAt: expiresAt,
    );
    final malformed = <InvitationEnvelope>[
      _copyEnvelope(draft.envelope, nonce: _encodedBytes(11)),
      _copyEnvelope(draft.envelope, ciphertext: _encodedBytes(31)),
      _copyEnvelope(draft.envelope, mac: _encodedBytes(15)),
      _copyEnvelope(draft.envelope, nonce: '${draft.envelope.nonce}='),
    ];

    for (final envelope in malformed) {
      await expectLater(
        codec.open(link: draft.link, envelope: envelope),
        throwsA(
          equals(
            const InvitationFailure(InvitationFailureCode.envelopeRejected),
          ),
        ),
      );
    }
  });

  test('separate drafts receive independent fresh capability bytes', () async {
    final codec = CryptographicFamilyKeyEnvelopeCodec();

    final first = await codec.createDraft(
      familyId: familyId,
      familyKey: familyKey,
      inviteId: inviteId,
      expiresAt: expiresAt,
    );
    final second = await codec.createDraft(
      familyId: familyId,
      familyKey: familyKey,
      inviteId: inviteId,
      expiresAt: expiresAt,
    );

    expect(first.link.token, isNot(first.link.wrappingSecret));
    expect(first.link.token, isNot(second.link.token));
    expect(first.link.wrappingSecret, isNot(second.link.wrappingSecret));
    expect(first.envelope.nonce, isNot(second.envelope.nonce));
  });

  test('invitation failures expose only their typed code', () {
    const failure = InvitationFailure(InvitationFailureCode.envelopeRejected);

    expect(
      failure,
      const InvitationFailure(InvitationFailureCode.envelopeRejected),
    );
    expect(failure.toString(), 'InvitationFailure(envelopeRejected)');
  });
}

FamilyInviteLink _copyLink(
  FamilyInviteLink source, {
  String? inviteId,
  String? token,
  String? wrappingSecret,
}) => FamilyInviteLink(
  inviteId: inviteId ?? source.inviteId,
  token: token ?? source.token,
  wrappingSecret: wrappingSecret ?? source.wrappingSecret,
);

InvitationEnvelope _copyEnvelope(
  InvitationEnvelope source, {
  int? version,
  String? inviteId,
  String? familyId,
  String? nonce,
  String? ciphertext,
  String? mac,
}) => InvitationEnvelope(
  version: version ?? source.version,
  inviteId: inviteId ?? source.inviteId,
  familyId: familyId ?? source.familyId,
  nonce: nonce ?? source.nonce,
  ciphertext: ciphertext ?? source.ciphertext,
  mac: mac ?? source.mac,
);

String _flipFirstByte(String encoded) {
  final bytes = base64Url.decode(base64Url.normalize(encoded));
  bytes[0] ^= 1;
  return _unpaddedBase64Url(bytes);
}

String _encodedBytes(int length) =>
    _unpaddedBase64Url(List<int>.filled(length, 0));

String _unpaddedBase64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');
