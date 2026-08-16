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

## Supabase family invitations

Cloud configuration is optional. Without it, ordinary capture and browsing remain available against the encrypted local database; only Invite and Join report that family invitations are unavailable. A configured build receives exactly these client-visible Dart defines:

- `KEEPERS_SUPABASE_URL`: the project's HTTPS API URL.
- `KEEPERS_SUPABASE_PUBLISHABLE_KEY`: a Supabase publishable key, or a legacy anon JWT while that project still uses one.

Both values must be present and valid together. They authorize no privileged operation by themselves: the signed-in JWT, row-level security, and the migration's RPCs enforce access. Never put a Supabase service-role key in Dart defines, source control, a mobile build, CI logs, or documentation.

From the repository root, link the intended project and apply the checked-in migration:

```powershell
supabase link --project-ref $env:KEEPERS_SUPABASE_PROJECT_REF
supabase db push
```

Then run the configured client from this `app` directory:

```powershell
flutter run --dart-define=KEEPERS_SUPABASE_URL=$env:KEEPERS_SUPABASE_URL --dart-define=KEEPERS_SUPABASE_PUBLISHABLE_KEY=$env:KEEPERS_SUPABASE_PUBLISHABLE_KEY
```

`supabase db push` must apply `supabase/migrations/202609050001_family_invitations.sql`. Verify the migration and its concurrency contract locally from the repository root:

```powershell
supabase start
supabase db reset --local
supabase test db --local
```

`supabase/config.toml` is nonsecret project configuration: PostgreSQL 17, migrations enabled, and seed execution disabled. The Supabase project's email template is separate server configuration and must render `{{ .Token }}` so sign-in sends the six-digit email OTP expected by Keepers. A magic-link-only template does not satisfy the flow. See `../supabase/README.md` for the RPC, RLS, expiry, replay, and race-verification contract.

### Invitation link and privacy contract

The only accepted invitation URI is:

```text
keepers://join?v=1&i=<invite-id>&t=<token>&s=<wrapping-secret>
```

Android declares only scheme `keepers` plus host `join` with `VIEW`, `DEFAULT`, and `BROWSABLE`; iOS declares the `keepers` URL scheme. Flutter's automatic deep-link handler is disabled on both platforms so the app's one-shot coordinator owns cold-start and warm-link delivery. This sprint intentionally does not claim universal links, Android App Links, domain verification, associated domains, wildcards, or web fallback.

Treat the complete URI as a bearer capability. The wrapping secret remains on the sender/recipient devices and is never sent to Supabase. Do not log, persist in route restoration, copy to analytics or diagnostics, expose through a clipboard helper, or include the link in screenshots. The Invite screen hands it directly to the operating-system share sheet for a named recipient.

Supabase stores only account identity, family roster metadata, invitation state, hashes of the recipient email and token, and the encrypted family-key envelope. It must never receive a plaintext family key or member key, memory payload, journal, reveal/kept content, transcript, or media. A recipient's private member key is generated locally after acceptance.

Only the original family owner may create or revoke invitations. Invitations are bound to one normalized email address, expire after 24 hours, are one-time and revocable before acceptance, and accept idempotently only for the same claimant. A device already joined to another family fails without changing local or remote membership.

### Offline and release acceptance

The SQLCipher roster is the canonical offline cache. A failed refresh keeps cached members visible; a successful remote refresh upserts the returned roster before publishing it. Membership is append-only in this sprint because removal and tombstone sync are out of scope. Invite and Join show honest configuration or network failures and never claim completion while offline.

Unit, widget, fake-gateway integration, and static platform tests are necessary but are not live-backend proof. Release certification also requires one migrated Supabase project and two physical devices built with the same URL and publishable key. The matrix must demonstrate owner invite/share, recipient email OTP and binding, acceptance, the same persisted roster on both phones after restart, unused-invite revocation, expiry/replay/wrong-email rejection, offline cached-roster behavior, and the absence of memory plaintext or plaintext keys in Supabase. Until evidence is recorded for that matrix—including live pgTAP/race execution, live OTP/RPC behavior, physical two-device behavior, and iOS runtime/accessibility review—those checks remain explicit gaps rather than passed checks.

## Commands

Run these from this directory:

    flutter pub get
    flutter analyze --fatal-infos
    flutter test

Do not add family content, database files, secrets, or exported keys to source control.
