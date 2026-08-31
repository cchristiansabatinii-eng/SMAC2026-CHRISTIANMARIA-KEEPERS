import 'package:flutter_test/flutter_test.dart';
import 'package:keepers/features/capture/domain/capture_models.dart';

void main() {
  test('Capsule keeps the legacy authenticated storage token', () {
    expect(PrivacyTier.capsule.storageValue, 'legacy');
    expect(PrivacyTier.fromStorage('legacy'), PrivacyTier.capsule);
    expect(PrivacyTier.journal.storageValue, 'journal');
    expect(PrivacyTier.reveal.storageValue, 'reveal');
  });

  test('privacy storage decoding rejects non-wire values', () {
    for (final value in ['capsule', 'unknown', '', ' legacy ']) {
      expect(
        () => PrivacyTier.fromStorage(value),
        throwsA(isA<FormatException>()),
        reason: 'Unexpectedly accepted $value',
      );
    }
  });
}
