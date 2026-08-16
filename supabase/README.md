# Keepers Supabase control plane

Supabase stores account identity, family roster metadata, invitation state,
token and recipient-email hashes, and the encrypted family-key envelope. It
must never receive a plaintext family key, member key, memory payload,
transcript, or media blob.

## Project setup

Install the Supabase CLI, sign in, and set the project URL, publishable key, and
project reference in the current PowerShell session. Link and deploy the
versioned migration with these commands:

```powershell
supabase link --project-ref $env:KEEPERS_SUPABASE_PROJECT_REF
supabase db push
flutter run --dart-define=KEEPERS_SUPABASE_URL=$env:KEEPERS_SUPABASE_URL --dart-define=KEEPERS_SUPABASE_PUBLISHABLE_KEY=$env:KEEPERS_SUPABASE_PUBLISHABLE_KEY
```

`KEEPERS_SUPABASE_URL` and `KEEPERS_SUPABASE_PUBLISHABLE_KEY` are client
configuration, not privileged credentials. A Supabase service-role key must
never be placed in Dart defines, committed to source control, or bundled in an
app build.

## Email OTP template

Email OTP is the only authentication method for this release. In the Supabase
Dashboard, configure the email OTP template to render the six-digit token using
the exact variable:

```text
{{ .Token }}
```

Do not replace it with a magic-link-only template. Keepers asks the user to
enter this token in the app.

## Database verification

The migration is idempotent and lives in `migrations/`. The executable pgTAP
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

The pgTAP transaction covers both serialized orderings (revoke then claim, and
claim then revoke), but a single pgTAP transaction cannot prove simultaneous
multi-session behavior. Before deployment, CI must start and reset an ephemeral
Supabase stack with the three commands above, then use two independent
PostgreSQL/PostgREST connections to release these calls at the same barrier:

1. Two recipients claim the same pending token. Exactly one may create the
   membership; the other must receive `P0001/ALREADY_CLAIMED`.
2. The recipient claims while the owner revokes the same pending invite. If
   revoke obtains the row lock first, claim must receive
   `P0001/INVITE_REVOKED`; if claim obtains it first, revoke must receive
   `P0001/ALREADY_CLAIMED`.
3. Two requests for the same previously unbootstrapped account call
   `bootstrap_owner_family` at the same barrier. With identical payloads, both
   calls must return the same successful result and create exactly one family,
   profile, and membership. With the same family/member IDs but any different
   family name, display name, demographic role, color, or avatar, the lock
   winner may succeed but the loser must receive `P0001/BOOTSTRAP_CONFLICT`;
   the committed profile and membership must contain only the winner's payload.

After each race, the CI step must query as its administrative test connection
and assert there is at most one membership, no claimed invitation is reported
as revoked, no revoked invitation has a membership created by that race, and a
bootstrap race never leaves mixed profile/membership fields. Bootstrap is
serialized before its initial membership probe with a transaction-scoped,
domain-separated 64-bit advisory lock derived from the complete authenticated
account UUID. A hash collision can only over-serialize unrelated accounts; it
cannot merge their data or weaken the replay checks.
This external multi-session gate is required in addition to `supabase test db`;
it was not run on the current CLI-less development host.

For the database-only CI job documented by Supabase, use:

```powershell
supabase db start
supabase test db
```

The database-only job is sufficient for pgTAP but does not replace the
independent two-session transition race described above.

## Family-code join-request rollout

Deploy `migrations/202609070001_family_code_join_requests.sql` before releasing
an app build that calls the family-code RPCs. The migration is additive: the
seven recipient-email invitation RPCs below remain callable during the legacy
compatibility window, while new clients use the eleven family-code RPCs.

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

Plaintext family codes and full family-join links are transient request inputs.
Redact them from API, proxy, database, crash, analytics, and support logs. Never
log joining private keys, family keys, approval shared secrets, or decrypted
envelopes. The database persists only a SHA-256 code hash, encrypted display
material, public keys, and ciphertext.

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

The seven authenticated RPCs are:

- `bootstrap_owner_family(uuid, text, uuid, text, text, text, jsonb)`
- `create_family_invite(uuid, uuid, text, text, jsonb)`
- `preview_family_invite(text)`
- `claim_family_invite(text, uuid, text, text, text, jsonb)`
- `complete_family_invite(uuid)`
- `revoke_family_invite(uuid)`
- `list_active_family_members(uuid)`

All invitation transitions execute through those RPCs. Client roles cannot
read `family_memberships` or mutate any backing table directly. The roster RPC
is the sole client projection of membership metadata, and unauthenticated
callers cannot execute any RPC.
