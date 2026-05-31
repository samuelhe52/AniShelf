//
//  CloudLibrarySyncChangeTokenStore.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import CloudKit
import Foundation

/// Persists CloudKit zone change tokens per container, account, owner, and zone.
public final class CloudLibrarySyncChangeTokenStore: @unchecked Sendable {
    /// Namespace separating one iCloud account/container's token from another.
    public struct Namespace: Hashable, Sendable {
        public let containerIdentifier: String
        public let accountIdentifier: String

        /// Creates a token namespace.
        ///
        /// - Parameters:
        ///   - containerIdentifier: CloudKit container identifier.
        ///   - accountIdentifier: CloudKit user record name for the current
        ///     iCloud account.
        public init(containerIdentifier: String, accountIdentifier: String) {
            self.containerIdentifier = containerIdentifier
            self.accountIdentifier = accountIdentifier
        }
    }

    private let userDefaults: UserDefaults
    private let keyPrefix: String

    /// Creates a change-token store.
    ///
    /// - Parameters:
    ///   - userDefaults: Storage backend for archived `CKServerChangeToken`
    ///     values.
    ///   - keyPrefix: Prefix used for all token keys.
    public init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "AniShelf.LibrarySync.ChangeToken"
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    /// Loads the last committed server token for a zone/account namespace.
    ///
    /// Corrupt archived tokens are removed and treated as missing.
    public func token(for zoneID: CKRecordZone.ID, namespace: Namespace) -> CKServerChangeToken? {
        let key = tokenKey(for: zoneID, namespace: namespace)
        guard let data = userDefaults.data(forKey: key) else { return nil }

        do {
            return try decodeToken(from: data)
        } catch {
            userDefaults.removeObject(forKey: key)
            return nil
        }
    }

    /// Persists or clears a server token.
    ///
    /// Passing `nil` removes the stored token. Encoding failures also remove the
    /// token so the next import can safely refetch from the beginning.
    public func setToken(
        _ token: CKServerChangeToken?,
        for zoneID: CKRecordZone.ID,
        namespace: Namespace
    ) {
        let key = tokenKey(for: zoneID, namespace: namespace)
        guard let token else {
            userDefaults.removeObject(forKey: key)
            return
        }

        do {
            userDefaults.set(try encodeToken(token), forKey: key)
        } catch {
            userDefaults.removeObject(forKey: key)
        }
    }

    /// Removes the stored token for a zone/account namespace.
    public func removeToken(for zoneID: CKRecordZone.ID, namespace: Namespace) {
        userDefaults.removeObject(forKey: tokenKey(for: zoneID, namespace: namespace))
    }
}

extension CloudLibrarySyncChangeTokenStore {
    func tokenKey(for zoneID: CKRecordZone.ID, namespace: Namespace) -> String {
        "\(keyPrefix).\(namespace.containerIdentifier).\(namespace.accountIdentifier).\(zoneID.ownerName).\(zoneID.zoneName)"
    }

    func encodeToken(_ token: CKServerChangeToken) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    func decodeToken(from data: Data) throws -> CKServerChangeToken {
        let coder = try NSKeyedUnarchiver(forReadingFrom: data)
        guard let token = coder.decodeObject(of: CKServerChangeToken.self, forKey: NSKeyedArchiveRootObjectKey)
        else {
            throw CocoaError(.coderReadCorrupt)
        }
        return token
    }
}
