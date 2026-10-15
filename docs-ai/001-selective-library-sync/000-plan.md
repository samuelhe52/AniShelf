# 001 — Selective library sync: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-05-30 |
| Origin | Retrospective reconstruction on 2026-10-07; not a plan written before implementation |
| Related | [Correctness follow-ups](../009-cloud-sync-correctness/000-plan.md) · [Proposed reusable package](../010-selective-sync-package/000-plan.md) |

## Background

The rich local library contains user state and reconstructible TMDb metadata.
Native mirroring of that entire graph was abandoned. Selective synchronization
keeps device-independent user edits in CloudKit while rebuilding metadata locally.

## Goals

- Sync identity, membership, tracking, custom poster choice, and episode progress.
- Keep fetched metadata out of the upload queue.
- Preserve offline edits, explicit deletion intent, and safe restore behavior.

## Design / approach

Keep the main SwiftData container local-only. Project user-owned fields into
`LibraryEntrySyncSnapshot`; use explicit CloudKit records, a persisted dirty
worklist, import-before-export orchestration, and scoped change tokens.
The [original implementation plan](historical/cloudkit-sync-implementation-plan.md)
retains the staged delivery and manual validation matrix.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Main store uses `cloudKitDatabase: .none` | Fetched metadata is cache data, not authoritative cross-device state. Whole-graph mirroring couples synchronization to the rich persistence graph. |
| Explicit compact records | The accepted implemented direction provides direct control over projection, clocks, tombstones, merge, and reconstruction. An earlier separate lean CloudKit-enabled SwiftData store was a design idea, not the final transport. |
| Exclude metadata refresh from dirty recording | Refreshing posters or descriptions must not masquerade as a user edit or overwrite tracking state. |
| Block raw store restore while sync is enabled | Restoring an old SQLite snapshot must not silently reconcile it against current cloud state. Re-enable goes through bootstrap and conflict policy. |

## Evidence and recovered rationale

The retained plan explicitly rejects full-store mirroring. Prior-discussion memory
also contained an earlier lean-store idea; the implementation plan and code take
precedence over that older idea. The abandoned scratch review cited by the original
plan is absent from the pre-migration tree; it was not fabricated or reconstructed.

## Validation and acceptance criteria

Inspect `DataProvider` configuration, snapshot projection, recorder suppression,
queue acknowledgment, bootstrap, and restore gating. Two-device CloudKit checks
remain a separate runtime activity and require authorization for remote writes.

## Amendments

None yet.
