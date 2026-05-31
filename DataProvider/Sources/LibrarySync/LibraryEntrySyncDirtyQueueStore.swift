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
/// Tombstones carry the last known user-owned snapshot plus `deletedAt` so
/// another device can decide whether the delete is newer than its local edits.
public struct LibraryEntrySyncTombstone: Codable, Equatable, Sendable {
    public var snapshot: LibraryEntrySyncSnapshot

    /// Captures an entry's current sync state as a delete tombstone.
    public init(entry: AnimeEntry, deletedAt: Date = .now) {
        var snapshot = LibraryEntrySyncSnapshot(entry: entry)
        snapshot.deletedAt = deletedAt
        self.snapshot = snapshot
    }

    /// Wraps an existing delete snapshot.
    ///
    /// The snapshot must already contain a `deletedAt` value.
    public init(snapshot: LibraryEntrySyncSnapshot) {
        precondition(snapshot.deletedAt != nil)
        self.snapshot = snapshot
    }

    public var identity: LibraryEntrySyncIdentity { snapshot.identity }
    public var deletedAt: Date { snapshot.deletedAt ?? .distantPast }

    /// Returns the tombstone as the snapshot to upload.
    public func syncSnapshot() -> LibraryEntrySyncSnapshot {
        snapshot
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
    public static let currentSchemaVersion = 1

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
        guard fileManager.fileExists(atPath: url.path) else {
            return .init()
        }

        do {
            let data = try Data(contentsOf: url)
            let queue = try JSONDecoder().decode(LibraryEntrySyncDirtyQueue.self, from: data)
            guard queue.schemaVersion <= LibraryEntrySyncDirtyQueue.currentSchemaVersion else {
                dirtyQueueLogger.warning(
                    "operation=load state=reset reason=unsupportedSchemaVersion schemaVersion=\(queue.schemaVersion, privacy: .public) currentSchemaVersion=\(LibraryEntrySyncDirtyQueue.currentSchemaVersion, privacy: .public)"
                )
                resetToEmptyQueue()
                return .init()
            }
            return queue
        } catch {
            dirtyQueueLogger.warning(
                "operation=load state=reset reason=decodeFailure errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            resetToEmptyQueue()
            return .init()
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
        try mutateQueue(for: pendingUpsert.identity, mutation: "upsert") { _, existing in
            if case .upsert(let previous) = existing, previous.dirtyAt >= pendingUpsert.dirtyAt {
                dirtyQueueLogger.debug(
                    "operation=setPendingUpsert decision=kept identity=\(pendingUpsert.identity.rawID, privacy: .private) existingDirtyAt=\(previous.dirtyAt, privacy: .public) incomingDirtyAt=\(pendingUpsert.dirtyAt, privacy: .public)"
                )
                return existing
            }
            dirtyQueueLogger.debug(
                "operation=setPendingUpsert decision=replaced identity=\(pendingUpsert.identity.rawID, privacy: .private) dirtyAt=\(pendingUpsert.dirtyAt, privacy: .public)"
            )
            return .upsert(pendingUpsert)
        }
    }

    @discardableResult
    /// Stores a delete tombstone unless an equal or newer tombstone is queued.
    ///
    /// - Returns: The previous entry for the identity, when one existed.
    public func setPendingDelete(_ pendingDelete: LibraryEntrySyncPendingDelete) throws
        -> LibraryEntrySyncDirtyQueueEntry?
    {
        try mutateQueue(for: pendingDelete.identity, mutation: "delete") { _, existing in
            if case .delete(let previous) = existing, previous.tombstone.deletedAt >= pendingDelete.tombstone.deletedAt
            {
                dirtyQueueLogger.debug(
                    "operation=setPendingDelete decision=kept identity=\(pendingDelete.identity.rawID, privacy: .private) existingDeletedAt=\(previous.tombstone.deletedAt, privacy: .public) incomingDeletedAt=\(pendingDelete.tombstone.deletedAt, privacy: .public)"
                )
                return existing
            }
            dirtyQueueLogger.debug(
                "operation=setPendingDelete decision=replaced identity=\(pendingDelete.identity.rawID, privacy: .private) deletedAt=\(pendingDelete.tombstone.deletedAt, privacy: .public)"
            )
            return .delete(pendingDelete)
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
        try mutateQueue(for: identity, mutation: "replaceEntry") { _, existing in
            switch entry {
            case .some:
                dirtyQueueLogger.debug(
                    "operation=replaceEntry decision=replaced identity=\(identity.rawID, privacy: .private)"
                )
            case .none where existing != nil:
                dirtyQueueLogger.debug(
                    "operation=replaceEntry decision=removed identity=\(identity.rawID, privacy: .private)"
                )
            case .none:
                dirtyQueueLogger.debug(
                    "operation=replaceEntry decision=keptMissing identity=\(identity.rawID, privacy: .private)"
                )
            }
            return entry
        }
    }

    /// Removes queued work for an identity.
    public func removeEntry(for identity: LibraryEntrySyncIdentity) throws {
        _ = try replaceEntry(nil, for: identity)
    }

    /// Replaces the persisted dirty queue in one atomic file write.
    ///
    /// Callers that need all-or-nothing multi-entry mutations should stage the
    /// full post-mutation queue in memory, then persist it through this method
    /// instead of chaining per-entry updates.
    public func replaceEntries(_ entries: [LibraryEntrySyncDirtyQueueEntry]) throws {
        let currentQueue = load()
        let queue = LibraryEntrySyncDirtyQueue(entries: entries)
        dirtyQueueLogger.debug(
            "operation=replaceEntries inputCount=\(entries.count, privacy: .public) storedCount=\(queue.entries.count, privacy: .public)"
        )
        guard currentQueue != queue else {
            dirtyQueueLogger.debug(
                "operation=replaceEntries decision=skipped reason=unchanged entryCount=\(queue.entries.count, privacy: .public)"
            )
            return
        }
        try writeQueue(queue)
    }

    /// Applies one identity-scoped queue mutation against the persisted JSON.
    ///
    /// The helper loads the current queue, asks the caller how to transform the
    /// existing entry, then writes the rewritten queue back only if it changed.
    private func mutateQueue(
        for identity: LibraryEntrySyncIdentity,
        mutation: String,
        _ transform: (_ queue: LibraryEntrySyncDirtyQueue, _ existing: LibraryEntrySyncDirtyQueueEntry?) ->
            LibraryEntrySyncDirtyQueueEntry?
    ) throws -> LibraryEntrySyncDirtyQueueEntry? {
        let queue = load()
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
            dirtyQueueLogger.debug(
                "operation=\(mutation, privacy: .public) identity=\(identity.rawID, privacy: .private) decision=removed inputCount=\(queue.entries.count, privacy: .public) outputCount=\(rewrittenQueue.entries.count, privacy: .public)"
            )
            guard queue != rewrittenQueue else {
                dirtyQueueLogger.debug(
                    "operation=\(mutation, privacy: .public) identity=\(identity.rawID, privacy: .private) decision=skipped reason=unchanged"
                )
                return existing
            }
            try writeQueue(rewrittenQueue)
            return existing
        }
        entriesByID[newEntry.identity.rawID] = newEntry
        let rewrittenQueue = LibraryEntrySyncDirtyQueue(
            entries: entriesByID.values.sorted { lhs, rhs in lhs.identity.rawID < rhs.identity.rawID }
        )
        dirtyQueueLogger.debug(
            "operation=\(mutation, privacy: .public) identity=\(identity.rawID, privacy: .private) decision=stored inputCount=\(queue.entries.count, privacy: .public) outputCount=\(rewrittenQueue.entries.count, privacy: .public)"
        )
        guard queue != rewrittenQueue else {
            dirtyQueueLogger.debug(
                "operation=\(mutation, privacy: .public) identity=\(identity.rawID, privacy: .private) decision=skipped reason=unchanged"
            )
            return existing
        }
        try writeQueue(rewrittenQueue)
        return existing
    }

    /// Writes the queue through the injected persistence hook.
    private func writeQueue(_ queue: LibraryEntrySyncDirtyQueue) throws {
        dirtyQueueLogger.debug(
            "operation=writeQueue entryCount=\(queue.entries.count, privacy: .public)"
        )
        try writeQueueHandler(queue)
    }

    /// Replaces a corrupt queue file with an empty queue if recovery succeeds.
    private func resetToEmptyQueue() {
        do {
            try writeQueue(.init())
        } catch {
            dirtyQueueLogger.error(
                "operation=resetToEmptyQueue result=failure errorType=\(String(describing: type(of: error)), privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
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
}
