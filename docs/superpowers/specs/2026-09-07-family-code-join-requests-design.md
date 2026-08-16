# Family Code And Join Requests Design

**Status:** Approved in conversation on 2026-09-07; awaiting written-spec review before implementation planning.

## Purpose

Replace recipient-email family invitations with a permanent family code and a
native family link. The code makes a family easy to find, while an explicit
approval from an existing member prevents possession of the code from granting
access. Account authentication remains a prerequisite, but family membership
no longer depends on receiving a family invitation code or link by email.

This design covers family discovery, join requests, approval, secure family-key
delivery, and the related interfaces. It does not replace the separate account
sign-up/sign-in work or implement remote memory storage.

## Product Decisions

- One authenticated account can belong to one family in the first release.
- Every family receives one permanent, human-readable code when it is created.
- The code stays unchanged until the family creator regenerates it.
- Every active family member can view and share the code and family link.
- Any active family member can approve or decline a join request, including a
  member represented as a child profile.
- Only the family creator can regenerate the family code.
- Regenerating the code invalidates the previous code and link and cancels all
  outstanding, unapproved requests made with the previous version.
- A code or link creates a join request. It never grants membership directly.
- A join request expires seven days after creation.
- Push notifications are not required in the first release. Realtime updates
  and refresh-on-resume provide request status and approval notices.

## Alternatives Considered

### Code grants immediate access

This is the shortest flow, but anyone who sees a screenshot or forwarded link
could enter the family. It also turns a permanent, visible code into a durable
security credential. Rejected.

### Permanent code creates an approval request

The code identifies the family and an existing member authorizes entry. It is
easy to understand, preserves a stable family-room identity, and supports a
safe cryptographic handoff. Selected.

### Rotating or single-use invitation codes

This reduces the lifetime of leaked codes but removes the always-present family
code and repeatedly interrupts sharing. Rejected for the first release.

## User Experience

### Main family interface

The top-right area displays a quiet two-line typographic control:

```text
Family code
K7M4-P2Q8
```

It is not presented as a badge or a large card. The code remains legible and
always visible without competing with the family bubbles. Tapping it and
tapping the existing Invite affordance open the same family-invite sheet.

The sheet contains:

- **Share family link**
- **Copy family code**
- **Copy link**
- **Regenerate code**, shown only to the family creator

Regeneration requires a consequence confirmation explaining that the previous
link and pending requests will stop working.

### Account entry

An authenticated account with no family sees two primary choices:

- **Create a family**
- **Join a family**

An account that already belongs to a family cannot start another creation or
join flow in the first release.

### Joining by code

The Join interface contains one case-insensitive code field and supports paste.
Formatting punctuation is optional. A valid code opens a minimal preview with
the family name and the existing family avatars. The primary action is
**Request to join**.

After submission, the requester sees **Waiting for a family member to let you
in**. This state survives app restarts and can be cancelled by the requester.

### Joining by native link

The shared URL uses a verified HTTPS App Link / Universal Link, conceptually:

```text
https://join.keepers.app/f/K7M4-P2Q8
```

When Keepers is installed, the link opens the family preview. When it is not
installed, an HTTPS landing page offers the correct store destination and
preserves the code so the flow can resume after installation. A signed-out user
authenticates first and then resumes the same preview without re-entering the
code.

### Approval

Every active family member sees a slim **Name wants to join** notice above the
family bubbles. Opening it shows the requester's name and avatar with
**Approve** and **Decline** actions. No memories or other private family
content are visible to the requester before approval completes.

The first valid approval or decline resolves the request. Other devices update
to the resolved state without presenting an error. After successful
installation, the new member's avatar gently settles into the family bubble
arrangement. Reduced-motion mode replaces the movement with a direct fade.

## Family Code Contract

- Codes contain eight random Crockford Base32 symbols, grouped `XXXX-XXXX`.
- Ambiguous symbols are excluded and input ignores case, spaces, and hyphens.
- The family name, owner name, email, and database identifiers are not encoded.
- Generation retries on a unique-index collision.
- The persisted lookup value is a SHA-256 hash of the normalized code.
- The displayable code is encrypted with the family key so active members can
  recover it without storing it as readable family metadata.
- Each active device caches the last authenticated, encrypted code material so
  the main interface can continue showing the code while offline.
- The server necessarily receives the submitted code while validating a
  request, but it does not persist the plaintext value.
- The code is a family locator, not an authentication factor or encryption key.

## Secure Join Protocol

1. The requester must have an authenticated account with no membership and no
   unresolved request for another family.
2. The requester device creates a dedicated X25519 joining key pair. The
   private key is stored in platform secure storage; the public key is included
   in the request.
3. The requester submits the normalized code, proposed member ID, display name,
   demographic role, color, avatar, and joining public key.
4. Supabase hashes the code, finds the current family-code version, validates
   all fields, and creates or returns the request idempotently.
5. An approving member obtains the request and public key through an
   authenticated, family-scoped projection.
6. The approving device derives an X25519 shared secret with an ephemeral
   approval key, derives an envelope key using HKDF-SHA-256 with the family ID,
   request ID, requester account ID, and code version as authenticated context,
   and encrypts the family key using AES-256-GCM.
7. The approval RPC verifies that the caller is an active member, locks the
   request, validates the envelope shape and context, and stores only the
   public key and ciphertext. Supabase never receives the plaintext family key.
8. The requester downloads the approved envelope, decrypts it locally, writes
   the family and member keys to secure storage, installs the roster and local
   identity transactionally, and then calls completion.
9. Completion activates the membership. If local installation fails, the
   membership does not become active and the requester can retry safely.

The protocol is two-phase so an approved account is not shown as an active
member until its device actually holds the family key and durable local state.

## Supabase Data Model

### Family join-code material

A versioned family-code record contains:

- family ID
- code version
- normalized-code hash with a unique index
- encrypted display-code nonce, ciphertext, and authentication tag
- creator account ID
- created and updated timestamps

Only active members may read the encrypted display-code material. Only the
family creator may replace it. Direct client mutations are revoked; generation
and regeneration use authenticated RPCs.

### Join request

A family join request contains:

- request ID and family ID
- requester account ID and proposed member ID
- validated display name, demographic role, color, and avatar
- requester joining public key
- code version used to create the request
- state: `pending`, `approved`, `installed`, `declined`, `cancelled`, or
  `expired`
- approving or declining account ID where applicable
- approval envelope and ephemeral approval public key where applicable
- created, expires, resolved, and updated timestamps

A partial unique constraint permits at most one unresolved request per account.
An additional family/account constraint makes repeat submission idempotent.
The existing unique membership constraint continues to enforce one family per
account.

### RPC surface

The backend exposes narrow authenticated operations:

- create the initial family code while bootstrapping a family
- fetch the current encrypted family-code material for an active member
- preview a family by code
- create or return a join request
- list pending requests for the caller's active family
- read the caller's own request status and approval envelope
- approve a request
- decline a request
- cancel the caller's own pending request
- complete an approved request after local installation
- regenerate the family code as the creator

All mutations execute through `security definer` RPCs with an empty search path,
explicit authenticated grants, strict response projections, row locks, and
idempotency checks. Direct table mutation remains revoked. Select policies may
expose only the minimum request rows required for Supabase Realtime: a
requester can observe their own request and active members can observe pending
requests for their family.

## State And Error Behaviour

- Invalid, unknown, and superseded codes return the same neutral **Family not
  found** response.
- An account with active membership receives **You already belong to a
  family** without cloud mutation.
- An unresolved duplicate submission returns the existing pending request.
- A requester can cancel while pending, but cannot cancel after approval has
  produced a family-key envelope.
- Approval while the requester is offline remains available until the request
  expires and completes when the requester returns.
- A declined requester sees **Your request wasn't accepted** without the name
  of the declining member.
- Regeneration cancels requests tied to the previous code version. Those
  requesters see **This family invitation has changed. Ask for the new code.**
- Network failures preserve the last authoritative state and expose Retry.
- App resume, session restoration, and connectivity restoration refresh pending
  state even when a Realtime event was missed.
- Approval and decline controls are disabled while submitting. Concurrent
  attempts resolve to the authoritative result rather than surfacing a false
  failure.

## Abuse Prevention And Retention

- Code preview and request creation are rate-limited by account and IP.
- Each family and account has a bounded number of pending attempts.
- Repeated invalid-code attempts receive increasing cooldowns without revealing
  whether a family exists.
- Pending requests expire after seven days.
- Declined, cancelled, expired, and superseded requests are purged after a short
  operational retention window.
- Logs and analytics must not contain plaintext family codes, full join URLs,
  joining private keys, family keys, approval shared secrets, or decrypted
  envelopes.

## Migration And Compatibility

The new schema and RPCs deploy before the new app release. The app then switches
the existing Invite and Join entry points to family-code join requests. Existing
recipient-email invitation RPCs remain temporarily callable for already-issued
app builds, but the new interface creates no email-bound family invitation.
They are removed only after the compatibility window and pending legacy invites
have expired.

Account confirmation and recovery email remain part of account authentication;
only family invitation delivery moves away from email.

## Accessibility

- The code is announced as grouped characters and has an explicit Copy action.
- All controls meet a 48 logical-pixel touch target.
- Focus moves to the first error and returns predictably after sheets close.
- Status changes use live-region announcements without repeated interruptions.
- Color never communicates request state alone.
- Text remains usable at the application's supported enlarged-text settings.
- The arrival animation follows reduced-motion settings.

## Verification

### Unit and widget tests

- code generation, normalization, formatting, hashing, collision retry, and
  encrypted display-code round trips
- joining-key generation and every approval-envelope tamper/context failure
- main-screen code, invitation sheet, preview, pending, approval, decline,
  regeneration, resolved, and error states
- restart restoration, account switching, missed Realtime events, and offline
  retry
- semantics, focus order, touch targets, enlarged text, and reduced motion

### Database and concurrency tests

- every RPC's authenticated, wrong-family, wrong-role, and malformed-input path
- code-guessing neutrality, quotas, expiry, purge, and regeneration
- simultaneous approve/approve, approve/decline, regenerate/request, and
  completion/expiry races
- idempotent request creation and completion
- one-family-per-account enforcement across concurrent requests
- RLS and response-shape proof that unrelated accounts cannot enumerate
  families or requests

### Real-device acceptance

- manual code entry and native-link entry on two physical Android devices
- equivalent iOS Universal Link coverage before iOS release
- app absent/install/resume, signed-out/authenticate/resume, warm start, cold
  start, process death, device restart, and offline approval recovery
- creator regeneration while requests and old links exist
- requester cancellation, decline, expiry, replay, and wrong-account cases
- inspection that cloud rows and logs contain no plaintext family key, memory,
  joining private key, or plaintext family code

## Definition Of Done

A family creator sees the permanent family code on the main interface. Any
member can share the corresponding verified link. A new authenticated account
can enter the code or follow the link, preview the family, and request entry.
Any active family member can approve. The requester securely installs the
family key, becomes active exactly once, and appears in every refreshed family
roster. The complete flow survives offline periods and app restarts; decline,
expiry, regeneration, concurrency, and abuse cases fail safely; and no
plaintext family key or memory reaches Supabase.
