# 003.003 — Root cause of the 1.93/1.94 launch crash: in-place V2.7.9 redefinition

## Context

Recovered on 2026-10-07 from prior-discussion memory of the crash investigation,
then checked against local Git history. TestFlight 1.94(1) reported a launch crash
at `fatalError("Could not create ModelContainer: …")` in `DataProvider.init`. The
maintainer also reported many silent crashes in 1.93. This failure is the kind of
launch trap the recovery workflow in this entry replaced.

## Finding

`SchemaV2_7_9` changed shape several times under one version stamp, `.init(2, 7, 9)`,
all on 2026-05-30:

| Commit | Change to `SchemaV2_7_9` |
| --- | --- |
| `4a02162` | Introduced for CloudKit library sync |
| `eec9aa7` | Reshaped for CloudKit requirements (optional/defaulted stored properties, migration markers) |
| `b99337a` | Removed when main-store CloudKit sync was disabled |
| `fba25c1` | Reintroduced with a different model shape |

The `SchemaV2_7_8` → `SchemaV2_7_9` stage is lightweight, and nothing bridges one
2.7.9 shape to another. A store written by an intermediate shape (for example, an
internal CloudKit test build) does not match the shipped 2.7.9 model. Opening the
container fails, and at that time the failure was fatal.

Rejected explanations, from the same investigation:

- The store-startup hardening in `99d644a` (missing parent directory) is harmless
  but does not address this failure.
- The V2.8.0 image-path migration ([entry 002](../002-image-path-storage/000-plan.md))
  first shipped in 1.94, so it cannot explain 1.93 crashes.

## Decision

Never change the model shape of a shipped or tested schema version in place. Add a
new version identifier and a migration stage instead. SwiftData keys store
compatibility on that version, so two shapes sharing one version is undefined
behavior that only surfaces when a store written by the other shape is opened.

No dedicated repair for intermediate 2.7.9 stores exists. Since `14ea0ad`
(first released in 1.94), an unopenable store is quarantined with a recovery
explanation instead of crashing the app.

## Refs and evidence

- Commits above; tags place `14ea0ad` and `99d644a` first in `v1.94`.
- `DataProvider/Sources/DataProvider/MigrationPlan.swift`: the lightweight 2.7.8 → 2.7.9 stage.
- The root-cause analysis is memory-derived. It was not reproduced with an
  intermediate-shape store during this backfill.

## Open questions

Git tags place all four schema commits first in `v1.92`, but the recovered report
says 1.92 was clean and the regression appeared between 1.92 and 1.93. One possible
reconciliation (inference only) is that crashes require a store written by an
intermediate internal build, so the affected population depends on who ran those
builds rather than on the release that first contained the commits.
