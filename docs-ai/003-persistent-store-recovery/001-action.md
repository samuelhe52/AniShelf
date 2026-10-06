# 003 — Persistent-store recovery: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-06-19 | Add recovery bootstrap, explanation, and exports | `14ea0ad` |
| 2026-08-06 | Support exact legacy V2.6 store schema | `8d8418e` |
| 2026-08-07 | Replace duplicate legacy tail with one-stage bridge | `5ac704f` |

## Outcome and current state (as of 2026-10-07)

The source OpenSpec tasks are all checked, and the implementation exists despite
the change having remained unarchived. Bootstrap copies matching store artifacts,
writes the manifest and pending acknowledgment, then removes the active originals.
`ModelContainerLoader` tries canonical migration and a known legacy bridge before
startup quarantine. Exports are prepared only on explicit action; acknowledging
recovery releases the app activity gate.

Key source files:

- `DataProvider/Sources/DataProvider/DataProvider+StartupRecovery.swift`
- `DataProvider/Sources/DataProvider/ModelContainerLoader.swift`
- `DataProvider/Sources/DataProvider/Recovery/LegacyV260/LegacyV260BridgePlan.swift`
- `MyAnimeList/Sources/Views/StartupRecoveryView.swift`
- `MyAnimeList/Sources/Utils/RecoveryExportManager.swift`
- `MyAnimeList/Sources/App/MyAnimeListApp.swift`

## Deviations from plan

Quarantine is copy-then-delete, not an atomic move. Diagnostics use the manifest;
full bundle compression is lazy. A persistent pending-acknowledgment marker resolves
the old design's question about losing the recovery explanation on a later launch.
Known historical schema mismatch gets a compatibility attempt before destructive replacement.

## Open questions

The original design asked about extra recent log excerpts. The export currently
copies only the manifest; no log collection exists.
