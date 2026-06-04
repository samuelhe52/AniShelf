//
//  LibraryEntrySyncDirtyQueueStore.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import DataProvider
import Foundation
import os

fileprivate let dirtyQueueLogger = Logger(
    subsystem: "com.samuelhe.MyAnimeList",
    category: "LibrarySync.DirtyQueue"
)

/// Persisted delete intent for one sync identity.
///
/// Tombstones carry only stable identity fields plus `deletedAt` so another
/// device can decide whether the delete is newer than its local edits without
/// keeping full user-state payloads in iCloud.
public struct LibraryEntrySyncTombstone: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var identity: LibraryEntrySyncIdentity
    public var tmdbID: Int
    public var parentSeriesID: Int?
    public var seasonNumber: Int?
    public var entryType: AnimeType
    public var deletedAt: Date

    /// Captures an entry's stable sync identity as a delete tombstone.
    public init(entry: AnimeEntry, deletedAt: Date = .now) {
        self.init(
            identity: entry.syncIdentity,
            tmdbID: entry.tmdbID,
            parentSeriesID: entry.type.parentSeriesID,
            seasonNumber: entry.type.seasonNumber,
            entryType: entry.type,
            deletedAt: deletedAt
        )
    }

    /// Creates a tombstone from stable identity fields.
    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        identity: LibraryEntrySyncIdentity,
        tmdbID: Int,
        parentSeriesID: Int?,
        seasonNumber: Int?,
        entryType: AnimeType,
        deletedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.tmdbID = tmdbID
        self.parentSeriesID = parentSeriesID
        self.seasonNumber = seasonNumber
        self.entryType = entryType
        self.deletedAt = deletedAt
    }
}

/// Decoded CloudKit change for one library entry identity.
public enum LibraryEntrySyncRemoteChange: Equatable, Sendable {
    case snapshot(LibraryEntrySyncSnapshot)
    case tombstone(LibraryEntrySyncTombstone)

    public var identity: LibraryEntrySyncIdentity {
        switch self {
        case .snapshot(let snapshot):
            snapshot.identity
        case .tombstone(let tombstone):
            tombstone.identity
        }
    }

    public var latestSyncClock: Date? {
        switch self {
        case .snapshot(let snapshot):
            snapshot.latestSyncClock
        case .tombstone(let tombstone):
            tombstone.deletedAt
        }
    }

    /// Coalesces multiple remote changes for the same identity.
    public func merged(with other: LibraryEntrySyncRemoteChange) throws -> LibraryEntrySyncRemoteChange {
        guard identity == other.identity else {
            throw LibraryEntrySyncSnapshot.MergeError.identityMismatch(
                local: identity,
                remote: other.identity
            )
        }

        switch (self, other) {
        case (.snapshot(let lhs), .snapshot(let rhs)):
            return .snapshot(try lhs.merged(with: rhs))
        case (.tombstone(let lhs), .tombstone(let rhs)):
            return .tombstone(lhs.deletedAt >= rhs.deletedAt ? lhs : rhs)
        case (.snapshot(let snapshot), .tombstone(let tombstone)):
            let snapshotClock = snapshot.latestUserStateClock ?? .distantPast
            return tombstone.deletedAt > snapshotClock ? .tombstone(tombstone) : self
        case (.tombstone(let tombstone), .snapshot(let snapshot)):
            let snapshotClock = snapshot.latestUserStateClock ?? .distantPast
            return snapshotClock > tombstone.deletedAt ? other : self
        }
    }
}

/// Dirty-queue entry for a local insert or update.
public struct LibraryEntrySyncPendingUpsert: Codable, Equatable, Sendable {
    public var identity: LibraryEntrySyncIdentity
    public var dirtyAt: Date

    public init(identity: LibraryEntrySyncIdentity, dirtyAt: Date) {
        self.identity = identity
        self.dirtyAt = dirtyAt
    }
}

/// Dirty-queue entry for a local delete tombstone.
public struct LibraryEntrySyncPendingDelete: Codable, Equatable, Sendable {
    public var tombstone: LibraryEntrySyncTombstone

    public init(tombstone: LibraryEntrySyncTombstone) {
        self.tombstone = tombstone
    }

    public var identity: LibraryEntrySyncIdentity { tombstone.identity }
}

/// Coalesced local sync work waiting to be exported.
public enum LibraryEntrySyncDirtyQueueEntry: Codable, Equatable, Sendable {
    case upsert(LibraryEntrySyncPendingUpsert)
    case delete(LibraryEntrySyncPendingDelete)

    public var identity: LibraryEntrySyncIdentity {
        switch self {
        case .upsert(let upsert):
            upsert.identity
        case .delete(let delete):
            delete.identity
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case payload
    }

    private enum Kind: String, Codable {
        case upsert
        case delete
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .upsert:
            self = .upsert(try container.decode(LibraryEntrySyncPendingUpsert.self, forKey: .payload))
        case .delete:
            self = .delete(try container.decode(LibraryEntrySyncPendingDelete.self, forKey: .payload))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .upsert(let upsert):
            try container.encode(Kind.upsert, forKey: .kind)
            try container.encode(upsert, forKey: .payload)
        case .delete(let delete):
            try container.encode(Kind.delete, forKey: .kind)
            try container.encode(delete, forKey: .payload)
        }
    }
}

/// Persisted collection of pending local sync work.
public struct LibraryEntrySyncDirtyQueue: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var entries: [LibraryEntrySyncDirtyQueueEntry]

    /// Creates a queue and coalesces duplicate identities.
    ///
    /// When multiple entries share an identity, the last entry in the input wins.
    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        entries: [LibraryEntrySyncDirtyQueueEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.entries = Self.coalesced(entries)
    }

    /// Returns the queued entry for an identity, if any.
    public func entry(for identity: LibraryEntrySyncIdentity) -> LibraryEntrySyncDirtyQueueEntry? {
        entries.first { $0.identity == identity }
    }

    fileprivate static func coalesced(
        _ entries: [LibraryEntrySyncDirtyQueueEntry]
    ) -> [LibraryEntrySyncDirtyQueueEntry] {
        let byIdentity = entries.reduce(into: [String: LibraryEntrySyncDirtyQueueEntry]()) { partialResult, entry in
            partialResult[entry.identity.rawID] = entry
        }
        return byIdentity.values.sorted { lhs, rhs in lhs.identity.rawID < rhs.identity.rawID }
    }
}

/// File-backed store for local library sync work.
///
/// The queue is small JSON state, written atomically, that lets AniShelf retry
/// local edits after app restarts or transient CloudKit failures.
public final class LibraryEntrySyncDirtyQueueStore: @unchecked Sendable {
    public static let defaultDirectoryURL = URL.applicationSupportDirectory
        .appendingPathComponent("AniShelf")
        .appendingPathComponent("Sync")
    public static let defaultFileURL =
        defaultDirectoryURL
        .appendingPathComponent("library-entry-sync-dirty-queue.json")

    private let fileManager: FileManager
    /// Serializes all queue access so reads, writes, and recovery stay atomic.
    private let stateLock = NSLock()
    /// Injected handler for writing the queue, used for testing purposes.
    private let writeQueueHandler: (LibraryEntrySyncDirtyQueue) throws -> Void
    public let url: URL

    /// Creates a file-backed dirty-queue store.
    ///
    /// - Parameters:
    ///   - url: JSON file used for the queue.
    ///   - fileManager: File manager used for reads, writes, and directory
    ///     creation.
    public init(
        url: URL = LibraryEntrySyncDirtyQueueStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.fileManager = fileManager
        self.writeQueueHandler = { queue in
            try Self.writeQueue(queue, to: url, fileManager: fileManager)
        }
    }

    init(
        url: URL,
        fileManager: FileManager = .default,
        writeQueueHandler: @escaping (LibraryEntrySyncDirtyQueue) throws -> Void
    ) {
        self.url = url
        self.fileManager = fileManager
        self.writeQueueHandler = writeQueueHandler
    }

    /// Loads the persisted queue, resetting corrupt or unsupported files.
    public func load() -> LibraryEntrySyncDirtyQueue {
        withLock {
            loadUnlocked()
        }
    }

    @discardableResult
    /// Stores an upsert unless an equal or newer upsert is already queued.
    ///
    /// A queued delete for the same identity is replaced by the upsert because
    /// the local entry now exists again.
    ///
    /// - Returns: The previous entry for the identity, when one existed.
    public func setPendingUpsert(_ pendingUpsert: LibraryEntrySyncPendingUpsert) throws
        -> LibraryEntrySyncDirtyQueueEntry?
    {
        try withLock {
            try mutateQueueUnlocked(for: pendingUpsert.identity) { _, existing in
                if case .upsert(let previous) = existing, previous.dirtyAt >= pendingUpsert.dirtyAt {
                    dirtyQueueLogger.debug(
                        "Skipped storing an older dirty-queue upsert for \(pendingUpsert.identity.rawID, privacy: .private)."
                    )
                    return existing
                }
                dirtyQueueLogger.debug(
                    "Stored a dirty-queue upsert for \(pendingUpsert.identity.rawID, privacy: .private) at \(pendingUpsert.dirtyAt, privacy: .public)."
                )
                return .upsert(pendingUpsert)
            }
        }
    }

    @discardableResult
    /// Stores a delete tombstone unless an equal or newer tombstone is queued.
    ///
    /// - Returns: The previous entry for the identity, when one existed.
    public func setPendingDelete(_ pendingDelete: LibraryEntrySyncPendingDelete) throws
        -> LibraryEntrySyncDirtyQueueEntry?
    {
        try withLock {
            try mutateQueueUnlocked(for: pendingDelete.identity) { _, existing in
                if case .delete(let previous) = existing,
                    previous.tombstone.deletedAt >= pendingDelete.tombstone.deletedAt
                {
                    dirtyQueueLogger.debug(
                        "Skipped storing an older dirty-queue delete for \(pendingDelete.identity.rawID, privacy: .private)."
                    )
                    return existing
                }
                dirtyQueueLogger.debug(
                    "Stored a dirty-queue delete for \(pendingDelete.identity.rawID, privacy: .private) at \(pendingDelete.tombstone.deletedAt, privacy: .public)."
                )
                return .delete(pendingDelete)
            }
        }
    }

    @discardableResult
    /// Replaces or removes the queued entry for one identity.
    ///
    /// This is used by delete rollback and export confirmation paths that need
    /// to restore an exact previous queue state.
    ///
    /// - Returns: The previous entry for the identity, when one existed.
    public func replaceEntry(
        _ entry: LibraryEntrySyncDirtyQueueEntry?,
        for identity: LibraryEntrySyncIdentity
    ) throws -> LibraryEntrySyncDirtyQueueEntry? {
        try withLock {
            try mutateQueueUnlocked(for: identity) { _, _ in
                switch entry {
                case .some:
                    dirtyQueueLogger.debug(
                        "Replaced the dirty-queue entry for \(identity.rawID, privacy: .private)."
                    )
                case .none:
                    dirtyQueueLogger.debug(
                        "Removed the dirty-queue entry for \(identity.rawID, privacy: .private)."
                    )
                }
                return entry
            }
        }
    }

    /// Removes queued work for an identity.
    public func removeEntry(for identity: LibraryEntrySyncIdentity) throws {
        _ = try replaceEntry(nil, for: identity)
    }

    /// Removes queued work only if it still matches the entry observed by the caller.
    ///
    /// Export confirmation uses this to avoid deleting newer local work that was
    /// queued while the CloudKit save request was in flight.
    @discardableResult
    public func removeEntry(
        for identity: LibraryEntrySyncIdentity,
        ifCurrentEntryMatches expectedEntry: LibraryEntrySyncDirtyQueueEntry
    ) throws -> Bool {
        try withLock {
            let queue = loadUnlocked()
            guard queue.entry(for: identity) == expectedEntry else {
                dirtyQueueLogger.debug(
                    "Kept the dirty-queue entry for \(identity.rawID, privacy: .private) because it changed before export confirmation."
                )
                return false
            }
            let rewrittenQueue = LibraryEntrySyncDirtyQueue(
                entries: queue.entries.filter { $0.identity != identity }
            )
            guard queue != rewrittenQueue else { return true }
            dirtyQueueLogger.debug(
                "Removed the dirty-queue entry for \(identity.rawID, privacy: .private) after matching export confirmation."
            )
            try writeQueueUnlocked(rewrittenQueue)
            return true
        }
    }

    /// Replaces the persisted dirty queue in one atomic file write.
    ///
    /// Callers that need all-or-nothing multi-entry mutations should stage the
    /// full post-mutation queue in memory, then persist it through this method
    /// instead of chaining per-entry updates.
    public func replaceEntries(_ entries: [LibraryEntrySyncDirtyQueueEntry]) throws {
        try withLock {
            let currentQueue = loadUnlocked()
            let queue = LibraryEntrySyncDirtyQueue(entries: entries)
            guard currentQueue != queue else { return }
            dirtyQueueLogger.debug(
                "Replaced the dirty queue with \(queue.entries.count, privacy: .public) entries."
            )
            try writeQueueUnlocked(queue)
        }
    }

    /// Applies one identity-scoped queue mutation against the persisted JSON.
    ///
    /// The helper loads the current queue, asks the caller how to transform the
    /// existing entry, then writes the rewritten queue back only if it changed.
    private func mutateQueueUnlocked(
        for identity: LibraryEntrySyncIdentity,
        _ transform: (_ queue: LibraryEntrySyncDirtyQueue, _ existing: LibraryEntrySyncDirtyQueueEntry?) ->
            LibraryEntrySyncDirtyQueueEntry?
    ) throws -> LibraryEntrySyncDirtyQueueEntry? {
        let queue = loadUnlocked()
        var entriesByID = queue.entries.reduce(into: [String: LibraryEntrySyncDirtyQueueEntry]()) {
            partialResult, entry in
            partialResult[entry.identity.rawID] = entry
        }
        let existing = entriesByID[identity.rawID]
        guard let newEntry = transform(queue, existing) else {
            entriesByID.removeValue(forKey: identity.rawID)
            let rewrittenQueue = LibraryEntrySyncDirtyQueue(
                entries: entriesByID.values.sorted { lhs, rhs in lhs.identity.rawID < rhs.identity.rawID }
            )
            guard queue != rewrittenQueue else { return existing }
            try writeQueueUnlocked(rewrittenQueue)
            return existing
        }
        entriesByID[newEntry.identity.rawID] = newEntry
        let rewrittenQueue = LibraryEntrySyncDirtyQueue(
            entries: entriesByID.values.sorted { lhs, rhs in lhs.identity.rawID < rhs.identity.rawID }
        )
        guard queue != rewrittenQueue else { return existing }
        try writeQueueUnlocked(rewrittenQueue)
        return existing
    }

    /// Writes the queue through the injected persistence hook.
    private func writeQueueUnlocked(_ queue: LibraryEntrySyncDirtyQueue) throws {
        try writeQueueHandler(queue)
        dirtyQueueLogger.debug(
            "The dirty queue now has \(queue.entries.count, privacy: .public) entries."
        )
    }

    /// Replaces a corrupt queue file with an empty queue if recovery succeeds.
    private func resetToEmptyQueueUnlocked() {
        do {
            try writeQueueUnlocked(.init())
        } catch {
            dirtyQueueLogger.error(
                "Failed to reset the iCloud sync dirty queue after a recovery attempt: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private func loadUnlocked() -> LibraryEntrySyncDirtyQueue {
        guard fileManager.fileExists(atPath: url.path) else {
            return .init()
        }

        do {
            let data = try Data(contentsOf: url)
            let queue = try JSONDecoder().decode(LibraryEntrySyncDirtyQueue.self, from: data)
            guard queue.schemaVersion == LibraryEntrySyncDirtyQueue.currentSchemaVersion else {
                dirtyQueueLogger.warning(
                    "Resetting the iCloud sync dirty queue because schema version \(queue.schemaVersion, privacy: .public) does not match \(LibraryEntrySyncDirtyQueue.currentSchemaVersion, privacy: .public)."
                )
                resetToEmptyQueueUnlocked()
                return .init()
            }
            dirtyQueueLogger.debug(
                "Loaded the dirty queue with \(queue.entries.count, privacy: .public) entries."
            )
            return queue
        } catch {
            dirtyQueueLogger.warning(
                "Resetting the iCloud sync dirty queue because it could not be decoded: \(error.localizedDescription, privacy: .private)"
            )
            resetToEmptyQueueUnlocked()
            return .init()
        }
    }

    private static func writeQueue(
        _ queue: LibraryEntrySyncDirtyQueue,
        to url: URL,
        fileManager: FileManager
    ) throws {
        try createParentDirectoryIfNeeded(for: url, fileManager: fileManager)
        let data = try JSONEncoder().encode(queue)
        try data.write(to: url, options: [.atomic])
    }

    private static func createParentDirectoryIfNeeded(for url: URL, fileManager: FileManager) throws {
        let directoryURL = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try operation()
    }
}
