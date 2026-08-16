# Supabase Family Invitations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fake Invite affordance and hard-coded relatives with a secure, account-backed Supabase invitation flow that adds a real member to the same durable family roster on both phones without uploading plaintext memory keys or content.

**Architecture:** Keep Supabase behind a `CloudFamilyGateway` and use it only for account identity, invitation state, roster metadata, and encrypted family-key envelopes. The inviter encrypts the family key locally into an email-bound, expiring invitation; the recipient decrypts and persists it locally before completing membership. SQLCipher remains the canonical offline cache, and the app remains usable when cloud configuration or connectivity is absent.

**Tech Stack:** Flutter/Dart 3.13, Riverpod 3.4, `supabase_flutter`, `app_links`, `share_plus`, SQLCipher, `flutter_secure_storage`, `cryptography` AES-256-GCM/HKDF/SHA-256, PostgreSQL/pgcrypto/RLS/security-definer RPCs, Flutter unit/widget/integration tests.

**Spec:** `docs/superpowers/specs/2026-09-05-supabase-family-invitations-design.md`

## Global Constraints

- Supabase never receives a plaintext family key, member key, memory payload, transcript, or media blob.
- Email OTP is the only account method in this release.
- Only the original owner may create or revoke invitations.
- Invites are bound to a normalized recipient email, expire after 24 hours, and are single-use and idempotent.
- A configured cloud is optional for ordinary local capture and browsing; Invite/Join must fail honestly when unconfigured.
- A phone already bound to another family is never overwritten or silently switched.
- Schibsted Grotesk and the existing Keepers background, heading token, controls, and navigation remain canonical.
- Every production behavior follows RED → GREEN → REFACTOR; each focused test must be observed failing for the expected reason before production code is added.
- Preserve existing untracked `outputs/` and `premium-audit.json` artifacts.

---

### Task 1: Invitation domain, link codec, and key envelope

**Files:**
- Create: `app/lib/features/family/domain/family_invitation.dart`
- Create: `app/lib/features/family/data/family_key_envelope_codec.dart`
- Test: `app/test/features/family/domain/family_invitation_test.dart`
- Test: `app/test/features/family/data/family_key_envelope_codec_test.dart`

**Interfaces:**
- Produces: `FamilyInviteLink`, `InvitationEnvelope`, `InvitationFailure`, `InvitationFailureCode`, `FamilyKeyEnvelopeCodec.createDraft`, `FamilyKeyEnvelopeCodec.open`.
- Consumes: `cryptography`, secure random bytes, UTF-8, UUID strings.

- [ ] **Step 1: Write failing link-codec tests**

```dart
test('invite link round-trips without exposing secrets in toString', () {
  final link = FamilyInviteLink(
    inviteId: '11111111-1111-4111-8111-111111111111',
    token: fixedToken,
    wrappingSecret: fixedSecret,
  );
  expect(FamilyInviteLink.parse(link.toUri()), link);
  expect(link.toString(), isNot(contains(fixedToken)));
  expect(link.toString(), isNot(contains(fixedSecret)));
});

test('invite parser rejects wrong scheme, version, UUID and secret length', () {
  for (final uri in malformedUris) {
    expect(() => FamilyInviteLink.parse(uri), throwsFormatException);
  }
});
```

- [ ] **Step 2: Run link tests and verify RED**

Run: `flutter test --no-pub test/features/family/domain/family_invitation_test.dart`

Expected: compilation fails because `FamilyInviteLink` does not exist.

- [ ] **Step 3: Implement immutable invitation domain values**

```dart
enum InvitationFailureCode {
  notConfigured,
  signedOut,
  invalidEmail,
  invalidOtp,
  networkUnavailable,
  forbidden,
  notOwner,
  malformedLink,
  expired,
  revoked,
  alreadyClaimed,
  emailMismatch,
  differentFamily,
  envelopeRejected,
  localPersistenceFailed,
  unknown,
}

final class FamilyInviteLink {
  static const version = 1;
  const FamilyInviteLink({
    required this.inviteId,
    required this.token,
    required this.wrappingSecret,
  });
  final String inviteId;
  final String token;
  final String wrappingSecret;
  Uri toUri();
  static FamilyInviteLink parse(Uri uri);
  @override String toString() => 'FamilyInviteLink(<redacted>)';
}
```

Require `keepers://join`, `v=1`, a canonical UUID, and two unpadded base64url
values that each decode to exactly 32 bytes.

- [ ] **Step 4: Write failing envelope tests**

```dart
test('family key survives a versioned envelope round-trip', () async {
  final draft = await codec.createDraft(
    familyId: familyId,
    familyKey: familyKey,
    inviteId: inviteId,
    expiresAt: expiresAt,
  );
  expect(await codec.open(link: draft.link, envelope: draft.envelope), familyKey);
  expect(draft.tokenHash, hasLength(43));
});

test('wrong secret, family, invite and every tampered field fail closed', () async {
  for (final mutation in envelopeMutations) {
    await expectLater(
      codec.open(link: mutation.link, envelope: mutation.envelope),
      throwsA(isA<InvitationFailure>()),
    );
  }
});
```

- [ ] **Step 5: Run envelope tests and verify RED**

Run: `flutter test --no-pub test/features/family/data/family_key_envelope_codec_test.dart`

Expected: compilation fails because `FamilyKeyEnvelopeCodec` does not exist.

- [ ] **Step 6: Implement the codec**

```dart
abstract interface class FamilyKeyEnvelopeCodec {
  Future<InvitationDraft> createDraft({
    required String familyId,
    required List<int> familyKey,
    required String inviteId,
    required DateTime expiresAt,
  });

  Future<List<int>> open({
    required FamilyInviteLink link,
    required InvitationEnvelope envelope,
  });
}
```

Generate independent 32-byte token and wrapping secret values with
`Random.secure`, hash the token with SHA-256, derive the envelope key with
HKDF-SHA-256 using UUID bytes as salt and `keepers-family-invite-v1` as info,
and encrypt with AES-256-GCM using a fresh 12-byte nonce and the specified AAD.
Validate lengths before invoking crypto and translate authentication failure to
`InvitationFailureCode.envelopeRejected`.

- [ ] **Step 7: Run both focused suites and commit**

Run: `flutter test --no-pub test/features/family/domain/family_invitation_test.dart test/features/family/data/family_key_envelope_codec_test.dart`

Commit: `feat: add secure family invitation envelopes`

---

### Task 2: Explicit local identity and real family roster

**Files:**
- Modify: `app/lib/storage/schema.dart`
- Modify: `app/lib/features/onboarding/data/member_repository.dart`
- Modify: `app/lib/features/onboarding/application/setup_controller.dart`
- Modify: `app/lib/features/onboarding/application/onboarding_providers.dart`
- Modify: `app/lib/features/onboarding/data/identity_key_service.dart`
- Create: `app/lib/features/family/domain/family_member.dart`
- Create: `app/lib/features/family/data/family_roster_repository.dart`
- Create: `app/lib/features/family/data/joined_family_installer.dart`
- Test: `app/test/storage/schema_test.dart`
- Test: `app/test/features/onboarding/data/setup_repositories_test.dart`
- Test: `app/test/features/onboarding/application/setup_controller_test.dart`
- Test: `app/test/features/onboarding/data/identity_key_service_test.dart`
- Create: `app/test/features/family/data/family_roster_repository_test.dart`
- Create: `app/test/features/family/data/joined_family_installer_test.dart`

**Interfaces:**
- Produces: schema v4, `FamilyMember`, `MemberRepository.bindLocalIdentity`, `FamilyRosterRepository.listLocal`, `FamilyRosterRepository.upsertCloudRoster`, `JoinedFamilyInstaller.install`, `IdentityKeyService.importFamilyKey`, and `IdentityKeyService.createMemberKey`.
- Consumes: existing v3 members/families tables, `AvatarConfig`, `SecureValueStore`.

- [ ] **Step 1: Write failing schema and binding tests**

```dart
test('v4 adds and backfills one explicit local identity binding', () async {
  await openV3WithLocalAdult(database);
  await migrate(database, from: 3, to: 4);
  expect(await database.query('local_identity_binding'), [
    {'singleton': 1, 'family_id': 'family-1', 'member_id': 'member-1', 'account_id': null},
  ]);
});

test('identity lookup follows binding rather than earliest adult', () async {
  await bind(database, memberId: 'member-2');
  expect((await repository.findLocalIdentity(database))?.memberId, 'member-2');
});
```

- [ ] **Step 2: Run focused tests and verify RED**

Run: `flutter test --no-pub test/storage/schema_test.dart test/features/onboarding/data/setup_repositories_test.dart`

Expected: schema version and identity lookup assertions fail.

- [ ] **Step 3: Implement schema v4 and binding-aware identity lookup**

```dart
static const versionFourStatements = [
  '''CREATE TABLE local_identity_binding (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    family_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    account_id TEXT,
    FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE,
    FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE
  )''',
  '''INSERT INTO local_identity_binding(singleton, family_id, member_id)
     SELECT 1, family_id, id FROM members
     WHERE member_key_ref IS NOT NULL
     ORDER BY created_at ASC, id ASC LIMIT 1''',
];
```

Make setup insert the singleton binding inside its existing transaction. Query
`LocalIdentity` by joining the binding, member, and family rows. Add an
idempotent method that binds `account_id` after authentication without changing
family/member IDs.

- [ ] **Step 4: Write failing key-import and roster tests**

```dart
test('remote roster upsert never overwrites the local member key reference', () async {
  await repository.upsertCloudRoster(database, familyId: familyId, members: cloudMembers);
  expect((await localMemberRow(database))['member_key_ref'], localKeyRef);
});

test('joined family install rolls back secure keys when SQL fails', () async {
  await expectLater(installer.install(claim), throwsA(isA<InvitationFailure>()));
  expect(secureStore.values, isEmpty);
});
```

- [ ] **Step 5: Run roster tests and verify RED**

Run: `flutter test --no-pub test/features/family/data/family_roster_repository_test.dart test/features/family/data/joined_family_installer_test.dart test/features/onboarding/data/identity_key_service_test.dart`

Expected: imports fail because the roster and installer APIs do not exist.

- [ ] **Step 6: Implement roster and joined-family installation**

```dart
final class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.familyId,
    required this.name,
    required this.role,
    required this.colorToken,
    required this.avatar,
    required this.joinedAt,
  });
}

abstract interface class JoinedFamilyInstaller {
  Future<void> install({
    required ClaimedFamily claim,
    required List<int> familyKey,
    required String accountId,
  });
}
```

Generate the recipient member key on-device, import the family key into secure
storage, insert/upsert family and roster data, and bind the recipient in one SQL
transaction. Delete only newly created secure references when the transaction
fails. Never copy another member's `member_key_ref`.

- [ ] **Step 7: Run local data suites and commit**

Run: `flutter test --no-pub test/storage/schema_test.dart test/features/onboarding/data/setup_repositories_test.dart test/features/onboarding/application/setup_controller_test.dart test/features/onboarding/data/identity_key_service_test.dart test/features/family/data/family_roster_repository_test.dart test/features/family/data/joined_family_installer_test.dart`

Commit: `feat: persist explicit identity and family roster`

---

### Task 3: Supabase schema, authorization, and RPC contract

**Files:**
- Create: `supabase/migrations/202609050001_family_invitations.sql`
- Create: `supabase/tests/family_invitations_test.sql`
- Create: `supabase/config.toml`
- Create: `supabase/README.md`
- Create: `app/test/features/family/data/supabase_contract_test.dart`
- Modify: `.gitignore`

**Interfaces:**
- Produces: cloud tables, RLS, grants, and seven RPCs named in the design spec.
- Consumes: Supabase Auth `auth.users`, `auth.uid()`, JWT email, PostgreSQL `pgcrypto`.

- [ ] **Step 1: Write SQL contract tests first**

```sql
begin;
select plan(12);
select has_table('public', 'cloud_families');
select has_table('public', 'family_memberships');
select has_table('public', 'family_invites');
select has_function('public', 'bootstrap_owner_family');
select has_function('public', 'create_family_invite');
select has_function('public', 'preview_family_invite');
select has_function('public', 'claim_family_invite');
select has_function('public', 'complete_family_invite');
select has_function('public', 'revoke_family_invite');
select has_function('public', 'list_active_family_members');
select policies_are('public', 'family_memberships', array['active family roster']);
select policies_are('public', 'profiles', array['own profile']);
select * from finish();
rollback;
```

- [ ] **Step 2: Verify RED with a repository SQL contract test**

Create `supabase_contract_test.dart` first. It reads
`../supabase/migrations/202609050001_family_invitations.sql`, asserts the file
exists, and verifies the required tables, functions, RLS enablement,
`security definer`, safe search paths, owner checks, token hashing, expiry, and
mutation revokes are present exactly once.

Run: `flutter test --no-pub test/features/family/data/supabase_contract_test.dart`

Expected: failure because the migration and required objects do not exist.

- [ ] **Step 3: Implement the idempotent migration**

Enable `pgcrypto`; create enums/check constraints, tables, indexes, RLS, grants,
and the exact RPCs from the spec. Every security-definer function must include:

```sql
security definer
set search_path = ''
```

Schema-qualify every referenced object and function, including
`pg_catalog` built-ins and `extensions.digest(..., 'sha256')`. Revoke direct
membership reads and all table mutations from `anon` and `authenticated`;
`list_active_family_members` is the only client roster projection. Use
`clock_timestamp()` for expiry checks, lock invitation rows `for update`,
authorize the owner against active membership, allow revocation only while
pending, and make claim/completion return the same successful result to the same
claimant. A replay of owner bootstrap with changed profile or membership payload
must fail before any profile mutation. Serialize bootstrap per authenticated
account with a transaction-scoped lock acquired before the initial membership
probe, including when no membership row exists. Document and run a two-session
CI case proving identical concurrent payloads are idempotent and differing
concurrent payloads reject without mixing profile or membership fields.

- [ ] **Step 4: Add setup and email-template documentation**

Document the exact commands:

```powershell
supabase link --project-ref $env:KEEPERS_SUPABASE_PROJECT_REF
supabase db push
flutter run --dart-define=KEEPERS_SUPABASE_URL=$env:KEEPERS_SUPABASE_URL --dart-define=KEEPERS_SUPABASE_PUBLISHABLE_KEY=$env:KEEPERS_SUPABASE_PUBLISHABLE_KEY
```

Document that the Supabase email OTP template must render `{{ .Token }}` and
that no service-role key belongs in Dart defines or source control. Ignore only
Supabase local runtime state, never migrations/tests. Commit a non-secret
`supabase/config.toml`, and document local verification in this order:

```powershell
supabase start
supabase db reset --local
supabase test db --local
```

- [ ] **Step 5: Run SQL lint/static contract and commit**

Run: `flutter test --no-pub test/features/family/data/supabase_contract_test.dart`

When a local Supabase CLI is available, also run:
`supabase start`, `supabase db reset --local`, then `supabase test db --local`.

Commit: `feat: add Supabase family invitation contract`

---

### Task 4: Cloud runtime and Supabase gateway

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/pubspec.lock`
- Modify: `app/lib/main.dart`
- Create: `app/lib/features/family/application/cloud_family_providers.dart`
- Create: `app/lib/features/family/data/cloud_family_gateway.dart`
- Create: `app/lib/features/family/data/supabase_cloud_family_gateway.dart`
- Create: `app/lib/features/family/data/unavailable_cloud_family_gateway.dart`
- Create: `app/lib/features/family/domain/cloud_family_models.dart`
- Create: `app/lib/features/family/data/cloud_config.dart`
- Test: `app/test/features/family/data/cloud_config_test.dart`
- Test: `app/test/features/family/data/supabase_cloud_family_gateway_test.dart`

**Interfaces:**
- Produces: `CloudConfig`, `CloudFamilyGateway`, `CreatedInvitation`, a Supabase adapter, and a safe unconfigured adapter.
- Consumes: Supabase RPCs, Auth email OTP, domain values from Tasks 1–3.

- [ ] **Step 1: Add dependencies**

Run:

```powershell
flutter pub add supabase_flutter app_links share_plus
```

Review the resolved versions and commit the lockfile. Do not add Firebase,
analytics, contacts, push notifications, or storage packages.

- [ ] **Step 2: Write failing configuration and gateway-mapping tests**

```dart
test('cloud config requires a valid https URL and publishable key together', () {
  expect(CloudConfig.parse(url: '', publishableKey: ''), isNotConfigured);
  expect(() => CloudConfig.parse(url: 'http://bad', publishableKey: 'x'), throwsFormatException);
});

test('gateway maps expired RPC error without leaking server details', () async {
  rpc.completeError(
    const PostgrestException(code: 'P0001', message: 'INVITE_EXPIRED'),
  );
  await expectLater(gateway.preview(link), throwsInvitation(InvitationFailureCode.expired));
});

test('gateway rejects every non-exact RPC error tuple', () async {
  for (final error in const [
    PostgrestException(code: 'INVITE_EXPIRED', message: 'INVITE_EXPIRED'),
    PostgrestException(code: 'P0001', message: 'raw INVITE_EXPIRED'),
    PostgrestException(
      code: 'P0001',
      message: 'raw',
      details: 'INVITE_EXPIRED',
      hint: 'INVITE_EXPIRED',
    ),
  ]) {
    rpc.completeError(error);
    await expectLater(
      gateway.preview(link),
      throwsInvitation(InvitationFailureCode.unknown),
    );
  }
});

test('gateway maps authoritative invitation creation metadata', () async {
  rpc.completeValue({
    'inviteId': '44444444-4444-4444-8444-444444444444',
    'familyId': '11111111-1111-4111-8111-111111111111',
    'state': 'pending',
    'createdAt': '2026-09-05T08:00:00Z',
    'expiresAt': '2026-09-06T08:00:00Z',
  });
  final created = await gateway.createInvitation(draft);
  expect(created.inviteId, '44444444-4444-4444-8444-444444444444');
  expect(created.familyId, '11111111-1111-4111-8111-111111111111');
  expect(created.state, CloudInvitationState.pending);
  expect(created.createdAt, DateTime.utc(2026, 9, 5, 8));
  expect(created.expiresAt, DateTime.utc(2026, 9, 6, 8));
});
```

- [ ] **Step 3: Run focused tests and verify RED**

Run: `flutter test --no-pub test/features/family/data/cloud_config_test.dart test/features/family/data/supabase_cloud_family_gateway_test.dart`

Expected: imports fail because the gateway is absent.

- [ ] **Step 4: Implement configuration and gateway contract**

```dart
abstract interface class CloudFamilyGateway {
  bool get isConfigured;
  String? get authenticatedAccountId;
  String? get authenticatedEmail;
  Future<void> requestEmailOtp(String email);
  Future<void> verifyEmailOtp({required String email, required String token});
  Future<void> bootstrapOwner(LocalOwnerFamily owner);
  Future<CreatedInvitation> createInvitation(CloudInvitationDraft draft);
  Future<InvitePreview> previewInvitation(FamilyInviteLink link);
  Future<ClaimedFamily> claimInvitation(JoinRequest request);
  Future<void> completeInvitation(String inviteId);
  Future<void> revokeInvitation(String inviteId);
  Future<List<FamilyMember>> listActiveMembers(String familyId);
}
```

Initialize Supabase in `main` only when both Dart defines pass validation, then
override the gateway provider inside `ProviderScope`. Ordinary startup must not
throw when configuration is absent. Translate known PostgREST/Auth/Socket errors
to typed failures and never include raw URI, token, wrapping secret, envelope,
JWT, or server exception text in presentation-facing messages.

`CreatedInvitation` must contain the authoritative server `inviteId`,
`familyId`, typed `CloudInvitationState`, UTC `createdAt`, and UTC `expiresAt`;
the gateway mapping test must prove all five RPC fields are consumed rather than
reusing draft timestamps. Map an RPC error only when its exact tuple is
`code == 'P0001'` and `message` is an explicitly allowlisted constant such as
`INVITE_EXPIRED`. Never infer a failure from `details`, `hint`, status text,
substrings, a non-`P0001` code, or an unallowlisted message; every such case maps
to the redacted unknown failure.

The complete P0001 message allowlist is: `SIGNED_OUT -> signedOut`,
`INVALID_EMAIL -> invalidEmail`, `NOT_OWNER -> notOwner`, `FORBIDDEN -> forbidden`,
`INVALID_TOKEN -> malformedLink`, `INVITE_NOT_FOUND -> malformedLink`,
`INVITE_EXPIRED -> expired`, `INVITE_REVOKED -> revoked`,
`ALREADY_CLAIMED -> alreadyClaimed`, `EMAIL_MISMATCH -> emailMismatch`,
`DIFFERENT_FAMILY -> differentFamily`, and `INVALID_ENVELOPE -> envelopeRejected`.
Every other P0001 message maps to `unknown`.

- [ ] **Step 5: Run gateway tests and commit**

Run: `flutter test --no-pub test/features/family/data/cloud_config_test.dart test/features/family/data/supabase_cloud_family_gateway_test.dart`

Commit: `feat: connect family membership to Supabase`

---

### Task 5: Invite and join application controllers

**Files:**
- Modify: `app/lib/storage/schema.dart`
- Modify: `app/lib/features/onboarding/domain/local_identity.dart`
- Modify: `app/lib/features/onboarding/data/member_repository.dart`
- Modify: `app/lib/features/family/data/joined_family_installer.dart`
- Create: `app/lib/features/family/data/pending_invite_completion_repository.dart`
- Create: `app/lib/features/family/application/family_invite_controller.dart`
- Create: `app/lib/features/family/application/family_join_controller.dart`
- Create: `app/lib/features/family/application/family_roster_provider.dart`
- Create: `app/lib/features/family/application/pending_invite_completion_controller.dart`
- Test: `app/test/storage/schema_test.dart`
- Test: `app/test/features/onboarding/data/setup_repositories_test.dart`
- Test: `app/test/features/family/data/joined_family_installer_test.dart`
- Test: `app/test/features/family/data/pending_invite_completion_repository_test.dart`
- Test: `app/test/features/family/application/family_invite_controller_test.dart`
- Test: `app/test/features/family/application/family_join_controller_test.dart`
- Test: `app/test/features/family/application/family_roster_provider_test.dart`
- Test: `app/test/features/family/application/pending_invite_completion_controller_test.dart`

**Interfaces:**
- Produces: immutable state machines and Riverpod providers used by Invite, Join, and Wheel.
- Consumes: gateway, key codec, secure key resolver, joined-family installer, roster repository, SQLCipher database, clock and ID factories.

Before controller work, advance the SQLCipher schema to v5 with a singleton
`pending_family_invite_completion` table containing only `invite_id`,
`family_id`, `account_id`, and `installed_at`. It must cascade with local family
deletion. Add nullable `accountId` to `LocalIdentity`, select it from
`local_identity_binding`, and test null legacy reads, successful/same-account
binding, and different-account rejection without mutation.

The joined-family installer must insert or validate the exact pending-completion
marker inside the same SQL transaction as roster/key-reference/identity
installation. A conflicting marker fails closed. Cleanup of attempt-created
secure keys is best-effort and must never replace the typed
`localPersistenceFailed` result if cleanup itself throws.

- [ ] **Step 1: Write failing owner controller tests**

```dart
test('two rapid create calls produce one invitation', () async {
  final first = controller.createInvite('mariam@example.com');
  final second = controller.createInvite('mariam@example.com');
  await Future.wait([first, second]);
  expect(gateway.createdInvitations, hasLength(1));
});

test('failed creation retains recipient and exposes typed recovery', () async {
  gateway.failNext(InvitationFailureCode.networkUnavailable);
  await controller.createInvite('mariam@example.com');
  expect(controller.state.recipientEmail, 'mariam@example.com');
  expect(controller.state.failure?.code, InvitationFailureCode.networkUnavailable);
});
```

- [ ] **Step 2: Run owner controller tests and verify RED**

Run: `flutter test --no-pub test/features/family/application/family_invite_controller_test.dart`

Expected: imports fail because the controller is absent.

- [ ] **Step 3: Implement owner state machine**

Use phases `checking`, `needsAuthentication`, `awaitingOtp`, `ready`,
`creating`, `created`, `revoking`, and `failed`. Normalize email for validation
but preserve the user's entered spelling for display. Bootstrap the owner family
once per authenticated account. After remote bootstrap succeeds, bind that exact
account to the local identity, invalidate the identity provider, and only then
enter ready. Reject a different already-bound account before remote mutation.
If local binding fails after remote bootstrap, retry the exact idempotent
bootstrap before retrying the bind. Resolve the family key only at create time,
and discard raw draft secret material when the controller is disposed or
invitation is revoked.

Re-read the authenticated account after every awaited auth/network operation,
ignore stale completions after account or controller-generation changes,
deduplicate every busy operation, and retain exact IDs and payloads for ambiguous
retries. Public controller state and `toString` output must never contain the
invite link, token, wrapping secret, token hash, envelope, family key, or member
key.

- [ ] **Step 4: Write failing join and roster tests**

```dart
test('join completes remotely only after secure local installation', () async {
  await controller.accept(name: 'Mariam', avatar: avatar);
  expect(events, [
    'claim',
    'decrypt',
    'install-and-mark',
    'complete',
    'delete-marker',
    'invalidate',
  ]);
});

test('different-family installation performs no cloud or local mutation', () async {
  await controller.load(link);
  expect(controller.state.failure?.code, InvitationFailureCode.differentFamily);
  expect(gateway.claimCalls, 0);
  expect(installer.calls, 0);
});
```

- [ ] **Step 5: Run join tests and verify RED**

Run: `flutter test --no-pub test/features/family/application/family_join_controller_test.dart test/features/family/application/family_roster_provider_test.dart`

Expected: imports fail because join and roster providers are absent.

- [ ] **Step 6: Implement join and roster state machines**

Use join phases `checking`, `needsAuthentication`, `awaitingOtp`, `preview`,
`joining`, `complete`, and `failed`. Keep the parsed link value private to the
controller and redact diagnostics. Enforce claim → decrypt → local install →
durable marker → remote complete → exact marker deletion. Copy the decrypted
family key into a mutable buffer and overwrite it in `finally`. If completion
fails, retain the marker and retry completion only—never reclaim, decrypt, or
reinstall. Provide a pending-completion recovery controller: for the matching
authenticated account it retries idempotent completion and deletes the marker;
signed-out, wrong-account, network, unknown, or local deletion failures retain
the marker. Task 7 will invoke this recovery from startup.

On refresh, emit the local roster immediately, then upsert a successful cloud
roster and emit the new local query. A network failure keeps the cached roster
and records only a non-blocking refresh status. Wrap the whole cloud-roster
upsert in a database transaction because the repository performs multiple
statements; deduplicate refreshes and ignore stale responses.

Tests must cover interruption after install/before completion, ambiguous remote
completion, response loss after remote acceptance, wrong-account recovery,
marker delete failure, exact reinstall idempotency, conflicting markers,
transaction rollback, rapid-call deduplication, account change during awaits,
and provider invalidation only after authoritative success.

- [ ] **Step 7: Run application tests and commit**

Run: `flutter test --no-pub test/features/family/application`

Commit: `feat: orchestrate remote family invitations`

---

### Task 6: Owner Invite interface and operating-system sharing

**Files:**
- Modify: `app/lib/features/family/application/family_invite_controller.dart`
- Create: `app/lib/features/family/presentation/family_invite_screen.dart`
- Create: `app/lib/features/family/data/invite_share_service.dart`
- Modify: `app/lib/features/vault/presentation/observatory_screen.dart`
- Modify: `app/lib/ui/family_wheel_screen.dart`
- Modify: `app/lib/features/ceremony/presentation/ceremony_screen.dart`
- Test: `app/test/features/family/presentation/family_invite_screen_test.dart`
- Test: `app/test/features/family/data/invite_share_service_test.dart`
- Modify: `app/test/features/family/application/family_invite_controller_test.dart`
- Modify: `app/test/features/vault/presentation/observatory_screen_test.dart`
- Modify: `app/test/ui/family_wheel_screen_test.dart`
- Modify: `app/test/features/ceremony/presentation/ceremony_screen_test.dart`

**Interfaces:**
- Produces: a contextual Invite route and `InviteShareService`.
- Consumes: Invite controller and the existing Keepers theme/background.

The invite link remains private to `FamilyInviteController`. Inject the share
service into that controller and expose `shareAgain`, `isSharing`, and a safe
share failure; the screen must never receive, display, log, retain, or copy the
URI. Sharing is orthogonal to the `created` phase, so a thrown share error or a
dismissed/unavailable result never erases the pending invitation or claims that
delivery occurred.

- [ ] **Step 1: Write failing Invite-screen behavior tests**

```dart
testWidgets('owner authenticates, creates, shares, and may revoke a pending invite', (tester) async {
  await pumpInvite(tester, gateway: fakeGateway);
  await enterEmailAndOtp(tester, ownerEmail, '123456');
  await tester.enterText(find.byKey(const Key('invite-recipient-email')), recipientEmail);
  await tester.tap(find.text('CREATE INVITATION'));
  await tester.pumpAndSettle();
  expect(shareService.links, hasLength(1));
  expect(find.text('SHARE AGAIN'), findsOneWidget);
  expect(find.text('CANCEL INVITATION'), findsOneWidget);
});

testWidgets('unconfigured and network failures are honest and recoverable', (tester) async {
  await pumpInvite(tester, gateway: unavailableGateway);
  expect(find.textContaining('CLOUD INVITATIONS ARE NOT CONFIGURED'), findsOneWidget);
  expect(find.text('INVITATION READY'), findsNothing);
});
```

- [ ] **Step 2: Run presentation test and verify RED**

Run: `flutter test --no-pub test/features/family/presentation/family_invite_screen_test.dart`

Expected: import fails because `FamilyInviteScreen` is absent.

- [ ] **Step 3: Implement the screen and share adapter**

Use one scroll surface, a contextual back action, the shared 20/600 heading,
stable 48-pixel buttons, real text-field labels, autofill hints, numeric OTP
keyboard, live-region errors, and no shadow or decorative gradient. `SharePlus`
receives one `ShareParams.text` payload containing the invitation message and
URI; `share_plus` 13.3 rejects simultaneous `text` and `uri` values. Supply the
initiating control's global rectangle as `sharePositionOrigin` when available.
The app never copies the capability to the clipboard, logs it, or inspects raw
share-result data. Only a thrown share exception becomes a retryable error.

Keep every state in the same single-column shell: checking; honest unconfigured;
owner email; six-digit OTP; recipient email; creating; created/pending; sharing;
revoking; and inline failure/recovery. Preserve entered values and stable control
geometry across busy and error states. Block duplicate operations and keep the
pending recipient/expiry plus Share Again and Cancel Invitation available after
share or revoke failures.

- [ ] **Step 4: Replace the placeholder callback and split semantics**

Rename the Wheel callback to `onAddMember` and route only the dashed `INVITE`
node to `FamilyInviteScreen`. Rename the gathering callback to
`onNudgeMissingMembers`; until messaging exists it may open the platform share
sheet with non-secret gathering copy, but it must not create a member invite.
Memory Key's `Ask family to come` uses only the nudge callback. Ceremony receives
both callbacks: its visible `INVITE` presence card creates a member invitation,
while the waiting-weekly action only nudges existing missing relatives. Remove
the placeholder success snackbar.

The contextual route uses the existing Keepers background and no global bottom
navigation. It must remain operable at 390×844, 1.4× text, reduced motion, and a
nonzero keyboard inset; every control is at least 44 pixels and submit buttons
remain 48 pixels. Prevent route disposal while create or revoke is in flight.

- [ ] **Step 5: Run Invite/navigation/accessibility tests and commit**

Run: `flutter test --no-pub test/features/family/presentation/family_invite_screen_test.dart test/features/family/data/invite_share_service_test.dart test/features/family/application/family_invite_controller_test.dart test/features/vault/presentation/observatory_screen_test.dart test/ui/family_wheel_screen_test.dart test/features/ceremony/presentation/ceremony_screen_test.dart`

Commit: `feat: make the family invite action functional`

---

### Task 7: Deep links, recipient authentication, and Join interface

**Files:**
- Create: `app/lib/features/family/data/invite_link_coordinator.dart`
- Create: `app/lib/features/family/presentation/family_join_screen.dart`
- Create: `app/lib/features/members/presentation/widgets/avatar_draft_picker.dart`
- Modify: `app/lib/features/members/presentation/avatar_editor_screen.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/lib/app.dart`
- Modify: `app/lib/features/onboarding/presentation/startup_gate.dart`
- Modify: `app/lib/features/onboarding/presentation/setup_screen.dart`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Modify: `app/ios/Runner/Info.plist`
- Test: `app/test/features/family/data/invite_link_coordinator_test.dart`
- Test: `app/test/features/family/presentation/family_join_screen_test.dart`
- Test: `app/test/platform/invite_link_platform_contract_test.dart`
- Modify: `app/test/app_test.dart`
- Modify: `app/test/features/onboarding/presentation/setup_screen_test.dart`

**Interfaces:**
- Produces: cold/warm `keepers://join` routing and the complete recipient flow.
- Consumes: `app_links`, Join controller, setup/avatar components, identity provider.

Wrap `app_links` behind an injectable `InviteUriSource`. Subscribe to its URI
stream before awaiting the initial URI because version 7.2 may deliver the same
initial link through both paths. Emit only a sealed valid-link event or a
redacted malformed-Join event; ignore unrelated URIs, deduplicate valid events
by invite ID in process memory, never persist capability material, and cancel
the stream on disposal.

- [ ] **Step 1: Write failing cold/warm-link routing tests**

```dart
testWidgets('cold-start invite opens Join before ordinary setup', (tester) async {
  await pumpApp(tester, initialLink: validInviteUri, identity: null);
  expect(find.text('JOIN FAMILY'), findsOneWidget);
  expect(find.text('NAME YOUR FAMILY SPACE'), findsNothing);
});

testWidgets('warm invite opens once and redacts route diagnostics', (tester) async {
  links.add(validInviteUri);
  links.add(validInviteUri);
  await tester.pumpAndSettle();
  expect(find.byType(FamilyJoinScreen), findsOneWidget);
});
```

- [ ] **Step 2: Run coordinator/app tests and verify RED**

Run: `flutter test --no-pub test/features/family/data/invite_link_coordinator_test.dart test/app_test.dart`

Expected: imports fail because the coordinator and route do not exist.

- [ ] **Step 3: Implement link coordination and platform declarations**

Initialize `AppLinks` once in `main` before awaiting optional Supabase startup so
there is no link-observation gap. Hold ordinary startup behind initial-link
resolution: a valid or malformed cold Join target renders Join first; no target
renders `StartupGate`. Buffer warm events until the root navigator exists and
push at most one Join route with a fixed safe route name and no route arguments.
Do not rewrite the app around a new router.

Add one exact Android `VIEW`/`DEFAULT`/`BROWSABLE` filter for scheme `keepers`
and host `join`, plus release `INTERNET`. Add the matching iOS
`CFBundleURLTypes`. Disable Flutter's built-in deep-link handler on both
platforms so it cannot compete with `app_links`; do not add auto-verify,
associated domains, wildcard paths, query schemes, or unrelated permissions.

- [ ] **Step 4: Write failing Join-screen tests**

```dart
testWidgets('valid recipient sees family before entering name and joining', (tester) async {
  await pumpJoin(tester, preview: validPreview);
  expect(find.text('RAHMAN FAMILY'), findsOneWidget);
  expect(find.byKey(const Key('join-member-name')), findsOneWidget);
  expect(find.text('JOIN FAMILY'), findsOneWidget);
});

testWidgets('expired, wrong-email and tampered-envelope states fail closed', (tester) async {
  for (final failure in protectedFailures) {
    await pumpJoin(tester, failure: failure);
    expect(find.text(failure.userMessage), findsOneWidget);
    expect(find.byKey(const Key('join-family-submit')), findsNothing);
  }
});
```

- [ ] **Step 5: Run Join tests and verify RED**

Run: `flutter test --no-pub test/features/family/presentation/family_join_screen_test.dart`

Expected: import fails because `FamilyJoinScreen` is absent.

- [ ] **Step 6: Implement the Join route and first-run choice**

Show `CREATE A FAMILY` and `JOIN A FAMILY` on first run; manual Join explains
that the user must open a family invitation link on this device. It has no URL
field, clipboard action, QR flow, or gateway mutation. Back from either branch
returns to the choice without changing the existing create-family form.

The incoming-link route owns OTP, preview, name, draft-only avatar selection,
busy/error states, and success. Extract the existing avatar option UI into a
pure draft picker shared with profile editing; it must not write a member row
during Join. Keep family/owner/expiry visible before profile entry, preserve the
stable controller-generated member/avatar seed, freeze changes while joining,
and retry only the controller's exact safe stage. Terminal protected failures
show no Join action and never reveal a URI.

On success, clear the entire navigation stack to `StartupGate` so Setup or an
older Join route cannot reappear. When an established identity starts normally,
render the existing app immediately and invoke pending-completion recovery once
post-frame; offline, signed-out, wrong-account, unknown, and marker-deletion
failures keep the app usable and the marker intact. A cold Join must not build
`StartupGate` behind it or race recovery.

Use one safe-area scroll surface, stable 48-pixel primary actions, live-region
progress/errors, ordinary editable fields, numeric six-digit OTP with one-time
code autofill, deterministic focus recovery, `PopScope` while joining, and the
existing Keepers background/type system. Verify 390×844, 1.4× text, keyboard
insets, reduced motion, long names, and 44-pixel minimum controls.

- [ ] **Step 7: Run link/join/startup tests and commit**

Run: `flutter test --no-pub test/features/family/data/invite_link_coordinator_test.dart test/features/family/presentation/family_join_screen_test.dart test/platform/invite_link_platform_contract_test.dart test/app_test.dart test/features/onboarding/presentation/setup_screen_test.dart`

Commit: `feat: accept family invitations from app links`

---

### Task 8: Replace demo relatives with the synchronized roster

**Files:**
- Modify: `app/lib/features/vault/presentation/observatory_screen.dart`
- Modify: `app/lib/ui/family_wheel_screen.dart`
- Modify: `app/lib/features/ceremony/presentation/ceremony_screen.dart`
- Modify: `app/lib/features/members/presentation/member_page_screen.dart`
- Modify: `app/lib/design_system/observatory/observatory_theme.dart`
- Modify: `app/lib/features/members/domain/avatar_catalog.dart`
- Modify: `app/test/features/vault/presentation/observatory_screen_test.dart`
- Modify: `app/test/ui/family_wheel_screen_test.dart`
- Modify: `app/test/features/ceremony/presentation/ceremony_screen_test.dart`
- Modify: `app/test/features/members/presentation/member_page_screen_test.dart`
- Modify: `app/test/app_test.dart`
- Modify: `app/test/features/members/domain/avatar_catalog_test.dart`

**Interfaces:**
- Produces: a Wheel, Memory Key, and member page driven only by persisted roster data.
- Consumes: `familyRosterProvider`, `FamilyMember.avatar`, existing color tokens.

- [ ] **Step 1: Write failing real-roster tests**

```dart
testWidgets('a local-only family starts with YOU and no demo relatives', (tester) async {
  await pumpObservatory(tester, roster: [currentMember]);
  expect(find.text('NOURA'), findsNothing);
  expect(find.text('MARIAM'), findsNothing);
  expect(find.text('INVITE'), findsOneWidget);
});

testWidgets('accepted roster member appears with persisted name, color and avatar', (tester) async {
  await pumpObservatory(tester, roster: [currentMember, mariam]);
  expect(find.text('MARIAM'), findsOneWidget);
  expect(find.byKey(const ValueKey('family-avatar-member-mariam')), findsOneWidget);
});
```

- [ ] **Step 2: Run Wheel integration tests and verify RED**

Run: `flutter test --no-pub test/features/vault/presentation/observatory_screen_test.dart test/ui/family_wheel_screen_test.dart`

Expected: tests fail because hard-coded relatives still render and roster injection is absent.

- [ ] **Step 3: Map persisted roster into presentation models**

Remove `_familyMembers`. Make `ObservatoryScreen` the only roster-to-presentation
adapter and preserve repository order. Add `avatar` and nullable contribution to
`FamilyWheelMember`; render the exact persisted recipe instead of a demo-ID
catalog lookup. Exclude `identity.memberId` strictly by ID, map canonical and
legacy color tokens through `ObservatoryTokens.memberColor`, use
`FamilyPresence.away`, and compute attendance from honest presence. Remote
contribution is unknown until memory synchronization exists, so omit its ring,
percentage, and percentage semantics instead of inventing `0%`. Compute only the
current member's contribution from entries authored by the current member. Feed
the same ordered real-member list to Memory Key and member details, remove demo
constructor defaults, fabricated key-holder state, and unsupported lock claims.

Do not truncate a persisted roster. Replace the repeating eight-anchor geometry
with deterministic, non-overlapping inner/outer floating-bubble rings that remain
pan/zoom accessible as the family grows; the Memory Key must likewise expose all
members rather than silently taking five. Keep the current member centered and
the Invite node distinct.

- [ ] **Step 4: Add cached/loading/refresh behavior**

Watch the provider only; it owns its automatic local-first load. Before the first
local result, show a neutral loader rather than a misleading current-only Wheel.
A first-load local database failure is blocking and retryable. Keep cached
members visible during cloud refresh. A refresh failure must not replace the
Wheel or remove family members; expose one generic accessible retry surface.
Refresh on app resume and after returning from Invite so a continuously mounted
owner sees accepted members without restarting. The current invitation system
has no member-removal operation, so its local roster is intentionally append-only;
introduce tombstones with that future feature rather than deleting member rows
and cascading local memories now.

- [ ] **Step 5: Run affected and full widget suites and commit**

Run: `flutter test --no-pub test/features/vault/presentation/observatory_screen_test.dart test/ui/family_wheel_screen_test.dart test/features/ceremony/presentation/ceremony_screen_test.dart test/features/members/presentation/member_page_screen_test.dart`

Commit: `feat: render the real synchronized family roster`

---

### Task 9: Configuration docs, visual QA, and full verification

**Files:**
- Modify: `app/README.md`
- Modify: `DESIGN.md`
- Modify: `UX-CONTRACT.md`
- Modify: `design-qa.md`
- Modify: `.github/workflows/ci.yml`
- Create: `app/test/features/family/presentation/family_invitation_accessibility_test.dart`
- Create: `app/test/features/family/presentation/family_invitation_test_harness.dart`
- Create: `app/integration_test/family_invitation_flow_test.dart`
- Create: `app/integration_test/support/family_invitation_flow_harness.dart`
- Create: `app/test_driver/family_invitation_screenshot_driver.dart`
- Modify as observed: invitation runtime/presentation files repaired from test and visual evidence

**Interfaces:**
- Produces: operator setup, durable product contract, regression evidence, and final build.
- Consumes: all prior tasks.

- [ ] **Step 1: Add failing responsive/accessibility and end-to-end fake-gateway tests**

```dart
testWidgets('Invite and Join remain operable at 390x844 and 1.4x text', (tester) async {
  setViewport(tester, const Size(390, 844), textScale: 1.4);
  await pumpCompleteInviteAndJoinStates(tester);
  expect(tester.takeException(), isNull);
  expect(primaryButtons.every((finder) => tester.getSize(finder).height >= 44), isTrue);
});
```

The integration test uses two isolated local installations (distinct databases,
secure stores, provider containers, and authenticated gateway sessions) backed
by one shared stateful fake cloud. It runs owner bootstrap → create/share →
cold-start recipient link delivery → authenticate → preview → claim/decrypt →
real local install/marker → complete → restart → owner roster refresh without a
live project or network. The capability crosses installations only through an
overridden recording `InviteShareService` and injectable `InviteUriSource`.

- [ ] **Step 2: Run new tests and verify RED**

Run the host widget test and emulator integration target separately:

```powershell
flutter test --no-pub test/features/family/presentation/family_invitation_accessibility_test.dart
flutter test --no-pub integration_test/family_invitation_flow_test.dart -d emulator-5554
```

Expected: failures identify any incomplete semantics, size, navigation, or integration behavior.

- [ ] **Step 3: Repair only the observed gaps and document the final contract**

Update runtime configuration commands, Supabase migration steps, OTP template,
custom scheme, privacy boundary, owner-only authorization, offline behavior, and
the explicit requirement for a live two-device acceptance pass. Reconcile
`DESIGN.md`/`UX-CONTRACT.md` so no text still calls cloud membership or the
hard-coded roster a preview.

- [ ] **Step 4: Run formatter, analyzer, tests, build, and static audit**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
& 'C:\Users\Chris\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' 'C:\Users\Chris\.codex\plugins\cache\openai-curated-remote\frontend-design-premium\1.4.0\skills\frontend-design-premium\scripts\audit_project.py' 'C:\Users\Chris\Documents\Codex\2026-08-31\github-plugin-github-openai-curated-remote-2\work\keepers-p0-03\.worktrees\p0-capture-vault' --mode strict --no-write
git diff --check
```

Rerun the explicit emulator integration target after all repairs; ordinary
`flutter test` does not discover `integration_test/`. Add that target to Android
CI and add an iOS simulator build gate for the modified URL declarations. Run
the grep-able anti-pattern scan from the premium verification checklist and fix
every changed-Dart match. Record that `audit_project.py` is only a supplemental
signal here because its source scanner excludes Dart; do not cite the existing
zero-finding JSON as Flutter coverage.

- [ ] **Step 5: Install and visually inspect primary states**

Use `integration_test_driver_extended.dart` and a QA-only Dart define to save
screenshots under `outputs/family-invitations/pass-1/` and `pass-2/`; keep all
screenshots local/untracked and never capture the operating-system share sheet.
Capture at least:

- Wheel with only YOU and Invite;
- Invite unconfigured;
- owner email and OTP;
- recipient entry, creating, pending, sharing, revoke failure;
- first-run Create/Join choice and manual Join explanation;
- recipient email entry;
- Join loading, preview, OTP, keyboard-open, recoverable and protected failure;
- Wheel with a newly joined persisted relative.
- long-content and reduced-motion states.

Inspect 390×844 and the Android emulator for typography, clipping, keyboard
avoidance, touch targets, focus order, safe areas, error stability, and absence
of accidental secret display. Record evidence in `design-qa.md` and repair every
visible issue before the second pass. Join success intentionally redirects to the
Wheel, so capture the joined Wheel rather than inventing a success screen.

- [ ] **Step 6: Run external acceptance when credentials exist**

Apply the SQL migration to the configured Supabase project and install builds
with the same URL/publishable key on two physical devices. Verify recipient-bound
auth, acceptance, restart persistence, expiry, revoke, replay, wrong email,
offline cached roster, and absence of memory/key plaintext in cloud rows.

If credentials or two devices are unavailable, report live Supabase pgTAP/race,
OTP/RPC, physical two-device, and unavailable iOS/runtime accessibility checks
as explicit external acceptance gaps; do not label them passed or substitute the
fake gateway. Static platform-contract tests and available CI gates remain
separate evidence.

- [ ] **Step 7: Final review and commit**

Commit: `feat: complete secure remote family invitations`
