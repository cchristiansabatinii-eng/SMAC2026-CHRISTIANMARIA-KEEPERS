# Weekly Waiting Room Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to execute this plan task by task.

**Goal:** Turn completed weekly photo progress into a glowing-key waiting-room entry, then gate the live weekly experience behind truthful 75% family attendance.

**Architecture:** Split the two gates explicitly. The family wheel owns the photo-completion gate; a new ceremony presentation owns quorum and the final transition. Observatory remains the state coordinator and is the only layer allowed to request the live weekly payload. Presence stays on the existing local-only model and fails closed.

**Tech Stack:** Flutter, Dart, flutter_test, existing Keepers theme/components, existing ceremony and vault presentation state.

**Spec:** `docs/superpowers/specs/2026-09-08-weekly-waiting-room-design.md`

## Global Constraints

- Preserve all unrelated dirty-worktree changes.
- Write a focused failing test before each production change.
- Do not add a cloud presence or current-week content path.
- Do not load or decrypt weekly entries while merely entering the waiting room.
- Reuse theme tokens and the current key visual; do not add raw palette values.
- Do not create a commit unless the user asks for one.

### Task 1: Separate the photo gate and expose the shared key medallion

**Files:**

- Modify: `app/lib/features/ceremony/presentation/weekly_experience_card.dart`
- Modify: `app/test/features/ceremony/presentation/weekly_experience_card_test.dart`
- Modify: `app/test/features/ceremony/presentation/weekly_photo_progress_test.dart`

**Steps:**

1. Add tests proving five photos unlock the key regardless of presence and fewer photos remain locked.
2. Run the focused tests and confirm the old combined gate fails.
3. Make weekly progress and card readiness photo-only, rename the entry callback for waiting-room intent, and expose the key medallion as a reusable public widget.
4. Update semantic labels to say “Enter weekly waiting room” and keep unavailable states truthful.
5. Run the focused tests to green.

### Task 2: Build a responsive, quorum-aware waiting room

**Files:**

- Create: `app/lib/features/ceremony/presentation/weekly_waiting_room_screen.dart`
- Create: `app/test/features/ceremony/presentation/weekly_waiting_room_screen_test.dart`

**Steps:**

1. Add pure-state tests for ceiling quorum, roster/presence deduplication, out-of-roster presence, and members still needed.
2. Add widget tests for below-quorum, exact ready CTA copy, member statuses, disabled duplicate starts, close/back, small viewport, large text, and reduced motion.
3. Run the new tests and confirm they fail because the screen does not exist.
4. Implement the pure attendance snapshot and focused full-screen presentation using only existing tokens and components.
5. Reuse the shared key medallion, provide stable action layout, and place the 560 ms pastel reveal before the start callback.
6. Run the new tests to green.

### Task 3: Integrate the room without exposing weekly content early

**Files:**

- Modify: `app/lib/ui/family_wheel_screen.dart`
- Modify: `app/lib/features/vault/presentation/observatory_screen.dart`
- Modify: `app/test/ui/family_wheel_screen_test.dart`
- Modify: `app/test/features/vault/presentation/observatory_screen_test.dart`
- Modify related ceremony presentation tests only where the renamed callback requires it.

**Steps:**

1. Add integration tests proving the completed key opens the waiting room, entry does not request weekly payload, start requests it once at quorum, and close returns to the wheel.
2. Run the focused tests and confirm the missing intermediate state fails.
3. Update the family wheel to enter the room directly after photo completion. Keep preview isolated and remove family presence from key eligibility.
4. Add an Observatory waiting state, build a unique member roster with the signed-in member present once, and render the waiting room before any live weekly load.
5. Route the room's start callback through the existing live weekly loader and route close/back to the wheel.
6. Run the focused tests to green.

### Task 4: Align product contracts and verify the shipped build

**Files:**

- Modify: `DESIGN.md`
- Modify: `docs/UX-CONTRACT.md`
- Modify: `docs/KEEPERS_SPEC.md` only if implementation wording needs alignment with its existing local-session architecture.

**Steps:**

1. Update design and UX prose to document the two gates and waiting-room states while preserving existing tokens.
2. Run Dart formatting over touched Dart files.
3. Run focused tests, the full Flutter test suite, and static analysis.
4. Inspect the resulting diff for unrelated changes and privacy regressions.
5. Build the debug APK with the local Supabase configuration.
6. Install the APK on the connected Samsung device, cold-launch it, and confirm the process remains healthy.
7. Report the implemented behavior and any genuine remaining transport limitation without overstating multi-device support.
