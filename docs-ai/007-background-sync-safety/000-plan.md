# 007 — Background sync suspension safety: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-08-25 |
| Origin | Retrospective reconstruction on 2026-10-07; not a plan written before implementation |
| Related | [Selective sync](../001-selective-library-sync/000-plan.md) |

## Background

A background suspension termination was associated with file/SQLite lock work.
A sync request can be active before the serialization gate, during account scope
resolution, so tracking only work inside that gate underestimates its lifetime.

## Goals

- Cover the whole sync request with bounded background protection.
- Cancel safely on expiration or inability to acquire background execution.
- Avoid inserting partly hydrated models before the final cancellation boundary.

## Design / approach

Track active requests around the complete coordinator request. Use
`LibrarySyncBackgroundExecutionController` for bounded execution; expiration
cancels rather than extending work indefinitely. Hydration produces detached
entries before synchronous insertion, relation repair, application, and save.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Whole-request activity tracking | `SyncGate` starts later than account resolution; gate-only protection misses active work. |
| Bounded protection and cancellation | Background execution is not permission for unrelated work or an unlimited sync pass. |
| Detached hydration until commit boundary | Inserting models during asynchronous planning can leak canceled work into a later shared-context save. |
| Preserve established result semantics | Cleanup should clear transient state without rewriting the meaning of a completed export or existing retry outcome. |

## Evidence and recovered rationale

Reasons were recovered from prior-discussion memory and checked against
`c53e994`, the background controller, coordinator activity counters, and remote
apply cancellation boundaries. The termination class did not prove which exact
save held the lock; that uncertainty is preserved.

## Validation and acceptance criteria

Exercise expiration, failed background-task acquisition, cancellation after
export, and detached hydration. Runtime background behavior requires separate
execution; historical passing tests do not prove every suspension path.

## Amendments

None yet.
