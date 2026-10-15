# 010 — Reusable selective sync package: Plan

| Field | Value |
| --- | --- |
| Status | Planned |
| Anchor date | 2026-09-27 |
| Origin | Existing proposal migrated on 2026-10-07; source design created 2026-09-27 |
| Related | [Correctness prerequisites](../009-cloud-sync-correctness/000-plan.md) |

## Background

The maintainer wants a package other developers can adopt, not merely AniShelf
code moved into a new target. A public library must own correctness guarantees
while adopters control identity, projection, reconstruction, and product policy.

## Goals

- Support explicit selected SwiftData fields, registered preferences, and custom values.
- Keep library-owned clocks and delivery metadata out of adopter model schemas.
- Preserve AniShelf's existing wire contract through an explicit compatibility codec.
- Establish durable capture, receipt, convergence, and lifecycle before convenience macros.

## Design / approach

The [full design and six pending stages](design.md) are migrated from the existing
proposal. Core, CloudKit transport, SwiftData, UserDefaults, and custom storage
remain logical boundaries, not finalized modules. Prototype an explicit schema API
before macros, and use a second small domain to challenge AniShelf-specific assumptions.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Library owns correctness; app supplies domain policy | Publishing app-shaped orchestration would leave adopters responsible for fragile acknowledgment, clocks, and recovery rules. |
| Library-owned metadata store | Required clock-mutator calls on every user action are easy to miss and unnecessarily couple adopter schemas to sync internals. |
| Library-defined default format | Unknown-field preservation and compatibility should work without every adopter implementing record encoding. |
| Failure-prone opt-in codec escape hatch | Existing released clients cannot be migrated by a simple internal refactor. AniShelf needs compatibility without making custom codecs the normal path. |
| Explicit schema first, macros later | Macro composition must be proved separately; syntactic convenience cannot substitute for durable change capture. |
| Transport spike separate from wire changes | Changing both at once makes compatibility and recovery failures harder to isolate. |

## Evidence and recovered rationale

The full design already records most boundary choices. Prior-discussion memory
and the recovered extraction summary confirm that the goal was a publishable
library and that the custom-codec path was deliberately accepted as failure-prone.
No concrete proposed API or storage technology is asserted to be implemented.

## Validation and acceptance criteria

All six design stages remain pending. Establish compatibility fixtures and
resolve the explicitly listed API decisions before stabilization. The existing
AniShelf `LibrarySync` target is not evidence of a finished reusable package.

## Amendments

None yet.
