# 020.011 — Quit without waiting for iCloud

## Context

On 2026-10-31 the maintainer reported that ⌘W and ⌘Q sometimes respond slowly
in the Mac app. A Codex investigation traced slow ⌘Q to the quit-time flush
from slice 2 ([004](004-slice-2-mac-shell.md)): when local sync work was
pending, or a sync request was already in flight, `applicationShouldTerminate`
returned `.terminateLater` and waited for a CloudKit pass, with a 10-second
timeout. Because the wait included in-flight passes, quitting could pause even
without a recent edit. The maintainer agreed with that diagnosis. Slow ⌘W is a
separate symptom, since closing the last window does not terminate the app
(`applicationShouldTerminateAfterLastWindowClosed` returns `false`); it is not
addressed here.

## Change

Quitting now depends only on local state being durable, not on iCloud:

- `applicationShouldTerminate` replies after one main-queue hop instead of
  flushing. The hop lets `ModelContext.didSave` notifications that background
  contexts already posted reach `LibrarySyncChangeRecorder`; those are delivered
  through `DispatchQueue.main.async` in `ModelContextSaveObserver`. A dropped
  notification would be lost to sync, because the next launch rebuilds the
  recorder's clock baseline from the store and would absorb the edit without
  queuing it.
- The termination-flush hooks (`configureTerminationFlush`, the timeout, and
  `TerminationReply`) and their wiring in `MyAnimeListApp` were removed.
- Sync is not cancelled at quit; the process exits with the dirty queue as it
  is. Cancelling would only record a cancelled sync status on the way out.

The safety argument: every local edit is written to the on-disk dirty queue
synchronously when its save is recorded, and the queue is rewritten atomically,
so unsent edits survive quit and upload on the next launch. The cost is that
another device sees edits made in the last moments before quitting (local edits
upload 1.5 s after they settle) only when the Mac app next opens.

Rejected: shortening the 10-second timeout, which only shortens the stall.

Unchanged: the before-sleep flush, the after-wake sync, and the iOS background
flush.

## Refs

- `MyAnimeList/Sources/Mac/MacLibraryLifecycle.swift`
- `MyAnimeList/Sources/App/MyAnimeListApp.swift`
- `MyAnimeList/Sources/ViewModels/Library/LibrarySyncChangeRecorder.swift`
- `MyAnimeList/Sources/Utils/ModelContextSaveObserver.swift`
- Validation: `make build-mac` passes. Not run: the app at runtime, and no
  tests.

## Open questions

- Quitting mid-upload can leave a record that reached CloudKit still queued; the
  next launch re-uploads it. The merge is expected to be idempotent but has not
  been exercised.
- Not exercised by hand: edit then quit immediately, quit while offline, and
  delete then quit, each followed by checking the upload after relaunch.
