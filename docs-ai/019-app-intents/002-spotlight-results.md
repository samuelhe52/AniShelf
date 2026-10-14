# 019.002 — Spotlight result fixes

## Context

The maintainer started validating Spotlight on 2026-10-14, on the iPhone 18 Pro, iOS
27.0 simulator, with the app showing Japanese titles. Two problems turned up
(maintainer screenshots):

- Searching an entry's title showed three AniShelf rows for one entry: two App
  Shortcut rows with a `…` button, both titled with the entry name, and the indexed
  entry itself.
- The indexed row's subtitle showed the English alternate title ("Goodbye, Lara")
  instead of the entity subtitle, and searching for that English title found nothing.

## Findings

Verified evidence, from a temporary debug probe (since removed) that logged the
entity's attribute set and ran `CSSearchQuery` against the app's own index, and from
Spotlight searches a Codex agent ran on the same simulator:

- `IndexedEntity.defaultAttributeSet` filled in only `title`. `displayName`,
  `contentDescription`, and `keywords` were empty, so the `displayRepresentation`
  subtitle never reached Spotlight. Spotlight showed the first alternate name in its
  place.
- The alternate names were stored. An in-app query on `alternateNames`, or on any
  field for "Goodbye" or "Lara", matched the entry.
- The two extra rows were the App Shortcuts whose phrases took an entry
  (`Open ${target}`, `Show ${target}`, and `Mark the next episode of ${entry}`).
  Spotlight lists such a shortcut once per suggested entity, so they appeared after
  `updateAppShortcutParameters()` ran.
- In home-screen Spotlight on this simulator, only the title matched. A plain
  `CSSearchableItem` (not an App Intents entity) with unique words in `keywords`,
  `alternateNames`, and `textContent` was found by its title only. None of those
  words matched, and neither did a word from an entry's overview.

## Change

- `LibraryEntryEntity.attributeSet` sets `displayName` to the name,
  `contentDescription` to the subtitle, and `keywords` to the alternate names, in
  addition to `alternateNames`. Spotlight now shows "TVシリーズ · 視聴中 · S1E7"
  as the subtitle, with the first alternate name on a third line (Codex simulator
  run).
- No App Shortcut phrase takes a library entry. Open Entry and Watched Next Episode
  keep their phrases without an entry, so Siri asks which entry to use, and the
  indexed entry opens it from Spotlight. The three phrases were removed from
  `AppShortcuts.xcstrings`. The indexer no longer calls
  `updateAppShortcutParameters()`, since the remaining parameters are fixed enums.
- `LibraryAppIntentsTests` checks the display name, subtitle, and keywords in the
  attribute set.

Rejected: keeping the entry phrases and giving each Spotlight row its own title.
The rows would still duplicate the indexed entry, which opens it anyway.

Rejected after a simulator test: joining the translated titles into `displayName`
while keeping `title` as the name. Spotlight showed the whole joined string as the
row title. 再见菈菈 matched, but "Goodbye", "Lara", and 안녕 still did not.

## Validation

- After the change, searching さよならララ shows one AniShelf row, with no `…`
  button (Codex simulator run).
- `make test-app-sim APP_TEST_ONLY='MyAnimeListTests/LibraryAppIntentsTests MyAnimeListTests/EntryDetailSessionTests'`
  passed, and `make build` succeeded.

## Open questions

- Translated titles are still not searchable in home-screen Spotlight. Developer
  reports on Apple's forums describe the same behavior on iOS 17 through 27 devices,
  not just the simulator. Spotlight matches only `title` and `displayName`, while
  `CSUserQuery`, `CSSearchQuery`, and `spotlightQuery(_:)` still match other fields
  ([837319](https://developer.apple.com/forums/thread/837319), FB23635795;
  [836372](https://developer.apple.com/forums/thread/836372), FB16995719;
  [835475](https://developer.apple.com/forums/thread/835475), FB23317556). None of
  the threads has a fix or an Apple-confirmed cause. The keywords stay in place in
  case Apple fixes this. Not checked on a device here.
- During one launch, 55 s passed between the first pass's delete-all and its first
  index batch. Another launch took 0.2 s. If the app is suspended or killed in that
  window, AniShelf has no Spotlight results until the next launch. Two probe launches
  that were killed early ended that way.
- The probe's plain test item (domain `probe`) is still in this simulator's index.
