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
import os

fileprivate let syncRecorderLogger = Logger(
    subsystem: .bundleIdentifier,
    category: "LibrarySync.Recorder"
)

/// Watches SwiftData saves and persists the local sync dirty queue.
///
/// The recorder converts `ModelContext.didSave` notifications into upsert or
/// delete queue entries, while also exposing explicit helpers for bulk delete
/// rollback and restore flows.
@MainActor
final class LibrarySyncChangeRecorder {
    /// Restores one previously queued delete if a bulk operation is rolled back.
    struct PendingDeleteRestoreToken {
        var identity: LibraryEntrySyncIdentity
        var previousEntry: LibraryEntrySyncDirtyQueueEntry?
    }

    /// Local baseline clock snapshot used to avoid enqueuing redundant saves.
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
    private var suppressionDepth = 0

    /// Creates a recorder for one `DataProvider` store.
    ///
    /// - Parameters:
    ///   - dataProvider: SwiftData backing store to observe.
    ///   - dirtyQueueStore: Optional queue store override for tests.
    ///   - notificationCenter: Notification center used to observe
    ///     `ModelContext.didSave`.
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

    /// Rebuilds the in-memory clock baseline from the current store contents.
    func rebuildBaseline() {
        let baseline = Self.makeBaseline(from: dataProvider)
        lastSeenClocksByIdentifier = baseline
        syncRecorderLogger.debug(
            "operation=rebuildBaseline count=\(baseline.count, privacy: .public)"
        )
    }

    /// Executes a synchronous operation without recording queue mutations.
    func withSuppressedRecording<T>(_ operation: () throws -> T) rethrows -> T {
        suppressionDepth += 1
        defer { suppressionDepth -= 1 }
        return try operation()
    }

    /// Executes an async operation without recording queue mutations.
    func withSuppressedRecording<T>(_ operation: () async throws -> T) async rethrows -> T {
        suppressionDepth += 1
        defer { suppressionDepth -= 1 }
        return try await operation()
    }

    /// Queues a tombstone for a single deleted entry.
    ///
    /// - Returns: A restore token that can put the previous queue entry back if
    ///   the delete must be rolled back.
    func recordDeletion(
        for entry: AnimeEntry,
        deletedAt: Date = .now
    ) throws -> PendingDeleteRestoreToken {
        let pendingDelete = LibraryEntrySyncPendingDelete(
            tombstone: LibraryEntrySyncTombstone(entry: entry, deletedAt: deletedAt)
        )
        let previousEntry: LibraryEntrySyncDirtyQueueEntry?
        do {
            previousEntry = try dirtyQueueStore.setPendingDelete(pendingDelete)
        } catch {
            syncRecorderLogger.error(
                "operation=recordDeletion result=queueWriteFailed identity=\(pendingDelete.identity.rawID, privacy: .private) errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            throw error
        }
        syncRecorderLogger.debug(
            "operation=recordDeletion result=queued identity=\(pendingDelete.identity.rawID, privacy: .private) deletedAt=\(pendingDelete.tombstone.deletedAt, privacy: .public) previousEntryPresent=\(previousEntry != nil, privacy: .public)"
        )
        return .init(identity: pendingDelete.identity, previousEntry: previousEntry)
    }

    /// Queues tombstones for a bulk delete as one atomic queue rewrite.
    ///
    /// - Returns: Restore tokens in the same order as the input entries.
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

        do {
            try dirtyQueueStore.replaceEntries(Array(entriesByID.values))
        } catch {
            syncRecorderLogger.error(
                "operation=recordDeletions result=queueWriteFailed count=\(tokens.count, privacy: .public) errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            throw error
        }
        syncRecorderLogger.debug(
            "operation=recordDeletions result=queued count=\(tokens.count, privacy: .public)"
        )
        return tokens
    }

    /// Restores one delete queue entry captured by `recordDeletion`.
    func restoreDeleteRecord(_ token: PendingDeleteRestoreToken) throws {
        do {
            try dirtyQueueStore.replaceEntry(token.previousEntry, for: token.identity)
        } catch {
            syncRecorderLogger.error(
                "operation=restoreDeleteRecord result=queueWriteFailed identity=\(token.identity.rawID, privacy: .private) errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            throw error
        }
        syncRecorderLogger.debug(
            "operation=restoreDeleteRecord result=restored identity=\(token.identity.rawID, privacy: .private) previousEntryPresent=\(token.previousEntry != nil, privacy: .public)"
        )
    }

    /// Restores a bulk delete queue mutation as a single queue rewrite.
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

        do {
            try dirtyQueueStore.replaceEntries(Array(entriesByID.values))
        } catch {
            syncRecorderLogger.error(
                "operation=restoreDeleteRecords result=queueWriteFailed count=\(tokens.count, privacy: .public) errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            throw error
        }
        syncRecorderLogger.debug(
            "operation=restoreDeleteRecords result=restored count=\(tokens.count, privacy: .public)"
        )
    }

    /// Converts one `didSave` notification into queue mutations.
    func processSaveNotification(_ notification: Notification) {
        let insertedIdentifiers = persistentIdentifiers(for: .insertedIdentifiers, in: notification)
        let updatedIdentifiers = persistentIdentifiers(for: .updatedIdentifiers, in: notification)
        let deletedIdentifiers = persistentIdentifiers(
            for: .deletedIdentifiers,
            in: notification
        )
        guard suppressionDepth == 0 else {
            syncRecorderLogger.debug(
                "operation=processSaveNotification result=suppressed insertedCount=\(insertedIdentifiers.count, privacy: .public) updatedCount=\(updatedIdentifiers.count, privacy: .public) deletedCount=\(deletedIdentifiers.count, privacy: .public) suppressionDepth=\(self.suppressionDepth, privacy: .public)"
            )
            return
        }

        syncRecorderLogger.debug(
            "operation=processSaveNotification result=received insertedCount=\(insertedIdentifiers.count, privacy: .public) updatedCount=\(updatedIdentifiers.count, privacy: .public) deletedCount=\(deletedIdentifiers.count, privacy: .public)"
        )

        for identifier in deletedIdentifiers {
            lastSeenClocksByIdentifier.removeValue(forKey: identifier)
        }

        let observedIdentifiers = insertedIdentifiers.union(updatedIdentifiers)

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
                syncRecorderLogger.debug(
                    "operation=processSaveNotification result=queuedUpsert identity=\(entry.syncIdentity.rawID, privacy: .private) dirtyAt=\(dirtyAt, privacy: .public) libraryClock=\(String(describing: currentBaseline.libraryUpdatedAt), privacy: .public) trackingClock=\(String(describing: currentBaseline.trackingUpdatedAt), privacy: .public)"
                )
                lastSeenClocksByIdentifier[identifier] = currentBaseline
            } catch {
                if let previousBaseline {
                    lastSeenClocksByIdentifier[identifier] = previousBaseline
                } else {
                    lastSeenClocksByIdentifier.removeValue(forKey: identifier)
                }
                syncRecorderLogger.error(
                    "operation=processSaveNotification result=queueWriteFailed identity=\(entry.syncIdentity.rawID, privacy: .private) errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    /// Subscribes to SwiftData save notifications and routes them to recording.
    private func observeSaves() {
        notificationCenter
            .publisher(for: ModelContext.didSave)
            .sink { [weak self] notification in
                self?.processSaveNotification(notification)
            }
            .store(in: &cancellables)
    }

    /// Extracts persistent identifiers from a `didSave` notification payload.
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

    /// Builds the initial clock baseline from the current library contents.
    private static func makeBaseline(from dataProvider: DataProvider) -> [PersistentIdentifier: ClockBaseline] {
        guard let entries = try? dataProvider.getAllModels(ofType: AnimeEntry.self) else {
            return [:]
        }

        return entries.reduce(into: [PersistentIdentifier: ClockBaseline]()) { partialResult, entry in
            partialResult[entry.id] = ClockBaseline(entry: entry)
        }
    }

    /// Picks an on-disk or temporary dirty-queue store for the current backing mode.
    private static func makeDefaultDirtyQueueStore(inMemory: Bool) -> LibraryEntrySyncDirtyQueueStore {
        guard inMemory else {
            return .init()
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AniShelf.LibrarySync.\(UUID().uuidString).json")
        return .init(url: tempURL)
    }
}
