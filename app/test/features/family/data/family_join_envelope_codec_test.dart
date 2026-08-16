import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/family/data/family_join_envelope_codec.dart';
import 'package:keepers/features/family/data/joining_key_store.dart';
import 'package:keepers/features/family/domain/family_join_request.dart';
import 'package:keepers/storage/database_key_store.dart';

void main() {
  const requesterId = '11111111-1111-4111-8111-111111111111';
  const memberId = '22222222-2222-4222-8222-222222222222';
  const familyId = '33333333-3333-4333-8333-333333333333';
  const requestId = '44444444-4444-4444-8444-444444444444';
  const context = JoinEnvelopeContext(
    requestId: requestId,
    familyId: familyId,
    requesterAccountId: requesterId,
    codeVersion: 1,
  );
  final familyKey = List<int>.generate(32, (index) => 160 + index);

  test('approver seals and requester opens the family key', () async {
    final requesterStore = SecureJoiningKeyStore(
      _MemorySecureValueStore(),
      seedFactory: _fixedSeed,
    );
    final joiningKey = await requesterStore.getOrCreate(
      accountId: requesterId,
      memberId: memberId,
    );
    final codec = CryptographicFamilyJoinEnvelopeCodec(
      randomBytes: (length) =>
          List<int>.generate(length, (index) => 32 + index),
    );

    final envelope = await codec.seal(
      context: context,
      requesterPublicKey: joiningKey.publicKey,
      familyKey: familyKey,
    );
    expect(
      envelope.ephemeralPublicKey,
      'NYBy1jZYgNGu6jKa35EhODhR7SGijjt16WXQ0s0WYlQ',
    );
    expect(envelope.nonce, 'ICEiIyQlJicoKSor');
    expect(envelope.ciphertext, 'iila3wkCfwJ1bx6vcyw8Xrt6XBzs-_2gTtiWd0CfRug');
    expect(envelope.mac, 'zi7T6j0P72rWfeTvQ0_Yqg');

    expect(
      await codec.open(
        envelope: envelope,
        expectedRequesterPublicKey: joiningKey.publicKey,
        joiningKey: joiningKey,
      ),
      familyKey,
    );
  });

  test('context and encrypted material tampering fail closed', () async {
    final store = SecureJoiningKeyStore(
      _MemorySecureValueStore(),
      seedFactory: _fixedSeed,
    );
    final key = await store.getOrCreate(
      accountId: requesterId,
      memberId: memberId,
    );
    final codec = CryptographicFamilyJoinEnvelopeCodec(
      randomBytes: (length) =>
          List<int>.generate(length, (index) => 32 + index),
    );
    final envelope = await codec.seal(
      context: context,
      requesterPublicKey: key.publicKey,
      familyKey: familyKey,
    );
    final tampered = <FamilyJoinApprovalEnvelope>[
      _copyEnvelope(
        envelope,
        requestId: '55555555-5555-4555-8555-555555555555',
      ),
      _copyEnvelope(envelope, familyId: '66666666-6666-4666-8666-666666666666'),
      _copyEnvelope(
        envelope,
        requesterAccountId: '77777777-7777-4777-8777-777777777777',
      ),
      _copyEnvelope(envelope, codeVersion: 2),
      _copyEnvelope(envelope, ephemeralPublicKey: _bytes(32)),
      _copyEnvelope(envelope, nonce: _bytes(12)),
      _copyEnvelope(envelope, ciphertext: _bytes(32)),
      _copyEnvelope(envelope, mac: _bytes(16)),
    ];

    for (final altered in tampered) {
      await expectLater(
        codec.open(
          envelope: altered,
          expectedRequesterPublicKey: key.publicKey,
          joiningKey: key,
        ),
        throwsA(
          const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected),
        ),
      );
    }
  });

  test('wrong joining key is rejected before envelope opening', () async {
    final store = SecureJoiningKeyStore(
      _MemorySecureValueStore(),
      seedFactory: _fixedSeed,
    );
    final key = await store.getOrCreate(
      accountId: requesterId,
      memberId: memberId,
    );
    final codec = CryptographicFamilyJoinEnvelopeCodec();
    final envelope = await codec.seal(
      context: context,
      requesterPublicKey: key.publicKey,
      familyKey: familyKey,
    );

    await expectLater(
      codec.open(
        envelope: envelope,
        expectedRequesterPublicKey: _bytes(32),
        joiningKey: key,
      ),
      throwsA(const FamilyJoinFailure(FamilyJoinFailureCode.invalidJoinKey)),
    );
  });

  test('separate approvals use fresh ephemeral material', () async {
    final store = SecureJoiningKeyStore(
      _MemorySecureValueStore(),
      seedFactory: _fixedSeed,
    );
    final key = await store.getOrCreate(
      accountId: requesterId,
      memberId: memberId,
    );
    final codec = CryptographicFamilyJoinEnvelopeCodec();

    final first = await codec.seal(
      context: context,
      requesterPublicKey: key.publicKey,
      familyKey: familyKey,
    );
    final second = await codec.seal(
      context: context,
      requesterPublicKey: key.publicKey,
      familyKey: familyKey,
    );

    expect(first.ephemeralPublicKey, isNot(second.ephemeralPublicKey));
    expect(first.nonce, isNot(second.nonce));
  });
}

List<int> _fixedSeed(int length) =>
    List<int>.generate(length, (index) => index);

FamilyJoinApprovalEnvelope _copyEnvelope(
  FamilyJoinApprovalEnvelope envelope, {
  String? requestId,
  String? familyId,
  String? requesterAccountId,
  int? codeVersion,
  String? ephemeralPublicKey,
  String? nonce,
  String? ciphertext,
  String? mac,
}) => FamilyJoinApprovalEnvelope(
  version: envelope.version,
  context: JoinEnvelopeContext(
    requestId: requestId ?? envelope.context.requestId,
    familyId: familyId ?? envelope.context.familyId,
    requesterAccountId:
        requesterAccountId ?? envelope.context.requesterAccountId,
    codeVersion: codeVersion ?? envelope.context.codeVersion,
  ),
  ephemeralPublicKey: ephemeralPublicKey ?? envelope.ephemeralPublicKey,
  nonce: nonce ?? envelope.nonce,
  ciphertext: ciphertext ?? envelope.ciphertext,
  mac: mac ?? envelope.mac,
);

String _bytes(int length) =>
    base64UrlEncode(List<int>.filled(length, 0)).replaceAll('=', '');

final class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
