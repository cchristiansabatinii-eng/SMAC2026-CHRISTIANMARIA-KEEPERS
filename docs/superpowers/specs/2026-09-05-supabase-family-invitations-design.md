# Supabase Family Invitations Design

## Status and decision

Approved direction: remote, account-backed family invitations using Supabase.
The user explicitly chose the remote option and asked for implementation to
continue unattended. This specification records the smallest complete version
of that direction.

Keepers remains local-first for memory content. Supabase is a control plane for
accounts, family membership, invitation state, and encrypted key envelopes. It
must never receive a plaintext family key, member key, journal entry, reveal
entry, kept-memory payload, transcript, or media blob.

## Product outcome

A family creator can tap the dashed `INVITE` bubble, authenticate with email,
enter a relative's email address, and share a single-use invitation link. A
recipient who already has Keepers can open the link, authenticate with the
invited email address, review the family, choose their name and avatar, and
join. Both devices then load the same persisted family roster and the new member
appears on the Family Wheel.

The feature is complete only when:

- the current placeholder snackbar is gone;
- the invite link is expiring, single-use, recipient-bound, and revocable before
  acceptance;
- the recipient can recover from a cold-start or warm-start link;
- the family key is encrypted on the inviter's phone and decrypted only on the
  recipient's phone;
- the recipient's private member key is generated locally and never uploaded;
- the roster is loaded from durable data rather than hard-coded relatives;
- retrying a partially completed join does not create duplicate members;
- local-only capture and existing screens still work when Supabase is absent or
  temporarily unreachable.

## Deliberate first-release constraints

- Email authentication is the only account method. A Supabase sign-in link and
  six-digit email token are equivalent routes to the same account session.
- The original family creator is the owner and is the only person allowed to
  create or revoke invitations.
- An invitation targets one normalized email address, expires after 24 hours,
  and can be claimed once.
- A device that already belongs to a different family cannot accept an invite.
  Multi-family accounts and destructive family switching are out of scope.
- Membership synchronization is cloud-backed; memory payload synchronization,
  notifications, contacts access, member removal, family-key rotation, and
  account recovery are out of scope.
- Existing local families are linked to the owner's Supabase account lazily when
  the owner first opens Invite. Normal capture and browsing do not require an
  account.
- App configuration is supplied using `KEEPERS_SUPABASE_URL` and
  `KEEPERS_SUPABASE_PUBLISHABLE_KEY` Dart defines. No service-role key or secret
  is shipped in the app.

## User journeys

### Owner creates an invitation

1. The owner taps the dashed `INVITE` bubble.
2. If Supabase is not configured, the screen explains that cloud invitations
   are unavailable in this build and exposes a retry after configuration. It
   never claims that an invitation was sent.
3. If unauthenticated, the owner enters an email address and requests an email.
   The stable button changes to a busy state without moving.
4. The owner opens the sign-in link routed through `keepers://auth-callback` or
   enters the six-digit code. On success, Keepers links the existing local family
   and current local member to that account as the family owner.
5. The owner enters the recipient's email and selects `CREATE INVITATION`.
6. Keepers generates an invite ID, bearer token, and wrapping secret locally.
   It resolves the existing family key from secure storage, derives a wrapping
   key, encrypts the family key, and uploads only hashes and ciphertext.
7. The app opens the operating-system share sheet with a `keepers://join` link.
   The screen also shows expiry, recipient address, and a `CANCEL INVITATION`
   action while the invitation is still pending.
8. Creation, authentication, network, and share failures retain the entered
   email and expose an inline retry. Duplicate taps cannot create two invites.

### Recipient accepts an invitation

1. Android or iOS routes `keepers://join` to Keepers. The app retains the link
   through cold start, warm start, authentication, and temporary navigation.
2. If this installation already belongs to another family, Keepers stops before
   any mutation and explains that family switching is not yet supported.
3. The recipient authenticates by opening the Supabase email sign-in link or by
   entering its six-digit code. Supabase verifies that the account's normalized
   email hash matches the invitation's recipient hash.
4. Keepers previews the family name, owner name, and expiry without exposing the
   encrypted key or token in logs or visible copy.
5. The recipient enters their display name and selects a Humation avatar.
6. `JOIN FAMILY` claims the invitation idempotently and returns the encrypted
   family-key envelope plus the active roster.
7. The app decrypts the envelope, writes the family key and a newly generated
   member key to platform secure storage, then commits the family, roster, and
   explicit local-identity binding to SQLCipher in one transaction.
8. Only after local persistence succeeds does the app call the completion RPC.
   It then invalidates identity and roster providers and opens the Family Wheel.
9. If the app is interrupted after claim, the same account and link can resume.
   Wrong secrets, tampered envelopes, expired links, revoked links, email
   mismatches, and server failures fail closed and preserve existing local data.

### Existing family roster

- The Family Wheel observes a family-roster provider backed by the local
  SQLCipher cache and refreshed from Supabase when authenticated and online.
- The current local member is excluded from the relative list and still renders
  as `YOU`.
- Other active members render using their persisted name, immutable color token,
  and Humation avatar recipe.
- Cloud membership does not assert physical presence. Remote members remain
  `away` until the foreground, family-private BLE waiting-room session observes
  their current rotating token nearby.
- The dashed bubble remains `INVITE`. `Ask … to come` is a separate nudge action
  and must not create a membership invitation or claim that a message was sent.

## Architecture

### Application boundaries

`CloudFamilyGateway` is the only application-facing cloud contract. Controllers
and widgets depend on this interface rather than `SupabaseClient`. Its Supabase
adapter maps RPC payloads into immutable domain values and converts remote
failure codes into typed invitation failures.

`FamilyInviteController` owns owner authentication, local-family bootstrap,
invitation creation, share state, cancellation, and duplicate-submit guards.

`FamilyJoinController` owns incoming-link validation, recipient authentication,
preview, claim, envelope decryption, local persistence, completion, and recovery.

`FamilyRosterRepository` owns local roster queries and idempotent remote-member
upserts. `familyRosterProvider` emits cached data first, then refreshes through
the gateway when available.

`InviteLinkCoordinator` owns cold-start and warm-start links. It emits parsed
`FamilyInviteLink` values and never logs their raw URI.

`FamilyKeyEnvelopeCodec` owns key derivation and AES-256-GCM wrapping. Raw tokens,
wrapping secrets, family keys, and member keys are byte values that are never
placed in widget state diagnostics, SQLite, analytics, or error strings.

### Local schema version 4

Add:

```sql
CREATE TABLE local_identity_binding (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  family_id TEXT NOT NULL,
  member_id TEXT NOT NULL,
  account_id TEXT,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE,
  FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE
);
```

Existing installations are backfilled on first read by selecting the earliest
adult with a non-null local member-key reference, then permanently binding that
member. New-family setup and remote join insert the binding transactionally.

Remote roster members use the existing `members` table. Their
`member_key_ref` is null because another person's private key does not belong on
this device. Repository upserts never overwrite the locally bound member's key
reference or avatar draft with stale cloud data.

### Supabase schema

The repository contains an idempotent SQL migration defining:

- `profiles`: account ID and non-sensitive display metadata;
- `cloud_families`: family ID, name, owner account ID, timestamps;
- `family_memberships`: family ID, account ID, stable member ID, display name,
  demographic role, color token, avatar JSON, membership role
  (`owner`/`member`), state (`pending_key`/`active`), timestamps;
- `family_invites`: invite ID, family ID, creator account ID, normalized
  recipient email hash, token hash, envelope version, nonce, ciphertext, MAC,
  state (`pending`/`claimed`/`accepted`/`revoked`), claimant account ID,
  expiry and timestamps.

Direct table access is denied by default. Row Level Security allows active family
members to read their family's active roster and their own profile. Invitation
mutation happens through security-definer RPCs that set a safe search path,
validate `auth.uid()`, normalize and hash the authenticated email, enforce owner
authorization, check expiry/state, and return only the fields required by the
current transition.

RPCs:

- `bootstrap_owner_family(...)`
- `create_family_invite(...)`
- `preview_family_invite(token)`
- `claim_family_invite(token, member profile)`
- `complete_family_invite(invite_id)`
- `revoke_family_invite(invite_id)`
- `list_active_family_members(family_id)`

Claim and completion are idempotent for the same authenticated account. A token
cannot be claimed by a different account after the first claim.

## Invitation link and envelope

The link is versioned:

```text
keepers://join?v=1&i=<invite-id>&t=<token>&s=<wrapping-secret>
```

The token and wrapping secret are independent 256-bit random values encoded as
unpadded base64url. Supabase stores only SHA-256 of the normalized token. The
wrapping secret is never sent to Supabase.

The family-key envelope uses HKDF-SHA-256 to derive an AES-256-GCM key from the
wrapping secret. The salt is the invite UUID bytes and the info string is
`keepers-family-invite-v1`. Associated data is the UTF-8 value
`v1:<invite-id>:<family-id>`. Supabase stores the random 96-bit nonce,
ciphertext, and 128-bit authentication tag separately. Decryption rejects wrong
versions, lengths, associated data, secrets, or tags.

The link is a sensitive bearer capability. UI copy tells the owner to send it
only to the named recipient. It is excluded from logs, crash messages, analytics,
clipboard helpers, screenshots generated by the app, and persisted navigation
state. Recipient email binding, 24-hour expiry, one-time claim, and owner
revocation limit exposure through the chosen messaging channel.

## Interface design

The feature extends the existing pale background, uppercase Schibsted Grotesk,
20/600 tracked heading token, quiet dividers, black actions, and edge-to-edge
navigation. It does not introduce gradients, glass, shadows, new decorative
cards, or a new navigation destination.

### Invite screen

- Contextual back navigation and heading `INVITE FAMILY`.
- A short privacy statement: `MEMORIES STAY ENCRYPTED. THIS INVITATION ONLY ADDS
  A FAMILY MEMBER.`
- Authentication appears inline as two deliberate steps: email, then six-digit
  code. Errors stay below the relevant field.
- Once authenticated, one email field and one full-width `CREATE INVITATION`
  button are shown.
- Pending success shows recipient, expiry, `SHARE AGAIN`, and
  `CANCEL INVITATION`; it never says the recipient joined before acceptance.

### Join screen

- Heading `JOIN FAMILY` and an explicit loading state while the invitation is
  checked.
- Expired, revoked, already-used, wrong-account, malformed-link, offline, and
  configuration failures each have plain-language recovery.
- Valid preview shows family name and inviter before any acceptance.
- Name and avatar inputs reuse setup and avatar-editor patterns.
- The fixed `JOIN FAMILY` action remains stable while busy and prevents duplicate
  submission.
- Success transitions to the Wheel only after local key and roster persistence.

All controls have at least 44 logical pixels of hit area, errors are accessible
live regions, keyboard traversal follows visual order, focus moves to the first
invalid field, and the flow remains usable at 390×844 with 1.4× text scaling.

## Error and recovery model

Typed failures include: `notConfigured`, `signedOut`, `invalidEmail`,
`invalidOtp`, `networkUnavailable`, `forbidden`, `notOwner`, `malformedLink`,
`expired`, `revoked`, `alreadyClaimed`, `emailMismatch`, `differentFamily`,
`envelopeRejected`, `localPersistenceFailed`, and `unknown`.

Network operations are pessimistic. Buttons disable only for the active
operation. Entered values and parsed link material remain available for retry in
memory. Local database and secure-storage writes use compensating cleanup:
created key references are deleted if the SQL transaction fails, and completion
is not called. A claimed invitation can be resumed by the same account.

## Configuration and deployment

The app reads only the Supabase project URL and publishable key from Dart
defines. Both are expected to be present in distributed clients and receive no
privileged database access without a valid user JWT and RLS. The service-role key
exists only in Supabase infrastructure and repository tooling; it is never
committed or bundled.

Without configured values, the main local application continues to operate and
the Invite/Join routes present an honest configuration error. A live cross-phone
acceptance cannot be certified until a Supabase project runs the included
migration and its URL/publishable key are provided to both signed builds.

## Verification

Automated coverage includes:

- invitation link round-trip and malformed/length/version rejection;
- envelope round-trip plus wrong-secret, tamper, wrong-invite, and wrong-family
  rejection;
- schema v4 upgrade, explicit identity binding, local roster upsert, and
  preservation of local key references;
- controller state transitions for authentication, creation, cancellation,
  preview, claim, local persistence, completion, retry, interruption, and
  duplicate taps;
- Invite and Join widget success/loading/error/accessible/responsive states;
- cold-start and warm-start link routing;
- the Family Wheel rendering only real persisted relatives;
- existing capture, archive, ceremony, avatar, and navigation regressions.

Repository verification runs format, analyze, the complete Flutter test suite,
an Android debug build, the strict premium UI audit, and SQL static checks. A
production acceptance pass additionally requires two physical devices and a
configured Supabase project: invite, share, authenticate as recipient, accept,
observe the same roster on both phones, restart both apps, revoke an unused
invite, reject expiry/replay/wrong email, and confirm no memory payload or
plaintext family key is present in Supabase.
