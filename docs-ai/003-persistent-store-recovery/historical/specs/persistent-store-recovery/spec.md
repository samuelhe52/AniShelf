## ADDED Requirements

### Requirement: Launch-time store open failures SHALL preserve the failed store before recovery
When AniShelf cannot open the main persistent store during startup, the app SHALL quarantine the failed store files into a recovery directory before using a replacement store.

#### Scenario: Failed startup store is quarantined
- **WHEN** AniShelf encounters a main-store open failure during launch
- **THEN** it SHALL create a recovery directory for that failure
- **AND** it SHALL move or copy the failed store artifacts into that recovery directory before replacing the active store

#### Scenario: Recovery metadata is recorded
- **WHEN** AniShelf quarantines a failed startup store
- **THEN** it SHALL create a diagnostic manifest describing the caught error, app/build context, recovery timestamp, and quarantined files

### Requirement: AniShelf SHALL recreate a clean store after successful quarantine
After the failed store has been quarantined successfully, AniShelf SHALL recreate a clean store at the normal active path so the app can continue launching.

#### Scenario: Launch continues with replacement store
- **WHEN** quarantine of the failed store succeeds
- **THEN** AniShelf SHALL create a new empty active store
- **AND** the app SHALL continue launching against that replacement store instead of terminating

#### Scenario: Recovery cannot preserve original data
- **WHEN** AniShelf cannot both preserve the failed store and create a replacement store
- **THEN** it SHALL treat startup recovery as failed
- **AND** it SHALL not silently delete the original store in place

### Requirement: AniShelf SHALL present a blocking recovery explanation after startup recovery
If startup recovery occurs, AniShelf SHALL present a blocking recovery experience before ordinary app content to explain what happened and what the user can do next.

#### Scenario: Recovery message explains quarantine and replacement
- **WHEN** AniShelf launches after quarantining a failed store
- **THEN** it SHALL tell the user that the database is corrupted or unreadable and AniShelf was unable to open it
- **AND** it SHALL tell the user that the original database files were quarantined
- **AND** it SHALL tell the user that AniShelf created a clean replacement store

#### Scenario: Recovery message points to backup options
- **WHEN** the recovery explanation is shown
- **THEN** it SHALL inform the user that backups from previous builds or iCloud sync may provide a recovery path

#### Scenario: Recovery message points users to developer contact
- **WHEN** the recovery explanation is shown
- **THEN** it SHALL tell users they can contact `samuelhe52@outlook.com` if they want the developer to try to resolve the issue

### Requirement: AniShelf SHALL support explicit diagnostic export after startup recovery
AniShelf SHALL allow the user to export a prepared diagnostic package after startup recovery, but only after explicit user action.

#### Scenario: User exports diagnostic package
- **WHEN** the user chooses the diagnostic export action from the recovery experience
- **THEN** AniShelf SHALL prepare a diagnostic package from the recorded recovery metadata
- **AND** it SHALL present a system share sheet for that prepared export

#### Scenario: User declines diagnostic export
- **WHEN** the user does not choose the diagnostic export action
- **THEN** AniShelf SHALL not share or upload the diagnostic package automatically

### Requirement: AniShelf SHALL support explicit recovery-bundle export after startup recovery
AniShelf SHALL allow the user to export the quarantined recovery bundle after startup recovery, but only after explicit user action.

#### Scenario: User exports recovery bundle
- **WHEN** the user chooses the recovery-bundle export action from the recovery experience
- **THEN** AniShelf SHALL prepare a shareable export from the quarantined recovery files
- **AND** it SHALL present a system share sheet for that prepared export

#### Scenario: User declines recovery-bundle export
- **WHEN** the user does not choose the recovery-bundle export action
- **THEN** AniShelf SHALL keep the quarantined recovery files local to the device
