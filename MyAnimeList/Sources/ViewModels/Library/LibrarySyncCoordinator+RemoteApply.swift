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
        forcedDomainsByIdentity: [LibraryEntryIdentity: Set<LibraryCloudSyncConflictDomain>] = [:],
        isBootstrap: Bool = false,
        isUserRetry: Bool = false,
        checkCancellation: () throws -> Void = {}
    ) async throws -> (appliedChangesCount: Int, hydratedEntriesCount: Int) {
        let remoteSnapshots = Dictionary(
            uniqueKeysWithValues: batch.changes.compactMap { change in
                if case .snapshot(let snapshot) = change { return (snapshot.identity, snapshot) }
                return nil
            })
        if isBootstrap {
            store.updateLibraryCloudSyncStatus { status in
                status.restoration?.totalEntries = remoteSnapshots.count
                status.restoration?.restoredEntries = 0
                status.restoration?.failures.removeAll { remoteSnapshots[$0.snapshot.identity] == nil }
            }
        }
        var firstFailure: LibrarySyncHydrationError?
        var applied = 0
        var hydrated = 0
        let batchSize = isBootstrap ? 16 : max(1, batch.changes.count)
        for start in stride(from: 0, to: batch.changes.count, by: batchSize) {
            var chunk = batch
            chunk.changes = Array(batch.changes[start..<min(start + batchSize, batch.changes.count)])
            var failedCount = 0
            let result = try await applyImportChunk(
                chunk, to: store, forcedDomainsByIdentity: forcedDomainsByIdentity,
                remoteSnapshots: remoteSnapshots, checkCancellation: checkCancellation
            ) { snapshot, error in
                guard isBootstrap else { throw error }
                failedCount += 1
                firstFailure = firstFailure ?? error
                store.updateLibraryCloudSyncStatus { status in
                    status.restoration?.recordFailure(
                        snapshot: snapshot, error: error, isUserRetry: isUserRetry, at: dateProvider()
                    )
                }
            }
            applied += result.appliedChangesCount
            hydrated += result.hydratedEntriesCount
            if isBootstrap {
                let snapshotCount = chunk.changes.filter { if case .snapshot = $0 { true } else { false } }.count
                store.updateLibraryCloudSyncStatus {
                    $0.restoration?.restoredEntries += snapshotCount - failedCount
                }
            }
        }
        if let firstFailure { throw firstFailure }
        return (applied, hydrated)
    }

    private func applyImportChunk(
        _ batch: CloudLibrarySyncImportBatch,
        to store: LibraryStore,
        forcedDomainsByIdentity: [LibraryEntryIdentity: Set<LibraryCloudSyncConflictDomain>],
        remoteSnapshots: [LibraryEntryIdentity: LibraryEntrySyncSnapshot],
        checkCancellation: () throws -> Void,
        onHydrationFailure: (LibraryEntrySyncSnapshot, LibrarySyncHydrationError) throws -> Void
    ) async throws -> (appliedChangesCount: Int, hydratedEntriesCount: Int) {
        var appliedChangesCount = 0
        var hydratedEntriesCount = 0
        var applicationPlans: [ApplicationPlan] = []
        var plannedEntriesByIdentity: [LibraryEntryIdentity: AnimeEntry] = [:]
        var entriesToInsert: [AnimeEntry] = []
        var completedIdentities: Set<LibraryEntryIdentity> = []
        for change in batch.changes {
            try checkCancellation()
            try Task.checkCancellation()
            let dirtyEntriesByIdentity = Self.coalescedDirtyEntriesByIdentity(
                store.syncChangeRecorder.dirtyQueueStore.load().entries
            )
            switch change {
            case .snapshot(let snapshot):
                if snapshot.isNotNewerThanPendingDelete(dirtyEntriesByIdentity[snapshot.identity]) {
                    librarySyncCoordinatorLogger.info(
                        "Skipped iCloud snapshot application for \(snapshot.identity.rawID, privacy: .private) because a newer local delete is pending export."
                    )
                    completedIdentities.insert(snapshot.identity)
                    continue
                }
                // A failed parent lookup must not leave its child staged for insertion.
                var candidateEntries = plannedEntriesByIdentity
                var candidateInserts = entriesToInsert
                let applicationTarget: ApplicationTarget?
                do {
                    applicationTarget = try await entryForApplying(
                        snapshot, store: store,
                        plannedEntriesByIdentity: &candidateEntries,
                        entriesToInsert: &candidateInserts,
                        remoteSnapshots: remoteSnapshots
                    )
                } catch let error as LibrarySyncHydrationError {
                    try onHydrationFailure(snapshot, error)
                    continue
                }
                plannedEntriesByIdentity = candidateEntries
                entriesToInsert = candidateInserts
                completedIdentities.insert(snapshot.identity)
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
                completedIdentities.insert(tombstone.identity)
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
        try checkCancellation()
        try Task.checkCancellation()
        let context = store.dataProvider.dataHandler.modelContext
        // Preserve any user edits made during hydration before the remote transaction.
        if context.hasChanges { try store.repository.save() }
        let currentDirtyEntries = Self.coalescedDirtyEntriesByIdentity(
            store.syncChangeRecorder.dirtyQueueStore.load().entries
        )
        applicationPlans = applicationPlans.filter { plan in
            guard case .snapshot(let snapshot) = plan.change else { return true }
            return !snapshot.isNotNewerThanPendingDelete(currentDirtyEntries[snapshot.identity])
        }
        let neededIdentities = Set(
            applicationPlans.flatMap { plan in
                [plan.target.entry.libraryIdentity] + (plan.target.parentSeriesEntry.map { [$0.libraryIdentity] } ?? [])
            })
        try store.syncChangeRecorder.withSuppressedRecording {
            do {
                for entry in entriesToInsert where neededIdentities.contains(entry.libraryIdentity) {
                    if store.repository.existingEntry(identity: entry.libraryIdentity) == nil {
                        store.repository.insert(entry)
                    }
                }
                for plan in applicationPlans {
                    // Another local action may have created this identity while hydration awaited.
                    let targetEntry =
                        store.repository.existingEntry(identity: plan.change.identity) ?? plan.target.entry
                    let isInitial = plan.target.isInitialMaterialization && targetEntry === plan.target.entry
                    try withAnimation {
                        switch plan.change {
                        case .snapshot(let snapshot):
                            if isInitial {
                                targetEntry.parentSeriesEntry = plan.target.parentSeriesEntry.map {
                                    store.repository.existingEntry(identity: $0.libraryIdentity) ?? $0
                                }
                                try targetEntry.applyInitialSyncSnapshot(snapshot)
                            } else {
                                try targetEntry.applySyncSnapshot(snapshot)
                                if !plan.forcedDomains.isEmpty {
                                    targetEntry.applyForcedSyncDomains(
                                        plan.forcedDomains,
                                        from: snapshot
                                    )
                                }
                            }
                        case .tombstone(let tombstone):
                            try targetEntry.applySyncTombstone(tombstone)
                        }
                    }
                }
                try store.repository.save()
            } catch {
                context.rollback()
                throw error
            }
        }
        store.rebuildSyncChangeTracking()
        try store.refreshLibrary()
        store.updateLibraryCloudSyncStatus { status in
            status.restoration?.failures.removeAll { completedIdentities.contains($0.snapshot.identity) }
        }
        return (appliedChangesCount, hydratedEntriesCount)
    }


    /// Refreshes derived library view state after imported changes are persisted.
    func refreshLibraryAfterImport(in store: LibraryStore) throws {
        try store.refreshLibrary()
    }


    /// Returns the local entry to update, hydrating a new one when needed.
    private func entryForApplying(
        _ snapshot: LibraryEntrySyncSnapshot,
        store: LibraryStore,
        plannedEntriesByIdentity: inout [LibraryEntryIdentity: AnimeEntry],
        entriesToInsert: inout [AnimeEntry],
        remoteSnapshots: [LibraryEntryIdentity: LibraryEntrySyncSnapshot]
    ) async throws -> ApplicationTarget? {
        if let entry = store.repository.existingEntry(identity: snapshot.identity) {
            return .init(entry: entry, isInitialMaterialization: false)
        }

        let entry: AnimeEntry
        if let plannedEntry = plannedEntriesByIdentity[snapshot.identity] {
            entry = plannedEntry
        } else {
            do {
                entry = try await hydrateMissingEntry(snapshot, store)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw LibrarySyncHydrationError(identity: snapshot.identity, underlyingError: error)
            }
            plannedEntriesByIdentity[snapshot.identity] = entry
            entriesToInsert.append(entry)
        }
        let parentSeriesEntry = try await parentSeriesEntryForApplying(
            snapshot,
            store: store,
            plannedEntriesByIdentity: &plannedEntriesByIdentity,
            entriesToInsert: &entriesToInsert,
            remoteSnapshots: remoteSnapshots
        )
        return .init(
            entry: entry,
            isInitialMaterialization: true,
            parentSeriesEntry: parentSeriesEntry
        )
    }

    private func parentSeriesEntryForApplying(
        _ snapshot: LibraryEntrySyncSnapshot,
        store: LibraryStore,
        plannedEntriesByIdentity: inout [LibraryEntryIdentity: AnimeEntry],
        entriesToInsert: inout [AnimeEntry],
        remoteSnapshots: [LibraryEntryIdentity: LibraryEntrySyncSnapshot]
    ) async throws -> AnimeEntry? {
        guard let parentSeriesID = snapshot.parentSeriesID else { return nil }
        let parentIdentity = LibraryEntryIdentity(entryType: .series, tmdbID: parentSeriesID)
        if let existingParent = store.repository.existingEntry(identity: parentIdentity) {
            return existingParent
        }
        if let plannedParent = plannedEntriesByIdentity[parentIdentity] {
            return plannedParent
        }

        let parentSeriesEntry: AnimeEntry
        do {
            if let parentSnapshot = remoteSnapshots[parentIdentity] {
                parentSeriesEntry = try await hydrateMissingEntry(parentSnapshot, store)
                try parentSeriesEntry.applyInitialSyncSnapshot(parentSnapshot)
            } else {
                parentSeriesEntry = try await AnimeEntry.generateParentSeriesEntryForSeason(
                    parentSeriesID: parentSeriesID,
                    fetcher: store.infoFetcher,
                    infoLanguage: store.language
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LibrarySyncHydrationError(
                identity: parentIdentity,
                underlyingError: error
            )
        }
        plannedEntriesByIdentity[parentIdentity] = parentSeriesEntry
        entriesToInsert.append(parentSeriesEntry)
        return parentSeriesEntry
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
        return entry
    }
}

/// Adds the failed metadata identity without changing retry classification.
struct LibrarySyncHydrationError: LocalizedError {
    let identity: LibraryEntryIdentity
    let underlyingError: Error

    var errorDescription: String? {
        let error = underlyingError as NSError
        let details = "\(error.localizedDescription) [\(error.domain):\(error.code)]"
        return String(localized: "Could not restore metadata for \(identity.rawID): \(details)")
    }
}

fileprivate struct ApplicationTarget {
    let entry: AnimeEntry
    let isInitialMaterialization: Bool
    var parentSeriesEntry: AnimeEntry? = nil
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
