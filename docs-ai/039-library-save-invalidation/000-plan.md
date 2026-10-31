# 039 — Library membership changes drive save refreshes

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-31 |
| Origin | Maintainer redirected the open-inspector delay fix from inspector gating to save classification. |
| Related | [023 display cache](../023-library-display-cache/000-plan.md), [021 earlier investigation](../021-mac-selection-model/002-hidden-inspector-work.md) |

## Background

`LibraryStore` discards the identifiers delivered by `ModelContextSaveObserver`
and refetches its entire visible library after every save. Replacing `library`
invalidates each window's display projection. Detail saves also bump
`libraryRevision`, which the inspector candidate observes, restarting its task.
An unchanged-response guard does not help when fetched metadata actually changes.

## Goals

- Classify saves before fetching: entry insertion/deletion, visibility/identity
  changes, and changed duplicate-winner inputs refresh membership. Unrelated
  detail, staff, character, and progress saves do not.
- Keep row-visible edits live through Observation, including unsaved edits.
- Preserve explicit remote-import/restore refresh boundaries and verify
  background-context membership updates, including hidden-to-visible changes.
- Synchronize the inspector for a changed selection or an actually replaced
  selected entry object, without a global revision dependency.
- Remove the 120 ms delay, selection cancellation hook, and suspend/resume
  state. Retain stale-result rejection with the simplest session lifecycle.
- Preserve hidden-inspector gating, row extraction, and unchanged-response guard.
- Keep the staff-jobs graph repair and its regression independently reviewable
  as a separate commit-sized change; do not commit either change.

## Approach

Record membership identities for every visible candidate, including duplicates,
when membership is fetched. Use changed identifier entity names to exclude child
models without resolving them. Resolve only updated entry IDs; detect entries
that became visible even when absent from the baseline. Compare duplicate
ranking inputs only while visible duplicates exist. Coalesce actual membership
changes during existing deferred-save scopes.

Consider container provenance so unrelated model stores cannot invalidate this
store. Keep the existing explicit import/reconstruction boundaries: these also
cover replay-style child writes that do not stamp the local tracking clock.
Check their source and regression behavior rather than assuming main-context
Observation sees all background changes.

The inspector observes the selected entry's object identity from the display
items. Metadata mutation of that same object must not recreate its session.

## Alternatives and decisions

| Choice | Reason |
| --- | --- |
| Changed IDs plus membership baseline | Save notifications expose IDs, not changed fields; a small baseline distinguishes visibility/identity changes from tracking or metadata edits. |
| Preserve Observation invalidation | Row-visible changes still need fresh snapshots; avoiding membership refetch must not freeze display values. |
| Remove inspector debounce and global revision key | They do not remove the save-triggered full-library work and introduce a feedback path. |
| Measure before further threading changes | Background persistence and off-main preparation remain out of scope until residual costs are reported. |

## Validation and acceptance

Focused native tests must cover child-only saves, row-visible metadata/progress
changes, visibility and identity changes, entry insertion/deletion, duplicate
winner changes, and saves from background and unrelated contexts. Existing sync
import and metadata-writer tests must pass. Re-check session preservation and
stale-result rejection after removing suspend/resume machinery.

Build macOS and iOS. Profile the open inspector with an actually changed detail
response and report refresh/display work separately from detail preparation and
rendering. Identify fixture, build mode, sampling/timing method, and any
measurement limits. Do not implement background persistence or off-main
preparation in this task.

## Amendments

- Updated 2026-10-31: Review follow-ups added current-container filtering, a background-write display invalidation, and per-model applied-detail tracking — see [001-action.md](001-action.md#review-follow-ups-2026-10-31).
