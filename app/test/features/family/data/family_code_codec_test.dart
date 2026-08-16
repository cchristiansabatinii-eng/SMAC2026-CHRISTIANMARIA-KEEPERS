import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/family_code_codec.dart';
import 'package:keepers/features/family/domain/family_code.dart';
import 'package:keepers/features/family/domain/family_join_failure.dart';

void main() {
  const familyId = '22222222-2222-4222-8222-222222222222';
  final familyKey = List<int>.generate(32, (index) => index + 1);

  test('encrypts, hashes, and opens code material', () async {
    final codec = CryptographicFamilyCodeCodec(
      randomSymbolIndex: () => 7,
      randomBytes: (length) => List<int>.generate(length, (index) => index),
    );
    final draft = await codec.createDraft(
      familyId: familyId,
      codeVersion: 1,
      familyKey: familyKey,
    );

    expect(draft.code.normalized, '77777777');
    expect(
      base64Url.decode(base64Url.normalize(draft.lookupHash)),
      hasLength(32),
    );
    expect(draft.lookupHash, isNot(contains('=')));
    expect(
      await codec.open(material: draft.material, familyKey: familyKey),
      draft.code,
    );
  });

  test('binds family and code version as authenticated data', () async {
    final codec = CryptographicFamilyCodeCodec(
      randomSymbolIndex: () => 7,
      randomBytes: (length) => List<int>.generate(length, (index) => index),
    );
    final draft = await codec.createDraft(
      familyId: familyId,
      codeVersion: 2,
      familyKey: familyKey,
    );
    final changed = draft.material.copyWith(codeVersion: 3);

    await expectLater(
      codec.open(material: changed, familyKey: familyKey),
      throwsA(
        equals(const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected)),
      ),
    );
  });

  test('rejects a wrong key and every material field mutation', () async {
    final codec = CryptographicFamilyCodeCodec();
    final draft = await codec.createDraft(
      familyId: familyId,
      codeVersion: 1,
      familyKey: familyKey,
    );
    const otherFamilyId = '33333333-3333-4333-8333-333333333333';
    final materials = <EncryptedFamilyCodeMaterial>[
      draft.material.copyWith(codecVersion: 2),
      draft.material.copyWith(familyId: otherFamilyId),
      draft.material.copyWith(codeVersion: 2),
      draft.material.copyWith(nonce: _flipFirstByte(draft.material.nonce)),
      draft.material.copyWith(
        ciphertext: _flipFirstByte(draft.material.ciphertext),
      ),
      draft.material.copyWith(mac: _flipFirstByte(draft.material.mac)),
    ];

    for (final material in materials) {
      await expectLater(
        codec.open(material: material, familyKey: familyKey),
        throwsA(
          equals(
            const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected),
          ),
        ),
      );
    }
    await expectLater(
      codec.open(material: draft.material, familyKey: List<int>.filled(32, 0)),
      throwsA(
        equals(const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected)),
      ),
    );
  });

  test('rejects malformed material and invalid creation inputs', () async {
    final codec = CryptographicFamilyCodeCodec();
    await expectLater(
      codec.createDraft(
        familyId: familyId,
        codeVersion: 0,
        familyKey: familyKey,
      ),
      throwsArgumentError,
    );
    await expectLater(
      codec.createDraft(
        familyId: familyId,
        codeVersion: 1,
        familyKey: List<int>.filled(31, 0),
      ),
      throwsArgumentError,
    );
    final draft = await codec.createDraft(
      familyId: familyId,
      codeVersion: 1,
      familyKey: familyKey,
    );
    await expectLater(
      codec.open(
        material: draft.material.copyWith(nonce: 'not_base64!'),
        familyKey: familyKey,
      ),
      throwsA(
        equals(const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected)),
      ),
    );
  });
}

String _flipFirstByte(String encoded) {
  final bytes = base64Url.decode(base64Url.normalize(encoded));
  bytes[0] ^= 1;
  return base64UrlEncode(bytes).replaceAll('=', '');
}
