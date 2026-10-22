# 030 — Open In Infuse and Kazumi: Plan

| Field | Value |
| --- | --- |
| Status | Implemented |
| Anchor date | 2026-10-20 |
| Origin | Maintainer request on 2026-10-20: replace the detail page's homepage button with a menu that opens the entry in Infuse, Kazumi, or the homepage. Kazumi's deep links come from the maintainer's own upstream PR, [Predidit/Kazumi#2736](https://github.com/Predidit/Kazumi/pull/2736). This plan was written after the implementation, in the same session, when the maintainer asked for a record because the deferred Bangumi mapping is substantial. |
| Related | [006-broadcast-and-reminders](../006-broadcast-and-reminders/000-plan.md) (TMDb-to-TVMaze identity mapping, the model for a future Bangumi mapping) |

## Background

The entry detail quick actions row had a Safari button that opened the entry's
homepage (`primaryLinkURL`, falling back to `AnimeEntry.linkToDetails`). People who
watch through a player app had no way to jump from AniShelf to that app.

Both target apps accept deep links:

- **Infuse** (Firecore, "API for Third-Party Apps & Services", Infuse 8.2+) opens
  library items by TMDb ID: `infuse://movie/{id}`, `infuse://series/{id}`,
  `infuse://series/{id}-{season}`, `infuse://series/{id}-{season}-{episode}`. A title
  missing from the user's library shows a TMDb placeholder page.
- **Kazumi** (iOS and macOS, added by Kazumi#2736) accepts
  `kazumi://bangumi/<Bangumi ID>` and `kazumi://search?query=<title>`.

AniShelf stores TMDb IDs but no Bangumi IDs.

## Goals

- One "Open In…" menu that lists Infuse, Kazumi, and Homepage.
- The same destinations in three places: the entry detail quick actions row (replacing the
  Safari button), the library context menu (iOS list, grid, and gallery; Mac list and
  grid), and a list-row swipe action (iOS and Mac).
- Infuse opens the exact movie, series, or season by TMDb ID.
- Kazumi opens a title search.

### Non-goals

- **TMDb-to-Bangumi ID mapping.** Opening Kazumi's exact detail page
  (`kazumi://bangumi/<ID>`) needs a Bangumi subject ID for each entry, and a season
  usually maps to its own Bangumi subject. This is deferred to a future entry; see
  [Future work: Bangumi mapping](#future-work-bangumi-mapping).
- Episode-level Infuse links.
- App Store links for apps that are not installed.

## Design / approach

`MyAnimeList/Sources/Views/Library/EntryOpenInMenu.swift` owns the feature:

- `EntryOpenInLinks` builds the three URLs from an `AnimeEntry` plus a homepage URL.
  - Infuse: `.movie` and `.series` use the entry's `tmdbID`; `.season` uses
    `infuse://series/{parentSeriesID}-{seasonNumber}`.
  - Kazumi: `kazumi://search?query=` with the parent series' `zh-CN` name
    translation, then `ja-JP`, then `displayName`. Seasons search for the series
    title, because TMDb season names are generic ("Season 2").
  - `hasHandler(for:)` checks installation: `UIApplication.canOpenURL` on iOS (needs
    `infuse` and `kazumi` under `LSApplicationQueriesSchemes` in
    `MyAnimeList/Resources/Info.plist`), and `NSWorkspace.urlForApplication(toOpen:)`
    on macOS.
- `EntryOpenInMenuItems` renders the items. An app that isn't installed stays listed
  but is disabled, with a "Not Installed" subtitle. Homepage appears only when a URL
  exists.
- `EntryDetailOpenInMenu` is the quick actions button (`arrow.up.forward.app`).
  `EntryOpenInSubmenu` is the submenu used in `LibraryEntryActionState.contextMenu`.
- On iOS, `LibraryListView` uses a plain `EntryOpenInSwipeButton` on the trailing
  edge beside Delete. The short label is "Open"
  (開く / 打开). It creates an `EntryOpenInRequest`, and the originating row's
  `entryOpenInAlert` presents a native alert with the entry title, Infuse, Kazumi,
  Homepage when available, and Cancel. Unavailable apps remain visible but
  disabled; the alert has no "Not Installed" message.
- The Mac list reuses the same plain swipe button, request, and native SwiftUI
  alert. Its Open button is on the trailing edge beside Delete, matching iOS. Native
  Mac default-button styling is retained, and swipe-close behavior is left
  unchanged as requested. There is no custom sheet, AppKit presenter, or
  animation workaround.

## Alternatives & decisions

| Choice | Reason and alternative |
| --- | --- |
| Kazumi search link now, Bangumi ID later | Maintainer decision: Bangumi mapping "is more complex and requires some research about API access methods and terms of use", and should build on the existing TVMaze/TMDb mapping. |
| Prefer the Chinese title, then Japanese, for the Kazumi query | Implementation inference: Kazumi searches Bangumi, whose titles are Chinese and Japanese, and Kazumi is primarily a Chinese-language app. Not measured against real search results. |
| Show uninstalled apps grayed out with "Not Installed" | Maintainer decision. The first implementation hid uninstalled apps; the maintainer preferred discoverability. |
| Swipe action and context menu both | Maintainer decision ("It should be available in both places"). Applies to the iOS and Mac lists alike. |
| iOS trailing swipe edge beside Delete | Maintainer decision. Edit and Share stay on the leading edge. Open became the outermost, full-swipe action in amendment 002. |
| Plain iOS swipe button with a native alert | The embedded Menu stretched the swipe actions and left a large gap on iPad in maintainer screenshots. A confirmation dialog omitted unavailable apps. The maintainer confirmed the alert looks good on iPhone and iPad. |
| Short iOS swipe label | "Open" (開く / 打开) keeps the swipe action compact; "Open In…" remains on menus and the alert title. |
| Disabled app choices without an alert message about installation | Maintainer decision. Menu subtitles retain "Not Installed"; the iOS alert uses disabled buttons alone. |
| Plain Mac swipe button with the existing native alert | Maintainer reported the embedded Menu does nothing. Reuse the iOS presentation code and retain native styling; swipe-close animation is explicitly outside this fix. |
| Rename the button to "Open In…" with `arrow.up.forward.app` | Maintainer asked for a rename and a new icon. The name and symbol were chosen during implementation to cover two apps and a website. |

## Future work: Bangumi mapping

Recorded so the follow-up entry starts from known constraints. Nothing here is
verified.

- **Model to follow:** the TVMaze integration from entry 006:
  `MyAnimeList/Sources/Network/TVMazeResolver.swift` resolves a TMDb series to a
  provider show, and `MyAnimeList/Sources/Network/TVMazeConfirmedMappingStore.swift`
  persists user-confirmed mappings, with a validation sheet for the user to
  correct mismatches.
- **Granularity:** Bangumi usually models each season (and each movie) as a separate
  subject, so the key is likely a TMDb series plus a season number, not a series ID.
- **Research needed:** how to access the Bangumi API (authentication, the required
  User-Agent, rate limits); its terms of use for third-party apps; and whether a
  maintained TMDb↔Bangumi dataset exists that is licensed for reuse.
- **Fallback:** keep the search link when no confirmed mapping exists.

## Validation and acceptance criteria

- Focused unit tests for URL construction: the Infuse season link and the Kazumi
  title choice and encoding (`EntryOpenInLinksTests`).
- iOS simulator test run and native macOS build.
- Maintainer visual pass: the detail button, the context menu, the list swipe action,
  the disabled menu items with their "Not Installed" subtitle, and the iOS swipe
  alert with disabled app choices and Cancel.

## Amendments

- Updated 2026-10-20: Use a compact trailing swipe button and native alert on iOS;
  see the iOS follow-up timeline and validation in [001-action.md](001-action.md).
- Updated 2026-10-20: Replace the non-presenting Mac swipe menu with the same
  plain button and native alert used by iOS. The maintainer explicitly excluded
  swipe-close animation changes from this minimal fix.
- Updated 2026-10-21: Swap Open and Delete on the trailing swipe edge, enable full
  swipe, and add a device-local default swipe destination; corrects the full-swipe
  text above — see
  [002-swipe-default-destination.md](002-swipe-default-destination.md)
