# 019.003 — Open Entry on native macOS

## Context

Rebasing this branch onto the native macOS work (merged to `main` in PR #23) broke the
Mac build: `TargetContentProvidingIntent` is unavailable on macOS, so the Mac target
could not compile `OpenLibraryEntryIntent` or its `onAppIntentExecution` handler. The
rebase first compiled the intent, its App Shortcut, and the handler for iOS only. That
left the Mac app indexing entries in Spotlight with nothing to open them. The
maintainer asked for a real Mac path, and for the pending route to be extracted rather
than reusing the airing-reminder coordinator.

## Decision

- **Shared route.** `LibraryEntryRouter` (`App/LibraryEntryRouter.swift`) now holds the
  pending "open this entry" route that `AiringReminderCoordinator` used to own
  (`pendingRoute`, `requestEntry(_:inSceneIdentifiedBy:)`, `claimPendingRoute`). The
  claim rules are unchanged: the target scene claims it, or any window does when the
  target has disconnected. `libraryWindowBehaviors` observes the router instead of the
  coordinator.
- **Mac delivery.** `MacLibraryWindows.openEntry(entryIdentityRawID:)` targets the
  frontmost library window, activates the app, and raises or opens a window. The Mac
  airing-reminder handler and the Mac `OpenLibraryEntryIntent.perform()` both call it.
  `perform()` resolves the entity through `AppIntentLibraryContext.entry(for:)`, so the
  recovery, duplicate-repair, and setup gates apply as they do to the other intents.
- **iOS unchanged.** On iOS the intent stays a `TargetContentProvidingIntent` (now an
  iOS-only extension), and the system still delivers it to one scene's
  `onAppIntentExecution`. The Open Entry App Shortcut is available on both platforms.

Rejected: writing the intent's route into `AiringReminderCoordinator`. It worked, but
it gave a reminder type a second, unrelated caller.

## Evidence

- Verified: `make build` and `make build-mac` succeed. `LibraryEntryRouterTests` (moved
  from `AiringReminderManagerTests`), `AiringReminderManagerTests`,
  `LibraryAppIntentsTests`, and `LibrarySyncNotificationBridgeTests` pass on the
  simulator; all but the iOS-only bridge suite also pass on native macOS.
- Verified by the maintainer on 2026-10-18 in a `make run-mac` build: clicking an
  indexed AniShelf result in macOS Spotlight opens the entry, both with the app running
  and from a cold launch.
