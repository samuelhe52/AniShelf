# 009 — Cloud sync convergence and partial failures: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-09-27 |
| Origin | Retrospective reconstruction on 2026-10-07; not a plan written before implementation |
| Related | [Package proposal](../010-selective-sync-package/000-plan.md) · [Progress-clear follow-up](../012-rewatch-tracking/000-plan.md) |

## Background

Clock-only dirty reconciliation could discard a local edit when a remote edit
was newer in another field group. Order-dependent merge ties and unreadable records
also undermined convergence and progress. These defects should not become the
contract of the proposed reusable package.

## Goals

- Preserve merged user state and make equal-clock results deterministic.
- Isolate record-level failures without erasing unreadable cloud state.
- Preserve queued work, retry ownership, and safe re-enable behavior.
- Keep existing CloudKit record compatibility while fixing selected defects.

## Design / approach

Compare merged local state against the fetched cloud record before clearing
pending work. Apply the selected merge values even on deterministic equal-clock
ties. Quarantine unsupported records and retain failed reconstruction state.
The [original defect plan](historical/cloud-sync-correctness-fixes-plan.md) preserves
failure scenarios, defect IDs, precision measurements, and deferred work.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Compare state, not just newest clock | A remote library edit can be newer while its tracking group is stale. Dropping the upload loses the merged local tracking edit. |
| Live snapshot wins an equal-clock delete tie | The accepted implementation prefers retaining data to deleting it on an ambiguous tie. This replaces the source plan's unresolved question. |
| Quarantine and block affected uploads | A fresh older-schema upload over an unreadable record could erase fields. Continue safe work without silently accepting data loss. |
| Defer change-tag transport redesign | `.allKeys` remains an eventual-repair limitation. Per-record server metadata and conditional writes belong to the proposed package; repair is not prevention. |
| Bound operations and drain canceled work | An auth-token await can stall before the ordinary network timeout. Off/on must cancel the underlying operation and allow a fresh bootstrap. |
| Simple neutral issues UI | The maintainer chose one orange concern treatment and concise unreadable-record wording rather than an unverified schema-cause claim or severity hierarchy. |

## Evidence and recovered rationale

The source plan supplies convergence rationale. Prior-discussion memory adds
the selected-fix scope, result ownership, 60-second preparation bound, and UI
simplicity decisions. Current transport still uses `.allKeys`; no claim of
conditional-write prevention is made. The source's live precision result is
preserved with its exact development-environment limits, not generalized.

## Validation and acceptance criteria

Check two-way convergence, equal-clock snapshot/tombstone order, quarantined
upload blocking, retry result ownership, and preparation cancellation. Live CloudKit
probes write remote data and need explicit authorization.

## Amendments

None yet.
