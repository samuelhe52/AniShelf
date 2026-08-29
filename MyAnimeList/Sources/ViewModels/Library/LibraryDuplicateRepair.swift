//
//  LibraryDuplicateRepair.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/29.
//

import DataProvider
import Foundation
import LibrarySync

struct LibraryDuplicateEntryGroup: Identifiable {
    let identity: LibraryEntryIdentity
    let entries: [AnimeEntry]

    var id: LibraryEntryIdentity { identity }
    var recommendedEntry: AnimeEntry { entries[0] }

    init?(entries: [AnimeEntry]) {
        guard entries.count > 1,
            let identity = entries.first?.libraryIdentity,
            entries.allSatisfy({ $0.libraryIdentity == identity }),
            let recommendedEntry = AnimeEntryDuplicateResolver.preferredEntry(from: entries)
        else {
            return nil
        }

        self.identity = identity
        self.entries = [recommendedEntry] + entries.filter { $0 !== recommendedEntry }
    }
}

enum LibraryDuplicateRepairError: LocalizedError {
    case groupNoLongerExists
    case selectedEntryNoLongerExists

    var errorDescription: String? {
        switch self {
        case .groupNoLongerExists:
            String(
                localized:
                    "These duplicate anime copies have already changed. Review the updated list and try again."
            )
        case .selectedEntryNoLongerExists:
            String(localized: "The selected anime copy is no longer available. Choose another copy to keep.")
        }
    }
}

extension LibraryStore {
    func resolveDuplicateEntryGroup(
        _ identity: LibraryEntryIdentity,
        keeping selectedEntry: AnimeEntry,
        at repairDate: Date = .now
    ) async throws {
        guard let group = duplicateEntryGroups.first(where: { $0.identity == identity }) else {
            throw LibraryDuplicateRepairError.groupNoLongerExists
        }
        guard let survivor = group.entries.first(where: { $0.id == selectedEntry.id }) else {
            throw LibraryDuplicateRepairError.selectedEntryNoLongerExists
        }

        let shouldQueueCloudUpsert = libraryCloudSyncStatus.isEnabled
        if shouldQueueCloudUpsert {
            await cancelLibrarySyncAndWaitForDuplicateRepair()
        }

        let previousDirtyEntry: LibraryEntrySyncDirtyQueueEntry?
        if shouldQueueCloudUpsert {
            previousDirtyEntry = try syncChangeRecorder.dirtyQueueStore.setPendingUpsert(
                .init(identity: identity, dirtyAt: repairDate)
            )
        } else {
            previousDirtyEntry = nil
        }

        let modelContext = dataProvider.dataHandler.modelContext
        do {
            try syncChangeRecorder.withSuppressedRecording {
                for duplicate in group.entries where duplicate !== survivor {
                    for childEntry in Array(duplicate.childSeasonEntries) {
                        childEntry.parentSeriesEntry = survivor
                    }
                    duplicate.resolveLibraryDisplayFaultsBeforeDeletion()
                    modelContext.delete(duplicate)
                }
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            if shouldQueueCloudUpsert {
                _ = try? syncChangeRecorder.dirtyQueueStore.replaceEntry(
                    previousDirtyEntry,
                    for: identity
                )
            }
            throw error
        }

        rebuildSyncChangeTracking()
        try refreshLibrary()

        if shouldQueueCloudUpsert {
            await resumeLibraryCloudSyncAfterDuplicateRepairIfReady()
        }
    }

    private func resumeLibraryCloudSyncAfterDuplicateRepairIfReady() async {
        guard !requiresDuplicateRepair else { return }

        switch libraryCloudSyncStatus.bootstrapState {
        case .completed:
            syncChangeRecorder.onDirtyQueueChanged?()
        case .notStarted, .running:
            _ = await performLibrarySyncResult(trigger: .localChange)
        case .needsConflictChoice, .failed:
            break
        }
    }
}
