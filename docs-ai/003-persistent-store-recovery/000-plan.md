# 003 — Persistent-store recovery: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-06-19 |
| Origin | Retrospective reconstruction on 2026-10-07; not a plan written before implementation |
| Related | [Image-path migration](../002-image-path-storage/000-plan.md) · [Legacy bridge amendment](002-legacy-schema-bridge.md) |

## Background

A launch-time `ModelContainer` failure previously trapped before the UI could
offer help. The user library is authoritative state, so treating it as disposable
cache would lose the evidence needed to diagnose or recover it.

## Goals

- Preserve unreadable store artifacts before creating a replacement.
- Explain quarantine and recovery options before normal library activity.
- Offer separate, explicit diagnostic and full-store exports.
- Try narrowly scoped compatibility recovery for known historical schemas.

## Design / approach

Bootstrap `DataProvider` with structured recovery metadata. Preserve matching
store files, a manifest, and pending acknowledgment in a timestamped local recovery
folder. Create the replacement only after preservation succeeds. Block ordinary
library activity until acknowledgment; prepare exports on demand.
The [original design](historical/design.md), [requirements](historical/specs/persistent-store-recovery/spec.md),
and [completed task list](historical/tasks.md) remain available.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Quarantine before recreation | Silent wiping destroys the only recoverable artifact and obscures the failure cause. |
| Dedicated blocking explanation | A toast or dense alert cannot adequately explain an empty replacement store and the export choices. |
| Separate diagnostic and recovery exports | Users can share metadata without immediately sharing the entire personal library. Automatic upload was explicitly excluded. |
| Preserve original bootstrap error if recovery fails | Compatibility attempts must not replace the primary failure with a less useful secondary error. |
| Frozen V2.6-to-V2.7 bridge, then canonical migrations | Duplicating the full migration tail requires maintaining two chains whenever the current schema advances. |

## Evidence and recovered rationale

The OpenSpec design records quarantine and export rationale. Prior-discussion
memory adds the TestFlight `_assertionFailure` versus source `fatalError` distinction
and the reason for the frozen legacy bridge. Source confirms the loader tries the
normal plan first, then the bridge. A schema mismatch alone does not prove SQLite corruption.

## Validation and acceptance criteria

Check quarantine inventory, acknowledgment persistence, export consent, lazy
packaging/temporary cleanup, and known legacy-schema fixtures. A real recovery
bundle must be tested on a disposable copy; historical success is not universal repair coverage.

## Amendments

- Updated 2026-10-07: Recover the legacy-schema bridge rationale — see [002-legacy-schema-bridge.md](002-legacy-schema-bridge.md).
- Updated 2026-10-07: Record the in-place V2.7.9 redefinition behind the 1.93/1.94 launch crash — see [003-v279-schema-collision.md](003-v279-schema-collision.md).
