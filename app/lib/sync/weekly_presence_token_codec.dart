import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

const weeklyPresenceTokenSlotDuration = Duration(seconds: 10);

abstract interface class WeeklyPresenceTokenEncoder {
  int slotFor(DateTime at);

  String serviceUuid({
    required List<int> familyKey,
    required String familyId,
    required String memberId,
    required int slot,
  });

  Map<String, String> expectedMembersByServiceUuid({
    required List<int> familyKey,
    required String familyId,
    required Iterable<String> memberIds,
    required DateTime at,
    int skewSlots = 1,
  });
}

final class WeeklyPresenceTokenCodec implements WeeklyPresenceTokenEncoder {
  WeeklyPresenceTokenCodec({
    this.slotDuration = weeklyPresenceTokenSlotDuration,
  }) {
    if (slotDuration.inMicroseconds <= 0) {
      throw ArgumentError.value(
        slotDuration,
        'slotDuration',
        'Must be greater than zero',
      );
    }
  }

  static const _familyKeyLength = 32;
  static const _maximumSignedInt64 = 0x7fffffffffffffff;
  static final _domain = utf8.encode('keepers.weekly-presence.v1');

  final Duration slotDuration;
  final DartHmac _hmac = DartHmac.sha256();

  @override
  int slotFor(DateTime at) {
    final microsecondsSinceEpoch = at.microsecondsSinceEpoch;
    if (microsecondsSinceEpoch < 0) {
      throw ArgumentError.value(at, 'at', 'Must not be before the Unix epoch');
    }
    return microsecondsSinceEpoch ~/ slotDuration.inMicroseconds;
  }

  @override
  String serviceUuid({
    required List<int> familyKey,
    required String familyId,
    required String memberId,
    required int slot,
  }) {
    _validateFamilyKey(familyKey);
    final normalizedFamilyId = _normalizedRequiredId(familyId, 'familyId');
    final normalizedMemberId = _normalizedRequiredId(memberId, 'memberId');
    _validateSlot(slot);

    final secretKey = SecretKeyData(
      Uint8List.fromList(familyKey),
      overwriteWhenDestroyed: true,
    );
    try {
      return _serviceUuidWithKey(
        secretKey: secretKey,
        familyId: normalizedFamilyId,
        memberId: normalizedMemberId,
        slot: slot,
      );
    } finally {
      secretKey.destroy();
    }
  }

  @override
  Map<String, String> expectedMembersByServiceUuid({
    required List<int> familyKey,
    required String familyId,
    required Iterable<String> memberIds,
    required DateTime at,
    int skewSlots = 1,
  }) {
    _validateFamilyKey(familyKey);
    final normalizedFamilyId = _normalizedRequiredId(familyId, 'familyId');
    if (skewSlots < 0) {
      throw ArgumentError.value(skewSlots, 'skewSlots', 'Must not be negative');
    }

    final currentSlot = slotFor(at);
    final firstSlot = currentSlot < skewSlots ? 0 : currentSlot - skewSlots;
    if (currentSlot > _maximumSignedInt64 - skewSlots) {
      throw ArgumentError.value(
        skewSlots,
        'skewSlots',
        'Extends past the supported slot range',
      );
    }
    final lastSlot = currentSlot + skewSlots;
    final normalizedMemberIds = <String>{
      for (final memberId in memberIds)
        if (memberId.trim().isNotEmpty) memberId.trim(),
    };
    final expected = <String, String>{};
    final ambiguousTokens = <String>{};
    final secretKey = SecretKeyData(
      Uint8List.fromList(familyKey),
      overwriteWhenDestroyed: true,
    );
    try {
      for (final memberId in normalizedMemberIds) {
        for (var slot = firstSlot; slot <= lastSlot; slot++) {
          final token = _serviceUuidWithKey(
            secretKey: secretKey,
            familyId: normalizedFamilyId,
            memberId: memberId,
            slot: slot,
          );
          if (ambiguousTokens.contains(token)) continue;

          final existingMemberId = expected[token];
          if (existingMemberId == null) {
            expected[token] = memberId;
          } else if (existingMemberId != memberId) {
            expected.remove(token);
            ambiguousTokens.add(token);
          }
        }
      }
    } finally {
      secretKey.destroy();
    }
    return Map<String, String>.unmodifiable(expected);
  }

  String _serviceUuidWithKey({
    required SecretKeyData secretKey,
    required String familyId,
    required String memberId,
    required int slot,
  }) {
    final mac = _hmac.calculateMacSync(
      _message(familyId: familyId, memberId: memberId, slot: slot),
      secretKeyData: secretKey,
      nonce: const [],
    );
    final uuidBytes = Uint8List.fromList(mac.bytes.take(16).toList());
    uuidBytes[6] = (uuidBytes[6] & 0x0f) | 0x80;
    uuidBytes[8] = (uuidBytes[8] & 0x3f) | 0x80;
    return _formatUuid(uuidBytes);
  }

  static Uint8List _message({
    required String familyId,
    required String memberId,
    required int slot,
  }) {
    final builder = BytesBuilder()
      ..add(_domain)
      ..addByte(0)
      ..add(_signedInt64(slot));
    _addLengthPrefixedUtf8(builder, familyId);
    _addLengthPrefixedUtf8(builder, memberId);
    return builder.takeBytes();
  }

  static void _addLengthPrefixedUtf8(BytesBuilder builder, String value) {
    final bytes = utf8.encode(value);
    if (bytes.length > 0xffffffff) {
      throw ArgumentError.value(value, 'identifier', 'UTF-8 value is too long');
    }
    final length = ByteData(4)..setUint32(0, bytes.length, Endian.big);
    builder
      ..add(length.buffer.asUint8List())
      ..add(bytes);
  }

  static Uint8List _signedInt64(int value) {
    final bytes = ByteData(8)..setInt64(0, value, Endian.big);
    return bytes.buffer.asUint8List();
  }

  static String _formatUuid(List<int> bytes) {
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  static String _normalizedRequiredId(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, field, 'Must not be empty');
    }
    return normalized;
  }

  static void _validateFamilyKey(List<int> familyKey) {
    if (familyKey.length != _familyKeyLength ||
        familyKey.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError.value(
        familyKey.length,
        'familyKey',
        'Must contain exactly $_familyKeyLength bytes',
      );
    }
  }

  static void _validateSlot(int slot) {
    if (slot < 0 || slot > _maximumSignedInt64) {
      throw ArgumentError.value(
        slot,
        'slot',
        'Must fit in a non-negative signed 64-bit integer',
      );
    }
  }
}
