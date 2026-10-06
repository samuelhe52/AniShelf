# AniShelf decision-record workflow

Use `docs-ai/` to preserve decisions that future implementation depends on.
The project-owned `write-ai-doc` skill defines the plan/action/amendment workflow
and templates; this document adds AniShelf-specific selection and evidence rules.

## Select work deliberately

Create a numbered entry for a substantial feature or a fix with enduring product,
architecture, persistence, compatibility, or operational implications. Record the
reason and rejected alternatives when code alone would not explain the choice.
Skip routine debugging, reviews, test reports, minor UI polish, dependency bumps,
and docs-only edits unless the maintainer requests a durable record. This migration
explicitly retains existing reviews as feature evidence; do not use it as a reason
to archive every future review.

## Plan, implement, and reconcile

1. Read the index and amend an existing topic when the decision still fits it.
2. For a new topic, choose the next free three-digit number and kebab-case slug.
   Create `000-plan.md` before coding: background, goals, approach, alternatives,
   reasons, validation criteria, and unresolved decisions.
3. Implement within the user's authorization. A plan or skill does not authorize
   committing, publishing, or any remote mutation.
4. Write `001-action.md` after implementation: dated outcomes, key source paths,
   actual validation, deviations, and remaining uncertainty. Set the plan status
   to Implemented only when the intended scope is complete. Use In progress for
   partial delivery and Planned for proposals.
5. Add `002-<topic>.md` and later amendments for related follow-ups. Link them from
   the plan and index. For a major redesign, create a new entry and cross-link the
   superseded one. Multi-slice plans record each slice as an amendment and finish
   the aggregate action record when the final slice completes.

Use concise documents rather than a mandatory size quota. Keep long behavioral
contracts or runbooks in named reference files beside the plan; link instead of
copying the same content into every amendment.

## Record intent and evidence

- Explain what constraint led to each choice and why a plausible alternative was
  rejected. Do not fabricate an alternatives discussion from code alone.
- Label recovered discussion memory and distinguish it from source documents,
  commit messages, tests, or runtime observations. Link corroborating repository
  evidence. Mark reasoning inferred from implementation as inference.
- A retrospective `000-plan.md` must say it was reconstructed and give both the
  historical anchor date and reconstruction date. Do not imply it preceded coding.
- State uncertainty where it occurs. Unverified historical reasons remain open
  questions rather than becoming rules for all future work.
- Separate proposed behavior, implemented source, and actual runtime verification.
  Checked historical tasks and old passing tests are not fresh validation results.
- Existing source paths must exist in the checkout. Proposed new paths may be
  named when explicitly marked proposed. Historical paths are allowed only in
  clearly identified preserved sources with their original provenance.
- Keep records truthful. When a follow-up invalidates plan or action text, correct
  it in place and note the correction in the dated amendment. Named contracts and
  runbooks are living files and are updated in place; `historical/` sources are not edited.

## Documentation ownership

`docs/` contains public English/Chinese tutorials and images. Keep the root READMEs
and privacy policy in their public locations. `docs-ai/` contains internal design,
implementation history, contracts, and operational references. Asset-package
READMEs stay with their assets. The source-control release skill remains separate.

AniShelf sources are under `MyAnimeList/Sources/` and `DataProvider/Sources/`.
Use the repository Makefile, focused tests, localization policy, and simulator
rules from `AGENTS.md`; Prowl module names, fork ledgers, and source paths do not
apply. Use the actual current date in new records.

## Source and local adaptation

The skill at `.agents/skills/write-ai-doc/SKILL.md` (linked from `.claude/skills/`)
was adapted from
[onevcat/Prowl](https://github.com/onevcat/Prowl/blob/main/.claude/skills/write-ai-doc/SKILL.md)
and is project-owned: it has no `skills-lock.json` entry, so `npx skills update`
does not manage it. Edit it in place; do not reinstall it from upstream.
