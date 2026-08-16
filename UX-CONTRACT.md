# Keepers UX Contract

## Product context

- Audience: multigenerational families using a private, offline-first memory ritual.
- Primary jobs: contribute privately, gather, reveal together, decide what to keep, and revisit kept history.
- Target market: global English-language sprint; no country-specific assumptions.
- Active locales: English UI; Unicode user content.
- Timezone/calendar policy: device-local display, UTC persistence as defined by the existing domain layer.
- Accessibility target: WCAG 2.2 AA principles adapted to Flutter mobile, with 44 logical-pixel important touch targets.

## Business-context sources

| Domain / scope | Authoritative source | Source type | Reviewed date |
|---|---|---|---|
| Privacy, keys, and entry visibility | `docs/KEEPERS_SPEC.md` | Product/domain specification | 2026-09-01 |
| UI flows and acceptance checks | `FABLE_UI_DIRECTIVE.md` supplied by the user | Approved UI directive | 2026-09-01 |
| Capture and vault behavior | `docs/superpowers/specs/2026-09-01-p0-03-capture-vault-design.md` | Maintained feature design | 2026-09-01 |
| Family invitations, membership, and roster privacy | `docs/superpowers/specs/2026-09-05-supabase-family-invitations-design.md` plus `supabase/migrations/202609050001_family_invitations.sql` | Maintained feature design + enforced database contract | 2026-09-05 |
| Deletion and retention | `docs/KEEPERS_SPEC.md` | Product/domain specification | 2026-09-01 |

## Visual contract

- Project design context: `DESIGN.md`.
- Token ownership: existing runtime canonical.
- Runtime source: `app/lib/theme/keepers_theme.dart`.
- Theme adapter: `app/lib/design_system/observatory/observatory_theme.dart`.
- Drift gate: theme/widget tests plus strict premium audit.
- Supported themes: every route and full-height capture surface uses the supplied `keepers-background-flat.png` canvas. Dark ritual colors remain inside memory and decision cards only.

## Canonical UI Map

| Capability | Canonical owner | Source of truth | Allowed variants | Verification |
|---|---|---|---|---|
| Form | Existing setup and capture controllers | P0-03 design | setup / capture | widget + integration |
| Toast/status | Flutter `ScaffoldMessenger` at route scope | This contract | info / error | widget |
| CRUD | Riverpod capture/vault providers | KEEPERS spec + P0-03 design | capture / open | integration |
| Destination shell | `KeepersDestinationScaffold` + `KeepersBottomNav` | DESIGN + this contract | daylight / ritual | widget + emulator |
| Family invitation forms | `FamilyInviteScreen` + `FamilyInviteController`; `FamilyJoinScreen` + `FamilyJoinController` | 2026-09-05 invitation design | owner / recipient / reauthentication recovery | widget + Android integration |
| Invitation link routing | `InviteLinkCoordinator` + root app navigation | invitation design + exact native URL declarations | cold start / warm event / ordinary launch | coordinator + app + platform-contract tests |
| Family roster | `familyRosterProvider` + encrypted `FamilyRosterRepository` | accepted remote roster committed to SQLCipher | local-only / cached / refreshed | repository + provider + app tests |
| Archive filters | Shared archive `ChoiceChip` rails | This contract | person / theme | widget |
| Memory Key modes | `CeremonyScreen` Memory Key landing | KEEPERS spec + this contract | weekly / random / family task lock | widget + emulator |
| Legacy approval | Timed pointer-hold control | UI directive Screen 7 | two-second preview / future persisted approval | duration widget test |

## Component behavior

| Component | Default | Focus | Active | Disabled | Busy | Error |
|---|---|---|---|---|---|---|
| Member node | gradient identity rim | visible ring | 220 ms focus scale | dimmed | n/a | n/a |
| YOU profile node | black double-ring treatment | visible ring | opens owner-only history | quiet ring | stable geometry | owner list owns recovery |
| Current-profile avatar editor | Settings `Your identity` preview, name, `Edit avatar`, and chevron | labeled back, category, option, and save controls | local Humation draft across Head, Body, Bottom, Item, Glasses, and Colors | all editor controls disabled only while saving | one encrypted update; duplicate save blocked | inline `Your avatar could not be saved. Try again.` with Retry preserves the draft |
| Owner invitation | recipient email + `Create invitation` | visible field/action focus | operating-system share sheet for one named recipient | unavailable when cloud configuration/session/ownership is invalid | stable progress with duplicate submission blocked | inline configuration, authentication, network, expiry, or revocation recovery; capability is never displayed |
| Recipient join | email + six-digit OTP inside the routed invitation context | error focus moves to the first field needing correction | acceptance commits local keys/membership/roster, then resets to Wheel | Continue remains unavailable until locally valid input exists | stable progress with duplicate submit/accept blocked | precise inline error; email mismatch focuses email and corrected OTP continues through the same flow |
| Primary navigation | Wheel, Memory Key, centered `+`, Archive, Settings | visible icon focus | black current-destination dot | named as unavailable | stable full-width geometry | destination/capture owns recovery |
| Capture privacy control | Reveal selected on step two | visible radio focus | selected card | muted | stable geometry | inline text |
| Memory list | ordered kept history | focused row | open viewer | unavailable row labeled | reserved loader | inline retry |
| Memory Key weekly | proximity status | visible button focus | pastel flood, then reel | real open stays disabled below two nearby devices; the local prototype may expose a separately labeled preview | stable card | stay on selector |
| Memory Key random | kept-memory summary | visible button focus | pastel flood, then one kept memory | empty vault remains enabled | stable card | honest empty state |
| Family task lock | named task and setter | visible approved action | pastel flood, then memory | no open action until approved | stable card | retain state label |

## Dataset navigation

- Archive uses a bounded render-all chronological list for the sprint, grouped by year and filterable by at least person and theme.
- Current-week entries never appear as browsable family/archive content. Their author may inspect them in the owner-only Your memories interface, where privacy and pending status remain explicit.
- Empty, filtered-empty, loading, and error states remain distinct and recoverable.

## Flow ledger

| Operation | Trigger | Pending | Success destination | Success feedback | Failure recovery | Focus outcome | Source ref |
|---|---|---|---|---|---|---|---|
| Capture | Tap the centered `+`, choose format/caption, then access | live waveform / stable two-step surface | originating main destination | contribution ring increases | inline retry/discard | centered `+` | Current user decision, 2026-09-02 |
| Browse own memories | Tap YOU | none | Your memories | all authored entries show privacy/status labels | owner-only empty/error state | Your memories heading | Current user decision, 2026-09-02 |
| Edit current-profile avatar | Settings → `Your identity` → `Edit avatar` | full-screen draft editor without global navigation; the six ordered categories are Head, Body, Bottom, Item, Glasses, and Colors | Settings after one encrypted save | Settings and the Wheel use the same saved Humation config | keep the draft and expose Retry after `Your avatar could not be saved. Try again.`; a dirty Back opens `Keep editing` / `Discard changes` | save returns focus to Settings `Edit avatar`; retry focuses Retry; the dirty-back dialog focuses its available recovery action | Humation avatar design, 2026-09-04 |
| Create/revoke family invitation | Tap Invite, authenticate with email OTP when required, enter one relative's email, then create/share or cancel | in-place authentication/create/revoke progress; duplicate actions blocked | Invite remains contextual; back returns to Wheel | OS share sheet opens without painting the capability; pending recipient/expiry stay visible | retry the failed stage without losing safe email input; unused invitation remains revocable | first invalid/recoverable field or corresponding Retry; share failure returns to Share again | Supabase family invitation design, 2026-09-05 |
| Accept family invitation | Open the exact `keepers://join` capability, enter bound email, request/verify six-digit OTP, then Continue | one-shot link ownership; in-place OTP/preview/accept/local-install progress | Wheel as a fresh root after durable local installation | accepted member roster is persisted and published; no invitation capability remains in navigation state | precise retry at network/auth/preview/accept/install stage; restart after remote commit performs completion only and never reclaims/reinstalls keys | email mismatch focuses email; OTP error focuses code; successful reset focuses Wheel | Supabase family invitation design, 2026-09-05 |
| Open member | Tap another member | none | Member page | route transition | remain on Wheel | member heading | UI directive Screen 3 |
| Run reel | Presence unlock or explicitly labeled local preview | convergence transition | Reel | host-controlled card advance; preview remains labeled `REHEARSAL MODE` | retry unlock | current reel card | UI directive Screen 4 + current prototype decision, 2026-09-04 |
| Draw random memory | Tap Random memory | 560 ms pastel flood | encrypted memory viewer / honest empty state | one kept entry selected, avoiding immediate repeat | return to Memory Key | opened memory | KEEPERS F10 |
| Open task-locked memory | Tap Open memory on an approved task | 560 ms pastel flood | assigned memory | only approved state exposes action | remain on task card | approved action | KEEPERS F11 |
| Keep/release | Swipe or accessible alternative | card remains visible | ceremony stack / Archive | seal or dated fade | retry in place | next card | UI directive Screen 5 |
| Browse archive | Archive destination | reserved loader | kept-only year timeline | stable filters | inline retry / clear filters | archive heading or opened memory | UI directive Screen 6 |
| Preview Legacy approval | Hold approval ring for two seconds | determinate ring | preview-approved state | inline seal state | release early to cancel | approval control | UI directive Screen 7 |
| Cancel/back | Back or explicit close | none | origin route | none | unsaved capture confirmation | originating node/card | P0-03 design |

## Navigation and responsive behavior

- Route titles use `{Screen} — Keepers` in platform route semantics where applicable.
- The Family Wheel is the owning home route. Capture returns to the main destination that opened it; member and owner-memory interfaces are pushed detail routes. Invite is a contextual owner route reached from the Wheel. Join is an incoming contextual route and is never added to primary navigation.
- The first-run Wheel contains only the persisted current member plus Invite. Accepted or otherwise persisted family members use balanced stable radial anchors with no rendered orbit, connector, arc, guide, or trail. Runtime surfaces never substitute sample relatives, demo roster entries, fabricated proximity, or fabricated contribution percentages.
- An exact `keepers://join?v=1&i=<invite-id>&t=<token>&s=<wrapping-secret>` opens Join on a cold start or one warm-link event. An ordinary launch reads no route, repeated delivery of the same capability produces no duplicate Join route, and a successful install removes Join from history before resetting to Wheel. The app has no manual invitation-URL field, universal-link claim, Android App Link claim, associated-domain claim, wildcard route, or web fallback in this sprint.
- The family title is the first content beneath the wordmark and sits immediately above the presence sentence and attendance marks. It is rendered in uppercase at a lighter interface weight to match the Wheel's tracked labels, while its accessibility label keeps the natural-case family name (for example, visible `RAHMAN FAMILY`, announced `Rahman family`). It has no segmented underline or header-side count. The Wheel does not duplicate the kept total. Archive begins with one noninteractive `KEPT FOREVER` strip showing the complete unfiltered total; its five pastel format marks remain decorative until real per-entry format totals are available.
- Every app-owned painted text surface uses the bundled Schibsted Grotesk face and uppercase presentation. Size, weight, line height, and tracking remain role-specific. Presented memories are uppercase without mutating stored content; editable fields preserve typed casing, and spoken accessibility labels remain natural-case.
- Only the family cluster pans and pinch-zooms. Scale is bounded to 0.85×–1.45× and pan remains bounded. Its authored identity position begins 16 logical pixels beneath the attendance row so the family opens near the visual center. Opening capture, the current member's memories, or another member resets the family-field transform first, so every return to Wheel opens unpanned and unscaled at that centered baseline.
- Every primary destination uses the same edge-to-edge white navigation bar in this order: Wheel, Memory Key, centered `+`, Archive, Settings. It extends through the bottom safe area and uses five equal hit regions, black iconography, and a small black current-destination mark; it has no capsule geometry, side margin, rounding, or shadow. The `+` opens the same capture flow from every main destination and never changes the selected route. Legacy Lock and Capsule remain visible contextual entries and are not duplicated in primary navigation. Memory Key uses a key icon. Settings exposes real local identity, encryption-at-rest, and device motion-policy information without fake controls. Onboarding, capture, memory viewing, member detail, and ceremony playback retain their contextual back or close behavior. The weekly action remains disabled until at least two nearby devices are reported. Until the proximity adapter exists, the local prototype may expose a separate `Preview weekly experience` action; it must leave the `1 of 2 devices` state unchanged and keep `REHEARSAL MODE` visible throughout the seeded reel. Random memory is available at any time and draws only from kept entries. Task-locked memories show their setter/approver and only expose Open memory after approval. The built-in example is labeled `PREVIEW TASK`, and presence/task interactions must not claim real sync or persisted approval until those engines are implemented.
- Settings owns the current profile only. Its `Your identity` entry shows the saved avatar preview, member name, `Edit avatar`, and chevron, then pushes the full-screen profile editor without the global bottom navigation. Option selection changes only a local draft; save is explicit, and the successful config refreshes the same current-member avatar in both Settings and the Family Wheel.
- Each route owns one primary scroll surface. Safe areas and the virtual keyboard may not obscure actions.
- Important labels wrap; identity names ellipsize only where the full value remains in semantics.
- Every gesture-only action has an accessible semantics action or labeled non-gesture alternative without adding a competing camera-first button row.

## Overlays and feedback

- Flutter app-owned dialogs/sheets only; no platform-generic confirmation copy.
- Discarding an unsaved capture requires explicit Keep editing / Discard actions.
- Back from a dirty avatar draft requires the same explicit `Keep editing` / `Discard changes` choice. A successful avatar save returns to Settings; a failed save remains in the editor with its draft and Retry action intact.
- Routine status uses route-scoped `ScaffoldMessenger`; corrective errors stay inline.
- Reduced motion freezes family-bubble drift, makes reset immediate, and replaces nonessential spatial travel with an opacity change of at most 100 ms. The shared background itself is static.
- Memory Key mode activation uses a 560 ms pastel flood over the full viewport; reduced motion skips it and completes the action immediately.

## Family invitation authorization and privacy

- Only the original family owner can create or revoke an invitation. The UI may hide owner-only actions, but Supabase row-level security and security-definer RPCs are the authorization boundary.
- Each invitation is bound to one normalized recipient email, expires after 24 hours, is usable once, and can be revoked only before acceptance. Repeated acceptance is idempotent for the same authenticated claimant and fails for everyone else. An existing local identity for another family fails without local mutation or family switching.
- Authentication is email OTP only. The client requests and verifies the six-digit token rendered by the Supabase `{{ .Token }}` template; it does not substitute a magic-link flow. The server-authenticated normalized email must match the invitation binding before preview or claim.
- The deep link is a bearer capability. Its token and device-to-device wrapping secret remain memory-only before claim and never enter logs, analytics, diagnostics, clipboard helpers, screenshots, or route restoration. Only the operating-system share sheet receives the full URI.
- Supabase may hold account identity, family roster metadata, invitation status, recipient-email/token hashes, and the encrypted family-key envelope. It never receives the wrapping secret, plaintext family/member keys, memory payloads, journals, reveal/kept content, transcripts, or media. The recipient member key is generated on the accepting device.
- Once profile submission reaches remote claim, name/avatar/member identity stay locked across reauthentication and retry so the original request is reused. After local installation, the encrypted pending-completion marker contains only the exact invite/family/account identity; restart or sign-in recovery performs completion and roster refresh only, never a second claim, unwrap, key generation, or installation.

## Async and resilience

- Encrypted save is pessimistic: success appears only after blob finalization and SQL insertion.
- Duplicate saves are blocked by the existing capture controller.
- Avatar save is likewise pessimistic: controls are disabled while its one encrypted repository update is in flight, repeat activation cannot create a second update, and a recoverable failure preserves the complete draft for retry.
- Offline storage is canonical for memory content and is the durable roster cache. Capture and browsing continue without Supabase configuration or network access. Invite and Join instead expose honest configuration/network errors and never imply remote completion.
- A roster refresh publishes only after its remote members have been upserted into SQLCipher. Refresh failure leaves cached members visible. This sprint's membership sync is append-only; removal and tombstones are explicitly out of scope.
- Invitation progress is pessimistic and stage-specific. Duplicate OTP, create, preview, claim, install, complete, refresh, share, and revoke actions are blocked while in flight; safe email/OTP corrections survive recoverable failures, while the link capability never becomes display state.
- The current Memory Key adapter reports one nearby device until the planned proximity service supplies trusted counts. The UI therefore cannot unlock Weekly recap by default or imply proximity that was not detected. Its opt-in local preview enters only the seeded rehearsal and does not alter presence state or expose current-week family payloads.
- Failed capture preserves safe input and exposes retry/discard through the capture surface.

## Validation

- Existing Riverpod controllers own validation and error mapping.
- Validate on explicit action, then while correcting an errored field.
- Invitation email is normalized consistently with the server contract. A recipient-email mismatch is announced as live inline feedback, focuses the email field, and allows a corrected address to request/verify OTP and continue through preview without reopening the link. OTP accepts the expected six digits and supports platform autofill/paste without storing the code beyond the active flow.
- Non-sensitive entered values survive recoverable failures; plaintext capture and invitation-capability cleanup follow their security designs.

## Verification

- Required repository gates: Dart format, Flutter analyze, focused invitation/controller/widget/platform tests, full Flutter tests, Android invitation integration on an emulator, iOS simulator build plus URL-plist validation, Android build/run, and emulator screenshots per screen.
- Matrix: 390×844 phone, 1.4× text, reduced motion, loading, empty, error, and successful interaction states.
- Canonical sibling flow: existing capture/vault providers and `StartupGate` routing.
- Fake gateways, widget tests, static native-file checks, and `tools/audit_project.py` are supplemental evidence only. The audit scanner does not cover Dart and therefore cannot certify Flutter runtime behavior or secret handling by itself.
- Production acceptance requires a migrated live Supabase project and two physical devices using the same `KEEPERS_SUPABASE_URL` and `KEEPERS_SUPABASE_PUBLISHABLE_KEY`. Evidence must cover owner create/share, recipient bound-email OTP, acceptance, identical roster on both devices, restart persistence, unused-invite revocation, expiry/replay/wrong-email rejection, cached roster while offline, and inspection confirming that no memory plaintext or plaintext key reached Supabase.
- Live pgTAP/race execution, live OTP/RPC behavior, two-device acceptance, and iOS runtime/accessibility review remain explicitly unpassed until their artifacts are recorded in `design-qa.md`; local automation cannot stand in for them.
