# 006 — Broadcast resolution and device-local reminders: Action record

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-10 | Add external-ID plumbing and TVMaze client | `049c72e`, `bfd269f` |
| 2026-08-11 | Persist confirmed TVMaze mappings | `2e5bd6f` |
| 2026-08-12–16 | Add session lifecycle, availability, controls, and match replacement | `60197fa`, `c53e555`, `1e83d50`, `35387fe` |
| 2026-08-21 | Add episode notifications, detail controls, and subscription management | `0b1f9b5`, `43be9af`, `c126db2`, `b12a22c` |
| 2026-08-21–22 | Reconcile orphaned/remapped requests; keep subscriptions and lead time across failures | `8606127`, `b884e9f`, `8283e5a`, `a766ad1` |
| 2026-08-23 | Replace episode notifications with airing reminders | `b479653` |
| 2026-09-06 | Unify reminder timing offsets and preserve timing on upgrade | `cf58c26`, `cabefd3` |

## Outcome and current state (as of 2026-10-07)

The resolver and detail broadcast model separate eligibility, automatic lookup,
user-assisted matching, and confirmed mapping persistence. `AiringReminderManager`
uses the embedded next episode, a device-local subscription dictionary, exact UTC
calendar components, and `repeats: false`. Subscription intent survives temporary
provider failure rather than being treated as the same thing as a scheduled request.
Recovery gates library-based pruning while a replacement store is temporarily empty.

Key source files:

- `MyAnimeList/Sources/Network/TMDbBroadcastEligibility.swift`
- `MyAnimeList/Sources/Network/TVMazeResolver.swift`
- `MyAnimeList/Sources/Network/TVMazeConfirmedMappingStore.swift`
- `MyAnimeList/Sources/Models/Library/EntryDetailBroadcastModel.swift`
- `MyAnimeList/Sources/Notifications/AiringReminderManager.swift`
- `MyAnimeList/Tests/MyAnimeListTests/AiringReminderManagerTests.swift`

## Deviations from plan

The original plan's notification-out-of-scope wording describes its first phase;
reminders were implemented afterward. The Q&A describes a general rolling-window
alternative for bounded schedules; AniShelf's narrower policy registers only the
currently verified next episode, not an unverified future weekly series.

## Open questions

Provider numbering is authoritative for reminder payloads. Do not silently
reinterpret it as TMDb season numbering. Current provider coverage is unsurveyed.
