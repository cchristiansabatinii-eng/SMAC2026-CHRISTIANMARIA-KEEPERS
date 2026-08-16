---
version: alpha
name: "Keepers"
description: "A tactile family-memory instrument built around presence, voice, and sealed weekly ritual."
colors:
  aura-ground: "#FFFAF2"
  aura-blush: "#FFE8DF"
  aura-ivory: "#FFFDF8"
  background-flat-fallback: "#F5E9DE"
  ink: "#11110F"
  ink-muted: "#6D6963"
  home-ink: "#201810"
  home-taupe: "#8B7E70"
  home-gold: "#BE8E20"
  home-clay: "#FF7A72"
  home-green: "#5BD5AA"
  home-blue: "#78A8FF"
  home-mauve: "#C99CFF"
  home-line: "#DDCFBF"
  home-avatar-gold: "#FFD563"
  legacy-olive: "#7C835C"
  ground: "#0B0A08"
  ground-vignette: "#171310"
  cream: "#EFE7D4"
  brass: "#C9A227"
  brass-light: "#E3C560"
  memorial-gold: "#A89468"
  avatar-base: "#14110C"
  member-green: "#7BC950"
  member-rose: "#E4626F"
  member-orange: "#E8873A"
  member-teal: "#3EB8A5"
  member-blue: "#5B9BD5"
  member-purple: "#9B6BD5"
typography:
  primary:
    fontFamily: "SchibstedGrotesk"
  heading:
    fontFamily: "SchibstedGrotesk"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "4.1px"
rounded:
  DEFAULT: "1rem"
  control: "0.75rem"
  circle: "999px"
spacing:
  screen-edge: "1.5rem"
  control-height: "2.75rem"
  compact-gap: "0.5rem"
  section-gap: "1.5rem"
components:
  family-wheel:
    role: "home signature"
  member-node:
    role: "identity and contribution"
  bottom-navigation:
    role: "edge-to-edge five-action primary navigation"
  your-memories:
    role: "owner-only memory history"
  ritual-card:
    role: "memory and ceremony content"
  destination-scaffold:
    role: "shared header, ambient field, and anchored navigation"
---

# Keepers Design System

## Overview

### Creative North Star

Keepers should feel like a living family keepsake: the supplied blush-ivory background is the continuous canvas beneath every interface, while people and memories float close enough to feel gathered. The background is rendered from `app/assets/backgrounds/keepers-background-flat.png`; `background-flat-fallback` is used only while the asset is unavailable. It is not a social feed or a dashboard.

### Product context and register

- **Audience and primary job:** Multigenerational families recording private memories and gathering for a weekly reveal.
- **Target market and evidence:** The product brief in `docs/KEEPERS_SPEC.md` and the approved UI direction in `FABLE_UI_DIRECTIVE.md`; no locale-specific market assumption is made.
- **Locales:** English for this sprint. User-authored memory content may use any script supported by the device.
- **Usage scene:** Phone-first, often one-handed, intimate, and intermittent; ritual screens become shared during an in-person gathering.
- **Register:** Product UI with one expressive ritual moment per screen.
- **Memorable signature:** The home screen turns family presence into a single editorial composition: a live gathering headline, colored attendance marks, and an orbit-free cluster of independently floating family bubbles.
- **Restraint:** Forms, permissions, errors, and metadata stay quiet and legible.
- **Anti-references:** Generic card grids, camera-first capture, purple-blue gradients, glassmorphism, translucent profile lenses, profile shadows, confetti, emoji icons, detached floating action buttons, and flat empty-state dashboards.
- **Token ownership/runtime mapping:** Runtime tokens in `app/lib/theme/keepers_theme.dart` are canonical. This document mirrors their exact accepted values. `KeepersTheme` in `app/lib/design_system/observatory/observatory_theme.dart` adapts them to Flutter `ThemeData`.

## Colors

The exact supplied background image owns every full-screen route, detail view, loading/error surface, and capture sheet. `background-flat-fallback` approximates its center tone without replacing the image. The supplied raster wordmark is the compact home signature and is rendered as black ink without its white source canvas. The home composition uses `home-ink`, `home-taupe`, `home-gold`, `home-clay`, `home-green`, `home-blue`, `home-mauve`, and `home-line` for its approved editorial presence language. The four member accents and `home-avatar-gold` are intentionally bright pastels; small names use a darker derived ink while avatar rings and presence dots retain the bright source color. Humation artwork keeps its saved internal palette and transparent background; the member accent is product-owned presentation outside the artwork. `ground`, `cream`, and brass remain available for self-contained ritual cards and legacy permanence—not full-screen backgrounds. Every member receives one immutable color; that color follows their avatar ring, entry edge, waveform, name chip, and vote dot. `memorial-gold` is reserved for memorial identity.

## Typography

SchibstedGrotesk is the sole application typeface across English interface text, including display headings, memory prose, body copy, controls, captions, metadata, statuses, dates, and navigation. All app-authored visible copy uses the product's uppercase treatment; user-authored memories adopt that treatment when presented, while editable fields preserve exactly what the family types. Primary page, modal, empty-state, and section titles use the same quiet family-title treatment: 20 pixels, weight 600, line height 1, and 4.1-pixel tracking. Supporting prose, eyebrow labels, timers, counts, buttons, dates, and metadata retain smaller or purpose-specific role scales so the interface does not become uniformly loud. Source strings and accessibility labels retain natural casing even when their painted presentation is uppercase. The font is bundled offline and must never be fetched. User-authored text in scripts outside Schibsted Grotesk's glyph coverage uses the device's script-appropriate fallback so family memories remain legible; future localized interface releases must bundle and document their chosen companion face. The raster Keepers wordmark remains artwork rather than interface typography.

## Layout

The phone safe area is the primary frame. Screen edges use 24–28 logical pixels where space permits, and important touch controls target at least 44 logical pixels. Home follows the approved vertical composition: the compact black Keepers wordmark is centered directly on the continuous app background with no header surface; the uppercase `FAMILY NAME + FAMILY` label sits immediately above the colored family-presence sentence and attendance marks; then a 16-pixel opening gap keeps the asymmetric family cluster near the visual center. The family label uses the tracked Schibsted presence face at 20 pixels and weight 600, preserving 0.205 em proportional tracking, without a segmented underline. The gathering invitation now flows directly into Legacy Lock and Capsule above persistent navigation. Archive begins with the quiet ivory `KEPT FOREVER` strip, presenting the complete real kept-memory total in 20-pixel Schibsted Grotesk and five decorative pastel format marks before any filter controls. Home never duplicates that total, and no header displays a kept or sealed-memory count. Only the cluster supports bounded 0.85×–1.45× pan and zoom; the surrounding editorial composition remains stable. Ceremony, Archive, and Locks reuse one destination scaffold so their header and navigation geometry do not jump. Long text wraps or scrolls inside reserved regions; core controls never move when loading.

## Elevation & Depth

Depth comes from spatial hierarchy and quiet member motion rather than visual effects: near family members are brighter while far members are slightly quieter. Family bubbles use opaque, softly member-tinted ivory surfaces with a clean edge and no shadow. They never use backdrop blur, translucency, refraction, sheen, or glass styling. Presence quieting applies only to decorative portrait, rim, and surface treatment; names and status copy remain fully opaque and contrast-safe. Bubbles keep stable radial anchors without any rendered orbit, connector, guide, or trail.

## Shapes

People, contribution, and presence use circular portraits and tight progress rims. Memories use paper-like or wax-stamped silhouettes. Controls use restrained 12-pixel rounding; fully circular geometry is reserved for identity, seals, and reset—not background tracks.

Humation 1's restrained hand-drawn, full-character linework is the avatar language inside the existing circular portrait surfaces. It does not introduce a separate visual system: Keepers retains its supplied background, Wheel geometry, navigation, typography, and product-owned member accents outside the artwork.

## Components

### Foundational visual states

Enabled controls retain visible labels or accessible names, 44-pixel targets, focused/pressed feedback, disabled semantics, and stable geometry. Loading uses a reserved Flutter progress indicator. Errors remain in the surface that can recover.

### Buttons and actions

The centered `+` in persistent navigation is the single capture entry point and is labeled “Keep a memory.” The YOU node opens the current member’s owner-only memory history. Photo, voice, and text have equal weight on capture step one; no camera-first action or detached FAB appears. Dangerous actions remain separated and explicitly named.

### Navigation and data display

The Wheel is home and starts with the current member only. People appear only after they are added locally or accepted through the real family-invitation flow, placed at stable asymmetric anchors without drawn orbit geometry. Membership and roster content are never seeded, hard-coded, or presented as a demo: the Wheel, Memory Key, and member detail all consume the same persisted roster. A remotely accepted member appears only after the durable local roster update succeeds; until a presence adapter exists, that member remains visually away and no invented contribution percentage is shown. YOU opens “Your memories”; another person receives a short focus animation before their Member page opens. Every primary surface uses one full-width white navigation bar with five equally spaced actions in this order: Wheel, Memory Key, centered `+`, Archive, and Settings. The bar is rectangular, flush to both viewport edges and the bottom safe area, separated from content only by a quiet top divider; it has no capsule, side margin, rounding, or shadow. A small black dot marks the current destination. The centered black `+` remains an independent “Keep a memory” action and never changes the selected destination. Legacy Lock and Capsule remain contextual routes rather than primary-navigation items. Settings shows only real local identity, privacy, and device-accessibility information; unsupported controls are never implied. The author can inspect every memory they created, with explicit privacy and lifecycle labels; family browsing still exposes only eligible kept history. Memory Key offers a proximity-gated Weekly recap and an always-available Random memory draw from kept entries. Family task locks expose locked, awaiting-approval, and approved states, and only an approved task may present an Open memory action. Proximity/presence and family-task approval remain explicitly labeled previews until their engines exist; invitation membership and the persisted roster do not.

### Forms and overlays

Capture is a light, full-height two-step surface. Step one chooses Photo, Voice, or Text and accepts an optional caption; step two asks who can open the memory and defaults to Weekly Reveal. Back preserves the draft, save is labeled “Keep memory,” and sheets/dialogs preserve safe areas, keyboard reachability, cancellation, and retry.

Invite and Join are contextual, full-height form routes rather than primary destinations. They reuse the continuous background, flat fields, direct status language, labeled back/close actions, and stable in-place progress/error regions. Email and six-digit OTP fields remain keyboard reachable and preserve safe corrections after recoverable failures; an email-binding mismatch focuses the email correction. The complete invitation capability and its wrapping secret are never painted, announced, copied to the clipboard, or retained in navigation state. Successful acceptance resets to the Wheel only after the encrypted family key, recipient's member key, membership, and roster have been committed locally.

### Iconography

Use Material Symbols only for familiar actions and always provide an accessible label for icon-only controls. Do not use emoji as interface icons.

### Motion

The supplied background stays still so its color and crop remain faithful across interfaces. Relative bubbles drift independently by roughly 3–6 logical pixels around stable anchors, and a tapped member focuses over 220 ms before navigation. Profile surfaces have no independent animation; only the existing bubble drift moves them. Pan or zoom pauses member motion; leaving the Wheel through a profile, member, or capture action restores the family field to identity so every return opens on the centered composition. Opening a Memory Key mode produces one 560 ms full-screen pastel flood before the selected content appears; reduced motion makes that transition immediate. The host-controlled reel travels only on explicit Next/Back actions, the Echo rises on request, and the Keeping seal responds to a deliberate decision. Normal feedback stays between 200–500 ms. Reduced motion freezes bubble movement, makes reel changes immediate, and retains short opacity feedback.

### Content and data visualization

Copy is plain, familial, and specific. Presence language states the condition required to gather; it never substitutes a bare countdown. Progress and presence always have text or semantic equivalents beyond color.

## Do's and Don'ts

- **Do:** Let identity color and presence geometry carry meaning consistently.
- **Do:** Preserve the existing encrypted data and Riverpod architecture behind the redesigned surfaces.
- **Don't:** turn family memory into a generic analytics dashboard or rounded-card grid.
- **Don't:** expose current-week content previews before the ceremony or make camera the primary capture action.
