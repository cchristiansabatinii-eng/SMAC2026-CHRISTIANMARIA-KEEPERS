# Humation Avatar System Design

**Date:** 2026-09-04  
**Status:** Approved direction; implementation pending  
**Supersedes:** `2026-09-04-lorelei-avatar-system-design.md`

## Context and decision

Keepers needs customizable illustrated identities on the Family Wheel and user profile. The Lorelei implementation does not match the product's quiet, graphic visual language and will be removed completely.

Keepers will use the MIT-licensed Humation 1 artwork through the native `humation_flutter` renderer. Rendering and customization remain on device. The app will not embed `humation.app`, call a remote avatar API, or transmit member identifiers or avatar choices.

The dependency is pinned to `humation_flutter: 0.1.0` because the Flutter port is new and community-maintained. Its bundled Humation 1 pack contains the artwork, while Keepers owns the surrounding editor, persistence, navigation, and accessibility behavior.

## Goals

- Replace every visible and persisted Lorelei concept with Humation.
- Let the current user customize Head, Body, Bottom, Item, Glasses, and Colors from their profile.
- Render one saved Humation identity consistently in Settings and on the Family Wheel.
- Preserve the Wheel's existing rings, presence marks, motion, names, and hit areas.
- Keep all avatar work private, deterministic, offline, and stored inside the existing encrypted database.
- Retain explicit save, retry, duplicate-save protection, and unsaved-change confirmation.

## Non-goals

- Embedding or visually cloning the Humation website.
- Humation account creation, export, or cloud synchronization.
- Photo-based avatars, AI generation, animation, or cultural wardrobe extensions.
- Editing another member's profile before real member management and permissions exist.
- Adding avatars to Memory Key or memorial surfaces in this replacement pass.

## Architecture

### Dependency boundary

`KeepersAvatar` remains the only reusable rendering boundary. Internally it will render `HumationAvatar` from the pinned package. Callers provide only an immutable Keepers `AvatarConfig`; no screen imports Humation directly.

The renderer keeps its fixed square geometry, circular clipping behavior, decorative/composite semantics, and existing `KeepersAvatarSurface`. The old DiceBear generator, Lorelei mapper, asynchronous SVG cache, and `flutter_svg` dependency are deleted.

Humation asset decoding is prewarmed before the app renders where supported, avoiding first-use work on the animated Wheel.

### Persisted model

The existing encrypted `members.avatar_config_json` column remains the storage boundary. `AvatarConfig` becomes Humation-specific schema version 2:

```text
schemaVersion: 2
styleId: humation-1
styleRevision: 1
seed: stable member UUID
selections:
  head: canonical Humation part ID
  body: canonical Humation part ID
  bottom: canonical Humation part ID
  item: canonical Humation part ID or none
  glasses: canonical Humation part ID or none
colors:
  hair: canonical hex
  skin: canonical hex
  clothes: canonical hex
  bottom: canonical hex
  stroke: canonical hex
```

Saved selections use canonical Humation part IDs when available. Input is allow-listed against the bundled manifest before saving or rendering. Map ordering and hex formatting are canonicalized so equality and serialized output remain deterministic.

Empty, malformed, unknown-version, and old `keepers-lorelei` schema-1 JSON intentionally reset to a deterministic Humation avatar derived from the same member seed. Lorelei traits are not approximated because the two systems have no faithful semantic mapping and the user explicitly rejected the previous visual identity. The next successful save writes only schema 2.

### Catalog

`AvatarCatalog` becomes a Humation-backed adapter with these ordered categories:

1. Head
2. Body
3. Bottom
4. Item
5. Glasses
6. Colors

Part options come from the bundled manifest and use stable app-facing labels. Color choices are restrained swatches for hair, skin, clothes, and bottom; the avatar background remains transparent and the Wheel continues to own each member's immutable accent color. Randomize and export are excluded.

Demo relatives receive fixed, distinct Humation presets. Their data remains clearly non-persisted until member management exists.

## Profile experience

Settings retains the existing `Your identity` entry with avatar preview, member name, `Edit avatar`, and chevron. It pushes a contextual full-screen editor without the global bottom navigation.

The editor retains:

- Back, `YOUR PROFILE`, and `Choose your avatar` header.
- A large live Humation preview and `Shown on your family wheel.` caption.
- One horizontally wrapping category rail.
- An adaptive option grid with real Humation part previews or color swatches.
- A fixed safe-area `Save avatar` action.

Selecting an option changes only the draft. Save performs one encrypted repository update, refreshes local identity, and returns to Settings. Failure keeps the draft and offers retry. Back with a dirty draft offers `Keep editing` and `Discard changes`. All interaction is disabled while saving.

## Accessibility and responsive behavior

- Picker options expose button, selected, enabled, label, and tap semantics; the visual check is not the only selected indicator.
- Wheel member nodes retain composite labels and semantic tap actions while their avatar artwork stays decorative.
- Important targets remain at least 44 logical pixels.
- The editor owns one vertical scroll surface; its save action remains reachable above keyboard and device safe areas.
- Verify 390 x 844 and 430 x 932 phone layouts at normal and 1.4x text scale.
- Reduced-motion behavior remains unchanged because avatar changes do not add motion.

## Error and compatibility behavior

- Invalid persisted data never prevents startup; it yields the deterministic Humation default.
- Invalid package part IDs are sanitized before render and save.
- Save errors use the existing exact recovery copy: `Your avatar could not be saved. Try again.`
- Package rendering failure preserves the avatar footprint and uses a neutral local fallback rather than a network image.
- The exact package version and lockfile are committed. Humation and community-port MIT notices are retained in third-party notices.

## Verification

- Model/codec tests for canonical schema-2 round trip, invalid-data fallback, and explicit Lorelei reset preserving the seed.
- Catalog tests for all six categories, manifest-valid IDs, distinct demo presets, and color allow-lists.
- Renderer tests for deterministic local output, fixed geometry, semantics, and no network path.
- Controller tests for draft state, save/retry, duplicate-save protection, and identity refresh.
- Widget tests for category selection, live preview, semantic activation, dirty back, saving guards, and narrow/enlarged layouts.
- Family Wheel and Settings integration tests proving the same saved Humation config appears on both surfaces.
- Full format, analyze, Flutter test suite, Android build, emulator run, and screenshots of Wheel, Settings, and editor.

## Sources and risk

- Official engine and artwork: https://github.com/humation-labs/humation
- Flutter renderer: https://pub.dev/packages/humation_flutter

The official engine and assets are MIT licensed and designed for deterministic local rendering. The Flutter renderer is an unofficial, recently published port with limited adoption. Pinning, keeping a narrow wrapper boundary, compatibility tests, and emulator verification contain that risk and leave a future vendored renderer possible without changing screen APIs or stored data.
