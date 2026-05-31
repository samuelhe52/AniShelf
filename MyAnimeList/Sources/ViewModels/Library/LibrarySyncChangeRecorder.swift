//
//  LibrarySyncChangeRecorder.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import Combine
import DataProvider
import Foundation
import LibrarySync
import SwiftData

@MainActor
final class LibrarySyncChangeRecorder {
    struct PendingDeleteRestoreToken {
        var identity: LibraryEntrySyncIdentity
        var previousEntry: LibraryEntrySyncDirtyQueueEntry?
    }

    private struct ClockBaseline: Equatable {
        var libraryUpdatedAt: Date?
        var trackingUpdatedAt: Date?

        init(entry: AnimeEntry) {
            libraryUpdatedAt = entry.libraryUpdatedAt
            trackingUpdatedAt = entry.trackingUpdatedAt
        }

        var dirtyAt: Date? {
            [libraryUpdatedAt, trackingUpdatedAt].compactMap(\.self).max()
        }

        func hasAdvanced(since previous: ClockBaseline?) -> Bool {
            guard let previous else {
                return dirtyAt != nil
            }
            return Self.isNewer(libraryUpdatedAt, than: previous.libraryUpdatedAt)
                || Self.isNewer(trackingUpdatedAt, than: previous.trackingUpdatedAt)
        }

        private static func isNewer(_ candidate: Date?, than existing: Date?) -> Bool {
            guard let candidate else { return false }
            guard let existing else { return true }
            return candidate > existing
        }
    }

    let dirtyQueueStore: LibraryEntrySyncDirtyQueueStore

    private let dataProvider: DataProvider
    private let notificationCenter: NotificationCenter
    private var cancellables = Set<AnyCancellable>()
    private var lastSeenClocksByIdentifier: [PersistentIdentifier: ClockBaseline]

    init(
        dataProvider: DataProvider,
        dirtyQueueStore: LibraryEntrySyncDirtyQueueStore? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.dataProvider = dataProvider
        self.notificationCenter = notificationCenter
        self.dirtyQueueStore = dirtyQueueStore ?? Self.makeDefaultDirtyQueueStore(inMemory: dataProvider.inMemory)
        self.lastSeenClocksByIdentifier = Self.makeBaseline(from: dataProvider)
        observeSaves()
    }

    func rebuildBaseline() {
        lastSeenClocksByIdentifier = Self.makeBaseline(from: dataProvider)
    }

    func recordDeletion(
        for entry: AnimeEntry,
        deletedAt: Date = .now
    ) throws -> PendingDeleteRestoreToken {
        let pendingDelete = LibraryEntrySyncPendingDelete(
            tombstone: LibraryEntrySyncTombstone(entry: entry, deletedAt: deletedAt)
        )
        let previousEntry = try dirtyQueueStore.setPendingDelete(pendingDelete)
        return .init(identity: pendingDelete.identity, previousEntry: previousEntry)
    }

    func recordDeletions(
        for entries: [AnimeEntry],
        deletedAt: Date = .now
    ) throws -> [PendingDeleteRestoreToken] {
        // Stage the full queue mutation first so bulk delete tombstones are
        // either all persisted together or not written at all.
        let initialQueue = dirtyQueueStore.load()
        var entriesByID = initialQueue.entries.reduce(into: [String: LibraryEntrySyncDirtyQueueEntry]()) {
            partialResult, entry in
            partialResult[entry.identity.rawID] = entry
        }

        let tokens = entries.map { entry -> PendingDeleteRestoreToken in
            let pendingDelete = LibraryEntrySyncPendingDelete(
                tombstone: LibraryEntrySyncTombstone(entry: entry, deletedAt: deletedAt)
            )
            let previousEntry = entriesByID[pendingDelete.identity.rawID]
            if case .delete(let previousDelete) = previousEntry,
               previousDelete.tombstone.deletedAt >= pendingDelete.tombstone.deletedAt
            {
                return .init(identity: pendingDelete.identity, previousEntry: previousEntry)
            }

            entriesByID[pendingDelete.identity.rawID] = .delete(pendingDelete)
            return .init(identity: pendingDelete.identity, previousEntry: previousEntry)
        }

        try dirtyQueueStore.replaceEntries(Array(entriesByID.values))
        return tokens
    }

    func restoreDeleteRecord(_ token: PendingDeleteRestoreToken) throws {
        try dirtyQueueStore.replaceEntry(token.previousEntry, for: token.identity)
    }

    func restoreDeleteRecords(_ tokens: [PendingDeleteRestoreToken]) throws {
        // Roll back the bulk delete queue mutation as a single queue rewrite so
        // we do not leave partially restored tombstones on disk.
        var entriesByID = dirtyQueueStore.load().entries.reduce(into: [String: LibraryEntrySyncDirtyQueueEntry]()) {
            partialResult, entry in
            partialResult[entry.identity.rawID] = entry
        }

        for token in tokens.reversed() {
            if let previousEntry = token.previousEntry {
                entriesByID[token.identity.rawID] = previousEntry
            } else {
                entriesByID.removeValue(forKey: token.identity.rawID)
            }
        }

        try dirtyQueueStore.replaceEntries(Array(entriesByID.values))
    }

    func processSaveNotification(_ notification: Notification) {
        let deletedIdentifiers = persistentIdentifiers(
            for: .deletedIdentifiers,
            in: notification
        )
        for identifier in deletedIdentifiers {
            lastSeenClocksByIdentifier.removeValue(forKey: identifier)
        }

        let observedIdentifiers = persistentIdentifiers(for: .insertedIdentifiers, in: notification)
            .union(persistentIdentifiers(for: .updatedIdentifiers, in: notification))

        for identifier in observedIdentifiers {
            guard let entry = dataProvider.dataHandler[identifier, as: AnimeEntry.self] else {
                lastSeenClocksByIdentifier.removeValue(forKey: identifier)
                continue
            }

            let currentBaseline = ClockBaseline(entry: entry)
            let previousBaseline = lastSeenClocksByIdentifier[identifier]

            guard currentBaseline.hasAdvanced(since: previousBaseline) else {
                lastSeenClocksByIdentifier[identifier] = currentBaseline
                continue
            }
            guard let dirtyAt = currentBaseline.dirtyAt else {
                lastSeenClocksByIdentifier[identifier] = currentBaseline
                continue
            }

            do {
                try dirtyQueueStore.setPendingUpsert(
                    .init(identity: entry.syncIdentity, dirtyAt: dirtyAt)
                )
                lastSeenClocksByIdentifier[identifier] = currentBaseline
            } catch {
                if let previousBaseline {
                    lastSeenClocksByIdentifier[identifier] = previousBaseline
                } else {
                    lastSeenClocksByIdentifier.removeValue(forKey: identifier)
                }
                libraryStoreLogger.error(
                    "Failed to persist sync upsert for \(entry.tmdbID, privacy: .public): \(error.localizedDescription)"
                )
            }
        }
    }

    private func observeSaves() {
        notificationCenter
            .publisher(for: ModelContext.didSave)
            .sink { [weak self] notification in
                self?.processSaveNotification(notification)
            }
            .store(in: &cancellables)
    }

    private func persistentIdentifiers(
        for key: ModelContext.NotificationKey,
        in notification: Notification
    ) -> Set<PersistentIdentifier> {
        if let identifiers = notification.userInfo?[key.rawValue] as? Set<PersistentIdentifier> {
            return identifiers
        }
        if let identifiers = notification.userInfo?[key.rawValue] as? [PersistentIdentifier] {
            return Set(identifiers)
        }
        return []
    }

    private static func makeBaseline(from dataProvider: DataProvider) -> [PersistentIdentifier: ClockBaseline] {
        guard let entries = try? dataProvider.getAllModels(ofType: AnimeEntry.self) else {
            return [:]
        }

        return entries.reduce(into: [PersistentIdentifier: ClockBaseline]()) { partialResult, entry in
            partialResult[entry.id] = ClockBaseline(entry: entry)
        }
    }

    private static func makeDefaultDirtyQueueStore(inMemory: Bool) -> LibraryEntrySyncDirtyQueueStore {
        guard inMemory else {
            return .init()
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AniShelf.LibrarySync.\(UUID().uuidString).json")
        return .init(url: tempURL)
    }
}
