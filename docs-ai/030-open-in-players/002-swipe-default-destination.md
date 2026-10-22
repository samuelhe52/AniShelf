# 030.002 — Swipe default destination

## Context

Maintainer request on 2026-10-21, after the swipe alert shipped in `8fa75a1`:

- Swap Delete and Open on the trailing swipe edge, and enable full swipe so a full
  swipe triggers Open.
- Let people choose a default destination for the swipe (Infuse or Kazumi for now).
  With no default, the current alert still appears; with one, the swipe opens that
  app directly.
- Applies to the iOS and Mac list swipe actions alike.

## Change

- **Order and full swipe.** Open is the first (outermost) trailing button in
  `LibraryListView` and `MacLibraryList`, with `allowsFullSwipe: true`, so a full
  swipe runs Open. Delete moves inward and is no longer the full-swipe action.
- **One app list.** An `EntryOpenInApp` enum (`infuse`, `kazumi`) in
  `MyAnimeList/Sources/Views/Library/EntryOpenInMenu.swift` holds each app's name,
  symbol, scheme, and URL lookup. The menus, the alert, and the setting iterate
  over it, so a new route is one new case.
- **Setting.** `EntryOpenInSwipeDestination` is `.ask` or `.app(EntryOpenInApp)`.
  It is `RawRepresentable` with stable string raw values (`ask`, `infuse`,
  `kazumi`) and stored with `@AppStorage` under the key
  `LibraryOpenInSwipeDestination`. A raw value that doesn't decode, such as a case
  removed later, reads as `.ask`. Adding cases needs no migration.
- **Device-local.** The key stays out of `String.cloudSyncedPreferenceKeys` and
  `String.allPreferenceKeys`. The maintainer asked for no iCloud sync. Leaving it
  out of backups is an implementation decision: installed apps differ per device,
  and the share-sheet settings follow the same rule.
- **Settings UI.** An "Open In" section in `LibraryProfileInterfaceSettingsSection`
  (iOS and Mac) has a "Swipe Action Opens" menu: Ask Every Time, Infuse, Kazumi.
  Apps that aren't installed are disabled, with the "Not Installed" subtitle
  (maintainer decision). The menu uses one `Toggle` per option rather than a
  `Picker`: the first build used a `Picker` with `.disabled` on each option, and
  the maintainer found on iOS that the options stayed selectable.
- **Swipe behavior.** `EntryOpenInSwipeButton` opens the chosen app's URL directly
  when the entry has one and the app is installed. Otherwise it falls back to the
  alert. This fallback covers an app uninstalled after it was chosen, and a Kazumi
  link with no usable title.

### Scope decisions

| Choice | Reason and alternative |
| --- | --- |
| Default applies to the swipe action only | Maintainer decision: the setting is a shortcut, "and one shortcut is enough". The context and detail menus keep listing every destination. |
| Keep the "Open" label and symbol when a default is set | The maintainer agreed an app-specific label is clearer but deferred it, because it needs the apps' icons imported and styled to match. Recorded as the next step. |
| Disable uninstalled apps in the picker | Maintainer decision, instead of letting people pick an app that can't open. |

## Next step

- Show the default app's name and icon on the swipe button. This needs Infuse and
  Kazumi icon assets and a check that they fit the current swipe-action style.

## Refs

- `MyAnimeList/Sources/Views/Library/EntryOpenInMenu.swift` (`EntryOpenInApp`,
  `EntryOpenInSwipeDestination`, `EntryOpenInSwipeButton`)
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileInterfaceSections.swift`
  (`LibraryProfileOpenInSettingsSection`)
- `MyAnimeList/Sources/Views/Library/LibraryListView.swift`,
  `MyAnimeList/Sources/Mac/MacLibraryList.swift`
- `MyAnimeList/Tests/MyAnimeListTests/EntryOpenInLinksTests.swift`
  (`testSwipeDestinationRawValuesStayStableAndDeviceLocal`)
