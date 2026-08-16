# P0-03 Capture and Vault Design

**Status:** Approved in chat; awaiting written-spec review  
**Date:** 2026-09-01  
**Parent:** P0-02 Flutter, Riverpod, and SQLCipher foundation  
**Visual baseline:** Design option 1, “Living Orrery”

## Purpose

P0-03 delivers the first complete Keepers loop on one device:

1. Create a minimal local family and adult member on first run.
2. Capture one photo, voice recording, or text memory.
3. Add an optional caption and choose a privacy tier.
4. Encrypt the content with the correct family or member key.
5. Save the entry and show it in the local vault after relaunch.

The feature must pass on at least one physical Android device and one physical iOS device.

## Approved Product Decisions

- First run asks only for a family name and the current member’s name. The first member has the `adult` role.
- A memory has exactly one primary format: `photo`, `voice`, or `text`.
- Photo capture supports both the camera and photo library.
- Voice recording uses tap-to-start and tap-to-stop.
- Every format supports an optional caption.
- Capture always shows the privacy selector. `Weekly Reveal` is the default, with `Private Journal` and `Legacy Milestone` available.
- Privacy is cryptographically enforced in P0-03. Journal content uses the current member’s key; reveal and legacy content use the family key.
- The selected visual baseline is the “Living Orrery” direction: a dark, orbital family space with member-color identity and brass permanence cues.

## Iteration Posture

The selected visual is a v0 baseline, not a frozen final composition. Later design rounds may change layout, art direction, node placement, motion curves, density, typography tuning, and memory rendering without changing capture, key selection, encryption, persistence, or repository contracts.

The implementation must therefore keep:

- design tokens separate from feature logic;
- orbit geometry and motion policy separate from stored models;
- tactile memory renderers behind a format-based component boundary;
- business state out of painters and animation widgets;
- accessibility fallbacks independent from the primary motion treatment.

## Scope

### Included

- First-run family and member creation.
- Family and member key generation in Keychain/Keystore.
- Stable member color assignment.
- Solo-state Observatory home with a central current-member node and encrypted memories entering the surrounding orbit.
- Photo, voice, and text capture.
- Optional encrypted caption.
- Privacy selection and per-tier key routing.
- Versioned AES-GCM payload encryption.
- SQLCipher entry metadata and encrypted blob references.
- Local vault observation, preview, and entry opening.
- Dynamic seal feedback, restrained orbit drift, and optional gyroscope parallax.
- Reduced-motion behavior and semantic accessibility.
- Focused unit, widget, integration, and physical-device verification.

### Deferred

- Family invitations, member management, or fake/demo family members.
- BLE presence, quorum, multi-device alignment, and ceremony synchronization.
- Weekly reveal playback, voting, keeping, expiration, Echo matching, archive rings, locks, capsules, or memorial mode.
- Transcription, embeddings, search, sync, export, and cloud services.
- Post-save edit and delete.
- Scan and recipe capture.

The v0 orbit must render correctly with one member. Future members will occupy the same scene model when their flows exist.

## Design Language: The Observatory

The interface is a place rather than a collection of cards. Chrome remains flat and quiet; memories appear as tactile objects.

### Laws

- **Color is a person.** A stable member color follows the member’s node, orbit, memory edge, waveform, and future ceremony activity.
- **Brass means permanence.** Old brass `#C9A227` is reserved for keeping, sealing, key ownership, and other permanent actions.
- **The present is sealed; the past is open.** P0-03 establishes sealed capture and local opening without implementing ceremony rules.
- **Chrome is quiet; memories are objects.** Avoid generic rounded card grids and ornamental control surfaces.

### Typography and surface

- Use Fraunces for emotionally weighted copy and memory content.
- Use Schibsted Grotesk for controls, metadata, and labels.
- Use a near-black ground with a restrained grain treatment.
- Do not use purple-blue gradients, glassmorphism, emoji icons, confetti, or a floating action button.
- Provide an equivalent daylight token set even if v0 ships with the dark Observatory as its primary presentation.

### Motion

- Orbit nodes drift by only a few logical pixels using slow spring motion.
- Device tilt may add a small parallax offset, capped so text and touch targets remain stable.
- Saving produces a short seal sequence: the memory contracts toward the orbit, a brass seal lands, and a soft double-tick haptic confirms success.
- Motion never communicates success before encryption and database persistence finish.
- Reduced-motion mode stops idle drift and parallax and replaces travel with a short opacity/scale transition.
- BLE-driven distance, quorum alignment, and ceremony choreography are not simulated in P0-03.

## User Experience

### Startup and first run

The app resolves local setup state before choosing its initial route.

- If no local family/member exists, show the minimal first-run screen.
- Submit is enabled only when both trimmed names are non-empty.
- Setup generates family and member keys, writes them to secure storage, and inserts the family/member records in one recoverable operation.
- If secure storage fails, no partial family is presented as ready. The user sees a retryable setup error.
- After success, route to the solo Observatory.

### Solo Observatory and vault

The home screen uses the selected orbital direction but does not invent family members. The current member sits at the center. Saved memories appear as small tactile objects or marks around the orbit, with their author color and privacy state available semantically.

The screen has one primary action integrated with the center node: add a memory. A conventional list remains available as the accessible vault representation and as the stable fallback for large text, reduced motion, and testability. Selecting a memory decrypts it on demand and opens a format-appropriate viewer.

### Capture

Capture opens quickly over the Observatory and supports one active format at a time.

- **Photo:** choose Camera or Photo Library, then show a preview with Replace and Continue.
- **Voice:** tap once to start, show elapsed time and an animated member-color waveform, then tap again to stop. Allow playback and re-record before saving.
- **Text:** show a focused multiline editor.
- Show the optional caption below the primary content.
- Show the three privacy choices with plain-language consequences. Default to Weekly Reveal.
- Save remains disabled until valid primary content exists and recording has stopped.
- Back or Discard with a non-empty draft asks for confirmation and cleans temporary plaintext after dismissal.

### Secure save

On Save:

1. Freeze the draft and prevent duplicate submissions.
2. Allocate the entry ID and timestamp.
3. Resolve the family or member key from the selected privacy tier.
4. Package the primary content, caption, and format metadata into a versioned payload.
5. Encrypt the payload to a staging file.
6. Atomically move the staging file to its final encrypted location.
7. Insert the entry metadata and encrypted blob reference in a SQLCipher transaction.
8. If the insert fails, delete the finalized encrypted file so it cannot become an orphan.
9. Remove plaintext temporary material.
10. Only then run the seal animation and return to the updated Observatory/vault.

If any step fails, remove partial encrypted output, preserve a recoverable draft when safe, and do not show success feedback.

## Architecture

Use focused feature slices connected through Riverpod.

### `features/onboarding`

- `SetupState` and `SetupController` own first-run validation and submission.
- `FamilyRepository` and `MemberRepository` own SQL operations.
- `IdentityKeyService` creates, resolves, and rolls back family/member keys through the existing `SecureValueStore` abstraction.
- `SecureValueStore` gains a delete operation so failed setup cannot leave unreachable keys behind.

### `features/capture`

- `CaptureDraft` is an immutable union-like model for photo, voice, and text states.
- `CaptureController` owns format switching, permission results, recorder/image-picker state, validation, privacy selection, and save orchestration.
- `PhotoCaptureAdapter` wraps camera/library selection.
- `VoiceCaptureAdapter` wraps recorder start, stop, playback metadata, interruption, and cleanup.
- `EntryPayloadCodec` serializes the versioned payload.
- `EntryCipher` encrypts/decrypts payload bytes and files.
- `EntryRepository` writes and queries entry metadata.
- `EncryptedBlobStore` owns staging, finalization, rollback, and relative blob references.

### `features/vault`

- `VaultRepository` exposes ordered entry metadata for the local family.
- `VaultController` resolves previews and viewer state without persisting decrypted copies.
- Format renderers implement a shared memory-view contract for photo, voice, and text.

### `design_system/observatory`

- Theme extensions own surface, brass, member-color, typography, texture, and motion tokens.
- `OrbitSceneModel` describes nodes and memory marks without database or Riverpod dependencies.
- `OrbitLayout` is a pure, testable geometry function.
- `MotionPolicy` derives normal or reduced-motion behavior from platform accessibility state.
- Painters and widgets consume scene models only; they never perform storage or capture work.

## Data and Schema

The existing `families`, `members`, and `entries` tables remain the core records.

### Schema version 2

Add stable identity fields to `members`:

- `member_key_ref TEXT` for the secure-storage reference. The migration may add it as nullable for compatibility, but setup-created active members must always have a value.
- `color_token TEXT NOT NULL DEFAULT 'ochre'` for stable design identity.

No caption column is added. Captions remain inside the encrypted payload.

P0-03 writes entries as follows:

- `entry_type`: `photo`, `voice`, or `text`.
- `privacy_tier`: `journal`, `reveal`, or `legacy`.
- `blob_ref`: relative reference to the encrypted payload.
- `state`: `pending`.
- `transcript`: `NULL` in P0-03 to avoid leaking private text outside the member-key payload.
- `embedding`: `NULL`.
- lifecycle timestamps other than `created_at`: `NULL`.

## Cryptography and Local Security

SQLCipher continues to protect the metadata database with its device-held database key. Entry payload protection is separate so privacy tiers have enforceable key scope.

- Generate independent 256-bit family and member keys with `Random.secure()`.
- Store key material only through Keychain/Keystore via `SecureValueStore`.
- Encrypt every entry payload with AES-256-GCM and a fresh 96-bit nonce.
- Include a payload format version and key-scope identifier in the envelope.
- Authenticate entry ID, family ID, author ID, entry type, privacy tier, and creation timestamp as additional authenticated data.
- Reject unknown payload versions, missing keys, tag failures, and metadata mismatches.
- Store only relative blob references under app-private storage.
- Never persist camera, library, recorder, caption, or text plaintext after the save/discard lifecycle ends.
- Decrypt previews in memory where practical. If a plugin requires a temporary media file, create it in app-private temporary storage and remove it immediately after use.

### Key routing

- `journal` -> author member key.
- `reveal` -> family key.
- `legacy` -> family key in P0-03. Later lock/capsule features may wrap this payload with additional access metadata without rewriting capture.

## Error Handling

- Camera denial leaves Photo Library, Voice, and Text available.
- Photo-library denial leaves Camera, Voice, and Text available.
- Microphone denial leaves Photo and Text available.
- Interrupted recording returns to a recoverable stopped draft when valid audio exists; otherwise it returns to idle with an explanation.
- Picker cancellation is not an error and leaves the draft unchanged.
- Low storage, encryption failure, secure-storage failure, and database failure show a retryable inline state and never run the seal animation.
- Failed saves clean staging and partial final files.
- Corrupt or unauthentic payloads render an unavailable state and never expose partial plaintext.
- Rapid repeated taps cannot create duplicate entries.

## Accessibility

- All capture actions have text labels and semantic roles; meaning never depends on icons, color, motion, or haptics alone.
- Minimum touch targets are 44 logical pixels.
- Member colors meet contrast requirements against both Observatory and daylight surfaces.
- Text remains usable at 1.4x scaling; the fallback vault list reflows rather than clipping.
- Voice state announces recording start, elapsed milestones sparingly, stop, and save results.
- Reduced-motion mode removes idle orbit drift, gyroscope parallax, and long travel.
- The vault list provides deterministic reading and focus order independent of orbit geometry.

## Testing

### Unit

- Setup validation, key creation, and rollback.
- Privacy-tier key routing.
- Payload codec round trips and version rejection.
- AES-GCM round trips, wrong-key failure, modified-metadata failure, and nonce uniqueness.
- Blob staging, finalization, and cleanup.
- Capture state transitions for all three formats.
- Duplicate-save prevention.
- Pure orbit geometry and motion-policy selection.

### Widget

- First-run routing and validation.
- Solo Observatory empty and populated states.
- Camera/library choice, voice tap start/stop, text editing, optional caption, and privacy selector.
- Permission denial alternatives.
- Save progress, retry, seal success, and discard confirmation.
- Vault ordering, format rendering, large text, semantics, daylight tokens, and reduced motion.

### Integration and device gate

On one physical Android device and one physical iOS device:

- Complete first run and relaunch.
- Capture from camera and photo library.
- Record with tap-to-start/tap-to-stop and play before saving.
- Save a text memory.
- Save each privacy tier and verify the expected key scope.
- Relaunch and open every saved format.
- Verify stored payload bytes do not contain recognizable caption, text, image, or audio plaintext.
- Deny and later grant camera, library, and microphone permissions.
- Interrupt a recording and retry a failed save.

## Acceptance Criteria

P0-03 is complete when:

1. A new install can create one local family and adult member.
2. Photo, voice, and text entries with optional captions can be saved and reopened.
3. The privacy selector is always visible and defaults to Weekly Reveal.
4. Journal uses the member key; reveal and legacy use the family key.
5. No primary content or caption is stored as plaintext.
6. Vault updates immediately and survives app relaunch.
7. The solo Observatory reflects the selected dynamic visual direction without fake members.
8. Reduced-motion and accessible list behavior are functional.
9. Automated tests pass.
10. The physical Android and iOS device gate passes.

## Future Design Iterations

Later design passes are expected. Each pass should identify whether it changes:

- tokens only;
- orbit composition or motion;
- memory-object rendering;
- navigation or interaction semantics;
- product behavior or data contracts.

The first three categories should remain isolated from domain and storage changes. Any iteration that changes product behavior, privacy meaning, or persistence returns to design review before implementation.

