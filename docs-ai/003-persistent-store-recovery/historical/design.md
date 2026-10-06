## Context

AniShelf currently constructs `DataProvider.default` during `MyAnimeListApp.init()`. If SwiftData cannot create the `ModelContainer`, `DataProvider` logs and then traps, which turns any launch-time store-open failure into a hard startup crash. The app already has code for backup packaging (`BackupManager`) and user-mediated export (`ShareSheetPresenter` / `LazyShareLink`), so the change can build on existing local file and share-sheet patterns rather than introducing network upload or a new external dependency.

This change crosses persistence, app launch, file packaging, and recovery UX. The design needs to preserve the failed store for later inspection, restore app usability with a clean store, and make user consent explicit before any diagnostic or recovery data leaves the device.

## Goals / Non-Goals

**Goals:**
- Replace fatal launch behavior for main-store open failures with a deterministic quarantine-and-recover path.
- Preserve the failed store files in a recovery directory for later export or manual inspection.
- Allow AniShelf to continue launching with a clean replacement store after quarantine succeeds.
- Present a blocking recovery experience that explains what happened, points users to backups or iCloud sync, and offers opt-in export actions.
- Reuse existing local packaging and share-sheet primitives where practical.

**Non-Goals:**
- Automatic server upload, background upload, or silent telemetry collection.
- Automatic restore from backups or iCloud sync.
- Best-effort repair of the quarantined database contents in-app.
- Recovery for arbitrary later runtime persistence failures outside the initial main-store bootstrap path.

## Decisions

### 1. Convert startup from trap-only bootstrap to recovery-aware bootstrap

`DataProvider` should stop exposing launch failure solely as `fatalError` and instead provide a recovery-aware bootstrap path that can either:
- return a normal provider, or
- quarantine the failed store, recreate a clean store, and return both the fresh provider and a recovery report for the UI.

Rationale:
- The current trap occurs before SwiftUI can present any remediation UI.
- The app needs structured recovery metadata to drive user messaging and export.

Alternatives considered:
- Keep `fatalError` and rely on TestFlight crash logs. Rejected because it preserves no self-service recovery path and no local export path once the crash is removed.
- Catch the error in `MyAnimeListApp` without changing `DataProvider`. Rejected because the failure originates before any usable provider instance exists; recovery needs file-level knowledge currently owned by `DataProvider`.

### 2. Quarantine the failed store in a timestamped recovery folder under the existing store parent

On launch-time store-open failure, AniShelf should move the relevant store artifacts (`mal.store`, `mal.store-wal`, `mal.store-shm`, and any adjacent matching files needed for forensic recovery) into a timestamped recovery directory under the persistent store root, for example `.../DataProvider/Recovery/<timestamp>/`.

The quarantine directory should include a manifest file with:
- app version/build
- OS version
- store file names and sizes
- caught error text
- recovery timestamp

Rationale:
- Preserves the original failure state for later export.
- Keeps the recovery bundle local, predictable, and scoped to AniShelf-managed files.
- Avoids silent deletion of user data.

Alternatives considered:
- Delete the failed store in place and recreate immediately. Rejected because it discards the only artifact that might explain or recover the issue.
- Leave the failed files in place and create a second active store elsewhere. Rejected because it complicates future backup/restore and leaves the launch path ambiguous.

### 3. Recreate a clean store immediately after successful quarantine

After quarantine succeeds, AniShelf should create a new empty main store at the normal path and continue launching against that new store. The recovery state should be surfaced to the app so the first visible screen is a blocking recovery experience rather than the normal library UI.

Rationale:
- Restores app usability in the same session.
- Avoids trapping again on the next launch because the bad files still occupy the active path.

Alternatives considered:
- Force-quit after quarantine and require the user to relaunch. Rejected because it adds friction and still requires a second path to explain what happened.

### 4. Use a dedicated blocking recovery screen with explicit export actions

AniShelf should present a dedicated recovery screen before ordinary app content when startup recovery has occurred. The screen should:
- state that the database is corrupted or unreadable and AniShelf could not open it
- confirm that AniShelf quarantined the original files
- explain that a clean store has been created
- tell users that backups from earlier builds or iCloud sync may help recover data
- offer `Export Diagnostic`, `Export Recovery Bundle`, and a non-export continue/dismiss path
- instruct users to contact `samuelhe52@outlook.com` if they want developer assistance

Rationale:
- Startup recovery is exceptional and should not be hidden behind a toast or transient alert.
- Export consent must be explicit and understandable.

Alternatives considered:
- Present a standard alert. Rejected because the message and actions are too dense for an alert and export may need preparation time.
- Automatically open a share sheet. Rejected because exporting the recovery data must remain opt-in.

### 5. Prepare two export packages and share them through the existing share-sheet path

AniShelf should prepare:
- a diagnostic export: manifest plus sanitized recovery metadata/log text
- a recovery bundle export: the quarantined store directory packaged for sharing

Both exports should be handed to the existing share-sheet presentation path. Packaging logic should live near backup/recovery file helpers so file handling stays centralized.

Rationale:
- The diagnostic export is the low-friction path users can share first.
- The recovery bundle is stronger but more sensitive and should remain a separate explicit action.
- Existing share-sheet code avoids inventing a new export UI pattern.

Alternatives considered:
- One combined package only. Rejected because some users will reasonably prefer to share metadata before the full quarantined store.
- Direct network upload. Rejected for scope, privacy, and user-consent reasons.

## Risks / Trade-offs

- [User-facing “database corrupted” copy may be broader than the underlying cause] → Pair the copy with “AniShelf was unable to open it” so the message stays understandable without claiming a proven low-level corruption mechanism.
- [Quarantine may fail if files cannot be moved while partially opened] → Fall back to copy-then-remove where needed, and keep the current fatal path only if AniShelf cannot both preserve the original files and create a clean replacement store.
- [Recovery bundles may contain sensitive personal library data] → Keep export fully opt-in, separate diagnostic and recovery actions, and never upload automatically.
- [A clean replacement store may make the library appear empty before the user restores data] → The blocking recovery screen must explain this clearly and point to backup/iCloud options before the user continues.
- [Accumulated recovery folders may consume disk space] → Limit automatic creation to real startup failures and name directories predictably so future cleanup tooling is possible.

## Migration Plan

1. Introduce a recovery-aware `DataProvider` bootstrap and structured recovery result.
2. Add quarantine directory creation and manifest writing around startup store-open failures.
3. Recreate the clean store and pass recovery state into app launch.
4. Add the blocking recovery screen and export actions.
5. Reuse or extend backup/share helpers to package diagnostic and recovery exports.
6. Add focused tests for quarantine, clean-store recreation, recovery-state presentation, and export packaging.

Rollback strategy:
- If the recovery path proves unstable during development, the app can temporarily fall back to the current trap-only behavior by disabling the recovery-aware bootstrap entrypoint while keeping the internal packaging helpers isolated.

## Open Questions

- Should the recovery screen remain dismissible after one acknowledgment, or should AniShelf keep a small persistent reminder until the user exports or explicitly declines?
- Should the diagnostic package include recent app log excerpts beyond the caught error and manifest?
- Should the recovery bundle be zipped eagerly during recovery or prepared lazily only when the user taps export?
