# Keepers implementation board

This issue-ready backlog is derived from Section 5 of [KEEPERS_SPEC.md](KEEPERS_SPEC.md). Each ID should map to one GitHub issue and one focused pull request. Owners are role defaults, not permanent assignments.

## Status legend

- [ ] Ready
- [x] Implemented or in review

## Phase 0 — Spine (Days 1–2)

- [x] **P0-01 · Repository, CI, and evidence docs (R1)** — Configure analyze/test CI; add the canonical spec, meeting-minutes template, AI-usage log, and issue-ready backlog. **Acceptance:** the workflow is valid, documentation links resolve, and the pull request is reviewable.
- [ ] **P0-02 · Flutter scaffold, Riverpod, and encrypted schema (R2)** — Create the Flutter app under app/, wire Riverpod, and implement the Section 4.2 SQLCipher schema. **Acceptance:** app boots, schema migrations run, analyze/tests pass.
- [ ] **P0-03 · Capture flow v0 (R3)** — Capture photo, voice, and text entries into encrypted storage and display them in the personal vault. **Acceptance:** capture → store → display works for all three types.
- [ ] **P0-GATE · Two-device capture gate (All)** — Demonstrate capture → store → display on two physical devices, using iOS and Android when available.

## Phase 1 — Sync core (Days 2–5)

- [ ] **P1-01 · BLE presence (R1)** — Advertise and scan with the family UUID; display the present-member list.
- [ ] **P1-02 · Local session and ritual fallback (R1)** — Implement mDNS/TCP host and join, authentication handshake, and QR fallback.
- [ ] **P1-03 · Resumable TransferProto (R1)** — Transfer manifests and encrypted blob frames idempotently with resume support.
- [ ] **P1-04 · Ceremony state machine (R1 + R3)** — Implement ROLLCALL with quorum/reciprocity, EXCHANGE, REEL control frames, and synchronized haptics.
- [ ] **P1-05 · Reel player (R3)** — Render lockstep entry cards for every supported entry type.
- [ ] **P1-GATE · Offline three-phone ceremony (All)** — Three phones unlock and play one synchronized reel using airplane-mode Wi-Fi only.

## Phase 2 — Intelligence (Days 4–6)

- [ ] **P2-01 · On-device transcription benchmark (R2)** — Compare platform STT and Whisper for Arabic; record evidence and select one.
- [ ] **P2-02 · Embeddings and tags (R2)** — Add the ONNX embedding pipeline, theme tagging, and face clustering.
- [ ] **P2-03 · Vault resurfacing (R2)** — Match new reveal entries to eligible cross-vault kept memories and render an inline reel card.
- [ ] **P2-04 · Prompt service (R2)** — Add the offline template bank, optional online refinement, and AI-usage logging.
- [ ] **P2-GATE · Deterministic resurfacing moment (All)** — A scripted teen-anxiety entry reliably surfaces the seeded 1994 grandfather voice note.

## Phase 3 — Ceremony completeness and archive (Days 5–7)

- [ ] **P3-01 · Keeping engine (R1)** — Add votes, Keeper tie-breaks, replication, and 30-day expiry.
- [ ] **P3-02 · Keeper rotation and closing ritual (R3)** — Rotate the weekly Keeper and auto-keep the closing-question recording.
- [ ] **P3-03 · Archive and Draw (R2 + R3)** — Implement weighted Draw, On this day, person/theme views, Timeline, and Family Draw.
- [ ] **P3-04 · Locks, capsules, and memorial state (R3)** — Complete one human-approved Legacy Lock, one date capsule, waiting shelf, and memorial flag.
- [ ] **P3-05 · Cold-start import (R2, schedule-dependent)** — Scan the local camera roll for family photos without uploading content.
- [ ] **P3-GATE · Repeatable happy path (All)** — Run the full happy path twice consecutively without a restart.

## Phase 4 — Hardening and submission (Days 7–8)

- [ ] **P4-01 · Demo mode (R3)** — Seed family data, lock the resurfacing match, and document the rehearsal script.
- [ ] **P4-02 · Reliability pass (R1)** — Test kill/rejoin, low battery, Bluetooth off, and no-Wi-Fi hotspot recovery.
- [ ] **P4-03 · Submission package (All)** — Produce the 2–3 minute video, two-page description, and finalized AI-usage report.
- [ ] **P4-GATE · Submit (All)** — Submit the complete project before Tuesday, 8 September 2026.

## Demo prep — 9–15 September

- [ ] **D-01 · Rehearsal and Q&A (All)** — Complete at least 30 full runs on the exact demo devices, pack the travel router, and verify every team member can explain every module.

## Hosted GitHub board setup

The connected automation can manage repository files and pull requests but cannot create GitHub Project items or issues. To mirror this backlog in GitHub Projects, create one issue per ID using the implementation-task issue form, add fields for Phase, Owner, and Status, then group by Phase. Keep this file as the source of truth until that one-time UI setup is complete.
