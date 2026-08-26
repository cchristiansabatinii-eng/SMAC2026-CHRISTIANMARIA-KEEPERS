# Design QA — Family Home v4

## Evidence

- Reference: `C:\Users\Chris\Downloads\keepers_v4 (1).png` (1200 × 2600)
- Target: Android emulator `emulator-5554` (1080 × 2400 physical pixels)
- First implementation: `outputs/v4-home/pass-1.png`
- First comparison: `outputs/v4-home/comparison-pass-1.png`
- Second implementation: `outputs/v4-home/pass-2.png`
- Second comparison: `outputs/v4-home/comparison-pass-2.png`
- Final implementation: `outputs/v4-home/final.png`
- Final comparison: `outputs/v4-home/comparison-final.png`

## Review history

### Pass 1

- **P1 — scale and hierarchy:** The display headline, avatar cluster, gathering prompt, and dock were materially larger than the reference.
- **P1 — collision:** The top member label sat beneath the central profile.
- **P2 — density:** Shortcut cards and the bottom dock left too little of the reference's quiet negative space.

Resolved by tightening the display and interface type, lowering and reducing the central profile, reducing member and dock geometry, narrowing the gathering prompt, and restoring the large lower pause.

### Pass 2

- **P2 — detail fidelity:** The invite control remained oversized and the Legacy Lock metadata needed a calmer wrap.
- **P2 — token drift:** Two accepted home accent values were still local literals rather than runtime theme tokens.

Resolved by reducing the invite node, refining shortcut typography and wrapping, and mapping every accepted accent through `KeepersColors` and `DESIGN.md`.

## Final review

- Hierarchy and typography follow the approved composition.
- Header, presence marks, family cluster, gathering prompt, shortcuts, and dock align to one vertical rhythm.
- Member names stay directly beneath their assigned faceless profile.
- No orbit or connector line is rendered.
- Current app data remains honest: the family name, sealed count, presence state, member names, and contribution arcs are not replaced with screenshot fixtures.
- Bounded pan/zoom, reduced motion, member drift, profile routes, capture, Archive, Memory Key, and Locks remain functional.
- 390 × 844 at 1.4× text scale has automated overflow coverage.
- No actionable P0, P1, or P2 visual issue remains in the final comparison.

## Global background update

### Evidence

- Source visual truth: `C:\Users\Chris\Downloads\keepers_background_flat.png` (1200 × 2600 pixels)
- Implementation viewport: Android emulator `emulator-5554`, 1080 × 2400 physical pixels, 411 × 914 logical pixels at 2.625 density
- Normalization: the source was aspect-filled and center-cropped to 1080 × 2400 for an equal-pixel comparison
- Populated home: `outputs/background-flat/home-final.png`
- Archive: `outputs/background-flat/archive.png`
- Memory Key: `outputs/background-flat/memory-key.png`
- Memory creation: `outputs/background-flat/current.png`
- Equal-pixel comparison: `outputs/background-flat/comparison.png`
- State: populated family home plus representative destination and modal states

### Final review

- The exact supplied bitmap is loaded through the shared application background and remains visible from the status bar through the bottom safe area.
- Home, Archive, Memory Key, and the full-height memory-creation surface all use the same continuous ivory-to-blush canvas; the former aura and dark full-screen ceremony backgrounds do not remain.
- Existing foreground typography, controls, cards, and navigation retain readable contrast against the quieter canvas.
- Focused-region comparison was not needed: this change concerns one exact full-screen bitmap asset, and its crop, color field, edge coverage, and safe-area behavior are legible in the equal-pixel full-view comparison.
- First comparison found no actionable P0, P1, or P2 differences, so no post-comparison repair iteration was required.

## Main home brand and navigation revision

### Evidence

- Base composition: `C:\Users\Chris\Downloads\keepers_v4 (1).png` (1200 × 2600 pixels)
- Exact wordmark source: `C:\Users\Chris\Downloads\ChatGPT Image Sep 2, 2026, 11_19_00 PM.png` (1517 × 1037 pixels)
- Rendered implementation: `outputs/home-wordmark/home-432x768.png` (1080 × 2400 physical pixels)
- Final installed-build capture: `outputs/home-wordmark/home-final.png` (1080 × 2400 physical pixels)
- Equal-view and focused comparison: `outputs/home-wordmark/comparison.png` (1500 × 1900 pixels)
- Interaction evidence: `outputs/home-wordmark/nav-archive-late.png` and `outputs/home-wordmark/nav-plus-late.png`
- Viewport: Android emulator `emulator-5554`, approximately 411 × 914 logical pixels at 2.625 density
- Normalization: the base composition and implementation were both downsampled to a 1420-pixel comparison height; the exact source wordmark and its rendered crop were independently aspect-fitted for focused inspection without stretching
- State: established Rahman family, three of five members present, empty kept-memory archive

### Full-view comparison

- The requested intentional differences from the earlier composition are present: the large prompt is replaced by a compact supplied wordmark, `SEALED` is replaced by `KEPT MEMORIES`, profile accents use brighter pastels, and the home dock contains only Memory Key, add, and Archive.
- The presence sentence and attendance marks remain directly below the wordmark, preserving the approved “are here” feature.
- The replacement wordmark leaves purposeful negative space without displacing the family cluster, gathering prompt, shortcut cards, or safe-area navigation.
- Fonts and typography retain the reference hierarchy: serif memory count, compact tracked metadata, and direct uppercase profile labels. No text clips or wraps incorrectly.
- Spacing and layout rhythm remain aligned to the source composition. The three-icon dock is centered and all controls retain generous touch targets.
- Colors and visual tokens use the requested bright coral, mint, blue, lilac, and yellow pastels against the supplied flat background while keeping labels legible.
- Copy is exact for the requested surfaces: `KEPT MEMORIES`, the live `ARE HERE` sentence, and the three home destinations.

### Focused wordmark comparison

- The implementation uses the supplied raster asset rather than a redrawn or substitute mark.
- The `Keepers` lettering and integrated key silhouette match the source crop, scale proportionally, and remain sharp at emulator density.
- The source image's white canvas is removed at paint time; the focused render shows the shared application background through the asset with no visible white rectangle, stretch, or edge halo.

### Interaction verification

- Memory Key opened from the left control and exposed the expected `Memory Key`, weekly recap, random memory, and task-locked content semantics.
- Archive opened from the right control after encrypted startup completed; the captured destination shows the Archive selected state.
- The center add control opened the two-step `Keep a memory` flow; the captured first step includes Photo, Voice, and Text.
- Automated navigation and home-composition coverage is included in the passing Flutter suite.

### Comparison history

- First comparison: no actionable P0, P1, or P2 mismatch. The visual differences from the earlier base mock are the user's explicit revisions, not design drift.
- No post-comparison repair iteration was required.

## Memory Key reference implementation

### Evidence

- Reference: `C:\Users\Chris\Downloads\download.jpg` (normalized to 922 × 2048)
- Target: Android emulator `emulator-5554`, 1080 × 2400 physical pixels, approximately 411 × 914 logical pixels at 2.625 density
- First implementation: `outputs/memory-key-reference-pass/memory-key-pass1.png`
- First side-by-side: `outputs/memory-key-reference-pass/comparison-pass1.jpg`
- Compact iteration: `outputs/memory-key-reference-pass/memory-key-pass2.png`
- Final implementation: `outputs/memory-key-reference-pass/memory-key-final.png`
- Final side-by-side: `outputs/memory-key-reference-pass/comparison-final.jpg`
- Lower-content verification: `outputs/memory-key-reference-pass/memory-key-lower.png`
- Runtime state: one of two devices nearby, zero weekly memories, and an empty kept archive. The reference's four-of-five, 11-weekly, and 247-kept values are visual examples rather than substituted production data.

### Review history

#### Pass 1

- **P1 — scale and fold:** The overlapping presence cards and weekly panel were materially larger than the reference, leaving the family challenge below the initial viewport.
- **P2 — hierarchy:** The weekly title and action outweighed the quieter editorial rhythm of the source.
- **P2 — task density:** Repeated preview and approval metadata made the locked-memory card taller and busier than the supplied composition.

Resolved by reducing the Key-only header inset, scaling the family-card fan to the source, tightening weekly and random panels while retaining 44-pixel actions, and collapsing duplicated task metadata.

#### Final comparison

- The page now follows the reference's sequence and rhythm: title, overlapping family presence, truthful proximity sentence, weekly gate, random draw, family challenge, dated capsule, and persistent dock.
- Weekly access preserves the confirmed two-device rule. Random access remains available at any time, challenge proof routes to Locks, the invite action is live, and the center capture action remains independent.
- Type, line weights, ivory surfaces, gold metadata, restrained blush panel, and faceless family portraits match the established Keepers system and the supplied reference.
- The fixed navigation remains slightly larger than the static mock to retain the application's established touch targets. A short, stable scroll reveals the complete time capsule; the lower-content capture confirms no overlap, clipping, or overflow.
- The final side-by-side has no actionable P0, P1, or P2 visual mismatch.

## Global five-destination navigation

### Evidence

- Geometry and icon-hierarchy reference: `C:\Users\Chris\AppData\Local\Temp\codex-clipboard-b5d31484-598a-47fb-94ec-a0c3ae8d22e2.png` (1440 × 190 pixels)
- Target: Android emulator `emulator-5554`, 1080 × 2400 physical pixels, approximately 411 × 914 logical pixels at 2.625 density
- First home pass: `outputs/nav-qa/home-pass1.png`
- Revised home pass: `outputs/nav-qa/home-pass2.png`
- Final foreground home: `outputs/nav-qa/home-final.png`
- Memory Key destination: `outputs/nav-qa/key.png`
- Archive destination: `outputs/nav-qa/archive-pass2.png`
- Settings destination: `outputs/nav-qa/settings.png`
- Add-memory flow: `outputs/nav-qa/plus-flow.png`
- State: populated family home, empty kept-memory archive, Memory Key content, truthful first-run Settings, and capture step one
- Normalization: the supplied landscape strip was used as a focused navigation reference rather than stretched into a full-screen mock; the complete 1080 × 2400 app captures verify safe-area and page integration.

### Full-view comparison

- The final home, Memory Key, Archive, and Settings captures were reviewed at the same emulator viewport. The navigation stays fixed, spans the full physical width, includes the bottom safe area, and does not obscure or clip page content.
- All primary destinations share identical geometry: a flat white rectangular field, quiet top divider, five equal-width controls, no side margin, no rounded outer container, and no shadow.
- The order is consistently Wheel, Memory Key, add, Archive, and Settings. The current primary destination is identified by a small black dot without changing layout.
- The centered add action opens the existing two-step `Keep a memory` flow. The first step renders correctly above the current destination and retains Photo, Voice, Text, and caption controls.

### Focused reference comparison

- The reference strip and `outputs/nav-qa/home-pass2.png` were inspected together. The implementation preserves its decisive edge-to-edge rectangular silhouette, five evenly spaced destinations, high-contrast monochrome icons, and strong central action.
- The palette is intentionally inverted to the user-approved Keepers treatment: white navigation surface with black accents instead of a dark surface with white accents.
- App-specific symbols replace the reference's unrelated social icons while keeping comparable visual weight and spacing. The center action uses a black circle with a white plus; Wheel, key, stacked Archive, and user-profile icons use the established icon library rather than custom drawings.

### Comparison history

#### Pass 1

- **P2 — icon contrast:** inactive destinations rendered grey even though the approved direction called for black icon accents.
- **P2 — destination semantics:** Archive used a history-clock symbol, which read as recents rather than a memory stack.

Resolved by giving every enabled destination a solid black icon and replacing the clock with the stacked-outline Archive symbol. A widget regression test now checks both decisions.

#### Pass 2

- The revised home and destination captures show consistent icon weight, exact destination order, stable active indicators, correct system-safe-area treatment, and no visible clipping, overflow, accidental capsule geometry, or shadow.
- Memory Key, Archive, Settings, capture, and return-to-Wheel interactions were exercised on the installed Android build. No actionable P0, P1, or P2 visual issue remains.

## Transparent home wordmark header

### Evidence

- Centered-header baseline: `outputs/home-header/pass1.png` (1080 × 2400 physical pixels)
- Final implementation: `outputs/home-header-transparent/home-final.png` (1080 × 2400 physical pixels)
- Original home composition reference: `C:\Users\Chris\Downloads\keepers_v4 (1).png` (1200 × 2600 pixels)
- Target: Android emulator `emulator-5554`, approximately 411 × 914 logical pixels at 2.625 density
- State: populated Rahman family, two relatives nearby, zero kept memories

### Comparison

- The supplied black Keepers wordmark remains centered at the same 94 × 38 logical-pixel size and safe-area position.
- The former white header fill is removed. The approved blush-ivory application background now continues uninterrupted beneath the status area and wordmark.
- Header height, kept-memory counter, family title, presence sentence, family cluster, lower actions, and fixed navigation retain their prior geometry; the change introduces no content jump.
- The final emulator capture shows no divider seam, clipping, overlap, unintended contrast loss, or touch-target change.
- The final capture and the previous white-bar capture were inspected together. No actionable P0, P1, or P2 visual issue remains.

## Home information hierarchy revision

### Evidence

- Presence reference: `C:\Users\Chris\AppData\Local\Temp\codex-clipboard-89fa3283-f67d-4842-8ee6-2bdcbbffb57e.png` (487 × 120 pixels)
- Family-summary reference: `C:\Users\Chris\AppData\Local\Temp\codex-clipboard-1d3655dd-f97f-4ffc-8703-f6f99e280086.png` (487 × 120 pixels)
- Previous implementation: `outputs/home-header-transparent/home-final.png` (1080 × 2400 physical pixels)
- Final implementation: `outputs/home-information-order/pass1.png` (1080 × 2400 physical pixels)
- Target: Android emulator `emulator-5554`, approximately 411 × 914 logical pixels at 2.625 density
- State: populated Rahman family, Noura and Mariam nearby, zero kept memories

### Comparison

- The reference crops and complete emulator render were inspected together at their native proportions.
- The presence sentence and attendance marks are now the first app content after the centered Keepers wordmark, with their original color, tracking, and two-line rhythm preserved.
- The family cluster remains fully interactive and visually unchanged beneath presence.
- The invite prompt remains directly actionable, followed by the relocated family summary and then the Legacy Lock and Capsule shortcuts.
- The visible label is `Rahman family`; it is sentence-cased and reduced from 26 to 20 logical pixels. The kept-memory number is also 20 pixels, preserving a quiet, balanced summary row.
- The segmented family mark remains aligned directly below the family label. The summary does not overlap the invitation, either shortcut, or the fixed navigation.
- No actionable P0, P1, or P2 issue was visible in the first implementation pass, so no repair iteration was needed.

## Compact home family summary

### Evidence

- Focused reference: `C:\Users\Chris\AppData\Local\Temp\codex-clipboard-14932609-52e9-4324-a01c-995cfc286ad5.png` (587 × 123 pixels)
- First implementation: `outputs/home-family-summary/pass1.png` (1080 × 2400 physical pixels)
- Cold-start verification: `outputs/home-family-summary/pass2.png` (1080 × 2400 physical pixels)
- Target: Android emulator `emulator-5554`, approximately 411 × 914 logical pixels at 2.625 density
- State: populated Rahman family with two nearby relatives and zero genuinely kept memories

### Pass 1 comparison

- The focused source and complete emulator screen were inspected together. The implementation carries over the source's compact left-title/right-number rhythm without copying its sample data.
- The approved label remains `Rahman family`, with no leading `The`; the right side exposes one truthful total and the single caption `KEPT`.
- Name and number share the same 20-pixel Fraunces scale and top alignment. The segmented family mark sits directly beneath the name.
- The summary now precedes the family invitation, while the invitation continues to precede both shortcut cards.
- No clipping, collision, wrapping, inconsistent alignment, or actionable P0/P1/P2 mismatch was visible.

### Pass 2 comparison

- The app was cold-started and captured again at the same viewport and state. The summary, invitation, shortcuts, and fixed navigation retained stable geometry.
- The reference's `SEALED`, secondary sample count, divider, and date line remain intentionally absent because the approved scope is the family label plus the app's real kept-memory total.
- The count is sourced only from entries whose state is `kept`; pending entries no longer inflate the visible value.
- No actionable P0, P1, or P2 issue remains.

final result: passed

## Home gathering and Weekly controls

### Evidence

- Source visual truth: `C:\Users\Chris\Downloads\ChatGPT Image Sep 6, 2026, 09_10_19 PM.png` (1820 × 864 pixels)
- Installed implementation: `after-home-buttons-pass2.png` (1080 × 2400 physical pixels)
- First focused comparison: `design-qa-home-buttons-pass1.jpg` (1820 × 1728 pixels)
- Final focused comparison: `design-qa-home-buttons-pass2.jpg` (1820 × 1728 pixels)
- Viewport: Android emulator `emulator-5554`, approximately 411 × 914 logical pixels at 2.625 density
- Normalization: the 1080 × 513 implementation control crop was resized to the source's 1820 × 864 pixels, then source and implementation were stacked in one comparison image.
- State: current member only; zero of five Weekly photos; locked Weekly experience; separately labeled rehearsal available below the compared control region.

### Review

- Fonts and typography: the supplied and installed controls use the same bundled Modern Society face, centered label treatment, weight, tracking, and single-line wrapping. Natural-case semantics remain unchanged.
- Spacing and layout rhythm: the gathering capsule preserves the source's proportions and centered placement. The Weekly field now uses a 16-logical-pixel gutter, matching the source's near-edge width while retaining the established 12-pixel gap and fixed navigation clearance.
- Colors and visual tokens: both locked controls use opaque `aura-ivory` with the new sampled warm-neutral `home-action-line` (`#D4BBAC`). Gold is reserved for the ready key, border, and restrained readiness aura.
- Image and icon fidelity: the overlapping pastel presence marks and Material lock retain their existing product-owned assets and geometry. No shadow, blur, gradient, or substitute artwork was introduced.
- Copy and behavior: Invite/nudge behavior, the five-photo gate, three-quarter family-presence gate, locked semantics, ready key swap, glow, and real open action remain intact. The progress bar and preview control sit outside the supplied crop and remain because they are existing product requirements.
- Accessibility and responsiveness: the capsule and Weekly field remain semantic buttons, disabled state removes the open action, ready state exposes one accessible action, reduced motion remains honored, and the 390 × 844 widget layout stays above the bottom navigation.

### Comparison history

- Pass 1 found one P2 spacing mismatch: the installed Weekly field retained a 28-pixel gutter and appeared visibly narrower than the supplied near-edge panel. Its warm-neutral color, typography, radii, double border, and medallion proportions otherwise matched.
- The Weekly gutter was reduced to 16 pixels and protected by a 390-pixel viewport regression test.
- Pass 2 confirmed the panel width, capsule geometry, warm-neutral line work, medallion scale, and ivory surfaces align with the source. No actionable P0, P1, or P2 finding remains.

final result: passed

## Unified heading scale

### Evidence

- Supplied family-heading reference: `C:\Users\Chris\AppData\Local\Temp\codex-clipboard-9fd5fa91-e964-4765-9a2d-070338ce628e.png`
- Final Family Wheel: `outputs/heading-scale/final-home.png`
- Final Archive empty state: `outputs/heading-scale/final-archive.png`
- Memory Key: `outputs/heading-scale/memory-key.png`
- Settings: `outputs/heading-scale/settings.png`
- Memory creation: `outputs/heading-scale/capture.png`
- Target: Android Pixel 8 emulator, 1080 × 2400 physical pixels

### Review

- Primary page, modal, section, and empty-state headings now share the established `RAHMAN FAMILY` treatment: uppercase Schibsted Grotesk at 20 pixels, weight 600, line height 1, and 4.1 pixels of tracking.
- Counts, timers, buttons, metadata, statuses, and body copy retain smaller role-specific sizing so the interface remains readable rather than uniformly enlarged.
- The installed Family Wheel, Archive, Memory Key, Settings, and memory-creation surfaces were reviewed for hierarchy, alignment, wrapping, clipping, and overflow. Their primary headings are consistent and no visible collision is present.
- A dedicated 390 × 844 regression test at 1.4× text scale confirms the two-line Memorial preview app-bar heading does not exceed its line budget.

final result: passed

## Family title and kept-forever strip

### Evidence

- Supplied removal reference: `C:\Users\Chris\AppData\Local\Temp\codex-clipboard-87d715f1-3a31-4b9f-a2df-9e1e0cdfb552.png` (104 × 25 pixels)
- Supplied kept-forever reference: `C:\Users\Chris\AppData\Local\Temp\codex-clipboard-345f6264-c698-4fe5-956e-17d6878be347.png` (580 × 99 pixels)
- Previous installed build: `C:\Users\Chris\Documents\Codex\2026-08-31\github-plugin-github-openai-curated-remote-2\ui-previews\before-kept-strip.png` (1080 × 2400 physical pixels)
- Updated installed build: `C:\Users\Chris\Documents\Codex\2026-08-31\github-plugin-github-openai-curated-remote-2\ui-previews\after-kept-strip-pass1.png` (1080 × 2400 physical pixels)
- Combined full-view and focused comparison: `C:\Users\Chris\Documents\Codex\2026-08-31\github-plugin-github-openai-curated-remote-2\ui-previews\comparison-kept-strip-pass1.png`
- Target: Android Pixel 8 emulator, approximately 411 × 914 logical pixels at 2.625 density; the source detail crops retain their native pixels and the emulator images are normalized to equal display widths in the comparison.
- State: populated Rahman family with Noura and Mariam nearby and zero genuinely kept memories.

### Review

- The segmented gold/taupe family marker and header-side kept total are absent. `RAHMAN FAMILY` moves into their former vertical space and now sits eight logical pixels above the presence sentence, while the attendance row and family cluster retain their established positions.
- The new strip follows the gathering invitation and precedes both shortcut cards. Its 12-pixel radius, quiet ivory fill, subtle border, compact tracked label, Fraunces total, and five pastel format tiles match the supplied detail without introducing the source image's sample count as fake app data.
- Fonts and typography: the family title retains the approved 20-pixel tracked Schibsted Grotesk at weight 600; the strip uses the established label face and 20-pixel Fraunces count. No clipping or substitution is visible.
- Spacing and layout rhythm: the title-to-presence gap is compact, the strip shares the 28-pixel page gutters and shortcut edges, and the lower action group remains above persistent navigation without overlap.
- Colors and visual tokens: the strip reuses the existing clay, green, blue, mauve, gold, ivory, line, ink, and taupe tokens. It has no shadow or gradient.
- Image quality and asset fidelity: the supplied raster background and wordmark are unchanged. The format marks use the app's existing Material icon system rather than approximate drawn assets.
- Copy and content: `KEPT FOREVER` replaces the old standalone `KEPT` caption. The displayed total remains sourced from genuinely kept entries, and the strip has one truthful singular/plural accessibility label; its illustrative format tiles are excluded from semantics.
- The combined comparison was inspected for hierarchy, alignment, typography, spacing, color, icon fidelity, copy, touch-area stability, and overflow. The focused 390 × 844 widget suite also passes at 1.4× text scale. No actionable P0, P1, or P2 mismatch remains, so no repair pass was required.

final result: passed

## Centered family return and family-label typography

### Evidence

- Centered composition reference: `C:\Users\Chris\AppData\Local\Temp\codex-clipboard-73bc77a6-a67f-489c-ab0c-c946fc0a3c49.png`
- Family-label type reference: `C:\Users\Chris\AppData\Local\Temp\codex-clipboard-c089895e-0936-45c4-97c9-2358d1d4c8e2.png`
- First installed-build capture: `outputs/home-center-font/pass1.png`
- First combined comparison: `outputs/home-center-font/comparison-pass1.png`
- Deliberately panned interaction state: `outputs/home-center-font/panned.png`
- Capture-flow transition: `outputs/home-center-font/capture-open.png`
- Returned home capture: `outputs/home-center-font/pass2.png`
- Second combined comparison: `outputs/home-center-font/comparison-pass2.png`
- Freshly rebuilt and reinstalled handoff capture: `outputs/home-center-font/final.png`
- Target: Android Pixel 8 emulator, 1080 × 2400 physical pixels

### Review

- The family cluster opens on the established centered asymmetric composition and remains directly manipulable within the existing bounded pan and zoom range.
- After the field was visibly panned, opening the central capture flow and returning recreated the family view at identity; the second capture confirms no stale translation or gesture inertia remained.
- `Rahman family` preserves its approved sentence case and 20-pixel scale while adopting the same bundled Schibsted face, strong weight, and tracked character of the supplied presence-line reference. The kept-memory total remains in Fraunces, preserving the intended metadata contrast.
- The fixed height and scale-down treatment were removed from the family label, so accessibility text scaling now enlarges it instead of shrinking it back to the default painted height.
- Both combined comparisons were inspected for hierarchy, alignment, clipping, line wrapping, spacing, cluster position, and navigation stability. No actionable P0, P1, or P2 issue remains within the approved scope.

### Final correction

- Final installed-build capture: `outputs/home-center-font/corrected.png`
- Final side-by-side comparison: `outputs/home-center-font/comparison-corrected.png`
- The family field now begins 50 logical pixels beneath the attendance marks, moving the complete bubble composition 46 logical pixels lower than the prior build and matching the supplied reference's vertical center.
- The visible family title is now `RAHMAN FAMILY`, using the same uppercase, tracked Schibsted Grotesk label treatment as the surrounding interface. Its assistive label remains natural-case `Rahman family`.
- The family summary, invitation, shortcut cards, and fixed bottom navigation retain their established lower alignment. The real 390 × 844 safe-area layout remains scrollable and hit-testable at 1.4× text scale.
- The final reference/current comparison shows no clipping, overlap, unintended font substitution, or actionable P0, P1, or P2 mismatch.

final result: passed

## Family summary header and lighter label

### Evidence

- Supplied presence reference: `C:\Users\Chris\AppData\Local\Temp\codex-clipboard-55ee9b2f-cdf1-4d14-8828-5f39366261fe.png` (328 × 102 pixels)
- Previous installed build: `outputs/home-center-font/corrected.png` (1080 × 2400 physical pixels)
- Updated installed build: `outputs/home-summary-header/pass1.png` (1080 × 2400 physical pixels)
- Combined comparison: `outputs/home-summary-header/comparison-pass1.png`
- Target: Android Pixel 8 emulator, approximately 411 × 914 logical pixels at 2.625 density
- State: populated Rahman family with Noura and Mariam nearby and zero kept memories

### Review

- The complete family summary now appears immediately below the centered Keepers wordmark and above the supplied two-line presence composition. The title, segmented family mark, kept count, and `KEPT` caption remain one aligned row.
- `RAHMAN FAMILY` retains the approved uppercase Schibsted Grotesk face, 20-pixel size, and 4.1-pixel tracking while reducing its weight from 800 to 600. In the focused side-by-side, the title is visibly quieter without losing hierarchy or legibility.
- The supplied presence sentence, colored attendance dots, and `OF FIVE` treatment remain visually unchanged. A 16-pixel gap beneath the attendance row keeps the family field near its established center after the summary moves above it.
- The family bubbles, gathering invitation, shortcut cards, and fixed navigation preserve their geometry and remain free of clipping or overlap. Natural-case `Rahman family` semantics and the full kept-memory count remain available to assistive technology.
- The reference crop, previous build, and updated build were inspected together for typography, spacing, color, imagery, copy, hierarchy, and layout stability. No actionable P0, P1, or P2 mismatch remains; no post-comparison visual repair was required.

final result: passed

## Unified Schibsted typography

### Evidence

- Family Wheel: `outputs/typography-final.png`
- Memory Key: `outputs/typography-memory-key.png`
- Weekly rehearsal: `outputs/typography-weekly.png`
- Archive empty state: `outputs/typography-archive.png`
- Settings: `outputs/typography-settings.png`
- Memory creation: `outputs/typography-capture.png`
- Target: Android Pixel 8 emulator, 1080 × 2400 physical pixels

### Review

- Schibsted Grotesk now carries every English interface role: display headings, memory copy, controls, captions, dates, statuses, and navigation. Existing size, weight, tracking, casing, and line-height distinctions remain intact.
- This approved system decision supersedes earlier entries in this historical QA log that describe Fraunces as the current heading or kept-count face. `DESIGN.md` and the runtime theme are the canonical current sources.
- The rebuilt Wheel, Memory Key, Weekly reel, Archive, Settings, and capture surfaces were inspected for font loading, hierarchy, line wrapping, clipping, overflow, alignment, and navigation stability. No actionable typography regression was visible.

final result: passed

## Uppercase Schibsted system and Archive kept summary

### Evidence

- Family Wheel: `outputs/uppercase-archive/final-home.png`
- Archive empty state: `outputs/uppercase-archive/final-archive.png`
- Target: Android Pixel 8 emulator, 1080 × 2400 physical pixels

### Review

- All app-authored interface copy now paints in uppercase Schibsted Grotesk. Weight remains semantic rather than uniform: supporting descriptions are lighter, labels and navigation are firmer, and primary titles retain clear hierarchy.
- Source strings and accessibility labels remain natural-case where that improves pronunciation, while editable fields preserve exactly what the user enters. Presented memory prose is uppercase without changing the stored memory.
- The `KEPT FOREVER` summary is removed from the Family Wheel and now opens the Archive body beneath its heading. Its count is based on the full kept collection, so filtering cannot change the family total.
- The installed build was reviewed for hierarchy, weight contrast, character spacing, wrapping, overflow, icon alignment, navigation stability, and empty-state balance. The Wheel remains uncluttered and the Archive summary is visible before any filtering or content.
- Formatter, static analysis, the focused interaction suite, the complete Flutter suite, and the Android debug build all pass after the final accessibility repairs.

final result: passed

## Permanent family-code joining and real-roster supersession

### Current data and invitation contract

This entry supersedes the legacy recipient-email/capability-link QA section and any use of historical populated-family captures as runtime evidence. New clients no longer ask for a relative's email or create a `keepers://join` bearer capability. They display one permanent family code, share `https://join.keepers.app/f/<code>`, create an authenticated request, and wait for any active member to approve or decline. Email remains account authentication only. Legacy invitation RPCs remain temporarily for already-issued builds.

References to the staged Rahman roster, Noura or Mariam being nearby, sample family counts, contribution rings, or preview membership remain useful only for judging composition, typography, and spacing at the time they were captured. They do not prove cloud membership, roster refresh, proximity, contribution, or joining. A relative appears in the product only from the persisted roster after local creation or completed remote membership; new remote members default to away until a real presence adapter reports otherwise.

### Repository evidence and honest boundaries

| Evidence area | Current repository evidence | Release status |
|---|---|---|
| Code and encrypted display material | Canonical eight-symbol parsing, SHA-256 lookup, AES-256-GCM encrypted material, encrypted offline cache, collision handling, and redacted diagnostics have focused tests. | Repository checkpoint only. |
| Secure approval and recovery | X25519/HKDF/AES approval envelopes, strict context validation, transactional local install, exact completion marker, account isolation, and idempotent recovery have focused tests. | Repository checkpoint only. |
| Backend contract | Migrations `202609050001`, `202609070001`, and `202609070002` plus `keepers-auth-bridge` are deployed to the hosted Keepers project; the required tables, RLS, eleven RPCs, serialization guards, Realtime publication, migration ledger, and callback redirect headers were verified on 2026-09-07. The repository also contains 106 pgTAP assertions and five deterministic two-session race fixtures. | The independent PostgreSQL concurrency harness still lacks a green run URL; that narrower gate remains open. |
| Requester and approver flows | Manual/link constructors, requester states, any-member decision controller, sheets, and focused accessibility behavior are under the Task 8–12 integration pass. | Do not claim end-to-end complete until the final integration suite and review close. |
| Native routing | Exact HTTPS parsing, Android `/f/` declaration, both iOS associated-domain entitlements, cold/warm routing, dedupe, and deliberate reopen have focused tests. | Domain ownership and OS verification are not proven by source declarations. |
| Operations | SQL account/family quotas and a service-role purge helper exist. | Daily 30-day purge scheduling and a separate production source-IP throttle are not configured or verified. |
| Android distribution | Debug and release-mode local builds can be produced from the ignored client config. | Gradle `release` currently uses debug signing; no production certificate fingerprint or two-physical-phone acceptance evidence exists. |
| iOS distribution | The bundle identifier is `app.keepers.keepers` and signed-build entitlement files request `applinks:join.keepers.app`. | No Apple Team ID, distribution signature, hosted AASA verification, physical runtime, or accessibility evidence exists. |
| Family presence | The current adapter reports only the local member and never infers proximity from cloud membership. | No trusted release proximity source exists, so real multi-person Weekly presence remains gated. |
| Visual acceptance | Earlier product screens have historical emulator QA. | The new family-code states have not yet completed the required two passes at 390×844 and 430×932, 1.4× text, and reduced motion. |

`tools/audit_project.py`, fake gateways, static platform checks, and emulator screenshots are supplemental only. They cannot prove Dart runtime key handling, live RLS/RPC behavior, production ingress controls, public domain association, or physical-device recovery.

### Approved reproducible-baseline staging manifest

The approved font, wordmark, and Weekly reference-image bundle is captured in
`f9001f9`. The app currently being exercised still depends on approved source
and platform resources outside `HEAD`. Those remaining paths must be reviewed
and committed as one coherent baseline before a build is represented as
reproducible.

Include:

- `.gitignore`, `DESIGN.md`, `UX-CONTRACT.md`, `design-qa.md`, `app/README.md`, and the maintained invitation specifications;
- the dirty Android launch resources under `app/android/app/src/main/res/**` and iOS launch resources under `app/ios/Runner/{Assets.xcassets/LaunchImage.imageset,Base.lproj/LaunchScreen.storyboard}`;
- all approved dirty or untracked `app/lib/**`, paired `app/test/**` and `app/integration_test/**`, launch goldens, `app/tool/generate_launch_wordmark.ps1`, and `app/test/storage/app_database_test.dart`;
- `supabase/{README.md,config.toml}`, `supabase/functions/keepers-auth-bridge/**`, and the paired auth-bridge tests.

Exclude:

- `app/config/supabase.local.json`, `.env*`, signing files, keystores, exported keys, and every credential or service-role key;
- `.dart_tool/`, build products, local Supabase `.branches/` and `.temp/`, IDE state, and worktrees;
- `outputs/**`, `app/outputs/**`, root/app `before-*` or `after-*` captures, `design-qa-*.jpg`, and `premium-audit*.json`;
- `outputs/normalize_final_coverage.ps1`, which contains machine-specific absolute paths. The two reusable playback/reference extraction scripts should be moved from `app/outputs/` to `app/tool/` before retaining them; otherwise exclude them with the output tree.

Do not use an unrestricted `git add .` for this baseline. Review the allowlist, confirm no active task is still editing an overlapping file, inspect the staged diff and file sizes, and run the clean-archive build/test check before committing.

### Acceptance evidence still required

A release-grade pass requires all three migrations on one live Supabase project plus at least two physical Android devices built from the same ignored client configuration. Record manual code and HTTPS link entry; signed-out authentication/resume; any-member approval; requester offline during approval; foreground/background/process death/device restart; regeneration, decline, cancel, expiry, and wrong-account recovery; exactly one active membership; the same roster on both phones; and inspection confirming that no plaintext memory, code, link, joining private key, shared secret, or family/member key reached cloud or diagnostic logs.

Until those artifacts exist, PostgreSQL concurrency execution, purge scheduling, production IP throttling, production signing/domain association, two-physical-phone joining, iOS runtime/accessibility, and a release proximity source remain explicitly unpassed. All three hosted migrations and auth-bridge deployment are complete. Manual code joining remains the required fallback when verified HTTPS association is unavailable. The build is not yet launch-ready.

final result: implementation and external acceptance pending

## Weekly photo-and-presence gate

### Evidence

- Source visual truth: `C:\Users\Chris\AppData\Local\Temp\codex-clipboard-dab10d4e-b6b2-4f27-a325-0c1f7d2eb93b.png` (2170 × 725 pixels)
- Installed implementation: `app/build/keepers-weekly-pass2.png` (1080 × 2400 physical pixels)
- Focused comparison: `app/build/weekly-panel-comparison-pass2.png` (1000 × 698 pixels)
- Opened preview: `app/build/keepers-weekly-preview.png` (1080 × 2400 physical pixels)
- Viewport: Android emulator `emulator-5554`, approximately 411 × 914 logical pixels at 2.625 density
- Normalization: the implementation's 970 × 312 panel crop and the source panel were independently scaled to 1000 pixels wide without distortion, then stacked in one comparison image.
- State: current member only; zero of five qualifying Weekly photos; one of two nearby devices; separately labeled rehearsal available.

### Full-view and focused review

- The Wheel now reads in the approved order: family bubbles, five-segment Weekly Vault progress, `Ask family to come`, the Weekly panel, then persistent navigation. The 1080 × 2400 capture shows no clipping, overlap, unstable wrapping, or hidden navigation.
- The focused comparison confirms the same low, wide ivory panel, quiet rounded geometry, warm-gold double line, centered concentric medallion, and generous internal space as the reference. The source shadow is intentionally omitted because the approved Keepers system forbids card shadows.
- Fonts and typography: all added copy uses Schibsted Grotesk through `KeepersText`, with tracked uppercase visual treatment and natural-case semantics. The 10-pixel status roles use the contrast-safe `inkMuted` token; automated contrast coverage requires at least 4.5:1 on aura ivory.
- Spacing and layout rhythm: the progress, invitation, and panel retain 12-pixel transitions and shared page gutters. The panel preserves a 104-logical-pixel touch target and the separate preview preserves 44 logical pixels.
- Colors and visual tokens: the implementation uses existing ivory, warm gold, ink, line, and five pastel family tokens. No gradient, glass, decorative blur, or shadow was introduced.
- Image and icon fidelity: no raster placeholder or approximate drawn asset is used. The installed Material key is the existing app-wide Memory Key symbol; its horizontal silhouette is a minor intentional departure from the reference keyhole so the symbol remains consistent across navigation and Weekly.
- Copy and behavior: the progress reports the real qualifying count, names both missing requirements, and the real action unlocks only at five photos plus at least three quarters of the family present, rounded up. The explicitly requested prototype bypass remains a separately labeled, non-mutating `Preview weekly experience`; the opened capture confirms `REHEARSAL MODE` remains visible.
- Accessibility: count semantics are not duplicated, requirement changes are a live region, disabled panels do not announce an open action, and the ready panel exposes one tap action.

### Comparison history

- Pass 1 found no visual P0, P1, or P2 mismatch after normalizing the source component against the installed panel. Read-only implementation review did identify contrast, duplicate announcement, clock-boundary, future-date, and unavailable-action truthfulness defects; each was repaired and regression-tested before the final capture.
- Pass 2 re-captured the installed build after opening and returning from the rehearsal. The composition remained stable, the Weekly preview opened successfully, and no actionable P0, P1, or P2 visual issue remained. The horizontal key glyph and intentionally shadowless treatment remain accepted P3/product-system deviations.

final result: passed

## Modern Society typography migration

### Evidence

- Installed Android captures: `app/outputs/modern-society-audit/home.png`, `key.png`, `archive.png`, `settings.png`, and `capture.png` at 1080 × 2400 physical pixels.
- Runtime owner: `app/lib/theme/keepers_theme.dart`; bundled asset and commercial-use notice: `app/assets/fonts/modern_society/`.
- The previous font asset is absent from the source tree and built APK; the APK contains `assets/flutter_assets/assets/fonts/modern_society/modernsociety-regular.otf`.

### Review

- Modern Society now owns every themed text role, while the existing role-specific sizes, weights, line heights, and tracking remain unchanged.
- App presentation uses Title Case through the shared `KeepersText` painter. Editable fields and stored content are not rewritten, and text-memory accessibility retains the authored value.
- Home, Memory Key, Archive, Settings, and memory creation render without visible clipping, overlap, or navigation movement on the Android emulator.
- Modern Society is a tall unicase-style display face, so its lowercase glyphs retain a deliberately capital-like silhouette even though the rendered strings use Title Case.

final result: passed

## Weekly cream gallery

### Evidence

- Motion reference: `C:\Users\Chris\Downloads\Diseno-de-ui-Disenos-de-unas-Diseno-de-app-Interfaces.mp4` (8 seconds, 720 × 720, 30 fps).
- Reference frame: `app/outputs/weekly-video-frames/frame-06-4.36s.png`.
- First installed gallery pass: `app/after-weekly-gallery-home.png`.
- Second installed gallery pass: `app/after-weekly-gallery-pass2.png`.
- Final installed photo state: `app/after-weekly-gallery-final.png` (1080 × 2400 physical pixels).
- Same-input reference comparison: `design-qa-weekly-gallery-final.jpg`.
- Target: Android Pixel 8 emulator `emulator-5554`.

### Review and repair loop

- The source's product pattern—not its presentation-video camera move—was translated into Keepers: contextual close, centered memory title, one portrait hero, centered date, and a synchronized horizontal thumbnail reel. The black source canvas was intentionally replaced by the app's supplied cream background, as requested.
- Pass one exposed a vertically centered reel, excessive space between the header and hero, and a title collision with the rehearsal marker. The transition container was made full-height, the compact header was re-composed as a centered two-line title/status group, and its stack was given full screen width so Close returned to the expected leading edge.
- Pass two confirmed the corrected hierarchy and stable voice presentation. The hero width and aspect ratio were then tuned closer to the reference, and the final source crop was cleaned to remove a captured black video edge.
- The final combined comparison shows the same quiet top controls, dominant rounded portrait memory, date rhythm, and selected-thumbnail sequence. Added format/count metadata is deliberately subordinate and makes photo, voice, and text states explicit without competing with the memory.
- Thumbnail taps and disclosed horizontal swipes update image, title, date, format, count, and selection semantics from one index. Selection uses a 170 ms opacity crossfade; reduced motion changes immediately. Voice retains a labeled play/pause control, the text memory retains its echo, and the final memory continues to the existing labeled Keep/Release decision.
- Weekly playback has no persistent app navigation. Close returns to the Family Wheel. The five-photo and rounded-up 75%-of-family presence gate remains owned by the Wheel; the local bypass remains visibly labeled `Rehearsal Mode` and does not mutate gate state.
- The 390 × 844 widget target and installed emulator were checked for hierarchy, alignment, crop, contrast, touch targets, navigation clarity, wrapping, overflow, and layout stability. No actionable P0, P1, or P2 visual issue remains.

final result: passed
