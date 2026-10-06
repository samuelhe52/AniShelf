## 1. Recovery-aware store bootstrap

- [x] 1.1 Replace the trap-only startup path in `DataProvider` with a recovery-aware bootstrap result that can surface either a normal provider or a recovered provider plus recovery metadata.
- [x] 1.2 Add file-level quarantine helpers that preserve `mal.store` and related files in a timestamped recovery directory and write a manifest with the caught error and file inventory.
- [x] 1.3 Recreate a clean active store after successful quarantine and keep the old fatal path only for cases where AniShelf cannot preserve the failed store and recreate a replacement store.

## 2. Recovery presentation and export actions

- [x] 2.1 Thread startup recovery state into `MyAnimeListApp` so launch can present a blocking recovery screen before normal library content.
- [x] 2.2 Build the recovery UI copy and actions to explain the corrupted/unreadable database, the quarantined original files, the clean replacement store, backup/iCloud recovery options, and the developer contact address.
- [x] 2.3 Add prepared export flows for a diagnostic package and a recovery bundle, using the existing share-sheet presentation path and explicit user actions only.

## 3. Packaging and recovery-file reuse

- [x] 3.1 Reuse or extend backup/recovery file helpers so diagnostic exports and recovery-bundle exports are produced from a single well-defined recovery directory structure.
- [x] 3.2 Decide whether recovery-bundle compression happens eagerly or lazily and implement cleanup rules for temporary export artifacts without deleting the quarantined originals.

## 4. Validation

- [x] 4.1 Add focused `DataProvider` tests for quarantine, manifest creation, and clean-store recreation after a simulated startup open failure.
- [x] 4.2 Add app-level tests for recovery-state presentation and for the availability of diagnostic and recovery-bundle export actions.
- [x] 4.3 Validate the affected paths with the smallest relevant AniShelf test targets and confirm the OpenSpec requirements are covered.
