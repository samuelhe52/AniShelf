# 013 — Curated decision records: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-10-07 | Inventory OpenSpec, development docs, installed skill, and memory | Maintainer request; local revision `1b5b5d6` |
| 2026-10-07 | Backfill twelve feature/fix/proposal topics and this migration record | [Index](../README.md) |
| 2026-10-07 | Preserve 23 source files and their task/requirement history | [Inventory](migration-inventory.md), [manifest](migration-manifest.json) |
| 2026-10-07 | Replace repository workflow guidance for both agents | `AGENTS.md`; `CLAUDE.md` is its existing symlink |
| 2026-10-07 | Remove migrated originals, OpenSpec directory, five Claude skills, and OPSX commands | Source coverage verified before deletion |
| 2026-10-07 | Maintainer removes five Codex OpenSpec skills | Verified absent; `anishelf-release` retained |
| 2026-10-07 | Audit fixes and project-owned skill rewrite | [002](002-audit-and-skill-rewrite.md) |

## Outcome and current state (as of 2026-10-07)

`docs-ai/` organizes substantial product and architecture decisions, implementation
outcomes, detailed contracts, and historical sources. Plans reconstructed from
past work say so explicitly. Recovered motives distinguish discussion memory from
source corroboration and implementation inference. The reusable package proposal
remains Planned with all staged tasks unchecked and no completion action record.

`AGENTS.md` directs both agents to the installed `write-ai-doc` skill and the
AniShelf-specific [workflow](../workflow.md). Public guides, images, root READMEs,
privacy policy, asset instructions, and release guidance keep their existing homes.

## Deviations from plan

The migrating session could not write `.agents/skills/write-ai-doc/SKILL.md` (a
protected path), so it left a proposed replacement in this folder. The maintainer
later installed it; the review in [002](002-audit-and-skill-rewrite.md) then
replaced it and removed the proposal copy.

The original `openspec/` directory, moved development documents, five Claude
OpenSpec skill directories, and `.claude/commands/opsx/` were removed after source
coverage passed. Public documents remain in place.

A deletion patch against `.codex/skills/openspec-apply-change/SKILL.md` was also
rejected by the protected-path permission policy. The maintainer subsequently
removed all five `.codex/skills/openspec-*` directories, and the follow-up check
confirmed they are absent. The unrelated release skill was preserved. OpenSpec
data, commands, and project-local skills are now fully removed.

## Validation

The migration checker compares original source hashes against revision `1b5b5d6`,
destination hashes, permitted link relocations, requirement/scenario/task counts,
local links, cited commits, and maintained source paths. All 23 input files have
destinations. The adaptive list retains 47 checked tasks, recovery retains 11
checked tasks, and the package proposal retains all of its unchecked staged tasks.
The final checker found no errors across 114 local links and 62 commit references;
maintained source paths resolve. `git diff --check` passed, and separate no-index
whitespace checks passed for new maintained files. The proposed skill replacement
passed the skill-creator frontmatter/scaffold validator. Historical source formatting
was retained rather than rewritten to hide its original presentation.
No app code changes, app tests, simulator launches, or CloudKit probes are part of
this documentation migration. Historical reports are preserved as dated claims.

## Open questions

None for the migration itself. Per-entry uncertainties remain in the individual records.
