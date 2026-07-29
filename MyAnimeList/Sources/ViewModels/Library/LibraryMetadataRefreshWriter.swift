//
//  LibraryMetadataRefreshWriter.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/11.
//

import DataProvider
import Foundation
import SwiftData

struct LibraryMetadataRefreshUpdate: Sendable {
    var entryID: PersistentIdentifier
    var info: EntryMetadata
    var detail: AnimeEntryDetailDTO
    /// Keeps a user's selected poster intact while replacing TMDb-owned metadata.
    var preservingCustomPoster: Bool
    /// The selected poster path to continue prefetching when `preservingCustomPoster` is true.
    var customPosterPath: String? = nil
}

struct LibraryMetadataRefreshParentUpdate: Sendable {
    var childEntryID: PersistentIdentifier
    var parentSeriesID: Int
    var parentInfo: EntryMetadata?
    var parentDetail: AnimeEntryDetailDTO?
}

struct LibraryMetadataRefreshApplyResult: Sendable {
    var writtenCount: Int
    var skippedCount: Int
}

struct LibraryMetadataRefreshWriter: Sendable {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func apply(
        updates: [LibraryMetadataRefreshUpdate],
        parentUpdates: [LibraryMetadataRefreshParentUpdate]
    ) async throws -> LibraryMetadataRefreshApplyResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let modelContext = ModelContext(modelContainer)
                do {
                    let result = try apply(
                        updates: updates,
                        parentUpdates: parentUpdates,
                        in: modelContext
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func apply(
        updates: [LibraryMetadataRefreshUpdate],
        parentUpdates: [LibraryMetadataRefreshParentUpdate],
        in modelContext: ModelContext
    ) throws -> LibraryMetadataRefreshApplyResult {
        assert(!Thread.isMainThread, "Metadata refresh should not run on the main thread.")
        do {
            var entriesByID: [PersistentIdentifier: AnimeEntry] = [:]
            var hasChanges = false
            var skippedIDs: Set<PersistentIdentifier> = []
            var writtenIDs: Set<PersistentIdentifier> = []

            for update in updates {
                guard let entry = try entry(for: update.entryID, in: modelContext) else { continue }
                entriesByID[update.entryID] = entry

                let metadataChanged = !entry.matchesRefreshMetadata(update.info)
                let detailChanged = !LibraryMetadataRefreshDetailComparator.matches(
                    existing: entry.detail,
                    fetched: update.detail
                )
                let shouldClearParent =
                    update.info.type.parentSeriesID == nil
                    && entry.parentSeriesEntry != nil

                guard metadataChanged || detailChanged || shouldClearParent else {
                    skippedIDs.insert(update.entryID)
                    continue
                }

                if metadataChanged {
                    entry.replaceMetadata(
                        from: update.info,
                        preservingCustomPoster: update.preservingCustomPoster
                    )
                }
                if detailChanged {
                    entry.replaceDetail(from: update.detail)
                }
                if shouldClearParent {
                    entry.parentSeriesEntry = nil
                }
                hasChanges = true
                writtenIDs.insert(update.entryID)
            }

            for parentUpdate in parentUpdates {
                let fetchedChildEntry: AnimeEntry?
                if let cachedEntry = entriesByID[parentUpdate.childEntryID] {
                    fetchedChildEntry = cachedEntry
                } else {
                    fetchedChildEntry = try entry(for: parentUpdate.childEntryID, in: modelContext)
                }

                guard let childEntry = fetchedChildEntry else { continue }

                if childEntry.parentSeriesEntry?.tmdbID == parentUpdate.parentSeriesID {
                    continue
                }

                let parentEntry: AnimeEntry?
                if let existingParent = try existingEntry(
                    tmdbID: parentUpdate.parentSeriesID,
                    in: modelContext
                ) {
                    parentEntry = existingParent
                } else if let parentInfo = parentUpdate.parentInfo,
                    let parentDetail = parentUpdate.parentDetail
                {
                    let insertedParent = AnimeEntry(fromInfo: parentInfo)
                    insertedParent.setDisplayState(false)
                    insertedParent.replaceDetail(from: parentDetail)
                    modelContext.insert(insertedParent)
                    parentEntry = insertedParent
                } else {
                    parentEntry = nil
                }

                if let parentEntry {
                    childEntry.parentSeriesEntry = parentEntry
                    hasChanges = true
                    skippedIDs.remove(parentUpdate.childEntryID)
                    writtenIDs.insert(parentUpdate.childEntryID)
                }
            }

            if hasChanges {
                try modelContext.save()
            }
            return LibraryMetadataRefreshApplyResult(
                writtenCount: writtenIDs.count,
                skippedCount: skippedIDs.count
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func entry(
        for id: PersistentIdentifier,
        in modelContext: ModelContext
    ) throws -> AnimeEntry? {
        var descriptor = FetchDescriptor(
            predicate: #Predicate<AnimeEntry> { entry in
                entry.persistentModelID == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func existingEntry(
        tmdbID: Int,
        in modelContext: ModelContext
    ) throws -> AnimeEntry? {
        let descriptor = FetchDescriptor(
            predicate: #Predicate<AnimeEntry> { entry in
                entry.tmdbID == tmdbID
            }
        )
        return AnimeEntryDuplicateResolver.preferredEntry(
            from: try modelContext.fetch(descriptor)
        )
    }
}

extension AnimeEntry {
    fileprivate func matchesRefreshMetadata(_ info: EntryMetadata) -> Bool {
        var persistedMetadata = entryMetadata
        var fetchedMetadata = info
        // Entry-level metadata does not persist logos; refreshed logos are compared through
        // AnimeEntryDetail.logoImagePath instead.
        persistedMetadata.logoPath = nil
        fetchedMetadata.logoPath = nil
        return persistedMetadata == fetchedMetadata
    }
}
