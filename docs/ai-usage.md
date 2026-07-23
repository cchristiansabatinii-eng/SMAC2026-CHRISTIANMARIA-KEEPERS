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
