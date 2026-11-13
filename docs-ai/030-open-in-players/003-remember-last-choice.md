# 030.003 — Remember Last Choice

## Context

The maintainer requested an optional remembered choice that takes precedence over the configured swipe default. The initial implementation used a global choice; the maintainer clarified that the choice should be per anime.

## Change

The setting and remembered choices are device-local. Each entry's stable library identity maps to its last successfully opened app. Successful explicit selections from menus or the swipe alert update that entry's choice; homepage and unsuccessful opens do not. Swipe uses the entry's remembered app when present, otherwise the configured default, retaining the existing unavailable-app alert. Disabling the setting ignores remembered choices without deleting them.

The initial global value cannot be associated with a specific entry and is ignored. Menus and the swipe alert carry the same entry identity.

## Refs

`MyAnimeList/Sources/Views/Library/EntryOpenInMenu.swift`, `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileInterfaceSections.swift`, `MyAnimeList/Tests/MyAnimeListTests/EntryOpenInLinksTests.swift`.

## Validation

The initial global implementation passed `make build-mac`, `make build`, seven `EntryOpenInLinksTests` on macOS, and a throwaway Swift smoke script covering the default, remembered choice, and disabled fallback.

After the per-entry correction, `make build-mac`, `make build`, and six `EntryOpenInLinksTests` on macOS passed. A throwaway Swift smoke script exercised the production preference logic with two independent identities and the legacy global value. `make run-sim DEVICE_PROCESS_LAUNCH_ARGS='-library-fixture 20'` launched on a booted iPhone simulator; the Japanese appearance settings showed the per-entry explanation and toggle. External-app opening was not exercised.
