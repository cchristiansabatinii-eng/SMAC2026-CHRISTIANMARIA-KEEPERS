# AI usage log

This log is competition evidence. Add an entry whenever an AI tool contributes to product decisions, code, design, documentation, tests, research, or media.

## Rules

- Record prompts during the work; do not reconstruct them at submission time.
- Never include family content, credentials, encryption keys, personal data, or unpublished secrets.
- Summarize long outputs, then link to the reviewed artifact or pull request.
- Record what a human checked and changed. AI output is not accepted until it is reviewed.
- Use sequential IDs: AI-001, AI-002, and so on.

## Entry template

### AI-NNN — Short title

- **Date/time:** YYYY-MM-DD HH:MM TZ
- **Tool/model:**
- **Backlog ID:**
- **Prompt:**

> Paste the project prompt or a faithful redacted version.

- **Output used:**
- **Human verification:**
- **Changes after review:**
- **Evidence:** Pull request, commit, issue, test output, or meeting-minutes link
- **Data sent externally:** None / describe only non-sensitive labels or metadata

---

## AI-001 — Phase 0 repository spine

- **Date/time:** 2026-08-31, Asia/Dubai
- **Tool/model:** OpenAI Codex
- **Backlog ID:** P0-01
- **Prompt:**

> Read KEEPERS_SPEC.md and the current repository structure. Execute the first task in the plan, build the necessary files, and ask for confirmation before moving to the next task.

- **Output used:** CI workflow, documentation index, meeting-minutes template, this AI-usage log, implementation backlog, issue form, and pull-request template.
- **Human verification:** Pending team review on the Phase 0 pull request.
- **Changes after review:** Pending.
- **Evidence:** Branch chore/phase-0-repo-ci-docs and its pull request.
- **Data sent externally:** Repository specification and non-sensitive repository metadata only.

---

## AI-002 — Flutter, Riverpod, and encrypted storage scaffold

- **Date/time:** 2026-08-31, Asia/Dubai
- **Tool/model:** OpenAI Codex
- **Backlog ID:** P0-02
- **Prompt:**

> Create the app.

- **Output used:** Flutter-generated Android/iOS scaffold, Riverpod root providers, SQLCipher database opener, secure database-key storage, normalized v1 schema, initial UI, platform hardening, and automated tests.
- **Human verification:** Pending team review on the stacked P0-02 pull request; GitHub Actions runs analyze and tests.
- **Changes after review:** Pending.
- **Evidence:** Branch feat/p0-flutter-riverpod-storage and its pull request.
- **Data sent externally:** Public package metadata, repository specification, and non-sensitive source code only.

---

## AI-003 — Post–August 31 AI-assistance reconciliation

- **Date/time:** 2026-09-09 02:18 +04:00, Asia/Dubai (reconciliation recorded; not a historical work-event timestamp)
- **Tool/model:** OpenAI Codex; specific historical model/version details are not recorded in this repository.
- **Backlog ID:** Multiple — P0-03, account and family onboarding, weekly family sync and reveal, Capsule, archive and Observatory, launch, conversation sparks, hardening, CI, and documentation.
- **Prompt:**

> Reconcile this log using authentic Git metadata, the current date, and existing repository evidence. Do not invent or backdate events, and do not claim prompts or evidence that cannot be substantiated.
>
> This is the current reconciliation instruction, not a reconstruction of the historical implementation prompts. A complete contemporaneous prompt record for work after 2026-08-31 is not present in this repository.

- **Output used:** As of this entry's timestamp, the submission branch's Git metadata records 180 commits authored as `Codex`, from 2026-09-01 01:22:02 +04:00 through 2026-09-09 02:02:17 +04:00. Their commit subjects and checked-in artifacts cover the encrypted capture and storage flow; account and family-code onboarding; encrypted family coordination and Weekly Reveal; Capsule task unlocks; archive, Observatory, and navigation work; launch branding; local conversation sparks; tests, CI, and documentation.
- **Human verification:** The repository does not contain a complete contemporaneous, per-session human-review record for this period, so this entry does not assert one. The authentic history preserves subsequent corrections, tests, and review material, while pull request #4 remains the source of truth for the current verification status and any outstanding gates.
- **Changes after review:** Per-prompt changes cannot be reconstructed reliably from the retained evidence. Later fixes and reversions remain visible in the authentic commit graph; this reconciliation does not rewrite or backdate them.
- **Evidence:** [Pull request #4](https://github.com/cchristiansabatinii-eng/SMAC2026-CHRISTIANMARIA-KEEPERS/pull/4); [first recorded Codex-authored commit after August 31](https://github.com/cchristiansabatinii-eng/SMAC2026-CHRISTIANMARIA-KEEPERS/commit/b9d57b7c21455451e0e5e0c2f2b7bd925cb9258a); [latest commit at reconciliation time](https://github.com/cchristiansabatinii-eng/SMAC2026-CHRISTIANMARIA-KEEPERS/commit/fcb3c027ec78d155a0def81f957d4f43f2cf9630); [repository overview](../README.md); [design context](../DESIGN.md); [UX contract](../UX-CONTRACT.md); [Flutter tests](../app/test/); [database tests](../supabase/tests/); and [CI workflow](../.github/workflows/ci.yml).
- **Data sent externally:** OpenAI Codex processed repository source, tests, documentation, and task instructions for the work summarized above. This repository does not retain a complete per-session data-transmission inventory for the period, so this entry makes no narrower claim.

---

## AI-004 — Submission-gate diagnosis and repair

- **Date/time:** 2026-09-09 05:11 +04:00, Asia/Dubai
- **Tool/model:** OpenAI Codex; the exact model/version is not recorded in this repository.
- **Backlog ID:** SMAC 2026 submission verification
- **Prompt:**

> Resume the submission work after the GitHub account upgrade. Conserve the remaining GitHub Actions allowance, complete every locally available gate, diagnose the current CI failures from their exact logs, and push one consolidated correction without rewriting history or fabricating dates.

- **Output used:** Diagnosis of GitHub Actions run #20 attempt 2; mobile-workflow contract tests; independently executable Android emulator commands; a deterministic, bounded, verbose iOS simulator smoke with failure diagnostics; and pgTAP fixture, RLS-observability, cooldown-isolation, and top-level data-modifying CTE corrections.
- **Human verification:** The repository owner authorized continuation and a final push. Detailed human review of these corrections remains pending; automated local verification and final CI are the acceptance evidence.
- **Changes after review:** An independent code-review pass confirmed the database-test corrections preserve the intended authorization and cooldown behavior. The Android and iOS workflow changes were developed with failing-then-passing contract tests based on the runners' observed behavior and Flutter 3.47.2's local device-launch implementation.
- **Evidence:** [Pull request #4](https://github.com/cchristiansabatinii-eng/SMAC2026-CHRISTIANMARIA-KEEPERS/pull/4); [GitHub Actions run #20](https://github.com/cchristiansabatinii-eng/SMAC2026-CHRISTIANMARIA-KEEPERS/actions/runs/34285478122); [CI workflow](../.github/workflows/ci.yml); [database tests](../supabase/tests/); and [Flutter CI contract tests](../app/test/ci/).
- **Data sent externally:** OpenAI Codex processed non-secret repository source, test code, workflow configuration, and CI logs. GitHub Actions processed the pushed repository revision. No credentials, encryption keys, family content, or unpublished secrets were included intentionally.
