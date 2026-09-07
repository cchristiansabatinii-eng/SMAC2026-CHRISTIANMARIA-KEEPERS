# Keepers Flutter app

The mobile client is generated from Flutter stable and targets Android and iOS.

## Foundation

- Riverpod owns dependency lifecycles from the root ProviderScope.
- SQLCipher encrypts the SQLite database at rest.
- A random 256-bit database key is stored through Android Keystore or Apple Keychain via flutter_secure_storage.
- The normalized v1 schema mirrors every entity in Section 4.2 of the Keepers specification.
- Database opening is lazy; the home screen does not touch device storage until a feature requests the database provider.

## Native encrypted-storage contract

- Production persistence is native-gated for Android x64/arm64, iOS arm64, Linux x64, and macOS x64/arm64. Every other ABI fails before filesystem mutation.
- Each removal gets a freshly created, euid-owned `0700` directory capability that is never adopted from disk. Cooperative app writers therefore never share a candidate pathname.
- Mobile sandboxing and app-private roots exclude other principals. Hostile or non-cooperating same-euid writers are outside this contract: POSIX discretionary permissions cannot provide mandatory exclusion from the owning identity.
- Physical Android and iOS acceptance remains part of the Phase 0 Task 9 device matrix; CI runs the same production persistence smoke on an Android emulator and iOS simulator.

## Weekly waiting-room presence

The production waiting room uses foreground Bluetooth Low Energy to discover
nearby signed-in family members who also have the room open. Each phone
advertises a rotating, family-keyed service UUID and scans only for roster
members' current tokens; raw family/member identifiers, device addresses, and
scan payloads are not persisted or logged. Remote attendance expires per member
after 15 seconds and fails closed when Bluetooth is off, permission is denied,
the app backgrounds, the room closes, or identity changes. Weekly content is
loaded only after Start performs a fresh photo-progress and three-quarter-quorum
check.

Android declares foreground scan/connect/advertise permissions and iOS declares
the Bluetooth usage description without background modes. The BSD-licensed
`flutter_ble_peripheral` 3.1.0 runtime is vendored under
`packages/flutter_ble_peripheral`; its local native patch resolves Android's
advertiser at call time, defers Darwin CoreBluetooth creation until first use,
and removes advertisement-payload logging. A two-physical-phone Android/iOS
matrix is still required before treating proximity as release-ready.

## Supabase family membership

Supabase configuration is required for a new installation to pass account setup
and access the app's normal family/local-memory flow. If the client is
unconfigured, startup remains blocked on the account setup screen with Retry;
configure `app/config/supabase.local.json` before running the app. Existing
device-local encrypted data is not deleted, but it is not reachable through the
normal startup flow until the required account configuration is available.

### Local configuration and exact build commands

Keep the two client-visible Dart defines in the ignored file
`app/config/supabase.local.json`:

- `KEEPERS_SUPABASE_URL`
- `KEEPERS_SUPABASE_PUBLISHABLE_KEY`

Do not commit or print that file. Both values must be present and valid together.
They are mobile client configuration, not administrative credentials; the
authenticated session, row-level security, and narrow RPCs enforce access.
Never place a service-role key in this file, Dart defines, source control, a
mobile build, logs, screenshots, or documentation.

From the `app` directory, run the configured client with:

```powershell
flutter run --dart-define-from-file=config/supabase.local.json
```

Build the Android demo APK with:

```powershell
flutter build apk --debug --dart-define-from-file=config/supabase.local.json
```

The eventual Play-distribution command is:

```powershell
flutter build appbundle --release --dart-define-from-file=config/supabase.local.json
```

The current Android `release` build type still uses the debug signing key. A
release-mode artifact may therefore be useful for local testing, but it is not a
store-ready or verified-App-Link artifact. Configure and protect the real release
keystore first, then rebuild and use that certificate's SHA-256 fingerprint for
the production association file.

### Permanent family-code flow

- A family receives one eight-symbol code, displayed as `XXXX-XXXX`, only after
  authenticated cloud bootstrap returns the authoritative record.
- Every active family member can view and share the code or
  `https://join.keepers.app/f/<code>` link. Only the creator can regenerate it.
- A signed-in account with no family enters the code or follows the link, sees
  only the family name and public avatar preview, and submits a join request.
- Any active member can approve or decline. The first valid decision wins.
- Approval encrypts the family key to a requester-owned X25519 joining key. The
  requester installs keys, roster, identity, and a durable recovery marker
  locally before the completion RPC activates membership.
- Pending requests expire after seven days. The first release permits one family
  membership per account.

Manual code entry is the reliable release path and does not depend on control of
`join.keepers.app`. The HTTPS link opens natively only after Android Digital Asset
Links or iOS Universal Links are published and verified with the real production
signing identities. Until then, a copied code can still be entered manually.

Email is used only for Supabase account authentication and recovery; family
invitations are no longer addressed or delivered by email. The legacy
recipient-email RPCs remain deployed temporarily for already-issued builds but
new clients do not create them.

### Privacy, offline behavior, and recovery

The plaintext family code and full family link are transient user-invoked inputs.
Do not write them to analytics, crash reports, API/proxy logs, diagnostics,
screenshots, or route restoration. Supabase stores code hashes, encrypted display
material, public keys, ciphertext, request state, account identity, and roster
metadata. It must never receive memory payloads, plaintext family/member keys,
joining private keys, approval shared secrets, or decrypted envelopes.

The SQLCipher roster is the durable offline cache. A failed refresh keeps cached
members visible. Realtime is only an invalidation signal; resume and reconnect
perform authoritative RPC reads. If completion is uncertain, the exact encrypted
local marker is retained and startup retries completion without reinstalling or
creating another membership.

### Backend and release acceptance

The backend must deploy before the client, in this order:

1. `supabase/migrations/202609050001_family_invitations.sql`
2. `supabase/migrations/202609070001_family_code_join_requests.sql`
3. `supabase/migrations/202609070002_membership_join_serialization.sql`
4. `supabase/migrations/202609080001_family_code_bootstrap_recovery.sql`
5. `supabase/migrations/202609080002_weekly_reveal_sync.sql`
6. `supabase/migrations/202609080003_weekly_reveal_create_only.sql`
7. `supabase/migrations/202609090001_family_code_cooldown_recovery.sql`
8. `supabase/migrations/202609090002_family_membership_timestamp_defaults.sql`
9. `supabase/functions/keepers-auth-bridge`, for account-email callback handoff
10. purge scheduling and an external per-IP throttle
11. the configured mobile build

See `../supabase/README.md` for exact deployment, retention, link-association,
and database verification steps.

Unit/widget tests and static platform checks are not live release evidence. The
first five hosted migrations and the mobile auth callback bridge are deployed.
The sixth, create-only hardening migration and the seventh, family-code cooldown
recovery migration, plus the eighth, membership timestamp-default repair, are
pending hosted deployment and migration-ledger verification. There is no
recorded PostgreSQL concurrency run, production IP
throttle, purge job, release-signing certificate, published domain association,
two-physical-phone family-code run, iOS runtime/accessibility pass, or physical
BLE proximity matrix. Manual-code joining is the reliable demo path; the
verified-link/store release remains gated by the missing external evidence.

Capsule payloads, assignments, and task-completion state remain local to the
capturing device. Cross-device Capsule delivery and unlock synchronization are
not implemented in this build.

## Commands

Run these from this directory:

    flutter pub get
    flutter analyze --fatal-infos
    flutter test

Do not add family content, database files, secrets, or exported keys to source control.
