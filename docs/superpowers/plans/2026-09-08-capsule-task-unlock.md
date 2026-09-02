# Capsule Task Unlock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Legacy Milestone and the preview-only Legacy Lock route with persisted Capsule memories and optional per-member task unlocking in Memory Key.

**Architecture:** Preserve the authenticated `legacy` storage token behind an explicit `PrivacyTier.capsule` codec. Save one Capsule assignment per persisted family member atomically with the encrypted entry, expose assignments through a dedicated repository/service/provider, and enforce task readiness before any recipient blob read. Memory Key renders real locked and ready assignments; capture owns the optional task draft.

**Tech Stack:** Flutter 3.47.2, Dart 3.13.2, Riverpod 3, SQLCipher through `sqflite_sqlcipher`, existing AES-GCM entry envelopes, Flutter widget tests.

**Spec:** `docs/superpowers/specs/2026-09-08-capsule-task-unlock-design.md`

## Global Constraints

- Keep the persisted/AAD privacy token exactly `legacy`; never rewrite existing encrypted rows.
- Capsule task text is 1–180 trimmed characters when enabled and is stored only in SQLCipher metadata.
- Insert the entry and all current-roster Capsule assignments in one transaction; failure leaves no entry row or finalized blob.
- Recipient open checks family, target, Capsule privacy, assignment state, and expiry before any key or blob read.
- Do not fabricate remote completion or claim cross-device payload synchronization.
- Remove all user-facing Legacy Milestone, Legacy Lock, approval-preview, and separate Locks destination UI.
- Follow `DESIGN.md` and `UX-CONTRACT.md`: Modern Society type, black primary actions, ivory cards, restrained gold accents, 48-pixel actions, stable loading/error/empty geometry, and reduced-motion support.

---

### Task 1: Stable Capsule privacy codec

**Files:**
- Modify: `app/lib/features/capture/domain/capture_models.dart`
- Modify: `app/lib/features/capture/data/entry_key_resolver.dart`
- Modify: `app/lib/features/capture/data/entry_repository.dart`
- Modify: `app/lib/features/vault/domain/vault_models.dart`
- Test: `app/test/features/capture/domain/capture_models_test.dart`
- Test: `app/test/features/capture/data/entry_key_resolver_test.dart`
- Test: `app/test/features/capture/data/entry_cipher_test.dart`

**Interfaces:**
- Produce `PrivacyTier.capsule`, `PrivacyTier.storageValue`, and `PrivacyTier.fromStorage(String)`.
- Every persisted/AAD value for Capsule remains `legacy`.

- [ ] Write tests asserting `capsule.storageValue == 'legacy'`, `fromStorage('legacy') == capsule`, unknown values throw, and a Capsule envelope authenticates with the legacy token.
- [ ] Run `flutter test test/features/capture/domain/capture_models_test.dart test/features/capture/data/entry_key_resolver_test.dart test/features/capture/data/entry_cipher_test.dart` and verify the new tests fail because the codec/case does not exist.
- [ ] Implement the explicit codec, replace `.name` persistence, replace `values.byName` decoding, and make key selection an exhaustive switch.
- [ ] Run the focused tests and verify they pass.

### Task 2: Capsule assignment repository and atomic capture save

**Files:**
- Create: `app/lib/features/capsule/domain/capsule_models.dart`
- Create: `app/lib/features/capsule/data/capsule_repository.dart`
- Modify: `app/lib/features/capture/domain/capture_models.dart`
- Modify: `app/lib/features/capture/data/entry_persistence_service.dart`
- Modify: `app/lib/features/capture/application/capture_providers.dart`
- Test: `app/test/features/capsule/data/capsule_repository_test.dart`
- Test: `app/test/features/capture/data/entry_persistence_service_test.dart`

**Interfaces:**
- Produce `CapsuleSaveOptions({String? unlockTask})` with normalized task validation.
- Produce `CapsuleAssignment` and `CapsuleRepository.insertAssignments`, `listForMember`, `completeTask`, `markOpened`, and `findForMember`.
- Extend `EntrySaveRequest` with optional `capsuleOptions`.

- [ ] Write repository tests for all-roster assignment creation, locked/ready initial states, current-member filtering, idempotent completion, opened state, and cross-family rejection.
- [ ] Write a persistence test whose Capsule assignment insert fails and assert the entry transaction rolls back and the finalized encrypted blob is compensated.
- [ ] Run the two focused test files and verify failures identify the missing models/repository/compound save.
- [ ] Implement the models and repository using the existing `capsules` table; use `shelf` for no task and the compatibility value `milestone` for a task.
- [ ] Extend the persistence transaction to insert assignments after entry metadata and before setting `metadataCommitted = true`.
- [ ] Run the focused tests and verify they pass.

### Task 3: Capture task state and validation

**Files:**
- Modify: `app/lib/features/capture/domain/capture_models.dart`
- Modify: `app/lib/features/capture/application/capture_controller.dart`
- Test: `app/test/features/capture/application/capture_controller_test.dart`

**Interfaces:**
- Add `CaptureDraft.capsuleTaskEnabled`, `capsuleTask`, and `capsuleTaskValid`.
- Add `CaptureController.setCapsuleTaskEnabled(bool)` and `updateCapsuleTask(String)`.

- [ ] Write controller tests proving Capsule task mode requires nonblank text, preserves the task through Back-equivalent edits, clears configuration when leaving Capsule, resets after dismissal/success, and forwards normalized `CapsuleSaveOptions` exactly once.
- [ ] Run the focused controller tests and verify they fail for the missing draft API.
- [ ] Implement the draft state, controller mutators, `canSave` validation, and save-request forwarding without changing media cleanup ownership.
- [ ] Run the focused controller tests and verify they pass.

### Task 4: Capture Capsule interface

**Files:**
- Modify: `app/lib/features/capture/presentation/capture_sheet.dart`
- Modify: `app/test/features/capture/presentation/capture_sheet_test.dart`
- Modify: `app/test/features/capture/presentation/capture_accessibility_test.dart`

**Interfaces:**
- Visible choice label `Capsule`.
- Switch key `capsule-task-toggle`; field key `capsule-task-field`.

- [ ] Write widget tests asserting Legacy Milestone is absent, Capsule is present, the task panel expands only for Capsule, the field appears only when enabled, blank input disables `Keep memory`, valid input enables it, and 1.4× text remains scrollable.
- [ ] Run the focused presentation tests and verify the new expectations fail.
- [ ] Implement the inline Capsule panel with exact labels, black primary action, 180-character multiline field, helper/error copy, keyboard-safe scrolling, and natural-case semantics.
- [ ] Run the focused presentation tests and verify they pass.

### Task 5: Fail-closed Capsule service and providers

**Files:**
- Create: `app/lib/features/capsule/application/capsule_service.dart`
- Create: `app/lib/features/capsule/application/capsule_providers.dart`
- Modify: `app/lib/features/vault/data/vault_repository.dart`
- Test: `app/test/features/capsule/application/capsule_service_test.dart`

**Interfaces:**
- Produce `capsuleAssignmentsProvider` for the current local member.
- Produce `CapsuleService.completeTask(String)` and `openForCurrentMember(String)`.
- Add `VaultRepository.findByIdForFamily` for canonical joined-entry lookup.

- [ ] Write tests proving locked, missing, wrong-target, wrong-family, wrong-privacy, and expired assignments return unavailable with zero blob reads.
- [ ] Write tests proving completion persists, ready/opened assignments decrypt, and only a successful open marks the assignment opened.
- [ ] Run the focused service tests and verify they fail for the missing service.
- [ ] Implement canonical reloading and fail-closed checks before delegating to `VaultController`.
- [ ] Run the focused service tests and verify they pass.

### Task 6: Unified Memory Key and Legacy Lock removal

**Files:**
- Modify: `app/lib/features/ceremony/presentation/ceremony_screen.dart`
- Modify: `app/lib/features/vault/presentation/observatory_screen.dart`
- Modify: `app/lib/ui/keepers_bottom_nav.dart`
- Delete: `app/lib/features/locks/presentation/locks_screen.dart`
- Delete: `app/test/features/locks/presentation/locks_screen_test.dart`
- Modify: `app/test/features/ceremony/presentation/ceremony_screen_test.dart`
- Modify: `app/test/features/vault/presentation/observatory_screen_test.dart`
- Modify: `app/test/ui/keepers_bottom_nav_test.dart`

**Interfaces:**
- `CeremonyScreen` receives real `List<CapsuleAssignment>`, task-completion callback, Capsule-open callback, loading/error state, and Retry.
- `KeepersNavDestination.locks` no longer exists.

- [ ] Write widget tests for locked and Capsule sections, Complete task confirmation, loading/error/empty states, successful Open memory callback, and complete absence of Legacy Lock/preview copy and the Locks destination.
- [ ] Run the focused widget tests and verify failures correspond to the old presentation and route.
- [ ] Replace the shortcut pair and preview models with the unified list, wire repository-backed state/actions in Observatory, and delete the separate Locks screen and enum case.
- [ ] Run the focused widget tests and verify they pass.

### Task 7: Contracts and verification

**Files:**
- Modify: `DESIGN.md`
- Modify: `UX-CONTRACT.md`
- Modify: `docs/KEEPERS_SPEC.md`

- [ ] Update product terminology and state tables so Capsule/optional-task behavior is canonical and no contract describes Legacy Lock UI or preview approval.
- [ ] Run `dart format` over changed Dart files.
- [ ] Run all focused Capsule, capture, ceremony, vault, storage, navigation, and app tests.
- [ ] Run `flutter analyze --fatal-infos` and then `flutter test`.
- [ ] Run the frontend premium strict audit and inspect every changed screen at 390×844 and 430×932 with normal and 1.4× text where the local target permits.
- [ ] Run `flutter build apk --debug --no-pub` to verify the mobile build when the Android toolchain permits it.
- [ ] Search changed source and contracts for `Legacy Milestone`, `Legacy Lock`, `legacy-approval`, `KeepersNavDestination.locks`, native `alert`, and placeholder markers; only internal compatibility tokens may remain.
