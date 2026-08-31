import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/sync/weekly_presence_token_codec.dart';

void main() {
  final familyKey = List<int>.generate(32, (index) => index);
  final codec = WeeklyPresenceTokenCodec();

  group('WeeklyPresenceTokenCodec', () {
    test('uses stable ten-second slots for the same instant', () {
      expect(
        codec.slotFor(DateTime.fromMillisecondsSinceEpoch(49_999, isUtc: true)),
        4,
      );
      expect(
        codec.slotFor(DateTime.fromMillisecondsSinceEpoch(50_000, isUtc: true)),
        5,
      );
      expect(codec.slotFor(DateTime.parse('1970-01-01T04:00:50+04:00')), 5);
    });

    test('encodes a deterministic HMAC-SHA256 RFC UUID', () {
      final first = codec.serviceUuid(
        familyKey: familyKey,
        familyId: 'family-a',
        memberId: 'member-a',
        slot: 5,
      );
      final second = codec.serviceUuid(
        familyKey: familyKey,
        familyId: 'family-a',
        memberId: 'member-a',
        slot: 5,
      );

      expect(first, 'b2813e64-322d-8c49-9a63-39b04e415fd5');
      expect(second, first);
      expect(
        first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-'
            r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('separates family, member, key, and time slot inputs', () {
      final changedKey = List<int>.generate(32, (index) => index + 1);
      final tokens = {
        codec.serviceUuid(
          familyKey: familyKey,
          familyId: 'family-a',
          memberId: 'member-a',
          slot: 5,
        ),
        codec.serviceUuid(
          familyKey: familyKey,
          familyId: 'family-b',
          memberId: 'member-a',
          slot: 5,
        ),
        codec.serviceUuid(
          familyKey: familyKey,
          familyId: 'family-a',
          memberId: 'member-b',
          slot: 5,
        ),
        codec.serviceUuid(
          familyKey: changedKey,
          familyId: 'family-a',
          memberId: 'member-a',
          slot: 5,
        ),
        codec.serviceUuid(
          familyKey: familyKey,
          familyId: 'family-a',
          memberId: 'member-a',
          slot: 6,
        ),
      };

      expect(tokens, hasLength(5));
      expect(tokens, contains('a5e0bbc3-9ba9-8e7d-98e7-53f0d115c707'));
      expect(tokens, contains('9844fe34-2c52-83cb-9d5e-d3ec74a30de9'));
      expect(tokens, contains('77e908fc-4816-8210-908e-6d99d07198fa'));
      expect(tokens, contains('5f4ee038-33b5-8539-a1ce-3ff8f74b10af'));
    });

    test('does not expose raw family or member identifiers', () {
      final token = codec.serviceUuid(
        familyKey: familyKey,
        familyId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        memberId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        slot: 5,
      );

      expect(token, isNot(contains('aaaaaaaa')));
      expect(token, isNot(contains('bbbbbbbb')));
    });

    test('normalizes identifiers and deduplicates roster members', () {
      final trimmed = codec.serviceUuid(
        familyKey: familyKey,
        familyId: 'family-a',
        memberId: 'member-a',
        slot: 5,
      );
      final padded = codec.serviceUuid(
        familyKey: familyKey,
        familyId: '  family-a  ',
        memberId: '\tmember-a\n',
        slot: 5,
      );
      final expected = codec.expectedMembersByServiceUuid(
        familyKey: familyKey,
        familyId: ' family-a ',
        memberIds: const [' member-a ', 'member-a', '', '  '],
        at: DateTime.fromMillisecondsSinceEpoch(50_000, isUtc: true),
      );

      expect(padded, trimmed);
      expect(expected, hasLength(3));
      expect(expected.values.toSet(), {'member-a'});
    });

    test('matches only current, previous, and next-slot roster tokens', () {
      final expected = codec.expectedMembersByServiceUuid(
        familyKey: familyKey,
        familyId: 'family-a',
        memberIds: const ['member-a'],
        at: DateTime.fromMillisecondsSinceEpoch(50_000, isUtc: true),
      );

      expect(expected, {
        '95a990ff-5959-8eb0-a522-a19c06c61ad6': 'member-a',
        'b2813e64-322d-8c49-9a63-39b04e415fd5': 'member-a',
        '5f4ee038-33b5-8539-a1ce-3ff8f74b10af': 'member-a',
      });
      expect(expected, isNot(contains('b098f30c-52b9-8aa7-9185-8f8a2a8d5c2d')));
      expect(expected, isNot(contains('f4b48385-3dc9-8de1-8bdb-0f534570c611')));
    });

    test('rejects tokens for members outside the active roster', () {
      final expected = codec.expectedMembersByServiceUuid(
        familyKey: familyKey,
        familyId: 'family-a',
        memberIds: const ['member-a'],
        at: DateTime.fromMillisecondsSinceEpoch(50_000, isUtc: true),
      );
      final outsider = codec.serviceUuid(
        familyKey: familyKey,
        familyId: 'family-a',
        memberId: 'outsider',
        slot: 5,
      );

      expect(expected[outsider], isNull);
      expect(expected['00000000-0000-8000-8000-000000000000'], isNull);
    });

    test('validates trusted key, identity, slot, and skew inputs', () {
      expect(
        () => WeeklyPresenceTokenCodec(slotDuration: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () =>
            codec.slotFor(DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true)),
        throwsArgumentError,
      );
      expect(
        () => codec.serviceUuid(
          familyKey: List<int>.filled(31, 0),
          familyId: 'family-a',
          memberId: 'member-a',
          slot: 5,
        ),
        throwsArgumentError,
      );
      expect(
        () => codec.serviceUuid(
          familyKey: familyKey,
          familyId: ' ',
          memberId: 'member-a',
          slot: 5,
        ),
        throwsArgumentError,
      );
      expect(
        () => codec.serviceUuid(
          familyKey: familyKey,
          familyId: 'family-a',
          memberId: '',
          slot: 5,
        ),
        throwsArgumentError,
      );
      expect(
        () => codec.serviceUuid(
          familyKey: familyKey,
          familyId: 'family-a',
          memberId: 'member-a',
          slot: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => codec.expectedMembersByServiceUuid(
          familyKey: familyKey,
          familyId: 'family-a',
          memberIds: const ['member-a'],
          at: DateTime.fromMillisecondsSinceEpoch(50_000, isUtc: true),
          skewSlots: -1,
        ),
        throwsArgumentError,
      );
    });

    test('never mutates the caller-owned family key', () {
      final callerKey = List<int>.generate(32, (index) => 255 - index);
      final original = List<int>.of(callerKey);

      codec.serviceUuid(
        familyKey: callerKey,
        familyId: 'family-a',
        memberId: 'member-a',
        slot: 5,
      );
      codec.expectedMembersByServiceUuid(
        familyKey: callerKey,
        familyId: 'family-a',
        memberIds: const ['member-a', 'member-b'],
        at: DateTime.fromMillisecondsSinceEpoch(50_000, isUtc: true),
      );

      expect(callerKey, original);
    });
  });
}
