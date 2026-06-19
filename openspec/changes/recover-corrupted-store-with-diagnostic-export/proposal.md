## Why

AniShelf currently crashes on launch when SwiftData cannot open the main store, which leaves affected users without a recovery path and gives the developer little actionable information. We need a user-visible recovery flow that preserves the failed store, restores app usability with a clean store, and lets users explicitly choose whether to export diagnostics or the quarantined recovery bundle for developer support.

## What Changes

- Detect launch-time main store open failures and quarantine the original store files into a recovery location instead of trapping immediately.
- Recreate a clean persistent store so AniShelf can continue launching after the failed store is isolated.
- Present a blocking recovery experience that explains the store could not be opened, confirms the original files were quarantined, and points users to backup or iCloud sync recovery paths.
- Offer explicit user actions to export a prepared diagnostic package or the recovery bundle through a share sheet.
- Direct users who want developer help to contact `samuelhe52@outlook.com` and share the exported package.

## Capabilities

### New Capabilities
- `persistent-store-recovery`: Recover from launch-time main store open failures by quarantining the failed store, recreating a clean store, informing the user, and supporting explicit diagnostic or recovery-bundle export.

### Modified Capabilities
- None.

## Impact

- Affected code will include `DataProvider` startup, app launch/recovery presentation, backup or recovery-file packaging helpers, and share-sheet presentation.
- The app will begin creating and retaining quarantined store bundles under a recovery directory when startup store open fails.
- No external service dependency is required for this change; export stays user-mediated via the system share sheet.
