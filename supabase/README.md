# Keepers Supabase control plane

Supabase stores account identity, family roster metadata, family-code hashes,
encrypted display-code material, join-request state, public joining keys,
encrypted family-key envelopes, and the opaque family-key-encrypted Weekly
Reveal relay. It must never receive a plaintext family or member key, joining
private key, approval shared secret, decrypted envelope, private Journal or
Capsule entry, transcript, photo, audio, or text. Legacy recipient-email
invitation rows remain temporarily supported only for already-issued clients.

## Project setup

Install the Supabase CLI and sign in. From the repository root, link the target
project and inspect the remote/local migration ledger before changing it:

```powershell
supabase link --project-ref $env:KEEPERS_SUPABASE_PROJECT_REF
supabase migration list
supabase db push
supabase functions deploy keepers-auth-bridge --no-verify-jwt
```

`supabase db push` must apply the checked-in migrations in this exact order:

1. `migrations/202609050001_family_invitations.sql`
2. `migrations/202609070001_family_code_join_requests.sql`
3. `migrations/202609070002_membership_join_serialization.sql`
4. `migrations/202609080001_family_code_bootstrap_recovery.sql`
5. `migrations/202609080002_weekly_reveal_sync.sql`
6. `migrations/202609080003_weekly_reveal_create_only.sql`
7. `migrations/202609090001_family_code_cooldown_recovery.sql`
8. `migrations/202609090002_family_membership_timestamp_defaults.sql`

Do not release a family-code client until all eight appear in the linked
project's migration history. The first remains for compatibility, the second
adds permanent codes and join requests, and the third serializes every
membership-producing path with those requests. The fourth repairs the family
routines' SQL `COALESCE` expressions so owner bootstrap and code joining can
run. The fifth adds the private, RLS-protected encrypted Weekly Reveal relay,
and the sixth removes author updates so published ciphertext objects remain
immutable. The seventh repairs the family-code cooldown routine's invalid
schema-qualified `LEAST` expression. The eighth gives omitted membership
timestamps one statement-stable instant so valid inserts cannot violate their
own ordering constraint. Deploying the app before any of these migrations
leaves family membership or shared Weekly readiness incomplete.

Keep the client URL and publishable key in the ignored
`app/config/supabase.local.json`. From `app`, use the file without printing its
values:

```powershell
flutter run --dart-define-from-file=config/supabase.local.json
flutter build apk --debug --dart-define-from-file=config/supabase.local.json
```

`KEEPERS_SUPABASE_URL` and `KEEPERS_SUPABASE_PUBLISHABLE_KEY` are client
configuration, not privileged credentials. A Supabase service-role key must
never be placed in Dart defines, committed to source control, or bundled in an
app build. On 2026-09-07, the hosted Keepers project was verified with the first
three migration-history rows and the deployed `keepers-auth-bridge` function.
The fourth and fifth migrations are also deployed. Migrations six (create-only
hardening), seven (family-code cooldown recovery), and eight (membership
timestamp-default repair) are pending hosted deployment and migration-ledger
verification. The earlier migrations were submitted through Supabase's
official Management API because a
noninteractive CLI link also requires the database password. This proves the
hosted schema and callback deployment, but not the separate concurrency CI
gate.

## Account authentication and callback

Keepers requires account authentication before Create or Join family. A local
identity proceeds only with a current compatible session: a bound account must
match, while a newly created unbound identity is bound only after the owner
bootstrap succeeds. A mismatch or `DIFFERENT_FAMILY` keeps the device-local
family, keys, and memories intact and offers `Use another account`. If the
Supabase client is unconfigured, a new installation remains blocked at the
account screen with Retry. A Supabase session links an account to family
membership; it does not restore a device-held encryption key by itself. After
an approved join installs the family key, the device can reconcile only the
family's opaque encrypted Weekly Reveal entries into its SQLCipher vault.

Keepers supports email OTP plus Google, Microsoft, and Apple. In Authentication
→ URL Configuration, allow both the email HTTPS handoff and the final app
callback:

```text
https://<project-ref>.supabase.co/functions/v1/keepers-auth-bridge**
keepers://auth-callback**
```

The `**` suffix is required because Keepers adds a bounded, opaque `attempt`
query parameter to each runtime redirect. Keep the origin and path before that
suffix exact. Set the Site URL to the HTTPS handoff without the wildcard or a
query string so a missing or rejected runtime redirect never falls back to
localhost.

In Authentication → Providers, enable Google, Azure (Microsoft), and Apple and
configure each provider's production client ID and secret. At each provider,
register Supabase's OAuth callback exactly as:

```text
https://<project-ref>.supabase.co/auth/v1/callback
```

Keep the Azure email permission enabled; the app requests the required `email`
scope so Supabase receives the address used for the account.

Keep `keepers://auth-callback**` in Supabase's redirect allow list. The app
passes that URI with its per-attempt marker as the post-OAuth redirect and opens
authorization in the external browser; the provider returns to Supabase first,
then Supabase returns the session to Keepers. Development and production
projects need their own matching provider credentials and callback
registrations.

Keepers permits only one pending PKCE authentication flow. If a user chooses a
different method, the client atomically removes an unclaimed verifier before
enabling the replacement flow. If the callback has already claimed that
verifier, it remains the sole in-flight sign-in so two browser callbacks cannot
share or overwrite one local verifier slot. The opaque attempt marker is stored
with that verifier and returned through the callback, so a stale browser result
cannot consume or clear a newer pending flow.

Deploy `functions/keepers-auth-bridge` with JWT verification disabled. This is
the pre-login callback, so no session token exists yet. The endpoint validates
the single PKCE `code` plus an optional single attempt marker, returns a no-store
platform redirect, and does not read or mutate family data. Code-only links stay
supported for already-issued email messages. Android is sent to a package-scoped
`intent://` callback; iOS and other clients are sent to
`keepers://auth-callback`.

Supabase's hosted default email currently supplies the sign-in link. After
custom SMTP is configured, keep both the sign-in link and the six-digit token
available in Authentication → Email Templates using these exact variables:

```text
Sign in: {{ .ConfirmationURL }}
Code: {{ .Token }}
```

The sign-in link must use Supabase's confirmation URL and return first to the
HTTPS handoff. The handoff opens the installed Keepers app and resumes the
waiting account or family-Join flow. With the custom template above, entering
the six-digit token in the app establishes the same account session when an
email client blocks external-app links. Email authenticates the account; it no
longer carries or addresses a new family invitation. Do not ship a custom
template that omits both authentication recovery paths.

## Database verification

The migrations are idempotent and live in `migrations/`. The executable pgTAP
authorization and transition suite lives in `tests/`; neither directory is
ignored. Only local Supabase CLI runtime state under `.branches/` and `.temp/`
is ignored.

From the repository root, run the local database contract with:

```powershell
supabase start
supabase db reset --local
supabase test db --local
```

`supabase start` must succeed before either database command. The committed
`config.toml` enables migrations, disables the absent seed file, and contains
only local, non-secret settings.

### Required concurrent-transition CI gate

The family-code pgTAP suite contains 107 authorization, privacy, quota,
projection, expiry, and transition assertions. A single pgTAP transaction
cannot prove simultaneous multi-session behavior, so CI must also run the
deterministic two-session race harness:

```text
supabase start
supabase db reset --local
supabase test db --local
bash supabase/tests/run_family_code_join_request_races.sh
```

The race harness proves these five pairs against real PostgreSQL locks:

1. approve / approve;
2. approve / decline;
3. regenerate / request;
4. completion / expiry; and
5. the same requester completing into two families.

Every pair must produce one authoritative result, never two memberships or two
decisions. The dedicated CI job is the runtime authority because this Windows
development host has no local PostgreSQL, Docker, or Bash runtime for that
harness. Static SQL review and Flutter adapter tests are not substitutes, and
no green concurrency-run URL is claimed in this document until it is recorded.

## Family-code join-request rollout

After the legacy migration, deploy
`migrations/202609070001_family_code_join_requests.sql` followed by
`migrations/202609070002_membership_join_serialization.sql` before releasing an
app build that calls the family-code RPCs. The migrations are additive: the
seven recipient-email invitation RPCs below remain callable during the legacy
compatibility window, while new clients use the eleven family-code RPCs.

A code or link identifies a family but never grants membership. It creates a
request from an authenticated account that is not already in a family. Any
active member may approve or decline; only the family creator may regenerate
the permanent code. The requester installs the encrypted family key and durable
local recovery state before `complete_family_join_request` activates the single
membership. Realtime only prompts a fresh authoritative RPC read, and restart
recovery safely retries uncertain completion.

Family-code requests stay pending for exactly seven days. SQL permits one
unresolved request per account, limits a family to 100 pending requests, limits
an account to 10 created requests and 60 code lookup attempts per hour, and
applies an increasing invalid-attempt cooldown capped at five minutes. These
account controls do not provide an IP boundary. Production ingress must impose
and verify a separate per-IP throttle before the family-code release gate is
considered complete.

The account throttle is a private, RLS-enabled counter/timestamp table with no
code, code hash, or link field. Neutral lookup failures return the single JSON
field `{"errorCode":"FAMILY_NOT_FOUND"}` so the invalid-attempt update can
commit; clients must map that projection to the same Family not found state as
malformed and superseded codes.

Schedule a service-role-only maintenance call at least daily to purge resolved
join requests past the chosen operational retention cutoff. For a 30-day
retention window, call
`private.purge_family_join_requests(now() - interval '30 days')`; do not grant
that helper to client roles. Pending rows are lazily expired by authenticated
request RPCs, while scheduled maintenance removes only installed, declined,
cancelled, and expired rows older than the explicit cutoff.

The first-release operations policy is a daily privileged run with a 30-day
cutoff. Configure it through a trusted database/backend scheduler, never from a
mobile client, and record a successful execution plus the next scheduled run in
release evidence. The repository defines the helper but does not create the
production schedule; that gate is currently open.

The production API gateway/WAF must also throttle family-code preview and
request creation by source IP in addition to the SQL account controls. It must
return a generic rate-limit response without revealing code validity, redact
the submitted code and URL, and be tested across multiple authenticated
accounts from one IP. No ingress policy is checked into this repository, so the
IP-throttle gate is currently open.

Plaintext family codes and full family-join links are transient request inputs.
Redact them from API, proxy, database, crash, analytics, and support logs. Never
log joining private keys, family keys, approval shared secrets, or decrypted
envelopes. The database persists only a SHA-256 code hash, encrypted display
material, public keys, and ciphertext.

## Verified family-link deployment

The app accepts only `https://join.keepers.app/f/<code>` for family joining.
Manual entry of the same code remains usable even when verified-link hosting is
not ready. To enable direct native opening, publish both files over HTTPS with
`application/json`, no authentication, and no redirect:

- `https://join.keepers.app/.well-known/assetlinks.json`
- `https://join.keepers.app/.well-known/apple-app-site-association`

Android Digital Asset Links must name package `app.keepers.keepers` and the
SHA-256 fingerprint of the real release certificate. The current Gradle
`release` build uses the debug signing configuration, so its fingerprint is not
a production association and the Android verified-link gate is open.

iOS Universal Links must name application identifier
`<APPLE_TEAM_ID>.app.keepers.keepers` and allow only `/f/*`. Both checked-in
entitlement files request `applinks:join.keepers.app`, but no Apple Team ID,
distribution signature, hosted AASA response, or physical iOS verification is
recorded. The iOS verified-link gate is open.

Before release, verify the hosted files from an uncached client, confirm the
response bodies use the actual shipping identities, install those exact signed
builds, and exercise cold start, warm start, signed-out authentication/resume,
reopen, and app-not-installed/store fallback. Routing tests in this repository
prove parsing and app navigation only; they do not prove domain ownership or OS
association.

The eleven authenticated family-code RPCs are:

- `bootstrap_owner_family_with_code(uuid, text, uuid, text, text, text, jsonb, text, jsonb)`
- `get_family_join_code(uuid)`
- `preview_family_by_code(text)`
- `create_family_join_request(uuid, text, uuid, text, text, text, jsonb, text)`
- `list_pending_family_join_requests(uuid)`
- `get_own_family_join_request()`
- `approve_family_join_request(uuid, jsonb)`
- `decline_family_join_request(uuid)`
- `cancel_family_join_request(uuid)`
- `complete_family_join_request(uuid)`
- `regenerate_family_join_code(uuid, integer, text, jsonb)`

The seven legacy authenticated recipient-email RPCs retained for compatibility
are:

- `bootstrap_owner_family(uuid, text, uuid, text, text, text, jsonb)`
- `create_family_invite(uuid, uuid, text, text, jsonb)`
- `preview_family_invite(text)`
- `claim_family_invite(text, uuid, text, text, text, jsonb)`
- `complete_family_invite(uuid)`
- `revoke_family_invite(uuid)`
- `list_active_family_members(uuid)`

All membership transitions execute through the corresponding narrow RPCs.
Client roles cannot read `family_memberships` or mutate any backing table
directly. The roster RPC is the sole client projection of membership metadata,
and unauthenticated callers cannot execute any RPC.

## Current release-gate truth

The permanent-code schema, Dart gateway, crypto/storage units, requester and
approver controllers, and native route declarations have focused automated
coverage. The first five migrations, including the recovery and encrypted
Weekly Reveal relay, plus the unauthenticated callback bridge are recorded as
deployed to the hosted Keepers project. Migrations six (create-only hardening),
seven (family-code cooldown recovery), and eight (membership timestamp-default
repair) are pending hosted deployment and migration-ledger verification. This
does not establish a
launch-ready backend. A green PostgreSQL concurrency run, configured daily
purge job, verified external IP throttle, production Android signing and hosted
Digital-Asset-Links/AASA files, two-physical-phone Android join run, iOS
runtime/accessibility run, and a release proximity source are not yet recorded
and must remain open release gates.
