# Weekly Waiting-Room BLE Presence Design

Date: 2026-09-08

## Goal

Make the Weekly waiting room detect which active family members have the room
open on nearby phones, entirely offline. The existing three-quarters quorum
remains the only gate that enables `START WEEKLY EXPERIENCE`.

## Product boundary

Presence is physical, foreground-only, and ephemeral. A phone participates only
while its signed-in member is viewing the Weekly waiting room. Closing the room,
starting the experience, switching account/family, or backgrounding the app stops
both advertising and scanning and immediately clears remote attendance.

No cloud heartbeat, location history, BLE hardware identifier, or attendance
record is persisted. The current member is still counted locally; only other
members require a fresh authenticated-family beacon.

## On-air protocol

Each participant advertises one rotating 128-bit BLE service UUID. It is derived
from HMAC-SHA256 using the locally stored 32-byte family key over this canonical
message:

`keepers.weekly-presence.v1|<family-id>|<member-id>|<10-second-slot>`

The first 16 MAC bytes become an RFC 4122-shaped UUID. This format works across
Android and iOS because both platforms advertise service UUIDs. It does not put
raw family IDs, member IDs, names, family codes, or stable identifiers on air.

Scanners run continuously without filters while the room is open, avoiding
Android's scan-restart rate limit. For the active roster they precompute the
current, previous, and next slot UUIDs, which tolerates modest clock skew and
rotation overlap. Unknown UUIDs and removed roster members are ignored.

The shared family key makes the beacon family-private and resistant to outsiders,
but it is a discovery proof, not malicious-insider-proof individual attestation.
The later local ceremony challenge/response remains responsible for stronger
participant authentication.

## Attendance semantics

Every recognized member has an independent `lastSeenAt`. A member counts only
for 15 seconds after their own most recent beacon. Another member's beacon cannot
extend that deadline. Future-dated observations, unavailable radio state, startup
failure, permission denial, and Bluetooth-off state all fail closed.

The presentation provider keeps the existing synchronous snapshot shape so the
waiting-room UI and start-time recheck do not race an asynchronous stream. The
snapshot adds per-member timestamps while preserving the existing aggregate
constructor for tests and injected adapters.

## Components

- `WeeklyPresenceTokenCodec`: deterministic rotating UUID creation and roster
  lookup, with key material supplied by the caller.
- `WeeklyPresenceRadio`: narrow advertise/scan/status seam.
- `FlutterWeeklyPresenceRadio`: production bridge using
  `flutter_ble_peripheral` 3.1.0 and pinned `flutter_blue_plus` 2.3.12.
- `WeeklyPresenceSession`: generation-guarded orchestration, key zeroization,
  token rotation, independent expiry, and radio recovery.
- Riverpod providers: own one family-scoped session and expose its latest
  fail-closed snapshot plus explicit start/stop actions.
- `ObservatoryScreen`: starts only after entering the waiting room, updates the
  active roster, and stops on every exit, lifecycle pause, identity change, and
  successful Start transition.

## Platform behavior

Android declares BLE scan/connect/advertise permissions plus API-30-and-earlier
Bluetooth/location compatibility permissions. BLE hardware remains optional so
unsupported phones fail closed instead of being excluded from installation.

iOS declares `NSBluetoothAlwaysUsageDescription`. No Bluetooth background mode
is enabled: background operation would violate the foreground-only room contract.

## Failure and privacy behavior

- Permission prompts happen only when a user deliberately enters the room.
- Unsupported, denied, off, or failed radios expose no remote members.
- A later ready adapter state starts a fresh radio session; stale callbacks from
  prior generations are ignored.
- Family-key copies are mutable only inside the active session and are overwritten
  on stop, error, replacement, or late start completion.
- Bluetooth addresses and scan payloads are neither logged nor stored.

## Verification

Pure tests cover deterministic/non-identifying UUIDs, family/member/slot
separation, skew windows, and outsider rejection. Session tests use a fake radio
and clock/tickers for start, stop, deduplication, independent expiry, rotation,
failure recovery, identity replacement, late-event rejection, and key cleanup.
Widget tests prove the Observatory lifecycle boundary and that presence never
loads Weekly content before an accepted Start. Static platform tests verify the
required manifest/plist declarations. Android compile verification catches plugin
registration/API drift; two physical phones remain the final radio validation.
