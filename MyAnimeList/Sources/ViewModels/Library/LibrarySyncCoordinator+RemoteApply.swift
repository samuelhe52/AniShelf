//
//  LibrarySyncCoordinator+RemoteApply.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import DataProvider
import Foundation
import LibrarySync
import SwiftUI
import os

extension LibrarySyncCoordinator {


    /// Applies remote changes to local entries, hydrating missing snapshots first.
    ///
    /// The method suppresses change recording while the imported changes are
    /// written so the local save pass does not enqueue its own changes.
    func applyImportedChanges(
        _ batch: CloudLibrarySyncImportBatch,
        to store: LibraryStore,
        forcedDomainsByIdentity: [LibraryEntrySyncIdentity: Set<LibraryCloudSyncConflictDomain>] = [:]
    ) async throws -> (appliedChangesCount: Int, hydratedEntriesCount: Int) {
        var appliedChangesCount = 0
        var hydratedEntriesCount = 0
        var applicationPlans: [ApplicationPlan] = []
        let dirtyEntriesByIdentity = Self.coalescedDirtyEntriesByIdentity(
            store.syncChangeRecorder.dirtyQueueStore.load().entries
        )
        for change in batch.changes {
            switch change {
            case .snapshot(let snapshot):
                if snapshot.isNotNewerThanPendingDelete(dirtyEntriesByIdentity[snapshot.identity]) {
                    librarySyncCoordinatorLogger.info(
                        "Skipped iCloud snapshot application for \(snapshot.identity.rawID, privacy: .private) because a newer local delete is pending export."
                    )
                    continue
                }
                let applicationTarget = try await entryForApplying(snapshot, store: store)
                guard let applicationTarget else { continue }
                appliedChangesCount += 1
                if applicationTarget.isInitialMaterialization {
                    hydratedEntriesCount += 1
                }
                applicationPlans.append(
                    .init(
                        change: .snapshot(snapshot),
                        target: applicationTarget,
                        forcedDomains: forcedDomainsByIdentity[snapshot.identity] ?? []
                    ))
            case .tombstone(let tombstone):
                guard let entry = store.repository.existingEntry(identity: tombstone.identity) else {
                    continue
                }
                appliedChangesCount += 1
                applicationPlans.append(
                    .init(
                        change: .tombstone(tombstone),
                        target: .init(entry: entry, isInitialMaterialization: false),
                        forcedDomains: []
                    ))
            }
        }
        try store.syncChangeRecorder.withSuppressedRecording {
            for plan in applicationPlans {
                try withAnimation {
                    switch plan.change {
                    case .snapshot(let snapshot):
                        if plan.target.isInitialMaterialization {
                            try plan.target.entry.applyInitialSyncSnapshot(snapshot)
                        } else {
                            try plan.target.entry.applySyncSnapshot(snapshot)
                            if !plan.forcedDomains.isEmpty {
                                plan.target.entry.applyForcedSyncDomains(
                                    plan.forcedDomains,
                                    from: snapshot
                                )
                            }
                        }
                    case .tombstone(let tombstone):
                        try plan.target.entry.applySyncTombstone(tombstone)
                    }
                }
            }
            try store.repository.save()
        }
        store.rebuildSyncChangeTracking()
        return (appliedChangesCount, hydratedEntriesCount)
    }


    /// Refreshes derived library view state after imported changes are persisted.
    func refreshLibraryAfterImport(in store: LibraryStore) throws {
        try store.refreshLibrary()
    }


    /// Returns the local entry to update, hydrating a new one when needed.
    private func entryForApplying(
        _ snapshot: LibraryEntrySyncSnapshot,
        store: LibraryStore
    ) async throws -> ApplicationTarget? {
        if let entry = store.repository.existingEntry(identity: snapshot.identity) {
            return .init(entry: entry, isInitialMaterialization: false)
        }

        return .init(
            entry: try await hydrateMissingEntry(snapshot, store),
            isInitialMaterialization: true
        )
    }


    /// Rebuilds a missing local entry from TMDb before remote data is applied.
    static func hydrateMissingEntry(
        _ snapshot: LibraryEntrySyncSnapshot,
        store: LibraryStore
    ) async throws -> AnimeEntry {
        let latestInfo = try await store.infoFetcher.latestInfo(
            entryType: snapshot.entryType,
            tmdbID: snapshot.tmdbID,
            language: store.language
        )
        let entry = AnimeEntry(fromInfo: latestInfo.0)
        entry.dateSaved = snapshot.dateSaved
        entry.replaceDetail(from: latestInfo.1)

        if let parentSeriesID = snapshot.parentSeriesID {
            if let parentSeriesEntry = store.repository.existingEntry(
                identity: .init(entryType: .series, tmdbID: parentSeriesID)
            ) ?? store.repository.existingEntry(tmdbID: parentSeriesID) {
                entry.parentSeriesEntry = parentSeriesEntry
            } else {
                let parentSeriesEntry = try await AnimeEntry.generateParentSeriesEntryForSeason(
                    parentSeriesID: parentSeriesID,
                    fetcher: store.infoFetcher,
                    infoLanguage: store.language
                )
                store.repository.insert(parentSeriesEntry)
                entry.parentSeriesEntry = parentSeriesEntry
            }
        }

        store.repository.insert(entry)
        return entry
    }
}

fileprivate struct ApplicationTarget {
    let entry: AnimeEntry
    let isInitialMaterialization: Bool
}

fileprivate struct ApplicationPlan {
    let change: LibraryEntrySyncRemoteChange
    let target: ApplicationTarget
    let forcedDomains: Set<LibraryCloudSyncConflictDomain>
}

extension AnimeEntry {
    fileprivate func applyForcedSyncDomains(
        _ domains: Set<LibraryCloudSyncConflictDomain>,
        from snapshot: LibraryEntrySyncSnapshot
    ) {
        if domains.contains(.library) {
            onDisplay = snapshot.onDisplay
            dateSaved = snapshot.dateSaved
            libraryUpdatedAt = snapshot.libraryUpdatedAt
        }
        if domains.contains(.tracking) {
            watchStatus = snapshot.watchStatus
            dateStarted = snapshot.dateStarted
            dateFinished = snapshot.dateFinished
            isDateTrackingEnabled = snapshot.isDateTrackingEnabled
            score = snapshot.score
            favorite = snapshot.favorite
            notes = snapshot.notes
            let wasUsingCustomPoster = usingCustomPoster
            usingCustomPoster = snapshot.usingCustomPoster
            if snapshot.usingCustomPoster {
                customPosterPath = snapshot.customPosterPath
            } else if wasUsingCustomPoster {
                customPosterPath = nil
            }
            trackingUpdatedAt = snapshot.trackingUpdatedAt
        }
        if domains.contains(.episodeProgress) {
            for progress in episodeProgresses {
                modelContext?.delete(progress)
            }
            episodeProgresses.removeAll()
            for progress in snapshot.episodeProgresses {
                applyEpisodeProgressSnapshot(
                    seasonNumber: progress.seasonNumber,
                    watchedThroughEpisode: progress.watchedThroughEpisode,
                    updatedAt: progress.updatedAt
                )
            }
        }
    }
}
