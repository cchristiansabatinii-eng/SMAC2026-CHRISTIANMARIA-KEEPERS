import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/cloud_config.dart';
import 'package:keepers/features/family/data/unavailable_cloud_family_gateway.dart';
import 'package:keepers/features/family/domain/cloud_family_models.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';
import 'package:keepers/features/members/domain/avatar_config.dart';

void main() {
  group('CloudConfig', () {
    test('empty values produce an unconfigured runtime', () {
      final config = CloudConfig.parse(url: '', publishableKey: '');

      expect(config.isConfigured, isFalse);
      expect(config.url, isNull);
      expect(config.publishableKey, isNull);
      expect(config.toString(), 'CloudConfig(unconfigured)');
    });

    test('valid values are trimmed and configured', () {
      final config = CloudConfig.parse(
        url: ' https://project.supabase.co ',
        publishableKey: ' sb_publishable_example ',
      );

      expect(config.isConfigured, isTrue);
      expect(config.url, Uri.https('project.supabase.co', ''));
      expect(config.publishableKey, 'sb_publishable_example');
      expect(config.toString(), 'CloudConfig(configured)');
      expect(config.toString(), isNot(contains('sb_publishable_example')));
    });

    test('normalizes a root slash before runtime initialization', () {
      final config = CloudConfig.parse(
        url: 'https://project.supabase.co/',
        publishableKey: 'sb_publishable_example',
      );

      expect(config.url.toString(), 'https://project.supabase.co');
    });

    test('configuration requires URL and key together', () {
      expect(
        () => CloudConfig.parse(
          url: 'https://project.supabase.co',
          publishableKey: '',
        ),
        throwsFormatException,
      );
      expect(
        () => CloudConfig.parse(url: '', publishableKey: 'publishable-key'),
        throwsFormatException,
      );
    });

    test('configuration requires a plain HTTPS origin', () {
      for (final url in <String>[
        'http://project.supabase.co',
        'not a URL',
        'https://user@project.supabase.co',
        'https://project.supabase.co?secret=value',
        'https://project.supabase.co/#fragment',
      ]) {
        expect(
          () => CloudConfig.parse(
            url: url,
            publishableKey: 'sb_publishable_example',
          ),
          throwsFormatException,
          reason: url,
        );
      }
    });

    test('accepts a well-formed legacy JWT with exact anon role', () {
      final credential = _legacyJwt(<String, Object?>{
        'iss': 'supabase',
        'role': 'anon',
      });

      final config = CloudConfig.parse(
        url: 'https://project.supabase.co',
        publishableKey: credential,
      );

      expect(config.isConfigured, isTrue);
      expect(config.publishableKey, credential);
      expect(config.toString(), isNot(contains(credential)));
    });

    test('rejects every other key shape with one redacted error', () {
      final invalidCredentials = <String>[
        'opaque-publishable-looking-value',
        'sb_unknown_example',
        'sb_publishable_',
        'sb_publishable_bad value',
        'sb_secret_do-not-ship-this-value',
        'one.two',
        'one.two.three.four',
        '${_base64UrlJson('not-a-header')}.'
            '${_base64UrlJson(<String, Object?>{'role': 'anon'})}.'
            '$_legacyJwtSignature',
        '${_base64UrlJson(<String, Object?>{'alg': 'HS256', 'typ': 'JWT'})}.'
            '*.'
            '$_legacyJwtSignature',
        '${_base64UrlJson(<String, Object?>{'alg': 'HS256', 'typ': 'JWT'})}.'
            '${_base64UrlJson(<String, Object?>{'role': 'anon'})}.'
            'not*base64url',
        '${_base64UrlJson(<String, Object?>{'alg': 'none', 'typ': 'JWT'})}.'
            '${_base64UrlJson(<String, Object?>{'iss': 'supabase', 'role': 'anon'})}.'
            '$_legacyJwtSignature',
        '${_base64UrlJson(<String, Object?>{'alg': 'HS256', 'typ': 'jwt'})}.'
            '${_base64UrlJson(<String, Object?>{'iss': 'supabase', 'role': 'anon'})}.'
            '$_legacyJwtSignature',
        '${_base64UrlJson(<String, Object?>{'alg': 'HS256', 'typ': 'JWT'})}=.'
            '${_base64UrlJson(<String, Object?>{'iss': 'supabase', 'role': 'anon'})}.'
            '$_legacyJwtSignature',
        '${_base64UrlJson(<String, Object?>{'alg': 'HS256', 'typ': 'JWT'})}.'
            '${_base64UrlJson(<String, Object?>{'iss': 'supabase', 'role': 'anon'})}.'
            'Bw',
        _legacyJwt(<String, Object?>{'role': 'anon'}),
        _legacyJwt(<String, Object?>{'iss': 'other', 'role': 'anon'}),
        _legacyJwt(<String, Object?>{'iss': 'supabase'}),
        _legacyJwt(<String, Object?>{'iss': 'supabase', 'role': 1}),
        _legacyJwt(<String, Object?>{
          'iss': 'supabase',
          'role': 'service_role',
        }),
        _legacyJwt(<String, Object?>{
          'iss': 'supabase',
          'role': 'authenticated',
        }),
        _legacyJwt(<String, Object?>{'iss': 'supabase', 'role': 'postgres'}),
        _legacyJwt(<String, Object?>{'iss': 'supabase', 'role': 'Anon'}),
      ];

      for (final credential in invalidCredentials) {
        try {
          CloudConfig.parse(
            url: 'https://project.supabase.co',
            publishableKey: credential,
          );
          fail('Invalid publishable credential was accepted');
        } on FormatException catch (error) {
          expect(error.message, 'Supabase publishable key is invalid');
          expect(error.toString(), isNot(contains(credential)));
        }
      }
    });
  });

  test(
    'unavailable gateway rejects every cloud operation with one safe code',
    () async {
      const gateway = UnavailableCloudFamilyGateway();
      const link = FamilyInviteLink(
        inviteId: '44444444-4444-4444-8444-444444444444',
        token: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        wrappingSecret: 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE',
      );
      const envelope = InvitationEnvelope(
        version: 1,
        inviteId: '44444444-4444-4444-8444-444444444444',
        familyId: '11111111-1111-4111-8111-111111111111',
        nonce: 'AgICAgICAgICAgIC',
        ciphertext: 'AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM',
        mac: 'BAQEBAQEBAQEBAQEBAQEBA',
      );
      const avatar = AvatarConfig.defaults(seed: 'member');
      final operations = <Future<Object?> Function()>[
        () => gateway.requestEmailOtp('person@example.com'),
        () => gateway.verifyEmailOtp(
          email: 'person@example.com',
          token: '123456',
        ),
        () => gateway.bootstrapOwner(
          const LocalOwnerFamily(
            familyId: '11111111-1111-4111-8111-111111111111',
            familyName: 'Sabati',
            memberId: '22222222-2222-4222-8222-222222222222',
            displayName: 'Chris',
            demographicRole: FamilyDemographicRole.adult,
            colorToken: 'ochre',
            avatar: avatar,
          ),
        ),
        () => gateway.createInvitation(
          const CloudInvitationDraft(
            inviteId: '44444444-4444-4444-8444-444444444444',
            familyId: '11111111-1111-4111-8111-111111111111',
            recipientEmail: 'person@example.com',
            tokenHash: 'BQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQU',
            envelope: envelope,
          ),
        ),
        () => gateway.previewInvitation(link),
        () => gateway.claimInvitation(
          const JoinRequest(
            link: link,
            memberId: '33333333-3333-4333-8333-333333333333',
            displayName: 'Mariam',
            demographicRole: FamilyDemographicRole.adult,
            colorToken: 'teal',
            avatar: avatar,
          ),
        ),
        () =>
            gateway.completeInvitation('44444444-4444-4444-8444-444444444444'),
        () => gateway.revokeInvitation('44444444-4444-4444-8444-444444444444'),
        () => gateway.listActiveMembers('11111111-1111-4111-8111-111111111111'),
      ];

      expect(gateway.isConfigured, isFalse);
      expect(gateway.authenticatedAccountId, isNull);
      expect(gateway.authenticatedEmail, isNull);
      for (final operation in operations) {
        await expectLater(
          operation(),
          throwsA(const InvitationFailure(InvitationFailureCode.notConfigured)),
        );
      }
    },
  );
}

String _legacyJwt(Map<String, Object?> payload) => <String>[
  _base64UrlJson(<String, Object?>{'alg': 'HS256', 'typ': 'JWT'}),
  _base64UrlJson(payload),
  _legacyJwtSignature,
].join('.');

const _legacyJwtSignature = 'BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc';

String _base64UrlJson(Object? value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
