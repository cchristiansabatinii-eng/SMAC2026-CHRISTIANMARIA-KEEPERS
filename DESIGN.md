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
  home-gold: "#FFD563"
  home-gold-text: "#8A650E"
  home-clay: "#FF7A72"
  home-green: "#5BD5AA"
  home-blue: "#78A8FF"
  home-mauve: "#C99CFF"
  home-action-line: "#D4BBAC"
  home-line: "#DDCFBF"
  home-avatar-gold: "#FFD563"
  legacy-olive: "#11110F"
  legacy-olive-text: "#6D6963"
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
    fontFamily: "ModernSociety"
  heading:
    fontFamily: "ModernSociety"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "0.8px"
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
- **Memorable signature:** The home screen turns family presence into a single editorial composition: a live gathering headline, colored attendance marks, and an orbit-free cluster of fixed family bubbles.
- **Restraint:** Forms, permissions, errors, and metadata stay quiet and legible.
- **Anti-references:** Generic dashboard card grids that turn unrelated actions or statistics into interchangeable panels, camera-first capture, purple-blue gradients, glassmorphism, translucent profile lenses, profile shadows, confetti, emoji icons, detached floating action buttons, and flat empty-state dashboards. Archive's dense, content-first media gallery is an intentional exception: its repeated squares index one homogeneous kept-memory collection rather than disguising unrelated controls as cards.
- **Token ownership/runtime mapping:** Runtime tokens in `app/lib/theme/keepers_theme.dart` are canonical. This document mirrors their exact accepted values. `KeepersTheme` in `app/lib/design_system/observatory/observatory_theme.dart` adapts them to Flutter `ThemeData`.

## Colors

The exact supplied background image owns every full-screen route, detail view, loading/error surface, and capture sheet. `background-flat-fallback` approximates its center tone without replacing the image. The supplied raster wordmark is the compact home signature and is rendered as black ink without its white source canvas. Generic interactive chrome—including primary buttons, outlined controls, focus accents, and account/setup status iconography—uses `ink` black instead of a green theme seed. The home composition uses `home-ink`, `home-taupe`, `home-gold`, `home-gold-text`, `home-clay`, `home-green`, `home-blue`, `home-mauve`, `home-action-line`, and `home-line` for its approved editorial presence language. `home-gold` and `home-avatar-gold` share the same vibrant pastel yellow; the former carries that yellow through every existing home-gold accent while the latter names its current-member role. Darker `home-gold-text` remains the contrast-safe ink and crisp progress edge. The four member accents are intentionally bright pastels; small names use darker derived ink while avatar rings, filled presence dots, and filled progress segments retain their bright source color. These semantic member/presence colors, provider-brand marks, errors, and brass/gold ritual states are deliberate exceptions to the neutral interface chrome. Humation artwork keeps its saved internal palette and transparent background; the member accent is product-owned presentation outside the artwork. `ground` and `cream` remain available for self-contained ritual cards and long-term permanence. The sole full-screen exception is the cold-launch sequence: `ground` creates a quiet black field and `cream` carries the supplied wordmark, phrases, rings, and memory forms before the interface dissolves into the usual supplied background. Every member receives one immutable color; that color follows their avatar ring, entry edge, waveform, name chip, and vote dot. `memorial-gold` is reserved for memorial identity.

## Typography

Modern Society is the sole application typeface across English interface text, including display headings, memory prose, body copy, controls, captions, metadata, statuses, dates, and navigation. App-owned painted copy uses Title Case, with the first letter of each word capitalized; presented memories use the same visual treatment without changing their stored value, while editable fields preserve exactly what the family types. The cold-launch brand phrases are the one casing exception and preserve the approved sentence case exactly: `Be present.`, `Be authentic.`, `Keep moments`, and `Be you.` Primary page, modal, empty-state, and section titles use the same quiet family-title treatment: 20 pixels, weight 600, line height 1, and restrained 0.8-pixel tracking. Supporting prose, eyebrow labels, timers, counts, buttons, dates, and metadata retain smaller or purpose-specific role scales so the interface does not become uniformly loud. Source strings and accessibility labels retain natural casing even when painted presentation is transformed. The font is bundled offline and must never be fetched. User-authored text outside Modern Society's glyph coverage uses the device's script-appropriate fallback so family memories remain legible; future localized interface releases must bundle and document their chosen companion face. The raster Keepers wordmark remains artwork rather than interface typography. The supplied commercial-use package contains one regular face, so Flutter synthesizes the existing role-specific weights and italics.

## Layout

The phone safe area is the primary frame. Screen edges use 24–28 logical pixels where space permits, and important touch controls target at least 44 logical pixels. Home follows the approved vertical composition: the compact black Keepers wordmark is centered directly on the continuous app background with no header surface; the Title Case `Family Name Family` label sits immediately above the colored family-presence sentence and attendance marks; then a 16-pixel opening gap keeps the asymmetric family cluster near the visual center. The family label uses the tracked Modern Society presence face at 20 pixels and weight 600, preserving restrained 0.04 em proportional tracking, without a segmented underline. A visually small outlined question mark sits immediately beside the family label inside a 48-logical-pixel touch target; it opens a safe-area help sheet that explains the Wheel without mutating family, memory, presence, or Weekly state. The cluster flows into five-photo Weekly progress, the standalone gathering prompt, then the separate Weekly panel above persistent navigation; Weekly is entered only from this home composition. The gathering capsule remains tightly centered while the Weekly panel uses a smaller 16-pixel gutter so its ritual field nearly spans the phone, matching the approved source composition. Completing progress opens a contextual full-screen waiting room with no bottom navigation; that room keeps its attendance summary, member statuses, and primary-action region stable as presence changes. Archive begins with the quiet ivory `Kept Forever` strip, presenting the complete real kept-memory total in 20-pixel Modern Society and five decorative pastel format marks before any filter controls, and it is the sole home of the always-present `Random Memory` control; the active filters determine whether drawing is currently enabled. Home never duplicates that total, and no header displays a kept or sealed-memory count. The family cluster is a fixed, centered composition and does not pan, drag, or pinch-zoom; families with more than four relatives continue in balanced static rows through the page's ordinary vertical scroll so every member remains reachable. The surrounding editorial composition remains stable. Memory Key is the sole home of Capsule memories, separating task-locked assignments from ready or opened Capsules in one stable destination scaffold. Long text wraps or scrolls inside reserved regions; core controls never move when loading.

## Elevation & Depth

Depth comes from spatial hierarchy and presence quieting rather than visual effects: near family members are brighter while far members are slightly quieter. Family bubbles use opaque, softly member-tinted ivory surfaces with a clean edge and no shadow. They never use backdrop blur, translucency, refraction, sheen, or glass styling. Presence quieting applies only to decorative portrait, rim, and surface treatment; names and status copy remain fully opaque and contrast-safe. Bubbles keep fixed anchors without any rendered orbit, connector, guide, or trail. Filled attendance dots, filled Weekly photo-progress segments, and the current member's active progress arc receive one compact, static, color-matched halo; empty indicators, relative progress arcs, and the portrait surfaces remain shadowless. The Weekly panel is a shadowless `aura-ivory` surface framed by two warm-neutral `home-action-line` borders while weekly progress is incomplete. Its centered concentric medallion shows a contrast-safe `home-taupe` lock until five qualifying photos are complete; at completion the frame and medallion change to a key with one restrained gold readiness aura. The waiting room repeats that same key medallion at larger scale. No halo pulses or spreads onto unrelated profiles or panels.

## Shapes

People, contribution, and presence use circular portraits and tight progress rims. Memories use paper-like or wax-stamped silhouettes. Controls use restrained 12-pixel rounding, except for the explicit Home gathering capsule and the Weekly ritual panel's 30-pixel outer and 25-pixel inset radii. Fully circular geometry is reserved for identity, seals, and reset—not background tracks.

Humation 1's restrained hand-drawn, full-character linework is the avatar language inside the existing circular portrait surfaces. It does not introduce a separate visual system: Keepers retains its supplied background, Wheel geometry, navigation, typography, and product-owned member accents outside the artwork.

## Components

### Foundational visual states

Enabled controls retain visible labels or accessible names, 44-pixel targets, focused/pressed feedback, disabled semantics, and stable geometry. Loading uses a reserved Flutter progress indicator. Errors remain in the surface that can recover.

### Buttons and actions

The centered `+` in persistent navigation is the single capture entry point and is labeled “Keep a memory.” The YOU node opens the current member’s owner-only memory history. Photo, voice, and text have equal weight on capture step one; no camera-first action or detached FAB appears. Dangerous actions remain separated and explicitly named.

### Navigation and data display

The Wheel is home and starts with the current member only. People appear only after they are added locally or accepted through the real family-invitation flow, placed at stable asymmetric anchors without drawn orbit geometry. Membership and roster content are never seeded, hard-coded, or presented as a demo: the Wheel and member detail consume the same persisted roster, while the Wheel alone composes that roster into the Weekly experience. Beneath the bubbles, five-photo Weekly progress appears first. A standalone gathering prompt follows, naming absent existing relatives as `Ask [waiting names] to come` and nudging them; for a one-person family with no relatives to nudge, it reads `Ask family to come` and opens Invite. The gathering prompt remains separate from the Weekly panel below it. Five photos unlock the Weekly key and entry to its waiting room; family presence is then counted against `ceil(active roster × 0.75)`, and the exact `Start weekly experience` action appears only at quorum. Member avatars in the room pair color with explicit `Here` or `Waiting` text. Entering or closing the room never loads current-week content. A remotely accepted member appears only after the durable local roster update succeeds, then becomes `Here` only through a fresh family-private BLE observation while that member's waiting room is foreground; no invented presence or contribution percentage is shown. YOU opens “Your memories”; tapping another person opens that member directly without displacing or scaling any bubble. Every primary surface uses one full-width white navigation bar with five equally spaced actions in this order: Wheel, Memory Key, centered `+`, Archive, and Settings. The bar is rectangular, flush to both viewport edges and the bottom safe area, separated from content only by a quiet top divider; it has no capsule, side margin, rounding, or shadow. A small black dot marks the current destination. The centered black `+` remains an independent “Keep a memory” action and never changes the selected destination. Memory Key owns Capsule entries rather than duplicating them on the Wheel or in primary navigation. Archive owns the always-present `Random Memory` control and selects only from the current filter-eligible kept set. Settings shows only real local identity, privacy, and device-accessibility information; unsupported controls are never implied. The author can inspect every memory they created, with explicit privacy and lifecycle labels; family browsing still exposes only eligible kept history. Capsule tasks expose locked, ready, and opened states. A locked assignment offers only an app-owned self-confirmation for the current member; Open memory appears only after that encrypted state update succeeds. Capsule payloads, assignments, and task-completion state are local to the capturing device; cross-device Capsule delivery and unlock synchronization are not implemented. Invitation membership, the persisted roster, and Weekly BLE presence remain separate concerns.

### Archive gallery

Archive is a content-first, kept-only media index grouped by year, with memories ordered newest first inside each year. Each phone-width year group uses a fixed three-column gallery of equal 1:1 tiles, 24 logical pixels from each screen edge and 4 logical pixels between tiles in both directions. Photo tiles show the real decrypted memory image with a cover crop; they load lazily only as they become visible, with at most three preview decryptions active at once. Source previews above 16 MiB fail closed until encrypted derivatives exist, and accepted images decode inside a 512 × 512 fit bound before the square cover crop. Their decrypted bytes remain owned only while the visible Archive surface owns them. Leaving visibility, changing destination or identity, disposing Archive, or completing a load after ownership ended clears those bytes rather than retaining a plaintext thumbnail cache. Voice and text memories occupy the same square geometry and identify their format with an explicit icon and visible or semantic text cue, never color alone.

Person and Theme remain separate horizontal `ChoiceChip` rails. Their visible capsule chrome is compact—32 logical pixels high, 12-pixel radius, 10–12 pixels of horizontal label padding, and 4-pixel visible gaps—while each option keeps a semantic and pointer target of at least 48 logical pixels. Chip copy and every Archive label use Modern Society with the established Title Case paint and natural-case semantics.

Archive owns one full-width `Random Memory` control inside the same 24-pixel edges. It is a stable 48-pixel-high outlined pill with a 24-pixel radius, transparent fill, a one-pixel `KeepersColors.homeTaupe` (`home-taupe`) border, Modern Society label, and a shuffle icon on the right. `home-taupe` is the accessible warm-token translation of the reference outline, reaching approximately 3.8:1 non-text contrast on `aura-ground`. The control stays visible, but its eligible pool is the current Person/Theme-filtered kept set: it avoids immediately repeating the last drawn ID when more than one result is eligible and is disabled honestly when no eligible memory remains.

### Weekly cream gallery

Weekly opens contextually as a full-screen cream gallery, not as a persistent destination: it has a compact Close / title header, no bottom navigation, and no outer phone or camera zoom. Five photos gate entry to the preceding waiting room; ceiling-75%-family presence gates its `Start weekly experience` action. Only that final start may load the live gallery payload. One large selected memory is paired with its centered date and a synchronized horizontal thumbnail rail. Tapping a thumbnail or swiping the hero selects that memory; both input paths use the same 160–180 ms opacity crossfade, while reduced motion changes immediately. Photo, voice, and text receive equivalent gallery layouts rather than format-specific hierarchy. A persistent action remains outside the reel's scroll region: `Next memory` advances non-final selections and `Choose what to keep` on the final selection enters the existing content-visible Keep / Release decision. Incomplete progress and a below-quorum waiting room expose no gallery bypass.

### Forms and overlays

Capture is a light, full-height two-step surface. Step one chooses Photo, Voice, or Text and accepts an optional caption; step two asks who can open the memory and defaults to Weekly Reveal. Back preserves the draft, save is labeled “Keep memory,” and sheets/dialogs preserve safe areas, keyboard reachability, cancellation, and retry.

Account authentication is mandatory before Create or Join family. The route order is `Create your Keepers account` → email OTP or Google, Microsoft, or Apple → Create or Join family. A local identity may continue to the Wheel only with a current matching account session, or while its first owner bootstrap is securely binding that account. New family setup persists the device-local identity unbound; the authoritative owner bootstrap is the sole step that binds it to an account. A signed-out profile, a different signed-in account, or an account that already belongs to another cloud family receives the same quiet full-height recovery language and an explicit `Use another account` action; local memories, keys, family, and member rows remain untouched. Browser authentication remains visibly pending; choosing another method first clears an unclaimed PKCE verifier, while a callback that has already claimed it remains the sole in-flight sign-in. Each launch carries an opaque, single-use attempt marker so stale or replayed callbacks cannot consume a replacement sign-in; completing a six-digit email code retires any earlier browser attempt. If cloud configuration is unavailable, new setup is blocked with an honest retry instead of falling through to local family creation. Authentication links an account to family membership; it does not restore device-local memories or encryption keys.

Invite and Join are contextual, full-height form routes rather than primary destinations. They reuse the continuous background, flat fields, direct status language, labeled back/close actions, and stable in-place progress/error regions. Email and six-digit OTP fields remain keyboard reachable and preserve safe corrections after recoverable failures; an email-binding mismatch focuses the email correction. The complete invitation capability and its wrapping secret are never painted, announced, copied to the clipboard, or retained in navigation state. Successful acceptance resets to the Wheel only after the encrypted family key, recipient's member key, membership, and roster have been committed locally.

### Iconography

Use Material Symbols only for familiar actions and always provide an accessible label for icon-only controls. Do not use emoji as interface icons.

The launcher artwork is an edge-to-edge black square with a centered white key: no painted corner radius, border, outside white, shadow, or glow. iOS and Android own the platform mask. Android adaptive launchers compose the same mark from a solid-black background and a mask-safe white-key foreground.

### Motion

The supplied background and family bubbles stay still so the home composition remains calm and predictable. The family field has no pan, drag, pinch-zoom, ambient drift, or tap-to-focus travel or scaling. Tapping the current member, another member, or Invite acts immediately. A newly persisted relative may enter with opacity only—220 ms normally and at most 90 ms with reduced motion—without changing position. Entering the Weekly waiting room is immediate and does not suggest that content has opened. Tapping its eligible `Start weekly experience` action, drawing Random memory in Archive, or opening a ready Capsule in Memory Key uses the established 560 ms full-screen pastel flood where that experience calls for a reveal; reduced motion makes that transition immediate. Weekly gallery selection crossfades by opacity in 160–180 ms for thumbnail taps and hero swipes, or changes immediately with reduced motion. The Keeping seal responds to a deliberate decision. Normal feedback stays between 200–500 ms.

One cold process launch plays the four-second Keepers opening composition. The cream wordmark holds alone on `ground`, followed by `Be present.`, `Be authentic.`, `Keep moments`, and `Be you.` with a restrained asymmetric gathering of cream rings, a narrow frame wipe, and one circle-to-line morph. The animation is native Flutter rather than a bundled video so it remains crisp, responsive, editable, and local. Tapping anywhere skips it without changing the resolved route. Native Android and iOS launch surfaces show the same centered cream wordmark on `ground`; Flutter's first frame is deferred until its optimized transparent counterpart has decoded, preventing either a light flash or an empty black handoff. The sequence never replays on foreground resume. Reduced motion bypasses the Flutter sequence on its first frame, makes reel changes immediate, and retains opacity feedback of at most 100 ms.

### Content and data visualization

Copy is plain, familial, and specific. Presence language states the condition required to gather; it never substitutes a bare countdown. Progress and presence always have text or semantic equivalents beyond color.

## Do's and Don'ts

- **Do:** Let identity color and presence geometry carry meaning consistently.
- **Do:** Preserve the existing encrypted data and Riverpod architecture behind the redesigned surfaces.
- **Don't:** turn family memory into a generic analytics dashboard or rounded-card grid.
- **Don't:** expose current-week content previews before the ceremony or make camera the primary capture action.
