# 003.002 — Preserve the released V2.6 schema boundary

## Context

Recovered from prior discussion on 2026-10-07 and corroborated by `8d8418e` and
`5ac704f`. An otherwise readable SQLite store can be unknown to SwiftData when a
historical model was edited in place: the version label stays the same while its
model hash changes. Quarantining every such case would skip a recoverable schema.

## Decision and rejected alternative

Keep the exact released `SchemaV2_6_0Legacy` contract frozen. Bridge only to
`SchemaV2_7_0`, release that container, and reopen with the ordinary `MigrationPlan`.
A second copy of the canonical migration tail was rejected because every schema
addition would require parallel maintenance and could drift.

Do not retrofit per-season episode-count fields into this historical schema.
Prior-discussion memory distinguishes the released top-level count from later
per-season counts; compatibility models must follow the released contract rather
than a synthetic fixture built from subsequently edited source.

## Change and current state

`DataProvider/Sources/DataProvider/ModelContainerLoader.swift` tries the ordinary
plan first, then `LegacyV260BridgePlan`, and preserves the primary error if every
attempt fails. In-memory containers skip this compatibility recovery.
The retained recovery bundle is not added to this repository.

## Refs and validation

- `8d8418e`: known legacy-schema recovery.
- `5ac704f`: one-stage frozen bridge.
- `DataProvider/Tests/DataProviderTests/Recovery/LegacyV260MigrationTests.swift`.

Prior real-bundle results are memory-derived evidence, not proof of arbitrary-store repair.
