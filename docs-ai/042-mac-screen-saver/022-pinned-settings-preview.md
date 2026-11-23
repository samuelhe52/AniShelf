# 042.022 — Pinned screen saver preview

## Context

Samuel reported that scrolling to Details hides the preview, so the feedback from toggling a detail is out of view. The settings destination used one grouped form for the entire pane.

## Change

Give the Mac Screen Saver destination its own layout. Keep one live preview and the primary pickers (Show, Entry Type, Layout, Mode) above the scroll boundary. Size the preview to leave room for the form at the minimum supported window height without changing the renderer's reference size. Put Customize first in the form, then Details, Setup, and Uninstall. Customize shows the current layout's controls directly, without a disclosure. The pinned card and form share a background; a small gap keeps the card's rounded corners clear of the scroll boundary.

Keep the preview mounted rather than swapping it for a sticky thumbnail: the same image remains readable and the renderer does not restart when the form scrolls. Other settings destinations still use the shared grouped form.

## Refs

- `MyAnimeList/Sources/Mac/ScreenSaver/MacScreenSaverSettingsPage.swift`
- `MyAnimeList/Sources/Views/Library/LibraryProfileSettings/LibraryProfileSettingsPages.swift`

## Validation

- `make build-mac` passed.
- A native SwiftUI harness using the production pane, preview header, and Details section left 301 pt for the form at a 560 pt content height. Scrolling to Tagline left the pinned header unchanged; clicking the toggle updated the visible fixture preview. This checked interaction and layout, not saver artwork rendering.
- A follow-up native harness confirmed that Deck and Cover Wall controls appear immediately when selected, and that the gutter below the preview remains continuous before and after scrolling.
