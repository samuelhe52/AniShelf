# 011 — Parent-preserving library deletion: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-09-28 |
| Origin | Retrospective reconstruction on 2026-10-07; not a plan written before implementation |
| Related | [Selective sync deletion intent](../001-selective-library-sync/000-plan.md) |

## Background

Season entries use their parent series for display metadata. Deleting the
parent backing row while an unselected season survives can break the child's
name and relationship even though the user's intent was to remove the series
from the visible library.

## Goals

- Remove selected parents from the visible library without breaking surviving seasons.
- Distinguish hide/upsert from actual deletion/tombstone.
- Keep batch deletion and save-failure rollback coherent.

## Design / approach

`LibraryRepository.deleteEntries` computes selected and surviving child IDs.
Hide a selected series when any child is unselected; hard-delete the rest.
Only actual deletions get deletion records; hidden parents save display state
through ordinary change recording.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Hide parents with surviving seasons | Child display metadata still depends on that row. Physical deletion would confuse visual removal with removing shared backing data. |
| Hard-delete parents selected with all children | Once no selected operation leaves a dependent child, preservation is unnecessary. |
| Tombstones only for physical deletions | A hide is still a live backing record needed by other devices; emitting a deletion would contradict that state. |

## Evidence and recovered rationale

The original symptom and distinction between persisted season name and displayed
parent name were recovered from prior-discussion memory. The rationale is also
captured by the source comment and `c3b3a39`. No personal backup contents or anime
library samples were copied into the repository.

## Validation and acceptance criteria

Use existing `LibrarySortingAndDeletionTests` for surviving-child hide, mixed
batch selection, tombstone identities, and failed-save rollback.

## Amendments

None yet.
