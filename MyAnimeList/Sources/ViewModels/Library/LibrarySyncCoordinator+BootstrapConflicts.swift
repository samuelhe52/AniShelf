//
//  LibrarySyncCoordinator+BootstrapConflicts.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/6/12.
//

import DataProvider
import Foundation
import LibrarySync
import os

extension LibrarySyncCoordinator {
    func resolvedBatch(
        from batch: CloudLibrarySyncImportBatch,
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot],
        conflicts: AmbiguousConflictSet,
        preference: LibraryCloudSyncConflictPreference
    ) throws -> CloudLibrarySyncImportBatch {
        let changes = try batch.remoteChanges.map { remoteChange -> LibraryEntrySyncRemoteChange in
            var resolvedChange = try resolvedChange(
                remoteChange,
                localSnapshotsByIdentity: localSnapshotsByIdentity
            )
            guard case .snapshot(var resolvedSnapshot) = resolvedChange,
                case .snapshot(let remoteSnapshot) = remoteChange,
                let localSnapshot = localSnapshotsByIdentity[remoteSnapshot.identity],
                let conflict = conflicts.conflictsByIdentity[remoteSnapshot.identity]
            else {
                return resolvedChange
            }

            switch preference {
            case .preferCloud:
                apply(conflict.domains, from: remoteSnapshot, to: &resolvedSnapshot)
            case .preferLocal:
                apply(conflict.domains, from: localSnapshot, to: &resolvedSnapshot)
            }
            resolvedChange = .snapshot(resolvedSnapshot)
            return resolvedChange
        }

        return .init(
            changes: changes,
            remoteChanges: batch.remoteChanges,
            settingsSnapshot: batch.settingsSnapshot,
            ignoredDeletedRecordIDs: batch.ignoredDeletedRecordIDs,
            changeToken: batch.changeToken,
            namespace: batch.namespace,
            zoneID: batch.zoneID
        )
    }

    private func resolvedChange(
        _ remoteChange: LibraryEntrySyncRemoteChange,
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot]
    ) throws -> LibraryEntrySyncRemoteChange {
        guard case .snapshot(let remoteSnapshot) = remoteChange,
            let localSnapshot = localSnapshotsByIdentity[remoteSnapshot.identity]
        else {
            return remoteChange
        }
        return .snapshot(try localSnapshot.merged(with: remoteSnapshot))
    }

    func stampLocalClocks(
        for conflicts: AmbiguousConflictSet,
        at date: Date,
        in store: LibraryStore
    ) throws {
        guard !conflicts.isEmpty else { return }
        let entries = try store.dataProvider.getAllModels(ofType: AnimeEntry.self)
        var changed = false
        try store.syncChangeRecorder.withSuppressedRecording {
            for entry in entries {
                guard let conflict = conflicts.conflictsByIdentity[entry.syncIdentity] else {
                    continue
                }
                if conflict.domains.contains(.library), entry.libraryUpdatedAt == nil {
                    entry.libraryUpdatedAt = date
                    changed = true
                }
                if conflict.domains.contains(.tracking), entry.trackingUpdatedAt == nil {
                    entry.trackingUpdatedAt = date
                    changed = true
                }
            }
            if changed {
                try store.repository.save()
            }
        }
        if changed {
            store.rebuildSyncChangeTracking()
        }
    }

    func dropCloudSupersededDirtyWork(
        conflicts: AmbiguousConflictSet,
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot],
        remoteChanges: [LibraryEntrySyncRemoteChange],
        in store: LibraryStore
    ) throws {
        guard !conflicts.isEmpty else { return }
        let remoteSnapshotsByIdentity = remoteChanges.reduce(
            into: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot]()
        ) { snapshotsByIdentity, remoteChange in
            guard case .snapshot(let snapshot) = remoteChange else { return }
            snapshotsByIdentity[snapshot.identity] = snapshot
        }

        let retainedEntries = store.syncChangeRecorder.dirtyQueueStore.load().entries.filter { entry in
            guard let conflict = conflicts.conflictsByIdentity[entry.identity],
                let localSnapshot = localSnapshotsByIdentity[entry.identity],
                let remoteSnapshot = remoteSnapshotsByIdentity[entry.identity]
            else {
                return true
            }
            return hasAuthoritativeLocalWork(
                localSnapshot,
                remoteSnapshot: remoteSnapshot,
                cloudPreferredDomains: conflict.domains
            )
        }
        try store.syncChangeRecorder.dirtyQueueStore.replaceEntries(retainedEntries)
    }

    func ambiguousConflicts(
        localSnapshotsByIdentity: [LibraryEntrySyncIdentity: LibraryEntrySyncSnapshot],
        remoteChanges: [LibraryEntrySyncRemoteChange]
    ) -> AmbiguousConflictSet {
        var conflictsByIdentity: [LibraryEntrySyncIdentity: AmbiguousConflict] = [:]
        for remoteChange in remoteChanges {
            guard case .snapshot(let remoteSnapshot) = remoteChange,
                let localSnapshot = localSnapshotsByIdentity[remoteSnapshot.identity]
            else {
                continue
            }

            var domains: Set<LibraryCloudSyncConflictDomain> = []
            if localSnapshot.libraryUpdatedAt == nil,
                remoteSnapshot.libraryUpdatedAt == nil,
                libraryValuesDiffer(localSnapshot, remoteSnapshot)
            {
                domains.insert(.library)
            }
            if localSnapshot.trackingUpdatedAt == nil,
                remoteSnapshot.trackingUpdatedAt == nil,
                trackingValuesDiffer(localSnapshot, remoteSnapshot)
            {
                domains.insert(.tracking)
            }

            if !domains.isEmpty {
                conflictsByIdentity[remoteSnapshot.identity] = .init(
                    identity: remoteSnapshot.identity,
                    domains: domains
                )
            }
        }
        return .init(conflictsByIdentity: conflictsByIdentity)
    }

    private func apply(
        _ domains: Set<LibraryCloudSyncConflictDomain>,
        from source: LibraryEntrySyncSnapshot,
        to target: inout LibraryEntrySyncSnapshot
    ) {
        if domains.contains(.library) {
            target.onDisplay = source.onDisplay
            target.dateSaved = source.dateSaved
            target.libraryUpdatedAt = source.libraryUpdatedAt
        }
        if domains.contains(.tracking) {
            target.watchStatus = source.watchStatus
            target.dateStarted = source.dateStarted
            target.dateFinished = source.dateFinished
            target.isDateTrackingEnabled = source.isDateTrackingEnabled
            target.score = source.score
            target.favorite = source.favorite
            target.notes = source.notes
            target.usingCustomPoster = source.usingCustomPoster
            target.customPosterPath = source.usingCustomPoster ? source.customPosterPath : nil
            target.trackingUpdatedAt = source.trackingUpdatedAt
        }
        if domains.contains(.episodeProgress) {
            target.episodeProgresses = source.episodeProgresses
        }
    }
}

struct AmbiguousConflict {
    var identity: LibraryEntrySyncIdentity
    var domains: Set<LibraryCloudSyncConflictDomain>
}

struct AmbiguousConflictSet {
    var conflictsByIdentity: [LibraryEntrySyncIdentity: AmbiguousConflict]

    var isEmpty: Bool {
        conflictsByIdentity.isEmpty
    }

    var summary: LibraryCloudSyncConflictSummary {
        LibraryCloudSyncConflictSummary(
            entryCount: conflictsByIdentity.count,
            libraryDomainCount: domainCount(.library),
            trackingDomainCount: domainCount(.tracking),
            episodeProgressDomainCount: domainCount(.episodeProgress)
        )
    }

    var domainsByIdentity: [LibraryEntrySyncIdentity: Set<LibraryCloudSyncConflictDomain>] {
        conflictsByIdentity.mapValues(\.domains)
    }

    private func domainCount(_ domain: LibraryCloudSyncConflictDomain) -> Int {
        conflictsByIdentity.values.filter { $0.domains.contains(domain) }.count
    }
}

fileprivate func libraryValuesDiffer(
    _ lhs: LibraryEntrySyncSnapshot,
    _ rhs: LibraryEntrySyncSnapshot
) -> Bool {
    lhs.onDisplay != rhs.onDisplay
        || lhs.dateSaved != rhs.dateSaved
}

fileprivate func trackingValuesDiffer(
    _ lhs: LibraryEntrySyncSnapshot,
    _ rhs: LibraryEntrySyncSnapshot
) -> Bool {
    lhs.watchStatus != rhs.watchStatus
        || lhs.dateStarted != rhs.dateStarted
        || lhs.dateFinished != rhs.dateFinished
        || lhs.isDateTrackingEnabled != rhs.isDateTrackingEnabled
        || lhs.score != rhs.score
        || lhs.favorite != rhs.favorite
        || lhs.notes != rhs.notes
        || lhs.usingCustomPoster != rhs.usingCustomPoster
        || lhs.customPosterPath != rhs.customPosterPath
}

fileprivate func hasAuthoritativeLocalWork(
    _ localSnapshot: LibraryEntrySyncSnapshot,
    remoteSnapshot: LibraryEntrySyncSnapshot,
    cloudPreferredDomains: Set<LibraryCloudSyncConflictDomain>
) -> Bool {
    if !cloudPreferredDomains.contains(.library),
        hasNewerClock(localSnapshot.libraryUpdatedAt, than: remoteSnapshot.libraryUpdatedAt)
    {
        return true
    }
    if !cloudPreferredDomains.contains(.tracking),
        hasNewerClock(localSnapshot.trackingUpdatedAt, than: remoteSnapshot.trackingUpdatedAt)
    {
        return true
    }
    return hasNewerLocalEpisodeProgress(localSnapshot, remoteSnapshot: remoteSnapshot)
}

fileprivate func hasNewerLocalEpisodeProgress(
    _ localSnapshot: LibraryEntrySyncSnapshot,
    remoteSnapshot: LibraryEntrySyncSnapshot
) -> Bool {
    let remoteProgresses = Dictionary(
        uniqueKeysWithValues: remoteSnapshot.episodeProgresses.map { ($0.seasonNumber, $0) }
    )
    for localProgress in localSnapshot.episodeProgresses {
        guard let remoteProgress = remoteProgresses[localProgress.seasonNumber] else {
            return true
        }
        if localProgress.updatedAt > remoteProgress.updatedAt {
            return true
        }
        if localProgress.updatedAt == remoteProgress.updatedAt,
            localProgress.watchedThroughEpisode > remoteProgress.watchedThroughEpisode
        {
            return true
        }
    }
    return false
}

fileprivate func hasNewerClock(_ candidate: Date?, than existing: Date?) -> Bool {
    guard let candidate else { return false }
    guard let existing else { return true }
    return candidate > existing
}
