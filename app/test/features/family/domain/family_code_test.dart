import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/domain/family_code.dart';

void main() {
  test('normalizes and groups an eight-symbol code', () {
    final code = FamilyCode.parse('k7m4 p2-q8');
    expect(code.normalized, 'K7M4P2Q8');
    expect(code.display, 'K7M4-P2Q8');
    expect(code.toString(), 'FamilyCode(<redacted>)');
  });

  test('rejects ambiguous and malformed input', () {
    for (final value in [
      'K7M4-I2Q8',
      'K7M4-L2Q8',
      'K7M4-O2Q8',
      'K7M4-U2Q8',
      'K7M4-P2Q',
      'K7M4-P2Q88',
    ]) {
      expect(() => FamilyCode.parse(value), throwsFormatException);
    }
  });

  test('accepts only the verified family-link shape', () {
    final link = FamilyJoinLink.parse(
      Uri.parse('https://join.keepers.app/f/K7M4-P2Q8'),
    );
    expect(link.code.display, 'K7M4-P2Q8');
    expect(link.toString(), 'FamilyJoinLink(<redacted>)');
    expect(
      () => FamilyJoinLink.parse(
        Uri.parse('https://join.keepers.app/f/K7M4-P2Q8?token=leak'),
      ),
      throwsFormatException,
    );
  });

  test('material accepts only its exact canonical storage representation', () {
    const materialJson = <String, Object?>{
      'codecVersion': 1,
      'familyId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'codeVersion': 1,
      'nonce': 'AAECAwQFBgcICQoL',
      'ciphertext': 'AAECAwQFBgc',
      'mac': 'AAECAwQFBgcICQoLDA0ODw',
    };

    final material = EncryptedFamilyCodeMaterial.fromJson(materialJson);

    expect(material.toJson(), materialJson);
    expect(material.toString(), 'EncryptedFamilyCodeMaterial(<redacted>)');
    for (final invalid in <Map<String, Object?>>[
      {...materialJson}..remove('mac'),
      {...materialJson, 'unexpected': true},
      {
        ...materialJson,
        'familyId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'.toUpperCase(),
      },
      {...materialJson, 'codeVersion': 0},
      {...materialJson, 'nonce': 'AAECAwQFBgcICQo'},
      {...materialJson, 'ciphertext': 'AAECAwQFBg'},
      {...materialJson, 'mac': 'AAECAwQFBgcICQoLDA0OD'},
    ]) {
      expect(
        () => EncryptedFamilyCodeMaterial.fromJson(invalid),
        throwsFormatException,
      );
    }
  });
}
