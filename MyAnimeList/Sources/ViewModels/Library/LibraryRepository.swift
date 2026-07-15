import DataProvider
import Foundation
import LibrarySync
import SwiftData

@MainActor
final class LibraryRepository {
    private let dataProvider: DataProvider
    private let syncChangeRecorder: LibrarySyncChangeRecorder?
    private let transactionSaver: @MainActor (ModelContext) throws -> Void

    init(
        dataProvider: DataProvider,
        syncChangeRecorder: LibrarySyncChangeRecorder? = nil,
        transactionSaver: (@MainActor (ModelContext) throws -> Void)? = nil
    ) {
        self.dataProvider = dataProvider
        self.syncChangeRecorder = syncChangeRecorder
        self.transactionSaver = transactionSaver ?? { try $0.save() }
    }

    func visibleLibraryEntries() throws -> [AnimeEntry] {
        try dataProvider.getAllModels(ofType: AnimeEntry.self, predicate: #Predicate { $0.onDisplay })
    }

    func newEntry(_ entry: AnimeEntry) throws {
        try dataProvider.dataHandler.newEntry(entry)
    }

    func deleteEntry(_ entry: AnimeEntry) throws {
        entry.resolveLibraryDisplayFaultsBeforeDeletion()
        let deleteToken = try syncChangeRecorder?.recordDeletion(for: entry)
        do {
            try dataProvider.dataHandler.deleteEntry(entry)
        } catch {
            if let deleteToken {
                try? syncChangeRecorder?.restoreDeleteRecord(deleteToken)
            }
            throw error
        }
    }

    func replaceEntry(_ entry: AnimeEntry, inserting replacements: [AnimeEntry]) throws {
        entry.resolveLibraryDisplayFaultsBeforeDeletion()
        var deleteToken: LibrarySyncChangeRecorder.PendingDeleteRestoreToken?
        do {
            deleteToken = try syncChangeRecorder?.recordDeletion(for: entry)
            for replacement in replacements {
                dataProvider.dataHandler.modelContext.insert(replacement)
            }
            dataProvider.dataHandler.modelContext.delete(entry)
            try transactionSaver(dataProvider.dataHandler.modelContext)
        } catch {
            dataProvider.dataHandler.modelContext.rollback()
            if let deleteToken {
                try? syncChangeRecorder?.restoreDeleteRecord(deleteToken)
            }
            throw error
        }
    }

    func clearLibrary() throws {
        let entries = try dataProvider.getAllModels(ofType: AnimeEntry.self)
        // Persist the delete tombstones before mutating SwiftData so a later
        // sync can still observe the deletion intent if the local delete succeeds.
        let deleteTokens = try syncChangeRecorder?.recordDeletions(for: entries)
        do {
            try dataProvider.dataHandler.deleteEntries(entries)
        } catch {
            if let deleteTokens {
                try? syncChangeRecorder?.restoreDeleteRecords(deleteTokens)
            }
            throw error
        }
    }

    func save() throws {
        try dataProvider.dataHandler.modelContext.save()
    }

    func toggleFavorite(_ entry: AnimeEntry) {
        dataProvider.dataHandler.toggleFavorite(entry: entry)
    }

    func insert(_ entry: AnimeEntry) {
        dataProvider.dataHandler.modelContext.insert(entry)
    }

    func existingEntry(tmdbID: Int) -> AnimeEntry? {
        do {
            return try matchingEntries(tmdbID: tmdbID)
                .sorted(by: compareExistingEntries)
                .first
        } catch {
            libraryStoreLogger.warning(
                "Failed to fetch existing entry \(tmdbID, privacy: .public): \(error.localizedDescription)")
            return nil
        }
    }

    func existingEntry(identity: LibraryEntrySyncIdentity) -> AnimeEntry? {
        guard let tmdbID = identity.tmdbID else {
            libraryStoreLogger.warning(
                "Failed to parse TMDb ID from sync entry \(identity.rawID, privacy: .public).")
            return nil
        }
        do {
            return try matchingEntries(tmdbID: tmdbID)
                .filter { $0.syncIdentity == identity }
                .sorted(by: compareExistingEntries)
                .first
        } catch {
            libraryStoreLogger.warning(
                "Failed to fetch sync entry \(identity.rawID, privacy: .public): \(error.localizedDescription)")
            return nil
        }
    }

    func existingEntry(identityRawID: String) -> AnimeEntry? {
        guard let suffix = identityRawID.split(separator: ":").last,
            let tmdbID = Int(suffix)
        else {
            libraryStoreLogger.warning(
                "Failed to parse TMDb ID from local entry identity \(identityRawID, privacy: .private).")
            return nil
        }
        do {
            return try matchingEntries(tmdbID: tmdbID)
                .filter { $0.syncIdentity.rawID == identityRawID }
                .sorted(by: compareExistingEntries)
                .first
        } catch {
            libraryStoreLogger.warning(
                "Failed to fetch local entry identity \(identityRawID, privacy: .private): \(error.localizedDescription)"
            )
            return nil
        }
    }

    private func matchingEntries(tmdbID: Int) throws -> [AnimeEntry] {
        try dataProvider.getModels(
            ofType: AnimeEntry.self,
            predicate: #Predicate { $0.tmdbID == tmdbID }
        )
    }

    private func compareExistingEntries(_ lhs: AnimeEntry, _ rhs: AnimeEntry) -> Bool {
        if lhs.onDisplay != rhs.onDisplay {
            return lhs.onDisplay && !rhs.onDisplay
        }

        if lhs.childSeasonEntries.count != rhs.childSeasonEntries.count {
            return lhs.childSeasonEntries.count > rhs.childSeasonEntries.count
        }

        if (lhs.detail != nil) != (rhs.detail != nil) {
            return lhs.detail != nil
        }

        if lhs.dateSaved != rhs.dateSaved {
            return lhs.dateSaved > rhs.dateSaved
        }

        return lhs.name < rhs.name
    }
}
