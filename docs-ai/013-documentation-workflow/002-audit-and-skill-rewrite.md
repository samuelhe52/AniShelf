# 013.002 — Migration audit fixes and project-owned skill

## Context

The maintainer asked Claude Code to audit the migration and review the skill
adaptation, both produced by Codex. The audit confirmed source coverage (all 23
manifest hashes, links, and cited commits) but found inaccurate or stale content,
missing topics, and a skill that had lost upstream structure.

## Change

Migration corrections (in place, per the amended correction rule):

- 001: timeline dates for `06fd2ca`, `6803b95`, `74c9b5d` corrected to 2026-05-30–31.
- 006: timeline now cites the reminder implementation and its
  airing-reminder replacement (`b479653`) instead of only a docs commit.
- 010 `design.md`: migration edits to the prerequisite wording now carry a dated
  header note and inline markers; manifest hash refreshed.
- 001–012 action records: repeated migration disclaimers removed; the index states
  the backfill limits once. Open questions now describe the topic, not the migration.
- `historical/README.md` files describe their own contents instead of one template.
- 013: stale "skill adaptation pending" state and session-permission narration corrected.

New records from recovered discussion memory, checked against Git:

- [003.003](../003-persistent-store-recovery/003-v279-schema-collision.md): the
  in-place `SchemaV2_7_9` redefinition behind the 1.93/1.94 launch crash. Filed as
  an amendment because that crash is what the recovery workflow replaced.
- [014](../014-multiselect-invariants/000-plan.md): multi-selection snapshot and
  gesture-mask invariants that refactors have broken.

Library identity disambiguation (`2fdd269`) and duplicate repair (`19ad920`) were
considered but not backfilled; no recorded rationale was found and none was invented.

Skill rewrite (`.agents/skills/write-ai-doc/SKILL.md`):

- Rebased on the upstream Prowl skill. Restored its templates (adjusted to the
  section layout the backfilled records use), its in-place correction rule,
  "when in doubt, do not write one", unverifiable facts under Open questions, the
  amendment line format, and the numbered-history versus living-document split.
- Replaced Prowl specifics (PR numbers, upstream ledger, `App/Sources` paths).
- Dropped migration-only rules from the everyday skill and kept a single rule for
  retrospective plans.
- Made the skill project-owned: removed `skills-lock.json` (its only entry pointed
  at `onevcat/Prowl`), so `npx skills update` can no longer overwrite it.
- `workflow.md` and `AGENTS.md` were aligned where they contradicted or misdescribed
  the skill. Their overlap with the skill is otherwise unchanged.

Rejected: keeping upstream unmodified with all AniShelf rules in `workflow.md`.
The adaptation was already substantial, and two diverging sources of truth were
what had produced the stale statements.

## Refs and validation

See [001-action.md](001-action.md) for the original migration checks. After these
changes, the migration checker was rerun: manifest hashes, local links, cited
commits, and current source paths.
