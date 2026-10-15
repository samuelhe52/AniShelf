# 008 — Multi-window presentation: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-09-27 |
| Origin | Retrospective reconstruction on 2026-10-07; not a plan written before implementation |
| Related | [Adaptive detail](../005-adaptive-library/000-plan.md) · [Review prompts](../004-respectful-review-prompts/000-plan.md) |

## Background

The maintainer wanted multiple-window support. A Mac search presentation crash
also prompted investigation, but the reported framework path did not establish
an AniShelf query or persistence defect.

## Goals

- Preserve independent window search and detail state.
- Present share sheets, purchases, and reminder routes in the initiating scene.
- Coordinate shared lifecycle work and global prompts once.

## Design / approach

Enable multiple scenes and distinguish scene-owned view state from shared
library/persistence services. Capture the invoking scene identifier before async
presentation work. Route UIKit presentation to that scene rather than selecting
the first visible key window across the app.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Scene-targeted presentation | With multiple windows, a global key-window lookup can present UI in the wrong window. |
| Shared store, per-window search/detail | Multiple view roots do not imply duplicating persistence or globally sharing every query and modal route. |
| Shared lifecycle/global-prompt coordination | Each window receiving a lifecycle event must not independently repeat app-wide work or prompt presentation. |
| Serialize duplicate repair | Two scenes can request shared mutation concurrently; per-view state does not protect the shared store. |

## Evidence and recovered rationale

Prior-discussion memory records the maintainer's explicit multi-window direction
and the difference between shared and scene-local state. Current source and the
September commit series corroborate the boundaries. The historical framework crash
correlation is not a fresh proof that enabling multiple scenes fixes it on every OS.

## Validation and acceptance criteria

Check per-window query persistence, targeted reminder/share presentation,
disconnected-window rerouting, duplicate repair serialization, and global prompt
ownership. Two-window runtime checks remain distinct from builds and unit tests.

## Amendments

None yet.
