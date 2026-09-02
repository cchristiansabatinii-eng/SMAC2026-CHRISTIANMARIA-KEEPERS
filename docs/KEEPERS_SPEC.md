# Keepers — Architecture & Implementation Spec

**Team:** k-of-n · **App:** Keepers · **Competition:** SMAC Summer 2026, Khalifa University
**Theme:** AI for Stronger Family Bonds · **Tagline:** *Every family has a keeper.*

**Deadlines:** Project submission **Tue 8 Sep 2026** (2–3 min video + 2-page description + GitHub) · Demo Day **Wed 16 Sep 2026**

---

## 1. Concept in one paragraph

Keepers is a family memory app whose weekly content is locked until the family physically gathers. Members deposit photos, voice notes, journal entries and recipes into personal vaults during the week; nothing is revealed until phones come together in the same room for the **Unlock Ceremony**, where the week is replayed as a synchronized multi-screen reel. AI's only job is to find the right family voice at the right moment — surfacing a grandfather's decades-old memory when a teenager logs the same fear today. At the end of each reveal the family decides together what is **kept** forever; everything else expires. Presence isn't a feature of the app — it's the price of admission.

**Design laws (every decision defers to these):**

1. **The lock is the transport.** Weekly entries never leave the author's phone until the phones are physically together. The lock is not a UI element — the data simply isn't there.
2. **The lock is on the present, not the past.** Only the current week is sealed. Everything ever *kept* is open to the whole family, always.
3. **No AI persona.** The AI never speaks in first person and never gives advice. The only voices in the app are the family's.
4. **Offline-first, serverless.** The entire core loop — capture, unlock, reel, keeping, archive — works with zero internet and zero backend. Replication happens in person.

---

## 2. Feature set (final)

| # | Feature | Priority |
|---|---------|----------|
| F1 | Personal Living Vaults — multimodal capture (photo, voice, text, scans, recipes); privacy tiers: Private Journal / Weekly Reveal / Capsule | **Core** |
| F2 | Automated Memory Structuring — on-device transcription; auto-tagging by theme, person, place, event (no emotion inference, no photo restoration) | **Core** |
| F3 | Touch Ritual / Proximity Unlock — BLE discovery + local Wi-Fi payload + shared passive NFC tag + QR fallback | **Core** |
| F4 | Reciprocity Gate — no contribution that week, no unlock | **Core** |
| F5 | Synchronized Family Reel — host-driven playback across all phones; adjacent handsets act as one continuous display | **Core** |
| F6 | The Keeper — rotating weekly role; runs the ceremony, breaks keeping ties | **Core** |
| F7 | Vault Resurfacing — semantic matching of current entries against the family's historical corpus, surfaced live during the reel | **Core — the win** |
| F8 | Live Discussion Prompts — context-aware, addressed to named people; offline fallback to a template bank | **Core** |
| F9 | Keeping Ceremony — collective vote at reel end; kept entries replicate to all devices; unkept entries expire in 30 days | **Core** |
| F10 | The Archive & The Draw — kept memories browsable by **Draw (weighted random)**, **On this day**, **By person**, **By theme**, **Timeline**; Family Draw mode during sessions; drawn memories can seed next week's reveal | **Core** |
| F11 | Capsule Tasks — a Capsule may name a specific real-world task; each family member confirms completion for themselves before that memory becomes available | Demo-quality: one full flow |
| F12 | Family Capsules — letters, recordings, and other memories shared from Memory Key immediately or after the recipient completes the optional task | Demo-quality: one full flow |
| F13 | Memorial State — deceased member's vault becomes read-only; their Capsules remain available under the same rules; no simulation, no generated content in their voice | Core (small) |
| F14 | Extended Family Bridge — reunion sync of missed highlights when distant relatives meet | Report only (same mechanic, different wrapper) |
| F15 | Cold-start import — on-device camera-roll scan pre-loads vaults with photos of family members | Should-have |

Explicitly excluded: photo restoration, emotion inference, distress detection/auto-triggered comfort content, CV-based task verification, TV casting, chatbots, feeds, streaks, remote content viewing of any kind.

---

## 3. Technology stack

| Layer | Choice | Why |
|---|---|---|
| Framework | **Flutter (Dart)** | One codebase for iOS + Android with three devs; mature plugins for every hardware feature we need. (If the team already knows React Native well, it's an acceptable substitute — decide day 1, never migrate.) |
| State management | Riverpod | Simple, testable, well-documented |
| Local DB | SQLite via `sqflite` + SQLCipher (encrypted at rest) | Offline-first, zero backend |
| Blob storage | App documents dir, AES-GCM encrypted files | Media too large for DB rows |
| Key storage | `flutter_secure_storage` (Keychain / Keystore) | Family key + device key |
| BLE presence | `flutter_blue_plus` (scan) + `flutter_ble_peripheral` (advertise) | Cross-platform discovery |
| Local network | `bonsoir` (mDNS/Bonjour) + `dart:io` TCP sockets | Payload transfer + reel sync |
| NFC | `nfc_manager` (passive tag read — both platforms) | The physical ritual |
| QR fallback | `qr_flutter` (render) + `mobile_scanner` (scan) | Session join that cannot fail |
| Speech-to-text | Platform STT (`speech_to_text`); evaluate whisper.cpp small for Arabic dialect quality | On-device, offline-capable |
| Face detection | Google ML Kit (`google_mlkit_face_detection`) | On-device person tagging |
| Embeddings | `paraphrase-multilingual-MiniLM-L12-v2` (384-d) via `onnxruntime` mobile | Arabic + English semantic matching, on-device |
| Generative prompts | Cloud LLM API when online; **template bank fallback offline** | Core loop must not depend on connectivity |
| CI | GitHub Actions — analyze + test on every push | Development evidence + hygiene |

Not used (documented as roadmap in the report): UWB (platform-restricted hardware), phone-to-phone NFC (dead on iOS), cloud backup, TV casting.

---

## 4. System architecture

```
┌──────────────────────────────────────────────────────────────┐
│  PRESENTATION (Flutter UI)                                   │
│  Vault · Capture · WaitingRoom · Ceremony · Archive/Draw ·   │
│  Memory Key / Capsules · Family Setup                        │
├──────────────────────────────────────────────────────────────┤
│  DOMAIN ENGINES                                              │
│  CeremonyEngine   — session lifecycle, roll call, reel state │
│  KeepingEngine    — votes, tie-break, replication, expiry    │
│  CapsuleEngine    — task gates, readiness, memorial state    │
│  DrawEngine       — weighted sampling, browse queries        │
│  KeeperRotation   — weekly role assignment                   │
├──────────────────────────────────────────────────────────────┤
│  INTELLIGENCE (all on-device unless noted)                   │
│  TranscribeSvc    — STT at capture time, one-shot            │
│  TagSvc           — themes (embedding similarity to seed     │
│                     vectors + rules), people (ML Kit faces + │
│                     local clustering), places/dates (EXIF)   │
│  ResurfaceSvc     — cosine similarity over local vector      │
│                     index, theme-filtered, cross-vault       │
│  PromptSvc        — cloud LLM when online / templates offline│
├──────────────────────────────────────────────────────────────┤
│  SYNC                                                        │
│  PresenceSvc      — BLE advertise/scan with family UUID      │
│  SessionSvc       — mDNS `_keepers._tcp` + TCP; Keeper's     │
│                     phone is host and source of truth        │
│  TransferProto    — length-prefixed frames: JSON control +   │
│                     encrypted blobs; resumable               │
│  RitualSvc        — NFC tag read / QR show+scan → session key│
├──────────────────────────────────────────────────────────────┤
│  STORAGE                                                     │
│  SQLite (SQLCipher) · encrypted blob store · vector index    │
│  (brute-force cosine — corpus ≪ 100k, no ANN lib needed) ·   │
│  secure keystore                                             │
└──────────────────────────────────────────────────────────────┘
```

### 4.1 Ceremony protocol (the heart of the app)

```
1. START    Keeper's phone taps the family NFC tag (or shows QR).
            Starts TCP host, advertises via BLE + mDNS.
2. JOIN     Member phones detect the BLE beacon → prompt → connect
            over TCP → challenge-response auth with the family key.
3. ROLLCALL Host verifies quorum (≥ configured k members present)
            and the Reciprocity Gate: each device reports its entry
            count for the week; any device with 0 joins as
            spectator-locked (sees the ceremony happening, not the
            content) until it contributes on the spot or sits out.
4. EXCHANGE Each device streams its week's entries (already
            encrypted) to the host. Host assembles the reel
            manifest, redistributes missing blobs to all devices.
            ← this is the moment the lock opens: the data arrives.
5. REEL     Host broadcasts control frames (show item N, play,
            pause). All screens advance in lockstep; synchronized
            haptic on unlock. ResurfaceSvc injects historical
            matches inline; PromptSvc injects named prompts.
            Side-by-side phones negotiate viewport offsets to act
            as one display.
6. KEEPING  Vote frames collected per entry; Keeper breaks ties.
            Kept entries + their transcripts/tags replicate to
            every device (this is also the backup strategy —
            n-way redundancy with zero servers).
7. CLOSE    Fixed final ritual: one question addressed to the
            eldest member present, recorded, auto-kept.
            Session summary → screens dim → "Put your phones down."
```

Failure handling: host loss → session aborts cleanly, nothing marked revealed (idempotent EXCHANGE means re-running is safe). Wi-Fi absent → any phone offers hotspot; QR carries the session credentials either way.

### 4.2 Data model

```
Family      id · name · familyKeyRef · quorum k · nfcTagIds[]
Member      id · familyId · name · role(adult/child/elder) ·
            birthDate? · memorialState(bool, date)
Device      id · memberId · publicKey · lastSeen
Entry       id · authorId · createdAt · type(photo/voice/text/
            scan/recipe) · privacyTier(journal/reveal/legacy) ·
            blobRef · transcript? · embedding(384f) ·
            tags[{kind: theme|person|place|event, value}] ·
            state(pending/revealed/kept/expired) · expiresAt?
Ceremony    id · date · keeperId · presentMemberIds[] ·
            reelManifest · closingQuestionEntryId
KeepVote    ceremonyId · entryId · memberId · vote
Capsule     id · authorId · targetId · contentEntryId ·
            optionalTask · state(locked/ready/opened)
DrawLog     entryId · memberId · shownAt        (feeds Draw weights)
```

### 4.3 Security & privacy model

- **Family key**: generated at family creation, distributed to new devices **in person via QR only**. Never leaves the family.
- **At rest**: DB via SQLCipher; media blobs AES-GCM with keys derived from the family key (HKDF, per-entry nonce). Private Journal entries additionally encrypted with a member-only key — unreadable to other family devices even after replication.
- **In transit**: TCP frames encrypted with a per-session key derived from family key + both-side nonces (libsodium secretbox).
- **Presence enforcement**: architectural, not cosmetic — weekly entries exist only on the author's device until EXCHANGE, which only occurs over the local link. There is no server to compromise and no remote path to the content.
- **AI locality**: transcription, tagging, embeddings, matching all on-device. The only optional network call is prompt generation, which sends theme labels — never entry content — and degrades to templates offline.
- **Q&A one-liner**: *"The lock isn't cryptography theatre — the data physically isn't on your phone until you're in the room."*

### 4.4 Intelligence details

- **Transcription** at capture time (one-shot, background). Language per entry (Arabic/English mixed households). Whisper-small on-device if platform STT proves weak on dialect; decide by day 3 benchmark.
- **Theme tagging**: cosine similarity of entry embedding against ~20 seed theme vectors (school, work, food, travel, loss, sport, faith, milestones…) + keyword rules; threshold → multi-label.
- **People tagging**: ML Kit face detection → local face-embedding clustering → user confirms cluster names once; corrections during the reel feed back into clusters.
- **Vault Resurfacing**: for each new reveal-tier entry, top-k cosine matches over *other members'* kept corpus, filtered to shared theme + minimum age (> 1 year old) so matches feel like time travel, not last week. Confidence floor; if nothing clears it, no card is shown (silence beats a bad match).
- **The Draw weighting**: `score = w₁·staleness(lastShown) + w₂·personOverlap(viewer) + w₃·calendarResonance(date) + w₄·noStoryAttached` → softmax sample. Start with hand-tuned weights; log DrawLog for tuning.
- **Prompts**: template bank organized by theme × relationship (30–40 hand-written prompts) as the offline floor; LLM refinement online. All LLM usage logged for the AI-usage report.

---

## 5. Implementation plan

Three developers: **R1 — Sync & Protocol**, **R2 — Intelligence & Data**, **R3 — UI/UX & Demo**. Everyone commits daily to `main` via short-lived branches + PR review by one teammate.

### Phase 0 — Spine (Days 1–2)
- [ ] Repo, CI (analyze + unit tests), issue board seeded from this spec, `docs/` with this file + meeting minutes template + AI-usage log *(R1)*
- [ ] Flutter scaffold, Riverpod wiring, SQLCipher schema from §4.2 *(R2)*
- [ ] Capture flow v0: photo + voice + text → encrypted store → vault list *(R3)*
- **Gate:** capture → store → display works on 2 physical devices (one iOS, one Android if available).

### Phase 1 — Sync core (Days 2–5) — *the critical path*
- [ ] BLE advertise/scan with rotating family-private member UUID; presence list implemented, physical Android/iOS matrix pending *(R1)*
- [ ] mDNS + TCP host/join; auth handshake; QR fallback *(R1)*
- [ ] TransferProto: manifest + blob frames, resumable *(R1)*
- [ ] Ceremony state machine: ROLLCALL (quorum + reciprocity) → EXCHANGE → REEL control frames; synchronized haptic *(R1 + R3)*
- [ ] Reel player UI: lockstep playback, entry cards per type *(R3)*
- **Gate:** 3 phones unlock together and watch a synchronized reel with airplane-mode Wi-Fi only. **This is demo-viable minimum — reach it before touching anything below.**

### Phase 2 — Intelligence (Days 4–6, overlaps P1)
- [ ] STT at capture + benchmark platform vs whisper for Arabic; pick one *(R2)*
- [ ] Embedding pipeline (ONNX) + theme tagging + face clustering *(R2)*
- [ ] Vault Resurfacing service + inline reel card *(R2)*
- [ ] Prompt template bank + online LLM path + usage logging *(R2)*
- **Gate:** a scripted teen-anxiety entry surfaces a pre-seeded 1994 grandfather voice note, live, reliably.

### Phase 3 — Ceremony completeness & Archive (Days 5–7)
- [ ] Keeping votes, tie-break, replication, 30-day expiry *(R1)*
- [ ] Keeper rotation + closing-question ritual *(R3)*
- [ ] Archive: Draw (weighted), On-this-day, By-person, By-theme, Timeline; Family Draw in-session *(R2 + R3)*
- [ ] One full Capsule flow with optional self-confirmed task, per-member readiness, and memorial flag *(R3)*
- [ ] Cold-start camera-roll import (if on schedule; else cut) *(R2)*
- **Gate:** full happy-path run-through end to end, twice in a row, no restarts.

### Phase 4 — Hardening & submission (Days 7–8)
- [ ] Demo mode: seeded family data, deterministic Resurfacing match, rehearsal script *(R3)*
- [ ] Reliability pass: kill/rejoin mid-session, low battery, Bluetooth off, no Wi-Fi → hotspot path *(R1)*
- [ ] Record 2–3 min video; write 2-page idea & functionality doc; finalize AI-usage report with prompts *(all)*
- [ ] **Submit before Tue 8 Sep** *(all)*

### Sep 9–15 — Demo prep
- ≥ 30 full demo run-throughs on the exact devices you'll use; travel router in the bag; Q&A drill — every member can explain every module, because the 25% Q&A will probe exactly the code you didn't write.

---

## 6. Demo script (3 minutes)

1. **Cold open** — three judges hold three phones, apart: *"This week: 11 entries. Locked."* Silence.
2. **The ritual** — phones brought together, NFC tag tapped. Synchronized haptic; all screens bloom at once.
3. **The reel** — a few real entries from a seeded week.
4. **The moment** — a teenager's nervous entry pauses the reel; a grandfather's 1994 voice note plays. Say nothing over it.
5. **Keeping** — the family (judges) votes one entry into forever; the rest will fade.
6. **Kicker** — a family member completes a Capsule task in Memory Key and opens the newly available memory. Screens dim: *"Put your phones down."*

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| BLE/mDNS flakiness on stage | QR join fallback; own travel router; 30+ rehearsals on the demo devices |
| Arabic STT quality | Benchmark day 3; pre-transcribed seed content for the demo either way |
| Multi-device sync bugs | Host-authoritative design; idempotent EXCHANGE; kill-and-rejoin tests in Phase 4 |
| Scope creep | Phase gates are hard: nothing from a later phase starts before the gate passes |
| iOS BLE peripheral limits (backgrounding) | Ceremony runs foreground-only by design — document as intentional |
| "AI generated your app" suspicion | Daily granular commits from all three accounts, meeting minutes in repo, complete prompt log — from day 1, not reconstructed |

---

## 8. Repository layout

```
keepers/
├── app/                    # Flutter project
│   ├── lib/
│   │   ├── ui/             # screens & widgets
│   │   ├── domain/         # ceremony, keeping, lock, draw engines
│   │   ├── intelligence/   # stt, tagging, resurfacing, prompts
│   │   ├── sync/           # presence, session, transfer, ritual
│   │   └── storage/        # db, blobs, keys, vector index
│   └── test/
├── docs/
│   ├── KEEPERS_SPEC.md     # this file
│   ├── minutes/            # dated meeting minutes (rubric evidence)
│   ├── ai-usage.md         # every prompt + what it contributed (required by rules)
│   └── personas.md         # wireframes & personas for the report
└── .github/workflows/ci.yml
```
