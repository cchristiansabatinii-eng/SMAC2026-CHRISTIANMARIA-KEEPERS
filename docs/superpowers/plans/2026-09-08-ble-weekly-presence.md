# Weekly Waiting-Room BLE Presence Implementation Plan

Date: 2026-09-08

1. Add RED tests for rotating HMAC service UUIDs, clock-skew matching, and
   non-disclosure of raw identifiers.
2. Implement the pure token codec and make those tests green.
3. Add RED tests around a fake `WeeklyPresenceRadio` for foreground start/stop,
   roster filtering, duplicate sightings, independent 15-second expiry, token
   rotation, radio failure/recovery, identity replacement, stale callbacks, and
   key zeroization.
4. Implement the generation-guarded `WeeklyPresenceSession`, its synchronous
   snapshot bridge, and explicit session actions.
5. Add Observatory lifecycle tests proving that waiting-room entry starts the
   session and close, Start, background, identity change, and disposal stop it.
   Keep existing start-time quorum and no-decryption assertions green.
6. Wire session actions into `ObservatoryScreen` and update the roster only while
   waiting.
7. Pin `flutter_blue_plus` 2.3.12, add `flutter_ble_peripheral` 3.1.0, implement
   the production radio adapter, and add required Android/iOS declarations.
8. Update the sync documentation and prior Weekly design to describe the live
   adapter and foreground BLE constraint.
9. Format; run focused sync/Observatory/platform tests, analyzer, full Flutter
   suite, and Android debug APK build. Run independent code/security review and
   fix actionable findings.
10. If the configured phone reconnects, install and relaunch the APK. Report iOS
    and two-phone physical-radio validation as outstanding when unavailable.
