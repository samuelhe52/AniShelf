# 012 — Rewatch tracking and clocked progress resets: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-03 |
| Origin | Retrospective reconstruction on 2026-10-07; not a plan written before implementation |
| Related | [Correctness plan D5 follow-up](../009-cloud-sync-correctness/000-plan.md) |

## Background

Rewatching needs a separate in-progress marker and completed rewatch count.
Starting over also exposed a cross-device reset race: deleting local episode
progress rows cannot represent a newer intentional zero against stale positive progress.

## Goals

- Count only completed marked rewatches, excluding the first viewing.
- Preserve an editable count and existing discard behavior.
- Carry explicit resets through persistence, sync, backups, and exports.
- Keep zero-only progress out of visible summaries.

## Design / approach

Add `isRewatching` and `rewatchCount` in `SchemaV2_8_2` with defaults for older
records. Starting a rewatch updates progress to timestamped zero rows. Per-season
merge compares timestamps so a newer zero wins over stale positive progress.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Editable count and marker | The user accepted these instead of the original unknown-count/Undo proposal, reusing established discard behavior. |
| Count only marked Watching-to-Watched completion | Other exits from Watching cancel the marker rather than counting an unfinished viewing. |
| Clocked zero instead of deleting progress | Absence has no timestamped clearing intent; unioning stale positive rows resurrects progress as “12 → 0 → 12”. |
| Preserve transport zeros, hide empty summaries | A sync tombstone-like reset is meaningful evidence without needing a visible zero-progress badge. |
| Do not add a special old-build workaround | The maintainer declined handling the specific old-release zero-marker loss pattern. Do not infer that old clients are fixed. |

## Evidence and recovered rationale

Recovered prior-discussion summaries confirm the simplification and approved
reset fix. Current `UserEntryInfo`, snapshot serialization, and the new schema
corroborate implementation. The declined mixed-version workaround is memory-derived
scope history, not a promise of compatibility beyond inspected behavior.

## Validation and acceptance criteria

Use schema migration and both-direction reset regressions, together with
snapshot/Codable coverage. Visual controls require actual inspection; builds alone
do not prove fitting or absence of clipping.

## Amendments

None yet.
