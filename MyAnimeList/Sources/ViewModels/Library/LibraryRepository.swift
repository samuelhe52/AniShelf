import DataProvider
import Foundation
import SwiftData

@MainActor
final class LibraryRepository {
    private let dataProvider: DataProvider
    private let syncChangeRecorder: LibrarySyncChangeRecorder?

    init(
        dataProvider: DataProvider,
        syncChangeRecorder: LibrarySyncChangeRecorder? = nil
    ) {
        self.dataProvider = dataProvider
        self.syncChangeRecorder = syncChangeRecorder
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

    func clearLibrary() throws {
        let entries = try dataProvider.getAllModels(ofType: AnimeEntry.self)
        let deleteTokens = try syncChangeRecorder?.recordDeletions(for: entries)
        do {
            try dataProvider.dataHandler.deleteAllEntries()
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

    func insert(_ entry: AnimeEntry) {
        dataProvider.dataHandler.modelContext.insert(entry)
    }

    func existingEntry(tmdbID: Int) -> AnimeEntry? {
        do {
            let entries = try dataProvider.getAllModels(
                ofType: AnimeEntry.self,
                predicate: #Predicate { $0.tmdbID == tmdbID }
            )
            return entries.sorted(by: compareExistingEntries).first
        } catch {
            libraryStoreLogger.warning(
                "Failed to fetch existing entry \(tmdbID, privacy: .public): \(error.localizedDescription)")
            return nil
        }
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
