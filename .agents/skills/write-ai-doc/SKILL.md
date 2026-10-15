---
name: write-ai-doc
description: Create and maintain curated AniShelf docs-ai/ records for substantial features and non-trivial, decision-shaping fixes (numbered entries with 000-plan.md before implementation and 001-action.md after). Do not use for reviews, audits, routine investigations, working notes, or status reports unless the maintainer explicitly asks for a docs-ai/ record.
---

# Write AI Doc

`docs-ai/` is AniShelf's curated product and design record, not a working-note log.
A numbered folder is reserved for a substantial feature or a non-trivial,
decision-shaping fix, each holding an RFC-like plan and an action log. Future humans
and agents use it to answer "why is it built this way?", so entries must be selected
deliberately and stay accurate against the code. Read `docs-ai/README.md` for the
index before starting.

Adapted from the `write-ai-doc` skill in
[onevcat/Prowl](https://github.com/onevcat/Prowl/blob/main/.claude/skills/write-ai-doc/SKILL.md).
This copy is project-owned: edit it in place, and do not reinstall it from upstream.

## When to write one

Create a new entry only when the work is either:

- a substantial feature with an enduring product or architecture decision (for example,
  a new UI surface, a sync or persistence mechanism, or a schema change);
- a non-trivial fix whose root cause, design decision, or resulting behavior must guide
  future implementation.

Do **not** create an entry merely because the work is detailed, takes time, or produces
useful findings. Skip reviews, code audits, routine research and debugging, status
reports, test runs, minor UI polish, formatting or dependency bumps, and docs-only
changes. The maintainer may explicitly request a record for an otherwise
non-qualifying task. When in doubt, do not write one.

## Workflow

### 1. New entry — plan first, before coding

1. Check the index for a related entry; an in-frame follow-up belongs there (section 2).
2. Pick the next number: `ls docs-ai/ | sort`, take the highest `NNN` + 1 (three digits).
3. Create `docs-ai/NNN-<kebab-slug>/000-plan.md` from the template below with
   status `Planned`. Write it as part of planning, not as an afterthought.
4. Implement the work within the user's authorization. A plan or this skill never
   authorizes a commit, push, or other remote mutation.
5. Write `001-action.md`: what actually happened, chronologically, with commit refs,
   the resulting key files, validation you actually performed, and deviations from
   the plan. Flip the plan status to `Implemented` only when the intended scope is
   complete; use `In progress` for partial delivery. When committing is authorized,
   commit the docs with the change.
6. Add or refresh the entry's row in `docs-ai/README.md`.

### 2. Follow-up on an existing entry (in-frame fix or extension)

1. Add the next-numbered file in the folder, for example `002-<topic>.md` (template below).
2. At the end of `000-plan.md`'s **Amendments** section append:
   `- Updated YYYY-MM-DD: <one line> — see [002-<topic>.md](002-<topic>.md)`.
3. If the follow-up invalidates part of the plan or action text, correct that text in
   place (keep it truthful) and note the correction in the amendment.
4. Work delivered in several slices: each slice adds its own `00N-<slice>.md`
   amendment, starting at `002`. Write `001-action.md` once, when the last slice lands
   (or the entry is superseded), summarizing the slices.

### 3. Large pivot / redesign

If the change replaces the entry's approach rather than patching it, open a NEW
numbered entry, cross-link both directions, and mark the old plan
`Superseded by [NNN-new-slug](../NNN-new-slug/000-plan.md)`.

## Templates

### 000-plan.md

```markdown
# NNN — <Title>: Plan

| Field | Value |
| --- | --- |
| Status | Planned \| In progress \| Implemented \| Superseded by <link> |
| Anchor date | YYYY-MM-DD |
| Origin | <who asked, or what triggered the work> |
| Related | [NNN-other](../NNN-other/000-plan.md), `docs/...` |

## Background
The product problem and its context; for a fix, the observed symptom.

## Goals
Bullets. Add a **Non-goals** subsection when scope exclusion is a real decision.

## Design / approach
The intended approach; name the key types and files it touches.

## Alternatives & decisions
| Choice | Reason and alternative |
| --- | --- |
Options considered and why the chosen one won. Record decisions, not just designs.

## Validation and acceptance criteria
What must be checked, and how (focused tests, simulator run, manual checks).

## Amendments
None yet.
```

### 001-action.md

```markdown
# NNN — <Title>: Action record

## Timeline
| Date | Change | Ref |
| --- | --- | --- |

## Outcome and current state (as of YYYY-MM-DD)
What exists in code now, followed by key source files as repo-relative paths.

## Deviations from plan
Where reality diverged from 000-plan.md, or "None known."

## Validation
Commands and checks actually run, with results. Omit nothing that failed.

## Open questions
Unverified claims, oddities worth revisiting, or "None."
```

### Amendment (002+)

```markdown
# NNN.00M — <Topic>

## Context
Why this follow-up happened.

## Change
What was decided and done, and any rejected alternative.

## Refs
Commits, files, tests. Add "## Current state" when useful.
```

## Writing rules

- English, factual, RFC-ish; prefer tables for timelines and decisions. Keep entries
  long enough to be useful and short enough to be read.
- Every repo-relative path you write must exist (verify before writing); label any
  proposed new path as proposed. Facts you can't verify belong under
  **Open questions**, not in prose.
- Never invent a rationale from code alone. If the reason for a choice is unknown,
  say so; if you infer it from the implementation, label it as inference.
- Do not state build or test results you didn't produce. Old passing tests and
  checked task lists are not fresh validation.
- Reference commits by short hash in backticks; dates come from Git. Cross-link
  sibling entries with relative links.
- Numbered files are history. **Non-numbered** files inside an entry folder (for
  example `006-.../broadcast-availability-policy.md`, `005-.../requirements/`) are
  living documents: update them in place when the contract they describe changes,
  and link them instead of duplicating their content. Files under `historical/`
  are preserved sources; do not edit them.
- A plan reconstructed after the work shipped must say so in its Origin field;
  never imply it preceded implementation. Such plans add an **Evidence and
  recovered rationale** section separating source documents, recalled discussion,
  and inference.
- `docs/` holds public tutorials and images; history, decisions, contracts, and
  runbooks belong in `docs-ai/`. Asset-package READMEs stay with their assets.
- AniShelf sources live in `MyAnimeList/Sources/` and `DataProvider/Sources/`. Use
  `AGENTS.md` for Makefile commands, test filters, simulator rules, and localization.
