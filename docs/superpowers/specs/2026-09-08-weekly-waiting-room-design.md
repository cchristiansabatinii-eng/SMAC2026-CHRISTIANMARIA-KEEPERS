# Weekly Waiting Room Design

**Status:** Approved by the user's direct request on 2026-09-08. Autonomous implementation was explicitly authorized.

## Outcome

Completing the five-photo weekly progress changes the locked weekly card into a glowing gold key button. Tapping the key opens a dedicated family waiting room. The weekly experience can begin only after at least three quarters of the active family roster is locally present and someone taps **Start weekly experience**.

## State Contract

1. Fewer than five weekly photos keeps the weekly card locked.
2. Five or more weekly photos unlocks the glowing key and enables entry to the waiting room. Family presence does not affect this first gate.
3. Entering the waiting room does not decrypt, lease, load, or expose current-week memories.
4. The waiting room counts unique active roster members and unique locally present members. The signed-in member is counted once and is present while using the waiting room.
5. Required attendance is `ceil(active family size * 0.75)`, with a minimum family size of one.
6. Unknown, stale, or failed presence never counts as present. Attendance therefore fails closed.
7. Below quorum, the waiting room shows truthful attendance and how many more members are needed. It does not render an enabled start action.
8. At quorum, the exact primary action label is **Start weekly experience**.
9. Tapping the start action triggers the existing 560 ms pastel reveal transition, then and only then loads the live weekly experience.
10. Closing or navigating back returns to the family wheel without changing progress or attendance.

## Privacy and Transport Boundary

Presence and current-week material remain local-only. The waiting room consumes a fail-closed family-presence snapshot backed by the foreground BLE adapter documented in `2026-09-08-ble-weekly-presence-design.md`. Nearby observations expire independently after 15 seconds. It does not introduce Supabase, cloud presence, or any remote path to current-week content. Until a real proximity signal marks another member as nearby, that member remains absent. Start rechecks the five-photo gate against the current device-local week so an open room cannot carry prior-week eligibility across Monday.

## Visual Direction

The supplied reference is the signature element:

- warm ivory surface using the existing `auraIvory` token;
- two clearly visible thin rounded `homeGold` outlines, with the darker existing `homeGoldText` reserved for the key itself;
- a restrained pale-gold aura around the ready state;
- a centered concentric circular medallion with the existing rounded key icon;
- no new gradients, artwork, or color tokens.

The family wheel retains the compact 104 px card used by the current product rather than copying the reference's desktop proportions literally. The waiting room reuses the same key medallion at a larger scale, so the transition reads as one continuous ritual.

The waiting room is a focused full-screen surface with no bottom navigation. It includes:

- a close control and weekly-experience title;
- the shared glowing key medallion;
- a live, semantic attendance summary such as “3 of 4 family members are here”;
- member avatars with clear “Here” and “Waiting” labels that do not rely on color alone;
- a stable primary-action region so the layout does not jump when quorum is reached;
- the single primary action **Start weekly experience** only when quorum is met.

## Accessibility and Resilience

- Interactive targets are at least 48 logical pixels; the primary button is at least 52 logical pixels tall.
- Ready, locked, present, and absent states have text or semantic labels in addition to color and glow.
- The room supports text scaling and small screens with safe areas and scrolling.
- Attendance changes are announced as a live semantic status.
- Reduced-motion settings bypass the reveal animation while preserving the state transition.
- Duplicate taps are ignored while the weekly experience is starting.

## Verification

Automated coverage must prove:

- five photos alone unlock the key;
- presence alone cannot unlock an incomplete progress bar;
- quorum uses ceiling arithmetic and deduplicates members;
- below-quorum and ready waiting-room states render the correct copy and actions;
- entry to the waiting room performs no weekly-content load;
- the start tap performs exactly one live weekly-content load;
- close/back returns to the wheel;
- the existing weekly preview remains separate from the live waiting-room path.
