# Sync

BLE presence, local session transport, transfer framing, and NFC/QR ritual code belong here. Current-week Weekly Reveal entries also use the private family relay: devices upload only the existing family-key-encrypted envelope plus strict routing and integrity metadata, then verify that ciphertext before importing it into the local encrypted vault. Private Journal and Capsule entries never use this relay, and plaintext or encryption keys never leave a family device.

`weekly_family_presence_provider.dart` is the fail-closed presentation boundary for the Weekly waiting room. Its production session uses `flutter_weekly_presence_radio.dart` to advertise and scan only while the waiting room is foreground. Rotating HMAC-derived service UUIDs avoid broadcasting raw family or member identifiers. Every nearby roster member expires independently after 15 seconds, and unsupported, denied, off, backgrounded, or failed radios expose nobody.

The beacon is a private family discovery signal, not malicious-insider-proof identity attestation: every device with the shared family key can derive the roster tokens. The ceremony's stronger challenge/response remains a separate session-layer responsibility.

`WeeklyRevealSyncService` is the idempotent cloud reconciliation boundary. It publishes only pending Reveal entries authored by the current member, rejects wrong-family or digest-mismatched downloads, and leaves local ciphertext authoritative when the network is unavailable. Supabase Realtime invalidates the vault manifest so each joined account sees the family's shared five-photo readiness without carrying presence or plaintext through the cloud.
