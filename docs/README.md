# Keepers project documentation

This directory contains both historical planning artifacts and maintained delivery
and competition evidence. `KEEPERS_SPEC.md` preserves the original concept brief;
it is not the source of truth for the shipped architecture or behavior.

For the current implementation, use the checked-in app and backend sources together
with the [repository overview](../README.md), [app guide](../app/README.md),
[Supabase guide](../supabase/README.md), and [UX contract](../UX-CONTRACT.md).

| Artifact | Purpose |
|---|---|
| [KEEPERS_SPEC.md](KEEPERS_SPEC.md) | Historical original-concept brief; see its status note before using it |
| [implementation-board.md](implementation-board.md) | Issue-ready backlog derived from the implementation plan |
| [minutes/TEMPLATE.md](minutes/TEMPLATE.md) | Repeatable meeting record for decisions and rubric evidence |
| [evidence/p0-03-device-gate.md](evidence/p0-03-device-gate.md) | P0-03 encrypted-storage verification record and remaining physical-device gates |
| [superpowers/specs/](superpowers/specs/) | Approved feature-level design specifications retained with the implementation |
| [superpowers/plans/](superpowers/plans/) | Dated implementation plans for the major shipped workstreams |

## Working agreement

- Use short-lived branches and one reviewed pull request per focused change.
- Reference the backlog ID in branch names, pull requests, meeting minutes, and AI-usage entries.
- Keep family content, credentials, keys, and personal data out of issues, logs, and AI prompts.
- A phase is complete only when its applicable maintained acceptance gate has been demonstrated.
