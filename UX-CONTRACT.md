# Keepers UX Contract

## Product context

- Audience: multigenerational families using a private, offline-first memory ritual.
- Primary jobs: contribute privately, gather, reveal together, decide what to keep, and revisit kept history.
- Target market: global English-language sprint; no country-specific assumptions.
- Active locales: English UI; Unicode user content.
- Timezone/calendar policy: device-local display, UTC persistence as defined by the existing domain layer.
- Accessibility target: WCAG 2.2 AA principles adapted to Flutter mobile, with 48 logical-pixel interactive touch targets.

## Business-context sources

| Domain / scope | Authoritative source | Source type | Reviewed date |
|---|---|---|---|
| Privacy, keys, and entry visibility | `docs/KEEPERS_SPEC.md` | Product/domain specification | 2026-09-01 |
| UI flows and acceptance checks | `FABLE_UI_DIRECTIVE.md` supplied by the user | Approved UI directive | 2026-09-01 |
| Capture and vault behavior | `docs/superpowers/specs/2026-09-01-p0-03-capture-vault-design.md` | Maintained feature design | 2026-09-01 |
| Family codes, join requests, membership, and roster privacy | `docs/superpowers/specs/2026-09-07-family-code-join-requests-design.md` plus migrations `202609050001`, `202609070001`, and `202609070002`; the 2026-09-05 invitation contract remains compatibility-only | Maintained feature design + enforced database contract | 2026-09-07 |
| Deletion and retention | `docs/KEEPERS_SPEC.md` | Product/domain specification | 2026-09-01 |

## Visual contract

- Project design context: `DESIGN.md`.
- Token ownership: existing runtime canonical.
- Runtime source: `app/lib/theme/keepers_theme.dart`.
- Theme adapter: `app/lib/design_system/observatory/observatory_theme.dart`.
- Drift gate: theme/widget tests plus strict premium audit.
- Supported themes: every route and full-height capture surface uses the supplied `keepers-background-flat.png` canvas. Dark ritual colors remain inside memory and decision cards, except for the approved cold-launch brand sequence on `KeepersColors.ground`, which dissolves into the resolved route.

## Canonical UI Map

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Form | Existing setup and capture controllers | P0-03 design | setup / capture | widget + integration |
| Toast/status | Flutter `ScaffoldMessenger` at route scope | This contract | info / error | widget |
| CRUD | Riverpod capture/vault providers | KEEPERS spec + P0-03 design | capture / open | integration |
| Destination shell | `KeepersDestinationScaffold` + `KeepersBottomNav` | DESIGN + this contract | daylight / ritual | widget + emulator |
| Family code and sharing | `FamilyCodeController` + `FamilyInviteSheet` | 2026-09-07 family-code design | cached/offline / member sharing / creator regeneration | controller + widget + integration |
| Family join request | `FamilyJoinScreen` + `FamilyJoinController` | 2026-09-07 family-code design | manual code / verified link / authentication resume / pending / terminal / recovery | controller + widget + Android integration |
| Join-request approval | `FamilyJoinRequestsController` + `FamilyJoinRequestSheet` | 2026-09-07 family-code design | any-active-member approve / decline / concurrent resolution | controller + widget + database race |
| Family-link routing | `InviteLinkCoordinator` + root app navigation | 2026-09-07 family-code design + exact native URL declarations | cold start / warm event / deliberate reopen / ordinary launch | coordinator + app + platform-contract tests |
| Cold-launch sequence | `KeepersLaunchSequence` mounted by `KeepersApp` | DESIGN + current approved launch direction | full motion / reduced-motion bypass / tap skip | widget + golden + platform-contract tests |
| Family roster | `familyRosterProvider` + encrypted `FamilyRosterRepository` | accepted remote roster committed to SQLCipher | local-only / cached / refreshed | repository + provider + app tests |
| Archive filters | Shared archive `ChoiceChip` rails | This contract | person / theme | widget |
| Wheel gathering prompt | `FamilyWheelScreen` gathering prompt | persisted roster + presence state | nudge absent relatives / invite first relative | widget + emulator |
| Weekly experience | `FamilyWheelScreen` Weekly entry and `CeremonyScreen` playback | KEEPERS spec + this contract | five-photo-and-three-quarters-present locked / labeled local preview / reel | widget + emulator |
| Random memory draw | `ArchiveScreen` | KEEPERS F10 + this contract | kept-memory result / honest empty state | widget + emulator |
| Memory Key entries | `CeremonyScreen` Memory Key landing | KEEPERS spec + this contract | Legacy Lock / Capsule | widget + emulator |
| Legacy approval | Timed pointer-hold control | UI directive Screen 7 | two-second preview / future persisted approval | duration widget test |

## Component behavior

| Component | Default | Focus | Active | Disabled | Busy | Error |
|---|---|---|---|---|---|---|
| Member node | gradient identity rim | visible ring | 220 ms focus scale | dimmed | n/a | n/a |
| YOU profile node | black double-ring treatment | visible ring | opens owner-only history | quiet ring | stable geometry | owner list owns recovery |
| Current-profile avatar editor | Settings `Your identity` preview, name, `Edit avatar`, and chevron | labeled back, category, option, and save controls | local Humation draft across Head, Body, Bottom, Item, Glasses, and Colors | all editor controls disabled only while saving | one encrypted update; duplicate save blocked | inline `Your avatar could not be saved. Try again.` with Retry preserves the draft |
| Family code and invite sheet | quiet top-right code plus the Wheel Invite affordance | grouped-character semantics; focus returns to trigger | explicit Share link / Copy code / Copy link; creator-only Regenerate | unavailable while signed out, unconfigured, or another code operation owns the controller | stable loading/regeneration geometry; dismissal blocked during regeneration | cached authoritative code remains available offline; Retry never replaces a valid prior code with an uncommitted candidate |
| Requester join | paste-friendly code field or exact verified-link code | first invalid field or recovery action receives focus | sanitized family preview, profile confirmation, Request to join, then local install and Wheel reset | action disabled for invalid input, active membership, or in-flight work | stable checking/requesting/installing states with duplicate work blocked | neutral Family not found, pending Retry/Cancel, declined, expired, invitation-changed, wrong-account, and network recovery remain distinct |
| Join-request decision | slim Wheel notice and requester-only approval sheet | trigger/action focus restored after close or error | any active member approves or declines; first authoritative decision wins | both decisions disabled while resolving | fixed progress geometry; modal cannot dismiss mid-decision | authoritative refresh absorbs concurrent resolution without showing a false failure |
| Primary navigation | Wheel, Memory Key, centered `+`, Archive, Settings | visible icon focus | black current-destination dot | named as unavailable | stable full-width geometry | destination/capture owns recovery |
| Capture privacy control | Reveal selected on step two | visible radio focus | selected card | muted | stable geometry | inline text |
| Memory list | ordered kept history | focused row | open viewer | unavailable row labeled | reserved loader | inline retry |
| Wheel gathering prompt | after five-photo progress, above the Weekly panel | visible button focus | nudges named absent relatives, or opens Invite when the current member is alone | unavailable only while its current action is running | stable home composition | remain on Wheel with retry |
| Wheel weekly experience | progress counts same-week pending Weekly Reveal photos; the goal is five | visible button focus | real open requires both five photos and at least three quarters of the full family roster present, rounded up, then runs the pastel flood and reel | the locked panel shows a lock and may expose a separately labeled, non-mutating local preview; the eligible panel shows a gold-aura key | stable home composition | stay on Wheel |
| Archive random draw | kept-memory summary | visible button focus | one kept memory opens | empty vault remains enabled | stable archive composition | honest empty state in Archive |
| Memory Key Legacy Lock entry | family lock summary | visible button focus | opens Legacy Lock list | unavailable only when the destination cannot load | stable Key composition | remain on Memory Key with recovery |
| Memory Key Capsule entry | scheduled capsule summary or empty status | visible button focus | opens the available capsule detail | no scheduled capsule is stated honestly rather than hidden | stable Key composition | remain on Memory Key with recovery |
| Family task lock | named task and setter | visible approved action | pastel flood, then memory | no open action until approved | stable card | retain state label |

## Dataset navigation

- Archive uses a bounded render-all chronological list for the sprint, grouped by year and filterable by at least person and theme.
- Weekly progress counts only photo-format entries from the same week whose access is Weekly Reveal and whose reveal state remains pending; the target is five.
- Current-week entries never appear as browsable family/archive content. Their author may inspect them in the owner-only Your memories interface, where privacy and pending status remain explicit.
- Empty, filtered-empty, loading, and error states remain distinct and recoverable.

## Flow ledger

| Operation | Trigger | Pending | Success destination | Success feedback | Failure recovery | Focus outcome | Source ref |
|---|---|---|---|---|---|---|---|
| Capture | Tap the centered `+`, choose format/caption, then access | live waveform / stable two-step surface | originating main destination | contribution ring increases | inline retry/discard | centered `+` | Current user decision, 2026-09-02 |
| Browse own memories | Tap YOU | none | Your memories | all authored entries show privacy/status labels | owner-only empty/error state | Your memories heading | Current user decision, 2026-09-02 |
| Edit current-profile avatar | Settings → `Your identity` → `Edit avatar` | full-screen draft editor without global navigation; the six ordered categories are Head, Body, Bottom, Item, Glasses, and Colors | Settings after one encrypted save | Settings and the Wheel use the same saved Humation config | keep the draft and expose Retry after `Your avatar could not be saved. Try again.`; a dirty Back opens `Keep editing` / `Discard changes` | save returns focus to Settings `Edit avatar`; retry focuses Retry; the dirty-back dialog focuses its available recovery action | Humation avatar design, 2026-09-04 |
| View or share family code | Tap the top-right family code or Invite bubble | encrypted cache load followed by authoritative cloud refresh | family invite sheet remains contextual to Wheel | explicit Share/Copy action reports short success feedback | offline uses only previously authenticated encrypted material; Retry preserves an existing valid code | returns to the triggering code/Invite control | Family-code join-request design, 2026-09-07 |
| Regenerate family code | Creator taps Regenerate and confirms that the prior code/link and pending requests stop working | sheet remains fixed and cannot be dismissed while regeneration resolves | same sheet with the server-authoritative replacement | replacement becomes visible only after the cloud record is committed and cached | failure retains the previous code; code collisions retry at most five submissions | Regenerate or Retry | Family-code join-request design, 2026-09-07 |
| Request family membership | Enter a family code or open exact `https://join.keepers.app/f/<code>`; authenticate when required; confirm name/avatar; tap Request to join | checking / authentication / preview / requesting / pending remain in one resumable flow | pending waits for a member; approved installs locally before Wheel reset | accepted roster is durable before publication and the new avatar can arrive on Wheel | Retry preserves authoritative state; requester may Cancel only while pending; decline, seven-day expiry, and regenerated-code cancellation are explicit | invalid code field, recovery action, or Wheel after completion | Family-code join-request design, 2026-09-07 |
| Decide a join request | Any active member opens `Name wants to join` | Approve and Decline are both disabled during one serialized decision | request disappears after authoritative approval/decline; approved requester completes when online | requester sees the resulting state after authoritative refresh | concurrent first decision is accepted as truth rather than surfaced as an error | restored Wheel notice trigger or next pending request | Family-code join-request design, 2026-09-07 |
| Open member | Tap another member | none | Member page | route transition | remain on Wheel | member heading | UI directive Screen 3 |
| Gather family | Beneath the Wheel bubbles, tap `Ask [waiting names] to come`; when no relatives exist, tap `Ask family to come` | stable prompt | Wheel for a nudge; Invite for a one-person family | absent existing members are nudged by name, or the current member can invite their first relative | remain on Wheel and retry the same action | gathering prompt or Invite heading | Current user decision, 2026-09-05 |
| Run Weekly gallery | On the Family Wheel, reach five qualifying photos with at least three quarters of the full family roster present, rounded up, or use the separately labeled local preview | 560 ms reveal transition, then one selected memory at a time | contextual full-screen cream gallery | compact Close / title / `Rehearsal Mode` header; centered date; synchronized thumbnail rail; thumbnail tap or hero swipe crossfades selection in 160–180 ms; preview does not mutate counts or entry state | return to the Weekly panel and retry unlock | selected hero memory; final memory proceeds to Keep / Release | UI directive Screen 4 + approved Weekly cream gallery decision, 2026-09-06 |
| Draw random memory | In Archive with at least one kept entry, tap Draw a memory | selected-memory transition | encrypted memory viewer | one kept entry selected, avoiding immediate repeat | empty Archive keeps Draw disabled; otherwise return to Archive | opened memory or disabled Draw | KEEPERS F10 |
| Open task-locked memory | In Memory Key, open Legacy Lock and tap Open memory on an approved task | 560 ms pastel flood | assigned memory | only approved state exposes action | remain on task card | approved action | KEEPERS F11 |
| Keep/release | Swipe or accessible alternative | card remains visible | ceremony stack / Archive | seal or dated fade | retry in place | next card | UI directive Screen 5 |
| Browse archive | Archive destination | reserved loader | kept-only year timeline | stable filters | inline retry / clear filters | archive heading or opened memory | UI directive Screen 6 |
| Preview Legacy approval | Hold approval ring for two seconds | determinate ring | preview-approved state | inline seal state | release early to cancel | approval control | UI directive Screen 7 |
| Cancel/back | Back or explicit close | none | origin route | none | unsaved capture confirmation | originating node/card | P0-03 design |

## Navigation and responsive behavior

- Route titles use `{Screen} — Keepers` in platform route semantics where applicable.
- A cold process launch begins immediately with the supplied Keepers wordmark alone on the black `ground` field, using matching optimized native and Flutter assets so the handoff never exposes a blank frame. It then plays `Be present.`, `Be authentic.`, `Be bold.`, and `Be you.` in Modern Society with cream memory forms before dissolving into the already-resolved route. It runs once per app process, never on foreground resume, and a full-screen tap skips without changing routing state. Cold-link and local-identity resolution continue beneath it.
- The Family Wheel is the owning home route and the sole entry to the Weekly experience. Capture returns to the main destination that opened it; member and owner-memory interfaces are pushed detail routes. The family-code sheet is contextual to the Wheel and opens from either the top-right code or Invite bubble for every active member; only regeneration is creator-only. Join is an incoming contextual route and is never added to primary navigation.
- The first-run Wheel contains only the persisted current member plus Invite. Accepted or otherwise persisted family members use balanced stable radial anchors with no rendered orbit, connector, arc, guide, or trail. Beneath the bubbles, the order is five-photo Weekly progress, then the standalone `Ask [waiting names] to come` prompt, then the Weekly panel. The prompt nudges absent existing members; for a one-person family with no relatives, `Ask family to come` opens Invite. It is not part of the Weekly panel. Runtime surfaces never substitute sample relatives, demo roster entries, fabricated proximity, or fabricated contribution percentages.
- Only exact `https://join.keepers.app/f/<code>` URLs enter family-link routing. Cold and warm delivery open `FamilyJoinScreen.forCode`; the active route coalesces duplicate OS delivery while a later deliberate reopen remains valid. Malformed URLs inside that namespace show the neutral malformed Join state and unrelated or legacy `keepers://join` URLs are ignored. Android declares an auto-verified `/f/` App Link and both signed iOS entitlement files request `applinks:join.keepers.app`, while the separate `keepers://auth-callback` account-authentication route remains intact. Native routing code does not prove public verification: the shipping certificate fingerprint, Apple Team ID, association documents, HTTPS responses, and physical-device behavior remain release gates. Manual code entry remains available when the verified-link infrastructure is unavailable.
- The family title is the first content beneath the wordmark and sits immediately above the presence sentence and attendance marks. It is rendered in Title Case at a lighter interface weight to match the Wheel's tracked labels, while its accessibility label keeps the natural-case family name (for example, visible `Rahman Family`, announced `Rahman family`). It has no segmented underline or header-side count. The Wheel does not duplicate the kept total. Archive begins with one noninteractive `Kept Forever` strip showing the complete unfiltered total; its five pastel format marks remain decorative until real per-entry format totals are available.
- Every app-owned painted text surface uses the bundled Modern Society face and Title Case presentation. Size, weight, line height, and tracking remain role-specific. The four approved launch phrases retain sentence case exactly. Presented memories use Title Case without mutating stored content; editable fields preserve typed casing, and spoken accessibility labels remain natural-case.
- Only the family cluster pans and pinch-zooms. Scale is bounded to 0.85×–1.45× and pan remains bounded. Its authored identity position begins 16 logical pixels beneath the attendance row so the family opens near the visual center. Opening capture, the current member's memories, or another member resets the family-field transform first, so every return to Wheel opens unpanned and unscaled at that centered baseline.
- Every primary destination uses the same edge-to-edge white navigation bar in this order: Wheel, Memory Key, centered `+`, Archive, Settings. It extends through the bottom safe area and uses five equal hit regions, black iconography, and a small black current-destination mark; it has no capsule geometry, side margin, rounding, or shadow. The `+` opens the same capture flow from every main destination and never changes the selected route. Memory Key uses a key icon and is the sole owner of the Legacy Lock and Capsule entries; neither is duplicated on the Wheel or in primary navigation. Archive is the sole owner of Random memory, which is reachable at any time, draws only from kept entries, and disables Draw honestly when the kept vault is empty. Settings exposes real local identity, encryption-at-rest, and device motion-policy information without fake controls. Onboarding, capture, memory viewing, member detail, and ceremony playback retain their contextual back or close behavior. The Weekly entry appears only on the Wheel and its real Open action remains disabled until both five qualifying photos and at least three quarters of the full family roster are reported present, rounded up. The locked medallion uses a lock; once both gates are satisfied and the action is available, it switches to a softly glowing key. Until the proximity adapter exists, the local prototype may expose a clearly separate `Preview weekly experience` action there; it must leave photo progress, reported family presence, and entry lifecycle unchanged while keeping `Rehearsal Mode` visible throughout the seeded reel. Task-locked memories reached through Memory Key show their setter/approver and only expose Open memory after approval; Capsule presents its scheduled state or an honest empty state in Memory Key. The built-in task example is labeled `Preview Task`, and presence/task interactions must not claim real sync or persisted approval until those engines are implemented.
- Settings owns the current profile only. Its `Your identity` entry shows the saved avatar preview, member name, `Edit avatar`, and chevron, then pushes the full-screen profile editor without the global bottom navigation. Option selection changes only a local draft; save is explicit, and the successful config refreshes the same current-member avatar in both Settings and the Family Wheel.
- Each route owns one primary scroll surface. Safe areas and the virtual keyboard may not obscure actions.
- Important labels wrap; identity names ellipsize only where the full value remains in semantics.
- Every gesture-only action has an accessible semantics action or labeled non-gesture alternative without adding a competing camera-first button row.

## Overlays and feedback

- Flutter app-owned dialogs/sheets only; no platform-generic confirmation copy.
- Discarding an unsaved capture requires explicit Keep editing / Discard actions.
- Back from a dirty avatar draft requires the same explicit `Keep editing` / `Discard changes` choice. A successful avatar save returns to Settings; a failed save remains in the editor with its draft and Retry action intact.
- Routine status uses route-scoped `ScaffoldMessenger`; corrective errors stay inline.
- Reduced motion bypasses the Flutter cold-launch sequence on its first frame, freezes family-bubble drift, makes reset immediate, and replaces nonessential spatial travel with an opacity change of at most 100 ms. The shared background itself is static.
- Eligible reveal activation from its canonical owner uses the established 560 ms pastel flood where specified; reduced motion skips it and completes the action immediately. Moving Weekly to the Wheel, Random to Archive, and Legacy Lock/Capsule to Memory Key does not change their privacy, eligibility, approval, or proximity rules.

## Family-code authorization and privacy

- The code is a permanent family locator, not an authentication factor or encryption key. It is eight Crockford Base32 symbols and is stored in lookup form only as a SHA-256 hash. Its display material is encrypted with the 32-byte family key and cached only in encrypted form.
- Every active member can view/share the current code and corresponding verified HTTPS link. Only the family creator can regenerate it. Regeneration invalidates the prior code/link and cancels old-version pending requests, while already-approved requests remain completable.
- A signed-in account with no current membership can preview only the family name and sanitized roster avatars, then submit one request. Possession of a code never exposes memories and never grants membership. The first release enforces one family per account and pending requests expire exactly seven days after creation.
- Any active member can approve or decline. The approving device encrypts the family key through X25519, HKDF-SHA-256, and AES-256-GCM to the requester's dedicated joining public key. Supabase receives public keys and ciphertext, never the joining private key, shared secret, or plaintext family key.
- The requester installs family/member keys, family row, roster, identity binding, and an exact completion marker locally before the completion RPC activates membership. Restart, resume, and reconnect reuse the same proposed member/key and recover an uncertain completion idempotently. A switched account cannot consume or delete another account's joining material.
- Plaintext family codes and full join URLs are permitted only at the explicit entry, clipboard, and operating-system share boundaries. They must not enter analytics, crash reports, API/proxy logs, diagnostics, screenshots, route restoration, or persistent display state. Errors and object diagnostics remain redacted.
- Account email sign-in and `keepers://auth-callback` remain separate authentication infrastructure. Email no longer addresses or transports a new family invitation. The legacy recipient-email invitation RPCs remain callable temporarily only for older app versions.
- PostgreSQL enforces per-account/family quotas and neutral cooldown behavior. A separately verified production ingress throttle by source IP and a privileged resolved-request purge schedule are mandatory release gates, not client features.

## Async and resilience

- Encrypted save is pessimistic: success appears only after blob finalization and SQL insertion.
- Duplicate saves are blocked by the existing capture controller.
- Avatar save is likewise pessimistic: controls are disabled while its one encrypted repository update is in flight, repeat activation cannot create a second update, and a recoverable failure preserves the complete draft for retry.
- Offline storage is canonical for memory content and is the durable roster cache. Capture and browsing continue without Supabase configuration or network access. Invite and Join instead expose honest configuration/network errors and never imply remote completion.
- A roster refresh publishes only after its remote members have been upserted into SQLCipher. Refresh failure leaves cached members visible. This sprint's membership sync is append-only; removal and tombstones are explicitly out of scope.
- Family joining is pessimistic and stage-specific. Duplicate code load, authentication, preview, request, approve/decline, install, complete, refresh, share, and regenerate actions are blocked while in flight. A cached authoritative code may remain visible through an ordinary network failure; an uncommitted candidate never becomes display state. Pending/approved state survives missed Realtime and process restart through authoritative refresh plus the exact completion marker.
- The current Weekly adapter on the Family Wheel reports only the current member as present until the planned proximity service supplies trusted family presence. The real two-condition gate therefore cannot unlock for a multi-person family by default or imply proximity that was not detected. The required count is `ceil(full family roster × 0.75)`, including the current member. Its separate opt-in local preview enters only the seeded rehearsal and does not alter photo progress, presence, or entry lifecycle, or expose current-week family payloads.
- Failed capture preserves safe input and exposes retry/discard through the capture surface.

## Validation

- Existing Riverpod controllers own validation and error mapping.
- Validate on explicit action, then while correcting an errored field.
- Family-code input ignores ASCII spaces and hyphens, normalizes case, accepts paste, and rejects ambiguous or malformed symbols locally. Invalid, unknown, throttled, and superseded lookup outcomes expose the same neutral Family not found state. Account-email validation remains owned by the separate authentication flow.
- Non-sensitive profile input survives recoverable failures. The proposed member ID and joining key are reused for matching retries; plaintext capture, code, link, family-key, and completion-marker cleanup follow their respective security contracts.

## Verification

- Required repository gates: Dart format, Flutter analyze, focused family-code/controller/widget/platform tests, full Flutter tests, executable Supabase pgTAP plus two-session races, the three-installation family-code integration harness, Android build/run, and two visual-review passes for every new state.
- Matrix: 390×844 and 430×932 phones, normal and 1.4× text, normal and reduced motion, code loaded/offline, noncreator and creator invite sheets, regeneration confirmation, manual entry, verified-link entry, preview, pending/cancel, approval/decline, expiry, invitation-changed, network recovery, and installed-avatar arrival.
- Canonical sibling flow: existing capture/vault providers and `StartupGate` routing.
- Fake gateways, widget tests, static native-file checks, and `tools/audit_project.py` are supplemental evidence only. The audit scanner does not cover Dart and therefore cannot certify Flutter runtime behavior or secret handling by itself.
- Production acceptance requires all three migrations on one live Supabase project and at least two physical Android devices built from the same source/configuration. Evidence must cover manual code and HTTPS link entry; signed-out authentication/resume; any-member approval; requester offline during approval; foreground/background/process death/device restart; regeneration while pending; decline/cancel/seven-day expiry; wrong-account recovery; exactly one active membership; and the same roster on both phones. Cloud and local diagnostics must be inspected for forbidden plaintext.
- External launch gates are a configured daily resolved-request purge with the approved retention cutoff, a verified API-gateway/WAF per-IP throttle, real Android release signing, hosted no-redirect `assetlinks.json`, an Apple Team ID/distribution signature plus hosted AASA, app-not-installed/store fallback, iOS runtime/accessibility acceptance, and a trusted release proximity source.
- At this checkpoint, migrations `202609050001`, `202609070001`, and `202609070002` plus the mobile auth callback bridge are deployed and verified. PostgreSQL concurrency execution, purge scheduling, IP throttling, production signing/domain association, two-physical-phone behavior, iOS runtime/accessibility, and release proximity remain explicitly unpassed. Focused unit/widget tests, fake gateways, emulator screenshots, static native declarations, or a debug-signed Android artifact cannot be relabeled as that evidence. Manual code entry remains the fallback when verified HTTPS association is unavailable.
