//
//  LibraryBackupRestoreTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import Foundation
import Testing
import ZIPFoundation

@testable import DataProvider
@testable import LibrarySync
@testable import MyAnimeList

struct LibraryBackupRestoreTests {
    @Test func testStartupRecoveryPresentationOffersBothExplicitExports() {
        #expect(StartupRecoveryPresentation.availableExports == [.diagnostic, .recoveryBundle])
    }

    @Test @MainActor func testStartupRecoveryActivityGateBlocksLibraryWorkUntilAcknowledged() {
        let gate = StartupRecoveryActivityGate(isBlocked: true)

        #expect(!gate.allowsLibraryActivity)

        gate.isBlocked = false

        #expect(gate.allowsLibraryActivity)
    }

    @Test func testRecoveryExportsUseQuarantineDirectoryAndCleanupOnlyTemporaryFiles() throws {
        let fileManager = FileManager.default
        let rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AniShelfTests-recovery-export-\(UUID().uuidString)", isDirectory: true)
        let recoveryDirectory = rootDirectory.appendingPathComponent("Recovery/20260619-120000-000")
        let manifestURL = recoveryDirectory.appendingPathComponent("manifest.json")
        try fileManager.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootDirectory) }
        try Data("diagnostic".utf8).write(to: manifestURL)
        try Data("store".utf8).write(to: recoveryDirectory.appendingPathComponent("mal.store"))

        let recovery = PersistentStoreRecovery(
            recoveredAt: Date(timeIntervalSince1970: 1_750_000_000),
            recoveryDirectoryURL: recoveryDirectory,
            manifestURL: manifestURL,
            files: [PersistentStoreRecoveryFile(name: "mal.store", size: 5)]
        )
        let diagnosticURL = try RecoveryExportManager.prepareExport(.diagnostic, for: recovery)
        let bundleURL = try RecoveryExportManager.prepareExport(.recoveryBundle, for: recovery)

        #expect(try Data(contentsOf: diagnosticURL) == Data("diagnostic".utf8))
        let archive = try Archive(url: bundleURL, accessMode: .read)
        #expect(archive.contains { $0.path.hasSuffix("/mal.store") })

        RecoveryExportManager.cleanupTemporaryExports(for: recovery)

        #expect(!fileManager.fileExists(atPath: diagnosticURL.deletingLastPathComponent().path()))
        #expect(fileManager.fileExists(atPath: recoveryDirectory.path()))
        #expect(fileManager.fileExists(atPath: manifestURL.path()))

        _ = try RecoveryExportManager.prepareExport(.recoveryBundle, for: recovery)
        RecoveryExportManager.cleanupAllTemporaryExports()

        #expect(!fileManager.fileExists(atPath: diagnosticURL.deletingLastPathComponent().path()))
        #expect(fileManager.fileExists(atPath: recoveryDirectory.path()))
    }

    @Test @MainActor func testRestoreBackupIsBlockedWhileLibraryCloudSyncIsEnabled() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        store.updateLibraryCloudSyncStatus { status in
            status.isEnabled = true
            status.bootstrapState = .completed
        }
        let actions = LibraryProfileSettingsActions(store: store)

        #expect(throws: LibraryBackupRestorePolicyError.cloudSyncEnabled) {
            try actions.restoreBackup(from: URL(fileURLWithPath: "/tmp/unused.mallib"))
        }
    }

    @Test @MainActor func testRestoreBackupIsBlockedWhileLibraryCloudSyncPhaseIsActive() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        store.updateLibraryCloudSyncStatus { status in
            status.isEnabled = false
            status.currentPhase = .exporting
            status.lastResult = nil
        }
        let actions = LibraryProfileSettingsActions(store: store)

        #expect(throws: LibraryBackupRestorePolicyError.cloudSyncEnabled) {
            try actions.restoreBackup(from: URL(fileURLWithPath: "/tmp/unused.mallib"))
        }
    }

    @Test @MainActor func testRestoreBackupClearsLocalSyncStateAndResetsCloudSync() throws {
        let fileManager = FileManager.default
        let sourceDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AniShelfTests-actions-restore-source-\(UUID().uuidString)", isDirectory: true)
        let targetDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AniShelfTests-actions-restore-target-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: sourceDirectory)
            try? fileManager.removeItem(at: targetDirectory)
        }

        let sourceProvider = DataProvider(url: sourceDirectory.appendingPathComponent("library.store"))
        try sourceProvider.dataHandler.newEntry(
            AnimeEntry(name: "Restored", type: .movie, tmdbID: 700_001)
        )
        let backupURL = try BackupManager(dataProvider: sourceProvider).createBackup()
        defer { try? fileManager.removeItem(at: backupURL) }

        let defaultsSuiteName = "MyAnimeListTests.RestoreBackupSyncState.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        let targetProvider = DataProvider(url: targetDirectory.appendingPathComponent("library.store"))
        try targetProvider.dataHandler.newEntry(
            AnimeEntry(name: "Replace Me", type: .movie, tmdbID: 700_002)
        )
        let store = LibraryStore(
            dataProvider: targetProvider,
            preferences: LibraryPreferences(defaults: defaults)
        )
        store.updateLibraryCloudSyncStatus { status in
            status.bootstrapState = .failed
            status.retryState = .init(
                failureRetryAttempt: 2,
                nextRetryAllowedAt: Date(timeIntervalSince1970: 1_800),
                automaticRetriesExhausted: true
            )
            status.lastResult = .retryableFailure
            status.lastFailureReason = "Previous failure"
        }
        try store.syncChangeRecorder.dirtyQueueStore.setPendingUpsert(
            .init(
                identity: .init(entryType: .movie, tmdbID: 700_002),
                dirtyAt: Date(timeIntervalSince1970: 1_700)
            )
        )

        let tokenDefaultsSuiteName = "MyAnimeListTests.RestoreBackupTokenStore.\(UUID().uuidString)"
        let tokenDefaults = UserDefaults(suiteName: tokenDefaultsSuiteName)!
        tokenDefaults.removePersistentDomain(forName: tokenDefaultsSuiteName)
        defer { tokenDefaults.removePersistentDomain(forName: tokenDefaultsSuiteName) }
        let tokenStore = CloudLibrarySyncChangeTokenStore(
            userDefaults: tokenDefaults,
            keyPrefix: "MyAnimeListTests.CustomChangeTokenStore"
        )
        let namespace = CloudLibrarySyncChangeTokenStore.Namespace(
            containerIdentifier: "test-container",
            accountIdentifier: "test-account"
        )
        let tokenKey = tokenStore.tokenKey(
            for: CloudLibrarySyncClient.recordZoneID,
            namespace: namespace
        )
        tokenDefaults.set(Data([0x01]), forKey: tokenKey)
        store.configureLibrarySyncCoordinator(changeTokenStore: tokenStore)

        let actions = LibraryProfileSettingsActions(
            store: store,
            refreshInfosHandler: { _, _ in }
        )

        try actions.restoreBackup(from: backupURL)

        #expect(store.library.map(\.tmdbID) == [700_001])
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
        #expect(tokenDefaults.object(forKey: tokenKey) == nil)
        #expect(store.libraryCloudSyncStatus == .defaultValue)
        #expect(store.preferences.load().cloudSyncStatus == .defaultValue)
    }

    @Test @MainActor func testStartupRecoveryRebootsEnabledCloudSyncWithFreshMetadata() async throws {
        let store = makeSyncReadyStore()
        let staleDeleteIdentity = LibraryEntrySyncIdentity(entryType: .movie, tmdbID: 910_001)
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries([
            .delete(
                .init(
                    tombstone: .init(
                        identity: staleDeleteIdentity,
                        tmdbID: 910_001,
                        parentSeriesID: nil,
                        seasonNumber: nil,
                        entryType: .movie,
                        deletedAt: referenceDate(year: 2026, month: 6, day: 10)
                    )
                )
            )
        ])

        let tokenDefaultsSuiteName = "MyAnimeListTests.StartupRecoveryTokenStore.\(UUID().uuidString)"
        let tokenDefaults = UserDefaults(suiteName: tokenDefaultsSuiteName)!
        tokenDefaults.removePersistentDomain(forName: tokenDefaultsSuiteName)
        defer { tokenDefaults.removePersistentDomain(forName: tokenDefaultsSuiteName) }
        let tokenStore = CloudLibrarySyncChangeTokenStore(
            userDefaults: tokenDefaults,
            keyPrefix: "MyAnimeListTests.StartupRecoveryChangeTokenStore"
        )
        let namespace = makeNamespace()
        let tokenKey = tokenStore.tokenKey(
            for: CloudLibrarySyncClient.recordZoneID,
            namespace: namespace
        )
        tokenDefaults.set(Data([0x01, 0x02, 0x03]), forKey: tokenKey)

        let client = CloudLibrarySyncClient()
        let remoteIdentity = LibraryEntrySyncIdentity(entryType: .movie, tmdbID: 910_002)
        let remoteSnapshot = makeSnapshot(
            identity: remoteIdentity,
            tmdbID: 910_002,
            entryType: .movie
        )
        let database = FakeCloudLibrarySyncDatabase(
            changes: [try makeChangeBatch(client: client, snapshots: [remoteSnapshot])]
        )
        store.configureLibrarySyncCoordinator(
            client: client,
            database: database,
            changeTokenStore: tokenStore,
            namespaceProvider: { namespace },
            hydrateMissingEntry: { snapshot, store in
                let entry = AnimeEntry(
                    name: "Recovered Placeholder",
                    type: snapshot.entryType,
                    tmdbID: snapshot.tmdbID
                )
                store.repository.insert(entry)
                return entry
            }
        )

        store.prepareLibraryCloudSyncAfterPersistentStoreRecovery()

        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
        #expect(tokenDefaults.object(forKey: tokenKey) == nil)
        #expect(store.libraryCloudSyncStatus.isEnabled)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .running)

        let result = await store.performLibrarySyncResult(trigger: .appLaunch)

        #expect(result == .success)
        #expect(database.fetchedChangeTokens.count == 1)
        #expect(database.fetchedChangeTokens[0] == nil)
        #expect(store.libraryCloudSyncStatus.bootstrapState == .completed)
        #expect(store.library.map(\.tmdbID) == [910_002])
        #expect(store.syncChangeRecorder.dirtyQueueStore.load().entries.isEmpty)
        #expect(!database.savedRecords.contains { $0.recordID == client.recordID(for: staleDeleteIdentity) })
    }

    @Test @MainActor func testLibraryProfileSettingsActionsCreateBackupReturnsArchive() throws {
        let fileManager = FileManager.default
        let storeDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AniShelfTests-create-backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: storeDirectory) }

        let dataProvider = DataProvider(url: storeDirectory.appendingPathComponent("create-backup.store"))
        let store = LibraryStore(dataProvider: dataProvider)
        let actions = LibraryProfileSettingsActions(store: store)

        let backupURL = try actions.createBackup()

        #expect(FileManager.default.fileExists(atPath: backupURL.path()))
    }


    @Test @MainActor func testLibraryProfileSettingsActionsClearLibraryRemovesEntries() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        store.newEntryFromEntryMetadata(
            EntryMetadata(
                name: "Clear Me",
                nameTranslations: [:],
                overview: nil,
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 100_001,
                onAirDate: nil,
                linkToDetails: nil,
                type: .movie
            )
        )
        try store.refreshLibrary()
        #expect(store.library.count == 1)

        let actions = LibraryProfileSettingsActions(store: store)
        actions.clearLibrary()
        try store.refreshLibrary()

        #expect(store.library.isEmpty)
    }
    @Test @MainActor func testBackup() throws {
        let fileManager = FileManager.default
        let storeDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AniShelfTests-backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: storeDirectory) }

        let dataProvider = DataProvider(url: storeDirectory.appendingPathComponent("backup.store"))
        let backupManager = BackupManager(dataProvider: dataProvider)
        let backupURL = try backupManager.createBackup()
        #expect(fileManager.fileExists(atPath: backupURL.path()))
        let attributes = try fileManager.attributesOfItem(atPath: backupURL.path())
        let size = attributes[.size] as? NSNumber
        #expect(size != nil && size!.intValue > 0, "Backup file should not be empty")

        let parentDirectoryURL = backupURL.deletingLastPathComponent()
        try fileManager.unzipItem(at: backupURL, to: parentDirectoryURL)
    }

    @Test @MainActor func testBackupUsesDeflateCompression() throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AniShelfTests-compressed-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        let dataProvider = DataProvider(url: storeDirectory.appendingPathComponent("compressed.store"))
        let entry = AnimeEntry(
            name: "Compression Fixture",
            type: .movie,
            tmdbID: 400_003,
            dateSaved: referenceDate(year: 2026, month: 5, day: 19)
        )
        entry.notes = String(repeating: "backup compression fixture ", count: 1_024)
        try dataProvider.dataHandler.newEntry(entry)

        let backupURL = try BackupManager(dataProvider: dataProvider).createBackup()
        let archive = try Archive(url: backupURL, accessMode: .read)
        let storeEntry = try #require(
            archive.first { $0.path.hasSuffix("/compressed.store") }
        )

        #expect(storeEntry.compressedSize < storeEntry.uncompressedSize)
    }

    @Test @MainActor func testRestoreBackupDoesNotDeleteCurrentStoreWhenArchiveIsInvalid() throws {
        let fileManager = FileManager.default
        let storeDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AniShelfTests-restore-rollback-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: storeDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: storeDirectory) }

        let dataProvider = DataProvider(url: storeDirectory.appendingPathComponent("restore.store"))
        let entry = AnimeEntry(
            name: "Keep Me",
            type: .movie,
            tmdbID: 400_004,
            dateSaved: referenceDate(year: 2026, month: 5, day: 20)
        )
        try dataProvider.dataHandler.newEntry(entry)
        #expect(try dataProvider.getAllModels(ofType: AnimeEntry.self).count == 1)

        let malformedRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("AniShelfTests-invalid-backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: malformedRootURL,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: malformedRootURL) }

        let stagedBackupURL = malformedRootURL.appendingPathComponent("BrokenBackup", isDirectory: true)
        try fileManager.createDirectory(
            at: stagedBackupURL,
            withIntermediateDirectories: true
        )

        let archiveURL = fileManager.temporaryDirectory.appendingPathComponent(
            "AniShelf-invalid-\(UUID().uuidString).mallib"
        )
        defer { try? fileManager.removeItem(at: archiveURL) }
        try fileManager.zipItem(
            at: stagedBackupURL,
            to: archiveURL,
            shouldKeepParent: true,
            compressionMethod: .deflate
        )

        let manager = BackupManager(dataProvider: dataProvider)

        #expect(throws: Error.self) {
            try manager.restoreBackup(from: archiveURL)
        }

        dataProvider.reloadDataStore()
        #expect(try dataProvider.getAllModels(ofType: AnimeEntry.self).map(\.tmdbID) == [400_004])
    }

    @Test @MainActor func testRestoreBackupReloadsCurrentSchemaLibraryAndAllowsSave() throws {
        let fileManager = FileManager.default
        let sourceDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AniShelfTests-restore-source-\(UUID().uuidString)", isDirectory: true)
        let targetDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AniShelfTests-restore-target-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: sourceDirectory)
            try? fileManager.removeItem(at: targetDirectory)
        }

        let sourceProvider = DataProvider(url: sourceDirectory.appendingPathComponent("library.store"))
        let restoredEntry = AnimeEntry(
            name: "Restored Cloud Library",
            type: .series,
            customPosterPath: "/posters/restored-custom.jpg",
            tmdbID: 500_001,
            detail: AnimeEntryDetail(
                language: "en-US",
                title: "Restored Cloud Library",
                episodeCount: 12
            ),
            dateSaved: referenceDate(year: 2026, month: 5, day: 27),
            dateStarted: referenceDate(year: 2026, month: 5, day: 28),
            score: 4,
            usingCustomPoster: true
        )
        restoredEntry.favorite = true
        restoredEntry.notes = "Restored notes"
        restoredEntry.applyEpisodeProgressSnapshot(
            seasonNumber: 1,
            watchedThroughEpisode: 7, updatedAt: referenceDate(year: 2026, month: 5, day: 29)
        )
        try sourceProvider.dataHandler.newEntry(restoredEntry)
        let backupURL = try BackupManager(dataProvider: sourceProvider).createBackup()
        defer { try? fileManager.removeItem(at: backupURL) }

        let targetProvider = DataProvider(url: targetDirectory.appendingPathComponent("library.store"))
        try targetProvider.dataHandler.newEntry(
            AnimeEntry(name: "Replace Me", type: .movie, tmdbID: 500_002)
        )

        try BackupManager(dataProvider: targetProvider).restoreBackup(from: backupURL)
        let entries = try targetProvider.getAllModels(ofType: AnimeEntry.self)
        let entry = try #require(entries.first)

        #expect(entries.count == 1)
        #expect(entry.tmdbID == 500_001)
        #expect(entry.notes == "Restored notes")
        #expect(entry.favorite)
        #expect(entry.score == 4)
        #expect(entry.usingCustomPoster)
        #expect(entry.customPosterPath == "/posters/restored-custom.jpg")
        #expect(entry.episodeProgressSummary(forSeason: 1).watchedThroughEpisode == 7)

        entry.notes = "Saved after restore"
        try targetProvider.dataHandler.modelContext.save()
        targetProvider.reloadDataStore()
        #expect(try targetProvider.getAllModels(ofType: AnimeEntry.self).first?.notes == "Saved after restore")
    }
}
