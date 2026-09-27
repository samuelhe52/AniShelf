//
//  CloudLibrarySyncQuarantineStore.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/9/27.
//

import CloudKit
import Foundation

/// Durable records that this build must not overwrite because it could not decode them.
public final class CloudLibrarySyncQuarantineStore: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var containerIdentifier: String
        public var accountIdentifier: String
        public var zoneName: String
        public var zoneOwnerName: String
        public var recordName: String
        public var recordType: String
        public var schemaVersion: Int?
        public var reason: String
        public var attemptedAppVersion: String

        public var recordID: CKRecord.ID {
            CKRecord.ID(
                recordName: recordName,
                zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName)
            )
        }

        public init(
            record: CKRecord,
            namespace: CloudLibrarySyncChangeTokenStore.Namespace,
            reason: String,
            attemptedAppVersion: String
        ) {
            containerIdentifier = namespace.containerIdentifier
            accountIdentifier = namespace.accountIdentifier
            zoneName = record.recordID.zoneID.zoneName
            zoneOwnerName = record.recordID.zoneID.ownerName
            recordName = record.recordID.recordName
            recordType = record.recordType
            schemaVersion = record["schemaVersion"] as? Int
            self.reason = reason
            self.attemptedAppVersion = attemptedAppVersion
        }

        fileprivate func belongs(
            to namespace: CloudLibrarySyncChangeTokenStore.Namespace,
            zoneID: CKRecordZone.ID
        ) -> Bool {
            containerIdentifier == namespace.containerIdentifier
                && accountIdentifier == namespace.accountIdentifier
                && zoneName == zoneID.zoneName
                && zoneOwnerName == zoneID.ownerName
        }
    }

    public let url: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniShelf/LibrarySync/quarantined-records.json"),
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.fileManager = fileManager
    }

    public func entries(
        namespace: CloudLibrarySyncChangeTokenStore.Namespace,
        zoneID: CKRecordZone.ID
    ) throws -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return try load().filter { $0.belongs(to: namespace, zoneID: zoneID) }
    }

    /// Applies the fetched change set when its change token is committed.
    ///
    /// A failure leaves the token uncommitted and stops export, preserving the blocked IDs.
    public func reconcile(
        namespace: CloudLibrarySyncChangeTokenStore.Namespace,
        zoneID: CKRecordZone.ID,
        decodedRecordIDs: Set<CKRecord.ID>,
        deletedRecordIDs: Set<CKRecord.ID>,
        failures: [Entry]
    ) throws -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        var all = try load()
        let resolvedIDs = decodedRecordIDs.union(deletedRecordIDs)
        all.removeAll { entry in
            entry.belongs(to: namespace, zoneID: zoneID) && resolvedIDs.contains(entry.recordID)
        }
        for failure in failures {
            all.removeAll { entry in
                entry.belongs(to: namespace, zoneID: zoneID) && entry.recordID == failure.recordID
            }
            all.append(failure)
        }
        try persist(all)
        return all.filter { $0.belongs(to: namespace, zoneID: zoneID) }
    }

    private func load() throws -> [Entry] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
    }

    private func persist(_ entries: [Entry]) throws {
        if entries.isEmpty && !fileManager.fileExists(atPath: url.path) { return }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
}
