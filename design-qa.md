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

## Supabase family invitations and real-roster supersession

### Current data contract

This entry supersedes any use of the historical populated-family captures above as runtime data evidence. References to the staged Rahman roster, Noura or Mariam being nearby, sample family counts, contribution rings, or preview membership remain useful only for judging composition, typography, and spacing at the time they were captured. They do not prove cloud membership, roster refresh, proximity, contribution, or invitation acceptance, and those names must not be shipped as fallback family data.

The current first-run Wheel contains only the encrypted, persisted current member and Invite. A relative appears on the Wheel, Memory Key, and Member page only from the shared persisted roster after local creation or successful remote acceptance. A remotely accepted member defaults to away until a real presence adapter reports otherwise, and the UI omits an unknown contribution percentage instead of inventing one. Proximity rehearsal and the explicitly labeled preview task remain preview-only; membership and roster data do not.

### Repository acceptance contract

| Evidence area | Required target or observation | Status boundary |
|---|---|---|
| Supabase configuration | Supply both `KEEPERS_SUPABASE_URL` and `KEEPERS_SUPABASE_PUBLISHABLE_KEY`; never a service-role key. Apply `supabase/migrations/202609050001_family_invitations.sql` with `supabase link` and `supabase db push`. | Configuration contract documented; no production credential is checked in or exercised by this docs pass. |
| Database behavior | From the repository root, run `supabase start`, `supabase db reset --local`, and `supabase test db --local` to cover RLS, RPC authorization, expiry, replay, revocation, idempotency, and races. | A recorded successful run is required; static SQL review is not a substitute. |
| Email authentication | The Supabase email template renders `{{ .Token }}` and the client requests/verifies the resulting six-digit OTP for the normalized, invitation-bound email. | A live OTP delivery/verification artifact is required; magic-link-only behavior does not pass. |
| Link routing | Only `keepers://join?v=1&i=<invite-id>&t=<token>&s=<wrapping-secret>` is accepted. Cold start and one warm event each produce one Join route; ordinary launches and duplicate events do not. | Coordinator/app/platform tests plus the Android integration target are required; neither universal links nor Android App Links are claimed. |
| Capability privacy | The full bearer URI is handed only to the OS share sheet and is absent from painted/semantic UI, logs, diagnostics, analytics, clipboard helpers, screenshots, persisted route state, and Supabase. | Automated redaction checks are necessary; a real capability must never be placed in QA artifacts. |
| Cloud privacy | Supabase contains identity, roster metadata, invitation state, recipient-email/token hashes, and an encrypted family-key envelope only. It never receives the wrapping secret, plaintext family/member keys, memory payloads, journals, reveal/kept content, transcripts, or media. | Inspect the live project after acceptance; a fake gateway cannot prove this boundary. |
| Offline behavior | Capture/browse work without cloud configuration or network. Invite/Join report the actual failure. Cached SQLCipher roster remains visible on refresh failure, and a successful refresh is durable before publication. Membership is append-only until removal/tombstone sync exists. | Exercise configured, unconfigured, offline, failed-refresh, successful-refresh, and restart states. |
| Mobile automation | CI runs `app/integration_test/family_invitation_flow_test.dart` on the existing Android x64 emulator and compiles an iOS debug simulator app after `Info.plist` lint. | A green CI run is required. The iOS build gate proves compilation/declarations, not runtime delivery or accessibility. |

`tools/audit_project.py` remains supplemental. Its source scan excludes Dart, so zero findings cannot be cited as proof of Flutter runtime behavior, link redaction, key handling, or complete invitation coverage.

### Emulator visual review

The invitation journey was captured twice through the Android integration driver in `app/outputs/family-invitations/pass-1` and `pass-2`: 22 non-empty PNGs per pass at a 390×844 logical viewport with 1.4× text. The cold-start acceptance path boots the real `KeepersApp`; the remaining QA states use focused `MaterialApp` and provider harnesses around the production screens. The manifest includes the local-only Wheel, unconfigured Invite, owner email and OTP, recipient entry, creating, pending, sharing, revoke failure, first-run Create/Join choice, manual Join, recipient email and OTP, preview, loading, keyboard-open, recoverable and protected failures, long content with reduced motion, and the post-acceptance Wheel. Join success is represented by the synchronized Wheel redirect; no artificial success screen or operating-system share sheet is captured.

Pass one exposed three production layout defects: the pending recipient label split, the bound-email failure was clipped, and the post-acceptance Legacy Lock shortcut truncated. The responsive detail row, join feedback region, and Wheel shortcut geometry were repaired and regression-tested. Pass two then exposed a remaining zero-gap detail alignment; an explicit 8 logical-pixel gap was added and the final capture confirmed the label, recipient address, expiry, protected failure copy, action geometry, and Wheel shortcuts remain readable without overlap. Keyboard-open evidence keeps the action reachable above the simulated inset, and reduced-motion states show stable bubbles rather than animated drift.

Both passes use inert fake-cloud capabilities generated inside the test harness. Before capture, the exact bearer token and wrapping secret are asserted absent from rendered text and semantics; the end-to-end path also checks secure storage and local SQLCipher state. The driver enforces an allowlisted, capability-free filename manifest. This does not constitute pixel-level secret scanning of the PNGs. These captures prove emulator composition and the credential-free harness only; they do not prove live Supabase, physical-device, or iOS behavior.

### Live acceptance evidence still required

A release-grade pass requires one migrated Supabase project and two physical devices built with the same project URL and publishable key. Record owner authentication and invitation sharing; recipient bound-email OTP and acceptance; the identical real roster on both phones; restart persistence; unused-invite revocation; expiry, replay, and wrong-email rejection; offline cached-roster behavior; and live inspection showing no memory plaintext or plaintext keys in Supabase.

Until those artifacts exist, live Supabase pgTAP/race execution, live OTP/RPC behavior, physical two-device acceptance, and iOS runtime/accessibility remain explicitly unpassed. Fake-gateway tests, Android emulator coverage, static platform checks, or an iOS simulator build must not be relabeled as that evidence. The QA screenshots are local, untracked evidence and contain no production capability.

final result: external acceptance pending
