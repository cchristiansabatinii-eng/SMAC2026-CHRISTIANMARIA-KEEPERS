import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/domain/family_invitation.dart';

void main() {
  const fixedToken = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  const fixedSecret = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE';
  const inviteId = '11111111-1111-4111-8111-111111111111';

  test('invite link round-trips without exposing secrets in toString', () {
    const link = FamilyInviteLink(
      inviteId: inviteId,
      token: fixedToken,
      wrappingSecret: fixedSecret,
    );

    expect(
      link.toUri(),
      Uri.parse('keepers://join?v=1&i=$inviteId&t=$fixedToken&s=$fixedSecret'),
    );
    expect(FamilyInviteLink.parse(link.toUri()), link);
    expect(link.toString(), 'FamilyInviteLink(<redacted>)');
    expect(link.toString(), isNot(contains(fixedToken)));
    expect(link.toString(), isNot(contains(fixedSecret)));
  });

  test('invite parser rejects wrong scheme, version, UUID and secret length', () {
    final malformedUris = <Uri>[
      Uri.parse('https://join?v=1&i=$inviteId&t=$fixedToken&s=$fixedSecret'),
      Uri.parse('keepers://wrong?v=1&i=$inviteId&t=$fixedToken&s=$fixedSecret'),
      Uri.parse('keepers://join?v=2&i=$inviteId&t=$fixedToken&s=$fixedSecret'),
      Uri.parse('keepers://join?v=1&i=not-a-uuid&t=$fixedToken&s=$fixedSecret'),
      Uri.parse(
        'keepers://join?v=1&i=11111111-1111-4111-8111-11111111111A&t=$fixedToken&s=$fixedSecret',
      ),
      Uri.parse(
        'keepers://join?v=1&i=$inviteId&t=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&s=$fixedSecret',
      ),
      Uri.parse(
        'keepers://join?v=1&i=$inviteId&t=$fixedToken&s=AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ',
      ),
    ];

    for (final uri in malformedUris) {
      expect(() => FamilyInviteLink.parse(uri), throwsFormatException);
    }
  });

  test('invite parser requires exact canonical query values', () {
    final malformedUris = <Uri>[
      Uri.parse('keepers://join?i=$inviteId&t=$fixedToken&s=$fixedSecret'),
      Uri.parse(
        'keepers://join?v=1&i=$inviteId&t=$fixedToken&s=$fixedSecret&extra=x',
      ),
      Uri.parse(
        'keepers://join?v=1&v=1&i=$inviteId&t=$fixedToken&s=$fixedSecret',
      ),
      Uri.parse('keepers://join?v=1&i=$inviteId&t=$fixedToken=&s=$fixedSecret'),
      Uri.parse(
        'keepers://join?v=1&i=$inviteId&t=${fixedToken.substring(0, 42)}B&s=$fixedSecret',
      ),
    ];

    for (final uri in malformedUris) {
      expect(() => FamilyInviteLink.parse(uri), throwsFormatException);
    }
  });
}
