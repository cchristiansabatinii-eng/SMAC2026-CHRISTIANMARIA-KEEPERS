# Capsule Task Unlock Design

## Goal

Replace the user-facing Legacy Milestone and preview-only Legacy Lock experience with one real Capsule flow. A captured memory may be placed in the Capsule immediately or protected by a specific task that each intended family member completes before opening it from Memory Key.

## Product decisions

- `Capsule` replaces `Legacy Milestone` everywhere visible to a person.
- A Capsule is addressed to every family member present in the persisted local roster when it is created.
- `Set specific task to unlock` is optional. When disabled, each recipient assignment begins ready to open. When enabled, a trimmed task of 1–180 characters is required and each recipient assignment begins locked.
- Completing a task is a self-confirmed, per-recipient action. It uses an app-owned confirmation dialog and immediately unlocks that recipient's assignment. The old proof upload, setter approval, two-second approval hold, memorial preview, and Legacy Locks screen are removed.
- The author may continue to inspect memories they created from `Your memories`. Recipient access from Memory Key always uses the Capsule gate.
- The app never fabricates another member's completion. Cross-device encrypted payload transfer and completion synchronization remain outside this change; the local model stores one assignment per roster member so a future sync layer can transport the same state without redesigning the UI.

## Compatibility and encryption

The existing encrypted envelope authenticates the persisted privacy string. Existing memories use `legacy`, so database rows must not be rewritten to `capsule`.

The Dart domain case becomes `PrivacyTier.capsule`, with an explicit stable codec:

- `PrivacyTier.capsule.storageValue` returns `legacy`.
- `PrivacyTier.fromStorage('legacy')` returns `PrivacyTier.capsule`.
- database writes and AES-GCM authenticated metadata use `storageValue`, never the enum name.

Journal remains member-key encrypted. Weekly Reveal and Capsule remain family-key encrypted. This is an application-policy lock on devices that possess the family key, not new recipient-specific cryptographic key wrapping.

## Persistence model

Use the existing SQLCipher-protected `capsules` table. Create one row per roster member inside the same database transaction that inserts the encrypted entry metadata.

- `id`: deterministic assignment ID derived from entry and target IDs.
- `family_id`, `author_id`, `target_id`, `content_entry_id`: validated against rows in the same family.
- `trigger_type`: `shelf` for an immediately available Capsule; the existing compatibility value `milestone` for a task Capsule.
- `trigger_value`: trimmed task text or `NULL`.
- `state`: `ready` without a task, `locked` with a task, and `opened` after first successful open.
- `created_at` and `opened_at`: UTC epoch milliseconds.

If any assignment insert fails, the entry transaction rolls back and the existing persistence compensation removes the finalized encrypted blob. Existing `legacy` entries without Capsule assignments are not inferred or exposed to recipients; the author retains access through `Your memories`.

## Capture flow

Keep the existing two-step capture sheet. Step two continues to default to Weekly Reveal and shows three choices: Private Journal, Weekly Reveal, and Capsule.

Selecting Capsule expands a stable inline panel containing:

- explanatory copy: the Capsule is available to the family through Memory Key;
- a switch labeled exactly `Set specific task to unlock`;
- when enabled, a multiline field labeled `Task to unlock` with a 180-character limit and helper text explaining that each family member confirms the task on their own device.

The task draft survives Back/Continue within the same capture. Changing away from Capsule clears the task configuration. `Keep memory` is disabled while task mode is enabled and the task is blank. Saving and dismissal retain the existing pessimistic and plaintext-cleanup behavior.

## Memory Key

Memory Key becomes the sole Capsule destination and owns one scrollable list with two sections:

1. `Locked by family` — current-member assignments with a task and `locked` state. Cards show safe metadata only: format, author, creation date, and task. The action is `Complete task`.
2. `Capsule` — current-member assignments that are `ready` or `opened`, including task assignments after completion. The action is `Open memory`.

Remove the top Legacy Lock/Capsule shortcut pair, `KeepersNavDestination.locks`, `LocksScreen`, and all Legacy Lock preview copy. Empty, loading, and error states keep the page geometry stable. All actions are at least 48 logical pixels, use the existing Modern Society typography, black high-emphasis buttons, ivory cards, restrained gold accents, textual state labels, and reduced-motion behavior.

## Access enforcement

`CapsuleService.openForCurrentMember(capsuleId)` reloads the canonical assignment and entry from SQLCipher. It verifies family, target member, Capsule privacy, and `ready|opened` state before requesting a key or encrypted blob. Locked, missing, mismatched, cross-family, or expired data returns the existing neutral unavailable result and performs no blob read.

After eligibility is confirmed, the service delegates decryption to `VaultController` and marks the assignment `opened` only when an `OpenedMemory` result is returned. Task completion updates only the current member's locked assignment and is idempotent.

## Error and accessibility states

- Capture validation stays inline and preserves entered task text after recoverable failures.
- A failed task-completion update leaves the card locked and shows route-scoped corrective feedback with Retry available through the same action.
- A failed Capsule load shows an inline error and Retry; it never substitutes sample capsules.
- Locked cards never show decrypted captions, images, audio, or text.
- Task switch, task field, confirmation dialog, card state, and actions expose natural-case semantics and visible focus.

## Verification

- Prove the `legacy` wire token still authenticates and decrypts after the domain rename.
- Prove entry and all Capsule assignments commit atomically and rollback together.
- Prove blank task validation, draft reset, and duplicate-save protection.
- Prove locked and wrong-recipient opens perform zero encrypted-blob reads.
- Prove task completion persists across provider reload and eligible Capsule opening renders the real memory.
- Prove all Legacy Lock copy, preview routes, and navigation have been removed.
- Run Dart format, focused tests, Flutter analyze, full Flutter tests, strict frontend audit, and Android debug build when the connected toolchain permits it.
