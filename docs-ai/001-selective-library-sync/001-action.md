# 001 — Selective library sync: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-05-30–31 | Add sync foundations, dirty tracking, and coordinator | `06fd2ca`, `6803b95`, `74c9b5d` |
| 2026-06-03 | Add opt-in settings and bootstrap UI | `16750a3`, `8b5e7be` |
| 2026-06-04 | Reset local sync state after restore | `6e8fe3d` |
| 2026-06-05 | Exclude metadata refresh from queued user edits | `1b7e5f6` |
| 2026-08-06–07 | Enable default sync and bootstrap it | `190b795`, `16952c3` |

## Outcome and current state (as of 2026-10-07)

`DataProvider` explicitly disables native CloudKit mirroring. `LibrarySync`
contains the record/snapshot boundary, queue, import, and export. App coordinators
own triggers, bootstrap choices, and metadata reconstruction.
The retained June plan's default-off setting and pending rollout state are
historical: later commits changed the default. They are not current instructions.

Key source files:

- `DataProvider/Sources/DataProvider/DataProvider.swift`
- `DataProvider/Sources/LibrarySync/LibraryEntrySyncSnapshot.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncCoordinator.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncChangeRecorder.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibraryPreferences.swift`

## Deviations from plan

The older idea of a lean CloudKit-enabled SwiftData store gave way to explicit
CloudKit records. Later correctness and lifecycle changes have their own entries.
The original stages 1–5 review is retained as dated evidence, not an active backlog.

## Open questions

The old Stage 8 manual two-device checklist is preserved. Whether every scenario
was subsequently exercised on real devices is unknown.
