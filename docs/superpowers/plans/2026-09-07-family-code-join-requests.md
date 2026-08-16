# Family Code And Join Requests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a permanent family code and verified family-link flow in which a signed-in requester asks to join, any active family member approves, and the family key is installed locally before membership becomes active.

**Architecture:** Add a parallel family-code capability beside the existing recipient-email invitation capability so already-issued builds remain compatible. Supabase owns discovery and the request state machine, while code display and family-key handoff remain end-to-end encrypted on devices using AES-256-GCM, X25519, and HKDF-SHA-256. Riverpod controllers coordinate encrypted local cache, restart recovery, Realtime invalidation, and focused Flutter surfaces without moving secrets into presentation state.

**Tech Stack:** Flutter 3 / Dart 3, Riverpod 3, `cryptography` 2.9, `flutter_secure_storage`, SQLCipher SQLite, Supabase Auth/Postgres/Realtime, pgTAP-style SQL contract tests, Android App Links, iOS Universal Links.

**Spec:** `docs/superpowers/specs/2026-09-07-family-code-join-requests-design.md`

## Global Constraints

- Keep `supabase/migrations/202609050001_family_invitations.sql`, `FamilyInviteLink`, `InvitationEnvelope`, and all legacy email-invitation RPCs operational during the compatibility window.
- Existing Supabase email OTP authentication is the account prerequisite for this feature; adding Google, Apple, or password providers is a separate account-authentication project.
- Treat the local offline setup as a draft family. A permanent code exists only after authenticated, atomic cloud bootstrap succeeds; never display or share an uncommitted candidate.
- Generate eight symbols from the canonical Crockford Base32 alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ`; reject `I`, `L`, `O`, and `U`; ignore input case, ASCII spaces, and hyphens; display `XXXX-XXXX`.
- Store only SHA-256 code hashes in lookup columns. Do not log or persist plaintext family codes, full family links, joining private keys, family keys, shared secrets, or decrypted envelopes.
- Encrypt display-code material with the 32-byte family key using AES-256-GCM and authenticated context `keepers-family-code:v1:<familyId>:<codeVersion>`.
- Use a dedicated X25519 joining keypair and derive approval-envelope keys with HKDF-SHA-256 bound to family ID, request ID, requester account ID, and code version.
- Keep the request states exactly `pending`, `approved`, `installed`, `declined`, `cancelled`, and `expired`; requests expire exactly seven days after creation.
- A code or link only creates a request. Any active member may approve or decline; one decision resolves it. Only the family creator may regenerate the code.
- Regeneration invalidates the previous lookup and cancels old-version `pending` requests, but does not strand already `approved` requests with an envelope.
- Install the family key, family row, roster, local identity, and durable completion marker before calling the completion RPC. Retain the marker across every uncertain failure.
- Enforce the existing one-account/one-family database constraint for the first release.
- Use refresh-on-resume plus Realtime invalidation; correctness must not depend on a push notification or delivery of a Realtime event.
- All interactive controls have a minimum 48 logical-pixel target, useful semantics, predictable focus, and stable layout at enlarged text sizes.
- Newly installed avatars settle into the bubble field; reduced-motion mode uses a direct fade.
- PostgreSQL enforces per-account quotas and cooldowns. The production Supabase ingress must also enforce per-IP throttling; do not claim the IP-control release gate from SQL tests alone.

## File Structure

### New focused units

- `app/lib/features/family/domain/family_code.dart` — family-code normalization, formatting, verified-link parsing, and encrypted code-material models.
- `app/lib/features/family/domain/family_join_request.dart` — request states, typed failures, preview, decision, and strict approval-envelope models.
- `app/lib/features/family/data/family_code_codec.dart` — code generation, SHA-256 parity helper, and family-key encryption/decryption.
- `app/lib/features/family/data/joining_key_store.dart` — dedicated X25519 seed storage keyed by account and proposed member.
- `app/lib/features/family/data/family_join_envelope_codec.dart` — X25519/HKDF/AES family-key envelope.
- `app/lib/features/family/data/family_code_cache_repository.dart` — encrypted current-code cache only.
- `app/lib/features/family/data/pending_join_completion_repository.dart` — exact durable post-install completion marker.
- `app/lib/features/family/data/approved_family_join_installer.dart` — transactional local installation before activation.
- `app/lib/features/family/application/family_join_crypto_providers.dart` — composition for the new crypto/storage boundaries.
- `app/lib/features/family/application/family_code_controller.dart` — bootstrap/load/share/copy/regenerate state.
- `app/lib/features/family/application/family_join_requests_controller.dart` — active-family pending list and decisions.
- `app/lib/features/family/application/pending_join_completion_controller.dart` — restart-safe completion retry and key cleanup.
- `app/lib/features/family/presentation/family_invite_sheet.dart` — shared code/link actions and creator-only regeneration.
- `app/lib/features/family/presentation/family_join_request_sheet.dart` — requester detail plus approve/decline actions.
- `supabase/migrations/202609070001_family_code_join_requests.sql` — additive tables, RLS, quotas, and state-transition RPCs.
- `supabase/tests/family_code_join_requests_test.sql` — schema, authorization, transition, and concurrency proofs.

### Existing units modified without broad refactoring

- `app/lib/features/family/data/cloud_family_gateway.dart` — add an independent `FamilyCodeJoinGateway` capability.
- `app/lib/features/family/data/supabase_cloud_family_gateway.dart` — strict RPC/realtime adapter for the new capability.
- `app/lib/features/family/data/unavailable_cloud_family_gateway.dart` — typed unavailable implementation.
- `app/lib/features/family/application/cloud_family_providers.dart` — expose the new gateway without changing legacy fakes.
- `app/lib/features/family/application/family_join_controller.dart` — replace immediate invite claim with code/request/pending/install states.
- `app/lib/features/family/presentation/family_join_screen.dart` — manual-code, link, preview, pending, and recovery surfaces.
- `app/lib/features/family/data/invite_link_coordinator.dart` and `app/lib/app.dart` — permanent HTTPS family-link routing and bounded duplicate delivery.
- `app/lib/features/onboarding/presentation/setup_screen.dart` and `startup_gate.dart` — working Join entry and pending-request restoration.
- `app/lib/features/vault/presentation/observatory_screen.dart` — orchestration, lifecycle refresh, approval sheet, and roster refresh.
- `app/lib/ui/family_wheel_screen.dart` — quiet code control, request notice, and avatar-arrival transition.
- `app/lib/features/family/data/invite_share_service.dart` — family-link share copy and injectable clipboard boundary.
- `app/lib/storage/schema.dart` — schema version 6 encrypted cache and completion marker.
- Android/iOS platform association files — verified HTTPS link routing while retaining the auth callback.
- `supabase/README.md` and `app/README.md` — deployment order, compatibility, retention, ingress throttle, and acceptance commands.

---

### Task 1: Family-code value and encrypted display material

**Files:**
- Create: `app/lib/features/family/domain/family_code.dart`
- Create: `app/lib/features/family/data/family_code_codec.dart`
- Test: `app/test/features/family/domain/family_code_test.dart`
- Test: `app/test/features/family/data/family_code_codec_test.dart`

**Interfaces:**
- Consumes: `cryptography` package and 32-byte family keys resolved by `IdentityKeyService.resolve(String)`.
- Produces: `FamilyCode.parse(String)`, `FamilyJoinLink.parse(Uri)`, `FamilyCodeCodec.createDraft({required String familyId, required int codeVersion, required List<int> familyKey})`, `FamilyCodeCodec.open({required EncryptedFamilyCodeMaterial material, required List<int> familyKey})`, and `FamilyCodeCodec.lookupHash(FamilyCode code)`.

- [ ] **Step 1: Write failing value-object tests**

```dart
test('normalizes and groups an eight-symbol code', () {
  final code = FamilyCode.parse('k7m4 p2-q8');
  expect(code.normalized, 'K7M4P2Q8');
  expect(code.display, 'K7M4-P2Q8');
  expect(code.toString(), 'FamilyCode(<redacted>)');
});

test('rejects ambiguous and malformed input', () {
  for (final value in ['K7M4-I2Q8', 'K7M4-L2Q8', 'K7M4-O2Q8',
    'K7M4-U2Q8', 'K7M4-P2Q', 'K7M4-P2Q88']) {
    expect(() => FamilyCode.parse(value), throwsFormatException);
  }
});

test('accepts only the verified family-link shape', () {
  final link = FamilyJoinLink.parse(
    Uri.parse('https://join.keepers.app/f/K7M4-P2Q8'),
  );
  expect(link.code.display, 'K7M4-P2Q8');
  expect(link.toString(), 'FamilyJoinLink(<redacted>)');
  expect(
    () => FamilyJoinLink.parse(
      Uri.parse('https://join.keepers.app/f/K7M4-P2Q8?token=leak'),
    ),
    throwsFormatException,
  );
});
```

- [ ] **Step 2: Run the focused tests and confirm the missing-type failure**

Run: `cd app && flutter test test/features/family/domain/family_code_test.dart`

Expected: FAIL because `FamilyCode` and `FamilyJoinLink` do not exist.

- [ ] **Step 3: Implement the immutable value objects and strict material decoder**

```dart
final class FamilyCode {
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  const FamilyCode._(this.normalized);
  final String normalized;

  static FamilyCode parse(String input) {
    final normalized = input
        .toUpperCase()
        .replaceAll(RegExp(r'[ -]'), '');
    if (normalized.length != 8 ||
        normalized.codeUnits.any(
          (unit) => !alphabet.codeUnits.contains(unit),
        )) {
      throw const FormatException('Invalid family code');
    }
    return FamilyCode._(normalized);
  }

  String get display =>
      '${normalized.substring(0, 4)}-${normalized.substring(4)}';
  Uri get joinUri => Uri.https('join.keepers.app', '/f/$display');

  @override
  String toString() => 'FamilyCode(<redacted>)';
}

final class FamilyJoinLink {
  const FamilyJoinLink._(this.code);
  final FamilyCode code;

  static FamilyJoinLink parse(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host != 'join.keepers.app' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first != 'f') {
      throw const FormatException('Invalid family join link');
    }
    return FamilyJoinLink._(FamilyCode.parse(uri.pathSegments.last));
  }

  @override
  String toString() => 'FamilyJoinLink(<redacted>)';
}
```

Define `EncryptedFamilyCodeMaterial` with the exact fields `codecVersion`, `familyId`, `codeVersion`, `nonce`, `ciphertext`, and `mac`; its decoder must reject missing or additional fields, require canonical lowercase UUID, require `codeVersion > 0`, and validate decoded lengths 12, 8, and 16 bytes. Define the record and draft types exactly as follows and redact both diagnostics:

```dart
final class EncryptedFamilyCodeRecord {
  const EncryptedFamilyCodeRecord({
    required this.material,
    required this.creatorAccountId,
    required this.createdAt,
    required this.updatedAt,
  });
  final EncryptedFamilyCodeMaterial material;
  final String creatorAccountId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class FamilyCodeDraft {
  const FamilyCodeDraft({
    required this.code,
    required this.lookupHash,
    required this.material,
  });
  final FamilyCode code;
  final String lookupHash;
  final EncryptedFamilyCodeMaterial material;
}
```

- [ ] **Step 4: Add failing deterministic crypto and tamper tests**

```dart
test('encrypts, hashes, and opens code material', () async {
  final codec = CryptographicFamilyCodeCodec(
    randomSymbolIndex: () => 7,
    randomBytes: (length) => List<int>.generate(length, (i) => i),
  );
  final draft = await codec.createDraft(
    familyId: familyId,
    codeVersion: 1,
    familyKey: List<int>.generate(32, (i) => i + 1),
  );
  expect(draft.code.normalized, '77777777');
  expect(base64Url.decode(base64Url.normalize(draft.lookupHash)), hasLength(32));
  expect(
    await codec.open(
      material: draft.material,
      familyKey: List<int>.generate(32, (i) => i + 1),
    ),
    draft.code,
  );
});

test('binds family and code version as authenticated data', () async {
  final draft = await codec.createDraft(
    familyId: familyId,
    codeVersion: 2,
    familyKey: familyKey,
  );
  final changed = draft.material.copyWith(codeVersion: 3);
  await expectLater(
    codec.open(material: changed, familyKey: familyKey),
    throwsA(const FamilyJoinFailure(FamilyJoinFailureCode.envelopeRejected)),
  );
});
```

- [ ] **Step 5: Implement AES-256-GCM code material and SHA-256 parity**

```dart
abstract interface class FamilyCodeCodec {
  Future<FamilyCodeDraft> createDraft({
    required String familyId,
    required int codeVersion,
    required List<int> familyKey,
  });
  Future<FamilyCode> open({
    required EncryptedFamilyCodeMaterial material,
    required List<int> familyKey,
  });
  Future<String> lookupHash(FamilyCode code);
}

List<int> familyCodeAad(String familyId, int codeVersion) => utf8.encode(
  'keepers-family-code:v1:$familyId:$codeVersion',
);
```

Generate each symbol with an injected unbiased `Random.secure().nextInt(32)`, hash the normalized eight ASCII bytes with SHA-256, and encrypt those same eight bytes using a fresh 12-byte nonce. Convert byte strings to canonical unpadded base64url and map format/authentication failures to `FamilyJoinFailureCode.envelopeRejected`.

- [ ] **Step 6: Run all Task 1 tests**

Run: `cd app && flutter test test/features/family/domain/family_code_test.dart test/features/family/data/family_code_codec_test.dart`

Expected: PASS, including every material-field mutation and wrong-key case.

- [ ] **Step 7: Commit Task 1**

```bash
git add app/lib/features/family/domain/family_code.dart app/lib/features/family/data/family_code_codec.dart app/test/features/family/domain/family_code_test.dart app/test/features/family/data/family_code_codec_test.dart
git commit -m "feat: add encrypted family codes"
```

### Task 2: Join-request domain and X25519 approval envelope

**Files:**
- Create: `app/lib/features/family/domain/family_join_request.dart`
- Create: `app/lib/features/family/data/joining_key_store.dart`
- Create: `app/lib/features/family/data/family_join_envelope_codec.dart`
- Test: `app/test/features/family/domain/family_join_request_test.dart`
- Test: `app/test/features/family/data/joining_key_store_test.dart`
- Test: `app/test/features/family/data/family_join_envelope_codec_test.dart`

**Interfaces:**
- Consumes: `SecureValueStore`, `X25519`, `Hkdf`, `AesGcm`, `AvatarConfig`, and Task 1 canonical decoding helpers.
- Produces: `StoredJoiningKey`, `JoiningKeyStore.getOrCreate({required String accountId, required String memberId})`, `FamilyJoinEnvelopeCodec.seal({required JoinEnvelopeContext context, required String requesterPublicKey, required List<int> familyKey})`, and `FamilyJoinEnvelopeCodec.open({required FamilyJoinApprovalEnvelope envelope, required String expectedRequesterPublicKey, required StoredJoiningKey joiningKey})`.

- [ ] **Step 1: Write strict model tests**

```dart
test('approval envelope round-trips only its exact wire shape', () {
  final envelope = FamilyJoinApprovalEnvelope.fromJson(validEnvelopeJson);
  expect(envelope.context.requestId, requestId);
  expect(envelope.toJson().keys, {
    'version', 'requestId', 'familyId', 'requesterAccountId',
    'codeVersion', 'ephemeralPublicKey', 'nonce', 'ciphertext', 'mac',
  });
  expect(envelope.toString(), 'FamilyJoinApprovalEnvelope(<redacted>)');
});
```

Implement exact models `FamilyJoinRequestState`, `FamilyJoinFailureCode`, `FamilyJoinFailure`, `FamilyJoinPreview`, `FamilyJoinProfileDraft`, `FamilyJoinRequestDraft`, `PendingFamilyJoinRequest`, `JoinEnvelopeContext`, `FamilyJoinApprovalEnvelope`, `OwnFamilyJoinRequest`, `FamilyJoinDecision`, and `ApprovedFamilyJoin`. Use these field contracts:

```dart
final class FamilyJoinPreview {
  FamilyJoinPreview({
    required this.familyId,
    required this.familyName,
    required this.codeVersion,
    required List<FamilyMember> members,
  }) : members = List.unmodifiable(members);
  final String familyId;
  final String familyName;
  final int codeVersion;
  final List<FamilyMember> members;
}

final class FamilyJoinProfileDraft {
  const FamilyJoinProfileDraft({
    required this.memberId,
    required this.displayName,
    required this.demographicRole,
    required this.colorToken,
    required this.avatar,
    required this.joiningPublicKey,
  });
  final String memberId;
  final String displayName;
  final FamilyDemographicRole demographicRole;
  final String colorToken;
  final AvatarConfig avatar;
  final String joiningPublicKey;
}

final class FamilyJoinRequestDraft {
  const FamilyJoinRequestDraft({required this.code, required this.profile});
  final FamilyCode code;
  final FamilyJoinProfileDraft profile;
}
```

`PendingFamilyJoinRequest` carries request/family/requester IDs, the exact profile fields, joining public key, code version, state, created time, and expiry. `OwnFamilyJoinRequest` adds family name, optional approval envelope, and an approved-state roster. `FamilyJoinDecision` carries request ID, family ID, authoritative state, and update time. `ApprovedFamilyJoin` carries request ID, family ID/name, local member ID, original joining public key, approval envelope, and roster. Require canonical UUIDs, positive versions, strict avatar decoding, and base64url lengths of 32 bytes for public keys/ciphertext, 12 for nonce, and 16 for MAC.

- [ ] **Step 2: Run the model test and confirm it fails**

Run: `cd app && flutter test test/features/family/domain/family_join_request_test.dart`

Expected: FAIL because the new request models are undefined.

- [ ] **Step 3: Implement the typed request models and failure codes**

```dart
enum FamilyJoinRequestState {
  pending,
  approved,
  installed,
  declined,
  cancelled,
  expired,
}

enum FamilyJoinFailureCode {
  notConfigured,
  signedOut,
  networkUnavailable,
  familyNotFound,
  alreadyMember,
  requestAlreadyPending,
  requestExpired,
  requestDeclined,
  requestCancelled,
  invitationChanged,
  codeCollision,
  codeVersionChanged,
  rateLimited,
  invalidJoinKey,
  notCreator,
  forbidden,
  envelopeRejected,
  localPersistenceFailed,
  unknown,
}

final class JoinEnvelopeContext {
  const JoinEnvelopeContext({
    required this.requestId,
    required this.familyId,
    required this.requesterAccountId,
    required this.codeVersion,
  });
  final String requestId;
  final String familyId;
  final String requesterAccountId;
  final int codeVersion;
}
```

- [ ] **Step 4: Write joining-key persistence tests before its implementation**

```dart
test('returns the same public key after a store restart', () async {
  final first = await store.getOrCreate(accountId: accountId, memberId: memberId);
  final restarted = SecureJoiningKeyStore(values, seedFactory: fixedSeed);
  final second = await restarted.getOrCreate(
    accountId: accountId,
    memberId: memberId,
  );
  expect(second.publicKey, first.publicKey);
  expect(second.reference, first.reference);
});

test('never exposes the private seed in its handle or diagnostics', () async {
  final key = await store.getOrCreate(accountId: accountId, memberId: memberId);
  expect(key.toString(), 'StoredJoiningKey(<redacted>)');
  expect(key.toString(), isNot(contains(base64UrlEncode(fixedSeed(32)))));
});
```

- [ ] **Step 5: Implement dedicated secure X25519 seed storage**

```dart
abstract interface class JoiningKeyStore {
  Future<StoredJoiningKey> getOrCreate({
    required String accountId,
    required String memberId,
  });
  Future<StoredJoiningKey?> find({
    required String accountId,
    required String memberId,
  });
  Future<T> use<T>({
    required StoredJoiningKey key,
    required Future<T> Function(SimpleKeyPair keyPair) operation,
  });
  Future<void> deleteExact(StoredJoiningKey key);
}
```

Use key reference `keepers.join.<accountId>.<memberId>.x25519-seed.v1`, store only a canonical 32-byte base64url seed, derive with `X25519.newKeyPairFromSeed`, and zero the mutable seed copy in `finally`. `deleteExact` must re-derive and compare the public key before deleting, so a stale handle cannot delete unrelated material.

- [ ] **Step 6: Write cross-device envelope tests**

```dart
test('approver seals and requester opens the family key', () async {
  final joiningKey = await requesterStore.getOrCreate(
    accountId: requesterId,
    memberId: memberId,
  );
  final envelope = await codec.seal(
    context: context,
    requesterPublicKey: joiningKey.publicKey,
    familyKey: familyKey,
  );
  expect(
    await codec.open(
      envelope: envelope,
      expectedRequesterPublicKey: joiningKey.publicKey,
      joiningKey: joiningKey,
    ),
    familyKey,
  );
});
```

- [ ] **Step 7: Implement X25519, HKDF-SHA-256, and AES-256-GCM**

```dart
abstract interface class FamilyJoinEnvelopeCodec {
  Future<FamilyJoinApprovalEnvelope> seal({
    required JoinEnvelopeContext context,
    required String requesterPublicKey,
    required List<int> familyKey,
  });
  Future<List<int>> open({
    required FamilyJoinApprovalEnvelope envelope,
    required String expectedRequesterPublicKey,
    required StoredJoiningKey joiningKey,
  });
}

List<int> joinEnvelopeAad(JoinEnvelopeContext context) => utf8.encode(
  'v1:${context.familyId}:${context.requestId}:'
  '${context.requesterAccountId}:${context.codeVersion}',
);
```

Use request UUID bytes as HKDF salt and `keepers-family-join-envelope-v1:<familyId>:<requesterAccountId>:<codeVersion>` as HKDF info. `seal` creates a fresh ephemeral X25519 key and nonce. `open` first checks that the stored joining public key equals the request public key. Zero mutable shared-secret and derived-key buffers in `finally`; never mutate the caller-owned family-key list.

- [ ] **Step 8: Run all Task 2 tests**

Run: `cd app && flutter test test/features/family/domain/family_join_request_test.dart test/features/family/data/joining_key_store_test.dart test/features/family/data/family_join_envelope_codec_test.dart`

Expected: PASS for restart stability, fixed wire vector, every context/material tamper, wrong key, fresh ephemeral keys, and exact deletion.

- [ ] **Step 9: Commit Task 2**

```bash
git add app/lib/features/family/domain/family_join_request.dart app/lib/features/family/data/joining_key_store.dart app/lib/features/family/data/family_join_envelope_codec.dart app/test/features/family/domain/family_join_request_test.dart app/test/features/family/data/joining_key_store_test.dart app/test/features/family/data/family_join_envelope_codec_test.dart
git commit -m "feat: add secure family join envelopes"
```

### Task 3: Encrypted local cache and two-phase installation recovery

**Files:**
- Modify: `app/lib/storage/schema.dart`
- Create: `app/lib/features/family/data/family_code_cache_repository.dart`
- Create: `app/lib/features/family/data/pending_join_completion_repository.dart`
- Create: `app/lib/features/family/data/approved_family_join_installer.dart`
- Create: `app/lib/features/family/application/pending_join_completion_controller.dart`
- Create: `app/lib/features/family/application/family_join_crypto_providers.dart`
- Test: `app/test/storage/app_database_test.dart`
- Test: `app/test/features/family/data/family_code_cache_repository_test.dart`
- Test: `app/test/features/family/data/pending_join_completion_repository_test.dart`
- Test: `app/test/features/family/data/approved_family_join_installer_test.dart`
- Test: `app/test/features/family/application/pending_join_completion_controller_test.dart`

**Interfaces:**
- Consumes: Task 1 encrypted material, Task 2 joining key store, `IdentityKeyService`, `FamilyRosterRepository`, `MemberRepository`, and `FamilyCodeJoinGateway.completeJoinRequest(String)` from Task 6.
- Produces: schema v6, `PendingJoinCompletion`, `ApprovedFamilyJoinInstaller.install({required ApprovedFamilyJoin approval, required List<int> familyKey, required String accountId})`, and `PendingJoinCompletionController.recover()`.

- [ ] **Step 1: Write migration tests for fresh and version-5 databases**

```dart
test('version 5 to 6 preserves legacy completion and adds join state', () async {
  final statements = KeepersSchema.statementsForUpgrade(5, 6).join('\n');
  expect(statements, contains('CREATE TABLE family_code_cache'));
  expect(statements, contains('CREATE TABLE pending_family_join_completion'));
  expect(statements, isNot(contains('DROP TABLE')));
  expect(KeepersSchema.tableNames, contains('pending_family_invite_completion'));
});
```

- [ ] **Step 2: Advance schema to version 6**

```sql
CREATE TABLE family_code_cache (
  family_id TEXT PRIMARY KEY,
  code_version INTEGER NOT NULL CHECK (code_version > 0),
  codec_version INTEGER NOT NULL CHECK (codec_version = 1),
  nonce TEXT NOT NULL,
  ciphertext TEXT NOT NULL,
  mac TEXT NOT NULL,
  creator_account_id TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  cached_at INTEGER NOT NULL,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE
)
```

```sql
CREATE TABLE pending_family_join_completion (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  request_id TEXT NOT NULL,
  family_id TEXT NOT NULL,
  member_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  installed_at INTEGER NOT NULL,
  FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE CASCADE,
  FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE CASCADE
)
```

- [ ] **Step 3: Write cache and exact-marker tests**

```dart
test('cache refuses to roll a family back to an older code version', () async {
  await repository.upsert(db, newerRecord);
  await expectLater(repository.upsert(db, olderRecord), throwsStateError);
  expect(await repository.find(db, familyId: familyId), newerRecord);
});

test('completion marker is idempotent only for the exact identity', () async {
  await repository.recordExact(db, pending);
  await repository.recordExact(db, pending);
  await expectLater(
    repository.recordExact(db, otherAccountPending),
    throwsStateError,
  );
});
```

- [ ] **Step 4: Implement encrypted cache and exact marker repositories**

`FamilyCodeCacheRepository.upsert` must accept a same-version identical record, accept a higher version, reject a lower version, and reject same-version changed ciphertext. It stores encrypted code material only. `PendingJoinCompletionRepository` mirrors the existing legacy exact-marker pattern but compares request, family, member, and account identifiers before insert or delete.

- [ ] **Step 5: Write installer rollback tests**

```dart
test('records completion only inside the local install transaction', () async {
  final pending = await installer.install(
    approval: approved,
    familyKey: familyKey,
    accountId: accountId,
  );
  expect(pending.requestId, approved.requestId);
  expect(await markers.find(db), pending);
  expect((await identities.findLocalIdentity(db))!.accountId, accountId);
});
```

- [ ] **Step 6: Implement transactional approved-family installation**

```dart
abstract interface class ApprovedFamilyJoinInstaller {
  Future<PendingJoinCompletion> install({
    required ApprovedFamilyJoin approval,
    required List<int> familyKey,
    required String accountId,
  });
}
```

Validate that the approved roster contains `localMemberId`. Import the family key, create the local member key, then transact family upsert, roster upsert, local-member key reference, identity binding, and marker insertion. On failure, roll back only secure keys whose `StoredIdentityKey.wasCreated` is true.

- [ ] **Step 7: Write completion-recovery tests**

```dart
test('retains marker through a network failure and retries idempotently', () async {
  gateway.completeFailure = const FamilyJoinFailure(
    FamilyJoinFailureCode.networkUnavailable,
  );
  await controller.recover();
  expect(await markers.find(db), pending);
  gateway.completeFailure = null;
  await controller.recover();
  expect(await markers.find(db), isNull);
  expect(gateway.completedRequestIds, [pending.requestId, pending.requestId]);
});
```

- [ ] **Step 8: Implement completion ordering and provider composition**

`recover()` must read the marker, verify the currently authenticated account exactly, call idempotent cloud completion, delete the matching joining key, then delete the exact marker. Any failure preserves the marker. Successful completion invalidates `localIdentityProvider` and the family roster provider. Compose codecs and repositories from `secureValueStoreProvider`, `identityKeyServiceProvider`, and `databaseProvider` in `family_join_crypto_providers.dart`.

- [ ] **Step 9: Run all Task 3 tests**

Run: `cd app && flutter test test/storage/app_database_test.dart test/features/family/data/family_code_cache_repository_test.dart test/features/family/data/pending_join_completion_repository_test.dart test/features/family/data/approved_family_join_installer_test.dart test/features/family/application/pending_join_completion_controller_test.dart`

Expected: PASS for 0→6 and 5→6 upgrades, failure rollback, conflicting marker refusal, account switching, and lost completion responses.

- [ ] **Step 10: Commit Task 3**

```bash
git add app/lib/storage/schema.dart app/lib/features/family/data/family_code_cache_repository.dart app/lib/features/family/data/pending_join_completion_repository.dart app/lib/features/family/data/approved_family_join_installer.dart app/lib/features/family/application/pending_join_completion_controller.dart app/lib/features/family/application/family_join_crypto_providers.dart app/test/storage/app_database_test.dart app/test/features/family/data/family_code_cache_repository_test.dart app/test/features/family/data/pending_join_completion_repository_test.dart app/test/features/family/data/approved_family_join_installer_test.dart app/test/features/family/application/pending_join_completion_controller_test.dart
git commit -m "feat: persist recoverable family joins"
```

### Task 4: Additive Supabase schema, RLS, and state-machine RPCs

**Files:**
- Create: `supabase/migrations/202609070001_family_code_join_requests.sql`
- Modify: `supabase/README.md`

**Interfaces:**
- Consumes: existing `private.is_valid_avatar_json(jsonb)`, `private.is_active_family_member(uuid)`, `public.cloud_families`, `public.profiles`, and `public.family_memberships`.
- Produces: two new tables and eleven authenticated JSON-returning RPCs named below.

- [ ] **Step 1: Start the migration with exact enums, tables, constraints, and indexes**

```sql
do $$ begin
  create type public.family_join_request_state as enum
    ('pending', 'approved', 'installed', 'declined', 'cancelled', 'expired');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.family_join_request_cancel_reason as enum
    ('requester', 'code_regenerated');
exception when duplicate_object then null; end $$;

create table if not exists public.family_join_codes (
  family_id uuid primary key references public.cloud_families(id) on delete cascade,
  code_version integer not null check (code_version > 0),
  code_hash bytea not null unique check (octet_length(code_hash) = 32),
  envelope_version integer not null check (envelope_version = 1),
  nonce text not null,
  ciphertext text not null,
  mac text not null,
  creator_account_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (updated_at >= created_at)
);
```

Create `family_join_requests` with every field in the approved spec, exact seven-day expiry, envelope columns nullable only outside `approved`/`installed`, canonical 43-character X25519 public keys, canonical 16/43/22-character nonce/cipher/MAC values, state/timestamp coherence checks, and partial unique indexes for one unresolved request per account and per `(family_id, requester_account_id)`.

- [ ] **Step 2: Add normalization, expiry, purge, and quota helpers**

```sql
create or replace function private.normalize_family_code(p_code text)
returns text
language plpgsql immutable
set search_path = ''
as $$
declare v_code text := upper(regexp_replace(coalesce(p_code, ''), '[ -]', '', 'g'));
begin
  if v_code !~ '^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{8}$' then
    raise exception using errcode = 'P0001', message = 'FAMILY_NOT_FOUND';
  end if;
  return v_code;
end;
$$;
```

`private.expire_family_join_requests()` updates elapsed `pending` requests to `expired`. `private.purge_family_join_requests(p_before timestamptz)` deletes resolved requests older than its explicit retention cutoff and is executable only by `service_role`. Add per-account invalid-attempt cooldown and bounded unresolved-request checks without storing submitted plaintext codes.

- [ ] **Step 3: Add RLS, publication, revoke, and grant boundaries**

Enable RLS on both tables. Active members may select their encrypted current code and pending requests for their own family; requesters may select only their own row. Revoke all direct table mutations from `anon` and `authenticated`. Add `family_join_requests` to `supabase_realtime` only when it is not already present.

- [ ] **Step 4: Implement atomic owner bootstrap with collision signaling**

```sql
create or replace function public.bootstrap_owner_family_with_code(
  p_family_id uuid,
  p_family_name text,
  p_member_id uuid,
  p_display_name text,
  p_demographic_role text,
  p_color_token text,
  p_avatar_json jsonb,
  p_code text,
  p_code_envelope jsonb
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_account_id uuid := auth.uid();
  v_code text;
begin
  if v_account_id is null then
    raise exception using errcode = 'P0001', message = 'SIGNED_OUT';
  end if;
  v_code := private.normalize_family_code(p_code);
  perform public.bootstrap_owner_family(
    p_family_id, p_family_name, p_member_id, p_display_name,
    p_demographic_role, p_color_token, p_avatar_json
  );
  begin
    insert into public.family_join_codes (
      family_id, code_version, code_hash, envelope_version,
      nonce, ciphertext, mac, creator_account_id
    ) values (
      p_family_id, 1, extensions.digest(v_code, 'sha256'),
      (p_code_envelope->>'version')::integer,
      p_code_envelope->>'nonce', p_code_envelope->>'ciphertext',
      p_code_envelope->>'mac', v_account_id
    ) on conflict (family_id) do nothing;
  exception when unique_violation then
    raise exception using errcode = 'P0001', message = 'CODE_COLLISION';
  end;
  return public.get_family_join_code(p_family_id);
end;
$$;
```

Validate the envelope's exact keys and bound `familyId`/`codeVersion` before insert. If the owner family already exists without code material, backfill version 1 idempotently; if it has material, return the authoritative existing record.

- [ ] **Step 5: Implement discovery and idempotent request creation**

Implement `get_family_join_code(uuid)`, `preview_family_by_code(text)`, and `create_family_join_request(uuid,text,uuid,text,text,text,jsonb,text)`. Preview returns only family name and public roster avatar projections. Preview and creation normalize and hash server-side. Malformed, unknown, and superseded inputs all emit exactly `FAMILY_NOT_FOUND`. Creation uses an account advisory lock, rejects an existing active membership, sets exactly seven-day expiry, and returns an existing unresolved request only when member/profile/public-key payloads match.

- [ ] **Step 6: Implement list/read and serialized decision transitions**

Implement `list_pending_family_join_requests(uuid)`, `get_own_family_join_request()`, `approve_family_join_request(uuid,jsonb)`, `decline_family_join_request(uuid)`, and `cancel_family_join_request(uuid)`. Every operation lazily expires requests first. Approval and decline require any active membership and lock the request with `FOR UPDATE`; a competing decision returns the authoritative resolved state. Approval validates every context field and envelope byte length. Cancellation is requester-only and valid only while `pending`.

- [ ] **Step 7: Implement activation and creator-only regeneration**

Implement `complete_family_join_request(uuid)` so it locks the approved request, rechecks one-family membership, inserts `profiles` and an `active` membership, and marks `installed` idempotently. Implement `regenerate_family_join_code(uuid,integer,text,jsonb)` so both owner membership and `cloud_families.owner_account_id` match the caller, `expectedVersion` matches, the version increments, old hash disappears, and old-version `pending` requests become `cancelled` with reason `code_regenerated`; approved requests remain completable.

- [ ] **Step 8: Verify the migration locally**

Run: `supabase db reset --local`

Expected: both migrations apply; the legacy invitation functions and all eleven new functions exist.

- [ ] **Step 9: Document deployment boundaries and commit**

Document migration-before-app rollout, legacy compatibility, seven-day expiry, resolved-row purge schedule, account quota, production ingress IP throttle, and the rule that plaintext codes/full links must be redacted from logs.

```bash
git add supabase/migrations/202609070001_family_code_join_requests.sql supabase/README.md
git commit -m "feat: add family join request backend"
```

### Task 5: Database authorization, neutrality, and concurrency proof

**Files:**
- Create: `supabase/tests/family_code_join_requests_test.sql`
- Create: `app/test/features/family/data/supabase_join_requests_contract_test.dart`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: Task 4 SQL contract.
- Produces: executable SQL/security checks and a static migration contract in Flutter CI.

- [ ] **Step 1: Add a failing static contract test**

```dart
test('family-code migration is additive and locked down', () {
  final sql = File('../supabase/migrations/202609070001_family_code_join_requests.sql')
      .readAsStringSync();
  expect(sql, contains('security definer'));
  expect(sql, contains("set search_path = ''"));
  expect(sql, contains('extensions.digest(v_code'));
  expect(sql, contains("interval '7 days'"));
  expect(sql, contains('for update'));
  expect(sql, contains('revoke insert, update, delete, truncate'));
  expect(sql, isNot(contains('DROP FUNCTION public.create_family_invite')));
});
```

- [ ] **Step 2: Run it before the final SQL contract is complete**

Run: `cd app && flutter test test/features/family/data/supabase_join_requests_contract_test.dart`

Expected: FAIL on any missing grant, lock, digest, expiry, or transition declaration.

- [ ] **Step 3: Add SQL assertions for every access and state boundary**

Use transactions with authenticated owner, member, requester, and unrelated UUID claims. Assert schema constraints, RLS visibility, no direct mutation grants, exact JSON keys, neutral family-not-found behavior, collision rollback, idempotent matching request replay, conflicting replay rejection, quota/cooldown, expiry, requester cancel, member approval/decline, creator regeneration, completion idempotency, and one-family uniqueness. Assert no column can hold a plaintext code, link, joining private key, family key, or shared secret.

- [ ] **Step 4: Add serialized race fixtures**

Use two psql sessions in the CI script for approve/approve, approve/decline, regenerate/request, completion/expiry, and completion into two families. Each second transaction must either return the first authoritative result or the documented typed failure; it must not create two memberships or two decisions.

- [ ] **Step 5: Run SQL and static contract suites**

Run: `supabase test db --local`

Run: `cd app && flutter test test/features/family/data/supabase_join_requests_contract_test.dart`

Expected: PASS with the pgTAP plan count exact and no failed assertions.

- [ ] **Step 6: Wire the commands into CI and commit**

```bash
git add supabase/tests/family_code_join_requests_test.sql app/test/features/family/data/supabase_join_requests_contract_test.dart .github/workflows/ci.yml
git commit -m "test: prove family join request security"
```

### Task 6: Additive Dart gateway and strict Supabase adapter

**Files:**
- Modify: `app/lib/features/family/data/cloud_family_gateway.dart`
- Modify: `app/lib/features/family/data/supabase_cloud_family_gateway.dart`
- Modify: `app/lib/features/family/data/unavailable_cloud_family_gateway.dart`
- Modify: `app/lib/features/family/application/cloud_family_providers.dart`
- Create: `app/test/features/family/data/supabase_family_code_join_gateway_test.dart`
- Modify: `app/test/features/family/data/supabase_cloud_family_gateway_test.dart`

**Interfaces:**
- Consumes: Task 1/2 domain models and Task 4 RPCs.
- Produces: separately injectable `FamilyCodeJoinGateway` plus invalidation streams.

- [ ] **Step 1: Add a fake-driven failing gateway contract test**

```dart
test('request creation sends code and public key but no private material', () async {
  await gateway.createFamilyJoinRequest(draft);
  expect(client.lastFunction, 'create_family_join_request');
  expect(client.lastParams['p_code'], draft.code.normalized);
  expect(client.lastParams['p_joining_public_key'], draft.joiningPublicKey);
  expect(client.lastParams.keys, isNot(contains('familyKey')));
  expect(client.lastParams.keys, isNot(contains('joiningPrivateKey')));
});
```

- [ ] **Step 2: Add the independent capability interface**

```dart
abstract interface class FamilyCodeJoinGateway {
  bool get isConfigured;
  String? get authenticatedAccountId;
  Future<EncryptedFamilyCodeRecord> bootstrapOwnerWithFamilyCode(
    LocalOwnerFamily owner,
    FamilyCodeDraft code,
  );
  Future<EncryptedFamilyCodeRecord> getFamilyCode(String familyId);
  Future<FamilyJoinPreview> previewFamilyByCode(FamilyCode code);
  Future<OwnFamilyJoinRequest> createFamilyJoinRequest(
    FamilyJoinRequestDraft draft,
  );
  Future<List<PendingFamilyJoinRequest>> listPendingJoinRequests(
    String familyId,
  );
  Future<OwnFamilyJoinRequest?> getOwnJoinRequest();
  Future<FamilyJoinDecision> approveJoinRequest(
    String requestId,
    FamilyJoinApprovalEnvelope envelope,
  );
  Future<FamilyJoinDecision> declineJoinRequest(String requestId);
  Future<FamilyJoinDecision> cancelJoinRequest(String requestId);
  Future<FamilyJoinDecision> completeJoinRequest(String requestId);
  Future<EncryptedFamilyCodeRecord> regenerateFamilyCode({
    required String familyId,
    required int expectedVersion,
    required FamilyCodeDraft replacement,
  });
  Stream<void> watchOwnJoinRequest();
  Stream<void> watchPendingJoinRequests(String familyId);
}
```

- [ ] **Step 3: Extend the Supabase client adapter only with narrow Realtime invalidations**

Add a `SupabaseCloudRealtimeClient` capability whose two methods return `Stream<void>` and filter `family_join_requests` by exact requester account ID or family ID. Keep payload decoding in RPC reads so Realtime never becomes authoritative state.

- [ ] **Step 4: Implement strict RPC encoding/decoding and failure mapping**

`SupabaseCloudFamilyGateway` implements both `CloudFamilyGateway` and `FamilyCodeJoinGateway`. Pin every RPC name and parameter key. Reject extra/missing response fields, noncanonical UUID/base64/timestamps, invalid state transitions, roster-family mismatches, and envelope-context mismatches. Map exact `P0001` messages to `FamilyJoinFailureCode`; map malformed/unknown/superseded lookups to `familyNotFound` without exposing distinctions.

- [ ] **Step 5: Add unavailable capability and provider composition**

Expose `familyCodeJoinGatewayProvider` by checking whether the existing gateway implements `FamilyCodeJoinGateway`; otherwise return `UnavailableFamilyCodeJoinGateway`, whose every operation throws `FamilyJoinFailureCode.notConfigured` and whose streams are empty.

- [ ] **Step 6: Run old and new gateway tests**

Run: `cd app && flutter test test/features/family/data/supabase_cloud_family_gateway_test.dart test/features/family/data/supabase_family_code_join_gateway_test.dart`

Expected: PASS; old email-invitation RPC payloads remain byte-for-byte compatible.

- [ ] **Step 7: Commit Task 6**

```bash
git add app/lib/features/family/data/cloud_family_gateway.dart app/lib/features/family/data/supabase_cloud_family_gateway.dart app/lib/features/family/data/unavailable_cloud_family_gateway.dart app/lib/features/family/application/cloud_family_providers.dart app/test/features/family/data/supabase_cloud_family_gateway_test.dart app/test/features/family/data/supabase_family_code_join_gateway_test.dart
git commit -m "feat: connect family codes to Supabase"
```

### Task 7: Family-code controller, copy/share actions, and invite sheet

**Files:**
- Create: `app/lib/features/family/application/family_code_controller.dart`
- Modify: `app/lib/features/family/data/invite_share_service.dart`
- Create: `app/lib/features/family/presentation/family_invite_sheet.dart`
- Keep: `app/lib/features/family/presentation/family_invite_screen.dart` as a compatibility facade for old routes until Task 11 removes only new-app references.
- Test: `app/test/features/family/application/family_code_controller_test.dart`
- Test: `app/test/features/family/presentation/family_invite_sheet_test.dart`

**Interfaces:**
- Consumes: Task 1 codec, Task 3 cache, Task 6 gateway, `IdentityKeyService`, `InviteShareService`, and an injectable clipboard boundary.
- Produces: one controller used by both top-right code and existing Invite bubble.

- [ ] **Step 1: Write failing controller tests for bootstrap, offline cache, and collision retry**

```dart
test('publishes only the authoritative committed code', () async {
  gateway.failures.add(const FamilyJoinFailure(FamilyJoinFailureCode.codeCollision));
  await container.read(familyCodeControllerProvider(familyId).notifier).load();
  final state = container.read(familyCodeControllerProvider(familyId));
  expect(codec.createCalls, 2);
  expect(state.displayCode, gateway.authoritativeCode.display);
  expect(state.displayCode, isNot(codec.firstCandidate.display));
});

test('opens cached encrypted material while offline', () async {
  gateway.failure = const FamilyJoinFailure(FamilyJoinFailureCode.networkUnavailable);
  await controller.load();
  expect(controller.state.displayCode, 'K7M4-P2Q8');
  expect(controller.state.isOffline, isTrue);
});
```

- [ ] **Step 2: Implement the controller state and commands**

```dart
enum FamilyCodePhase { loading, ready, regenerating, failed }

final class FamilyCodeState {
  const FamilyCodeState({
    this.phase = FamilyCodePhase.loading,
    this.displayCode,
    this.codeVersion,
    this.isCreator = false,
    this.isOffline = false,
    this.feedback,
    this.failure,
  });
  final FamilyCodePhase phase;
  final String? displayCode;
  final int? codeVersion;
  final bool isCreator;
  final bool isOffline;
  final String? feedback;
  final FamilyJoinFailure? failure;
}
```

`load()` first decrypts valid cached material, then refreshes from cloud. If the family has no cloud code, it resolves the local family key, generates version-1 candidates, and retries `CODE_COLLISION` at most five times. Cache only the server-returned encrypted record. `regenerate()` creates `currentVersion + 1`, uses optimistic version matching, and replaces UI/cache only with the authoritative response.

- [ ] **Step 3: Add clipboard and share boundaries**

```dart
abstract interface class FamilyClipboard {
  Future<void> writeText(String value);
}

Future<void> shareFamilyLink(
  FamilyCode code, {
  Rect? sharePositionOrigin,
}) => shareInvitation(code.joinUri, sharePositionOrigin: sharePositionOrigin);
```

The controller writes plaintext only to the explicit user-invoked clipboard/share boundary and emits short success feedback; diagnostics remain redacted.

- [ ] **Step 4: Write invite-sheet widget tests**

```dart
testWidgets('shows sharing actions and creator-only regeneration', (tester) async {
  await tester.pumpWidget(harness(isCreator: true));
  expect(find.text('Share family link'), findsOneWidget);
  expect(find.text('Copy family code'), findsOneWidget);
  expect(find.text('Copy link'), findsOneWidget);
  expect(find.text('Regenerate code'), findsOneWidget);
  await tester.tap(find.text('Regenerate code'));
  await tester.pumpAndSettle();
  expect(find.textContaining('previous code and pending requests'), findsOneWidget);
});
```

- [ ] **Step 5: Build `FamilyInviteSheet.show` with stable states**

Use a scroll-controlled modal bottom sheet with SafeArea, the app background/colors/type, and 48dp rows. Show code, Share family link, Copy family code, Copy link, and creator-only Regenerate. The confirmation states the exact consequences. Disable all decision actions during regeneration, restore focus after cancel/error, and keep the sheet height stable while showing progress or Retry.

- [ ] **Step 6: Run Task 7 tests and commit**

Run: `cd app && flutter test test/features/family/application/family_code_controller_test.dart test/features/family/presentation/family_invite_sheet_test.dart`

```bash
git add app/lib/features/family/application/family_code_controller.dart app/lib/features/family/data/invite_share_service.dart app/lib/features/family/presentation/family_invite_sheet.dart app/lib/features/family/presentation/family_invite_screen.dart app/test/features/family/application/family_code_controller_test.dart app/test/features/family/presentation/family_invite_sheet_test.dart
git commit -m "feat: share permanent family codes"
```

### Task 8: Requester join controller, screen, and restart restoration

**Files:**
- Rewrite: `app/lib/features/family/application/family_join_controller.dart`
- Rewrite: `app/lib/features/family/presentation/family_join_screen.dart`
- Modify: `app/lib/features/onboarding/presentation/setup_screen.dart`
- Modify: `app/lib/features/onboarding/presentation/startup_gate.dart`
- Test: `app/test/features/family/application/family_join_controller_test.dart`
- Test: `app/test/features/family/presentation/family_join_screen_test.dart`
- Test: `app/test/features/onboarding/presentation/setup_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 key/envelope models, Task 3 installer/recovery, Task 6 gateway/auth events, and existing avatar catalog.
- Produces: manual-code, link-code, preview, pending, cancel, approved-install, and terminal requester states.

- [ ] **Step 1: Write controller tests for the complete two-phase path**

```dart
test('approval installs locally before cloud activation', () async {
  await controller.loadCode(FamilyCode.parse('K7M4-P2Q8'));
  await controller.requestJoin(profile);
  gateway.ownRequest = approvedOwnRequest;
  await controller.refreshStatus();
  expect(events, ['install', 'complete', 'deleteJoiningKey']);
  expect(controller.state.phase, FamilyJoinPhase.complete);
});

test('missed realtime is recovered on resume', () async {
  gateway.ownRequest = approvedOwnRequest;
  await controller.onResumed();
  expect(installer.installCalls, 1);
});
```

- [ ] **Step 2: Implement the explicit state machine**

```dart
enum FamilyJoinPhase {
  enteringCode,
  checking,
  needsAuthentication,
  awaitingOtp,
  preview,
  requesting,
  pending,
  installing,
  complete,
  declined,
  cancelled,
  expired,
  invitationChanged,
  failed,
}
```

Expose `loadCode(FamilyCode)`, `requestEmailOtp(String)`, `verifyEmailOtp({required String email, required String token})`, `requestJoin(FamilyJoinProfileDraft)`, `refreshStatus()`, `cancel()`, and `onResumed()`. Generate and persist a proposed member UUID plus X25519 key before request creation. Matching repeat submissions reuse both. Subscribe to own-request Realtime only as an invalidation signal. On approval, validate envelope context, decrypt, install, zero the controller's family-key copy, call completion, clean up the joining key, and refresh identity/roster. Preserve authoritative pending state on network errors.

- [ ] **Step 3: Write screen tests for manual, link, preview, and terminal states**

```dart
testWidgets('manual entry accepts pasted formatting and previews a family', (tester) async {
  await tester.pumpWidget(harness(screen: const FamilyJoinScreen.manual()));
  await tester.enterText(find.byKey(const Key('family-code-field')), 'k7m4 p2-q8');
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  expect(find.text('Rahman family'), findsOneWidget);
  expect(find.text('Request to join'), findsOneWidget);
  expect(find.textContaining('memory'), findsNothing);
});
```

- [ ] **Step 4: Build the join surface**

Provide constructors `FamilyJoinScreen.manual()`, `FamilyJoinScreen.forCode(FamilyCode)`, and `FamilyJoinScreen.malformed()`. Manual mode has exactly one paste-friendly code field. Link mode skips code entry. Signed-out state uses the existing account email OTP flow and resumes the same code. Preview shows family name and sanitized avatars only, then a compact name/avatar profile confirmation and Request to join. Pending says “Waiting for a family member to let you in” and has Cancel. Terminal copy exactly distinguishes declined, expired, invitation changed, already-member, and neutral Family not found. Network errors preserve the last state and expose Retry.

- [ ] **Step 5: Make Setup Join functional and restore pending work at startup**

The Setup screen Join action opens `FamilyJoinScreen.manual()`. `StartupGate` first runs completion recovery, then asks `getOwnJoinRequest()` for a signed-in account with no local identity. Pending/approved requests resume the join screen before local family setup. Declined/cancelled/expired requests return to Setup with one live-region status message.

- [ ] **Step 6: Run Task 8 tests and commit**

Run: `cd app && flutter test test/features/family/application/family_join_controller_test.dart test/features/family/presentation/family_join_screen_test.dart test/features/onboarding/presentation/setup_screen_test.dart`

```bash
git add app/lib/features/family/application/family_join_controller.dart app/lib/features/family/presentation/family_join_screen.dart app/lib/features/onboarding/presentation/setup_screen.dart app/lib/features/onboarding/presentation/startup_gate.dart app/test/features/family/application/family_join_controller_test.dart app/test/features/family/presentation/family_join_screen_test.dart app/test/features/onboarding/presentation/setup_screen_test.dart
git commit -m "feat: request family membership by code"
```

### Task 9: Existing-member approval controller and sheet

**Files:**
- Create: `app/lib/features/family/application/family_join_requests_controller.dart`
- Create: `app/lib/features/family/presentation/family_join_request_sheet.dart`
- Test: `app/test/features/family/application/family_join_requests_controller_test.dart`
- Test: `app/test/features/family/presentation/family_join_request_sheet_test.dart`

**Interfaces:**
- Consumes: Task 2 envelope codec, Task 6 gateway/Realtime, local identity family-key reference, and roster invalidation.
- Produces: family-scoped pending-request state plus serialized `approve(String)` and `decline(String)` commands.

- [ ] **Step 1: Write decision and zeroization tests**

```dart
test('any active member seals one approval and accepts authoritative resolution', () async {
  await controller.refresh();
  await controller.approve(requestId);
  expect(codec.lastContext.requestId, requestId);
  expect(gateway.approvals, hasLength(1));
  expect(controller.state.requests, isEmpty);
  expect(familyKeyBuffer.every((byte) => byte == 0), isTrue);
});

test('concurrent decline resolved elsewhere is not shown as a false failure', () async {
  gateway.decision = FamilyJoinDecision(requestId: requestId, state: FamilyJoinRequestState.approved);
  await controller.decline(requestId);
  expect(controller.state.failure, isNull);
  expect(controller.state.requests, isEmpty);
});
```

- [ ] **Step 2: Implement family-scoped state and commands**

```dart
final class FamilyJoinRequestsState {
  const FamilyJoinRequestsState({
    this.requests = const [],
    this.isRefreshing = false,
    this.resolvingRequestId,
    this.failure,
  });
  final List<PendingFamilyJoinRequest> requests;
  final bool isRefreshing;
  final String? resolvingRequestId;
  final FamilyJoinFailure? failure;
}
```

`refresh()` reads authoritative pending rows. Realtime only calls `refresh()`. `approve()` resolves the 32-byte family key, copies it into a mutable buffer, seals an envelope for the request context/public key, submits the decision, zeros the buffer in `finally`, and refreshes. `decline()` uses the same per-request dedupe and treats another member's valid first decision as authoritative success.

- [ ] **Step 3: Write approval-sheet behavior and accessibility tests**

```dart
testWidgets('shows requester identity and disables both decisions while resolving', (tester) async {
  await tester.pumpWidget(harness(resolving: true));
  expect(find.text('Mariam wants to join'), findsOneWidget);
  expect(tester.widget<ButtonStyleButton>(find.text('Approve')).onPressed, isNull);
  expect(tester.widget<ButtonStyleButton>(find.text('Decline')).onPressed, isNull);
  expect(find.bySemanticsLabel('Mariam profile'), findsOneWidget);
});
```

- [ ] **Step 4: Build the request sheet**

Show only requester avatar/name and Approve/Decline—no family memories. Use a confirmation for Decline, stable in-place progress, focus recovery, live-region resolution, and minimum 48dp controls. Close after authoritative resolution and invalidate the list.

- [ ] **Step 5: Run Task 9 tests and commit**

Run: `cd app && flutter test test/features/family/application/family_join_requests_controller_test.dart test/features/family/presentation/family_join_request_sheet_test.dart`

```bash
git add app/lib/features/family/application/family_join_requests_controller.dart app/lib/features/family/presentation/family_join_request_sheet.dart app/test/features/family/application/family_join_requests_controller_test.dart app/test/features/family/presentation/family_join_request_sheet_test.dart
git commit -m "feat: approve family join requests"
```

### Task 10: Main family interface integration and arrival motion

**Files:**
- Modify: `app/lib/ui/family_wheel_screen.dart`
- Modify: `app/lib/features/vault/presentation/observatory_screen.dart`
- Test: `app/test/ui/family_wheel_screen_test.dart`
- Test: `app/test/features/vault/presentation/observatory_screen_test.dart`

**Interfaces:**
- Consumes: Tasks 7 and 9 controller states and sheets, existing family roster provider, and `keepersReduceMotion(context)`.
- Produces: top-right code, shared Invite entry, slim pending notice, and newly installed avatar arrival.

- [ ] **Step 1: Write pure wheel layout and semantics tests**

```dart
testWidgets('keeps wordmark centered while code is top-right', (tester) async {
  await tester.pumpWidget(wheel(familyCode: 'K7M4-P2Q8'));
  expect(find.text('Family code'), findsOneWidget);
  expect(find.text('K7M4-P2Q8'), findsOneWidget);
  expect(find.bySemanticsLabel('Family code K 7 M 4 P 2 Q 8'), findsOneWidget);
  final wordmark = tester.getCenter(find.byKey(const ValueKey('keepers-wordmark')));
  expect(wordmark.dx, closeTo(195, 1));
  expect(tester.getSize(find.byKey(const ValueKey('family-code-action'))).height, greaterThanOrEqualTo(48));
});

testWidgets('places a join notice above the bubble field', (tester) async {
  await tester.pumpWidget(wheel(pendingName: 'Mariam'));
  expect(
    tester.getTopLeft(find.byKey(const ValueKey('family-join-request-notice'))).dy,
    lessThan(tester.getTopLeft(find.byKey(const ValueKey('family-field-interactive-viewer'))).dy),
  );
});
```

- [ ] **Step 2: Extend the pure wheel contract**

Add nullable props `familyCode`, `onFamilyCodeTap`, `pendingJoinRequestName`, and `onPendingJoinRequestTap`. `_WheelHeader` becomes a Stack: wordmark remains geometrically centered, while a quiet two-line InkResponse sits top-right. The existing Invite bubble and code control call the same invite-sheet callback. Insert the slim “Name wants to join” notice after presence and before the field.

- [ ] **Step 3: Add arrival motion tests and implementation**

Track roster member IDs in `didUpdateWidget`. A new ID enters with a short offset-to-position plus opacity animation. When reduced motion is true, offset remains zero and only opacity changes. Existing bubbles must not replay. The transition cannot change the field's measured size.

- [ ] **Step 4: Wire orchestration and lifecycle refresh**

`ObservatoryScreen` watches family code and request controllers, supplies pure props, opens `FamilyInviteSheet` from both entry points, and opens `FamilyJoinRequestSheet` from the notice. On resume refresh roster, code, own pending completion, and family pending requests. When an installed request disappears or the roster invalidates, refresh the roster so the avatar arrives without app restart.

- [ ] **Step 5: Verify small/large mobile and enlarged text**

Run: `cd app && flutter test test/ui/family_wheel_screen_test.dart test/features/vault/presentation/observatory_screen_test.dart`

Expected: PASS at 390×844 and 430×932 fixtures, 1.4× text scaling, reduced motion, offline cached code, noncreator sheet, and installed-avatar refresh.

- [ ] **Step 6: Commit Task 10**

```bash
git add app/lib/ui/family_wheel_screen.dart app/lib/features/vault/presentation/observatory_screen.dart app/test/ui/family_wheel_screen_test.dart app/test/features/vault/presentation/observatory_screen_test.dart
git commit -m "feat: surface family code and join approvals"
```

### Task 11: Permanent HTTPS link routing and platform associations

**Files:**
- Modify: `app/lib/features/family/data/invite_link_coordinator.dart`
- Modify: `app/lib/app.dart`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Modify: `app/ios/Runner/Info.plist`
- Modify: `app/ios/Runner/Runner.entitlements`
- Modify: `app/test/features/family/data/invite_link_coordinator_test.dart`
- Modify: `app/test/platform/invite_link_platform_contract_test.dart`
- Modify: `app/test/app_test.dart`

**Interfaces:**
- Consumes: `FamilyJoinLink.parse(Uri)` from Task 1 and `FamilyJoinScreen.forCode(FamilyCode)` from Task 8.
- Produces: cold/warm verified-link routing that coalesces duplicate OS delivery without permanently suppressing the reusable link.

- [ ] **Step 1: Replace capability-link tests with reusable permanent-link tests**

```dart
test('coalesces dual cold delivery but permits a later deliberate reopen', () async {
  source.initial = Uri.parse('https://join.keepers.app/f/K7M4-P2Q8');
  source.emit(source.initial!);
  final first = await coordinator.takeInitialLink();
  expect(first, isA<ValidFamilyJoinLinkEvent>());
  source.emit(source.initial!);
  await expectLater(coordinator.events, emits(isA<ValidFamilyJoinLinkEvent>()));
});
```

- [ ] **Step 2: Rewrite parsing and bounded dedupe**

Parse only `https://join.keepers.app/f/<code>` into `ValidFamilyJoinLinkEvent`; malformed links under that path become `MalformedFamilyJoinLinkEvent`; unrelated URLs are ignored. Replace permanent `seenInviteIds` storage with one cold-delivery digest and a short bounded queue so reopening the same permanent code is valid after the active route closes.

- [ ] **Step 3: Update root navigation**

Cold and warm valid events build `FamilyJoinScreen.forCode(event.link.code)`. Keep the current route-presentation mutex and abandon/complete callbacks so a second link cannot stack while one Join screen is active.

- [ ] **Step 4: Configure platform routes without weakening auth callback handling**

Android gets an `android:autoVerify="true"` HTTPS intent filter for scheme `https`, host `join.keepers.app`, and path prefix `/f/`. iOS adds `applinks:join.keepers.app` to associated domains. Retain the separate `keepers://auth-callback` scheme and its strict callback predicate.

- [ ] **Step 5: Run routing and platform contract tests**

Run: `cd app && flutter test test/features/family/data/invite_link_coordinator_test.dart test/platform/invite_link_platform_contract_test.dart test/app_test.dart`

Expected: PASS for cold start, warm start, signed-out auth/resume, malformed neutrality, dual OS delivery, deliberate reopen, and retained auth callback.

- [ ] **Step 6: Commit Task 11**

```bash
git add app/lib/features/family/data/invite_link_coordinator.dart app/lib/app.dart app/android/app/src/main/AndroidManifest.xml app/ios/Runner/Info.plist app/ios/Runner/Runner.entitlements app/test/features/family/data/invite_link_coordinator_test.dart app/test/platform/invite_link_platform_contract_test.dart app/test/app_test.dart
git commit -m "feat: route verified family join links"
```

### Task 12: End-to-end verification, accessibility, deployment, and visual repair

**Files:**
- Rewrite: `app/integration_test/family_invitation_flow_test.dart`
- Rewrite: `app/integration_test/support/family_invitation_flow_harness.dart`
- Rewrite: `app/test/features/family/presentation/family_invitation_accessibility_test.dart`
- Modify: `app/README.md`
- Modify: `supabase/README.md`
- Modify: `design-qa.md`

**Interfaces:**
- Consumes: the complete family-code flow.
- Produces: investor-demo-safe acceptance evidence and exact deployment/runbook gates.

- [ ] **Step 1: Build a two-device integration harness**

Model owner, existing member, and requester with separate secure stores, databases, sessions, and Realtime streams. Exercise code load/share, manual entry, link entry, preview, request, approval, offline requester, reconnect, local install, completion, and roster arrival. Keep fixture keys deterministic and explicitly development-only.

- [ ] **Step 2: Add recovery and terminal integration cases**

Cover process death before approval, after approval, during local install, after marker write, and after server completion; missed Realtime; decline; requester cancel; seven-day expiry; creator regeneration; stale link; switched account; concurrent decisions; and a lost completion response. Assert exactly one active membership and no private content in preview.

- [ ] **Step 3: Run formatting, analysis, unit, widget, SQL, and integration suites**

Run: `cd app && dart format --output=none --set-exit-if-changed lib test integration_test`

Run: `cd app && flutter analyze`

Run: `cd app && flutter test`

Run: `supabase test db --local`

Run: `cd app && flutter test integration_test/family_invitation_flow_test.dart`

Expected: every command exits 0 with no analyzer warnings or test failures.

- [ ] **Step 4: Capture and critique the required UI states twice**

Capture 390×844 and 430×932 for main code loaded/offline, noncreator code sheet, creator regeneration confirmation, manual code entry, family preview, pending/cancel, join-request notice, approval sheet, decline, expiry, invitation-changed, network failure/retry, and the installed-avatar arrival end state. Repeat at 1.4× text and reduced motion. Review hierarchy, clipping, focus, contrast, 48dp targets, semantics, copy wrapping, keyboard insets, and route stability; fix each visible defect and record both passes in `design-qa.md`.

- [ ] **Step 5: Run real-device Android acceptance**

Install on two connected Android devices. Test manual code and HTTPS link; app absent/install/resume; signed-out/authenticate/resume; foreground/background/process death/device restart; requester offline during approval; regeneration while pending; decline/cancel/expiry; and wrong-account recovery. Inspect Supabase rows/logs and local diagnostics to verify no plaintext family key, memory, joining private key, shared secret, or full join URL appears.

- [ ] **Step 6: Complete external release gates without false claims**

Deploy the migration before the app. Configure the resolved-request purge schedule and production account/IP throttles. Publish `assetlinks.json` and `apple-app-site-association` on `join.keepers.app` with the actual release signing certificate and Apple application identifier, then verify both over HTTPS with no redirects. If those production credentials or domain controls are unavailable, mark the corresponding verified-link and IP-throttle gates explicitly blocked while manual code joining remains functional; do not label the build launch-ready.

- [ ] **Step 7: Run final regression and commit evidence**

Run: `cd app && flutter test && flutter analyze`

Run: `supabase test db --local`

Expected: all tests pass after visual repairs.

```bash
git add app/integration_test/family_invitation_flow_test.dart app/integration_test/support/family_invitation_flow_harness.dart app/test/features/family/presentation/family_invitation_accessibility_test.dart app/README.md supabase/README.md design-qa.md
git commit -m "test: verify family code joining end to end"
```

## Plan Self-Review Record

- **Spec coverage:** Tasks 1–3 cover code secrecy, encrypted cache, X25519 handoff, two-phase install, and restart recovery. Tasks 4–6 cover the data model, RLS, neutral lookup, expiry, quotas, concurrency, compatibility, and strict gateway. Tasks 7–11 cover code display/share/regeneration, manual and native-link entry, approval, Realtime/resume refresh, main-screen notice, reduced motion, and platform routes. Task 12 covers accessibility, device acceptance, retention, verified-domain deployment, and the explicit IP-throttle release gate.
- **Intentional subsystem boundary:** Existing email OTP authentication is reused. Social/password account-provider work and remote memory synchronization are not silently added to this feature.
- **Type consistency:** `FamilyCode`, `EncryptedFamilyCodeMaterial`, `EncryptedFamilyCodeRecord`, `FamilyCodeDraft`, `OwnFamilyJoinRequest`, `PendingFamilyJoinRequest`, `FamilyJoinDecision`, `FamilyJoinApprovalEnvelope`, `StoredJoiningKey`, and `PendingJoinCompletion` have a single producer and are consumed by the named later tasks.
- **Compatibility:** The plan adds `FamilyCodeJoinGateway` instead of expanding every legacy `CloudFamilyGateway` fake, leaves the 2026-09-05 migration intact, and keeps old invite RPCs callable.
- **Operational truthfulness:** SQL/account throttling is testable in the repository; production IP throttling and verified-domain association remain mandatory deployment gates that require the real ingress, domain, and signing credentials.
