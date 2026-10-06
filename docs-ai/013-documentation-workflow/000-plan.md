# 013 — Curated decision records: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-07 |
| Origin | Maintainer request in this session |
| Related | [Documentation index](../README.md) |

## Background

AniShelf's design history is split between OpenSpec, development documents under
`docs/`, Git history, and prior discussions. Code records the resulting behavior
but often omits the alternatives and reasons that led to it. The maintainer chose
Prowl's lighter `write-ai-doc` workflow and requested a project-wide migration.

## Goals

- Make `docs-ai/` the indexed home for substantial design decisions and their outcomes.
- Preserve existing requirements, plans, task completion, and unresolved work.
- Recover relevant decision rationale from prior discussions without presenting
  recollection or inference as independently verified historical evidence.
- Keep public tutorials and images under `docs/`.
- Remove project-local OpenSpec artifacts, commands, and skills after verifying migration coverage.
- Make the installed skill usable for AniShelf and both supported agents.

## Design / approach

Create concise numbered records for existing substantial features and fixes.
Mark reconstructed plans as retrospective and date all current-state summaries.
Retain source documents as historical attachments with a migration inventory and
hashes. A completed checklist is historical evidence, not a fresh test result.
Keep the reusable sync package proposal planned. Preserve detailed requirements
as topic references without requiring OpenSpec tooling.

Use repository guidance to define selection, plan/action/amendment handling,
validation, evidence provenance, and current documentation ownership. Adapt the
installed `write-ai-doc` skill while retaining its source attribution.

## Alternatives & decisions

- Keep OpenSpec alongside the new workflow: rejected by the maintainer's explicit
  request to switch the whole project and remove its project-local tooling.
- Delete old specifications after a short summary: rejected because detailed
  scenarios, unresolved decisions, and task history would be lost.
- Treat every historical plan as shipped: rejected because proposals and dated
  review findings have different evidentiary status.
- Backfill every commit: unnecessary. Select enduring design decisions and retain
  existing evidence; Git remains the record for routine changes.

## Validation and acceptance criteria

Verify every migrated source against its pre-migration hash, check the index and
local links, confirm cited commits and current source paths, inspect the final
diff, and run `git diff --check`. No app code changes are intended, so app builds,
simulator boots, cloud probes, and publication are unnecessary for this migration.
Report any filesystem permission restriction that prevents finishing local tooling changes.

## Amendments

- Updated 2026-10-07: Audit fixes, new backfilled records, and the project-owned skill rewrite — see [002-audit-and-skill-rewrite.md](002-audit-and-skill-rewrite.md).
