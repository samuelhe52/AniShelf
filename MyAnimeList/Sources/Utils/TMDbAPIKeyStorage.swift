//
//  TMDbAPIKeyStorage.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/6/10.
//

import Foundation
import Security
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "TMDbAPIKeyStorage")

enum TMDbAPIKeyLookupState {
    case checking
    case available
    case missing
}

struct TMDbAPIKeyStorageKeychainClient: @unchecked Sendable {
    var add: ([String: Any]) -> OSStatus
    var update: ([String: Any], [String: Any]) -> OSStatus
    var delete: ([String: Any]) -> OSStatus
    var copyMatching: ([String: Any]) -> (OSStatus, AnyObject?)

    static let system = Self(
        add: { query in
            SecItemAdd(query as CFDictionary, nil)
        },
        update: { query, attributes in
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        },
        delete: { query in
            SecItemDelete(query as CFDictionary)
        },
        copyMatching: { query in
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result)
        }
    )
}

@Observable
class TMDbAPIKeyStorage {
    private let account = "TMDbAPIKey"
    private static let resetArgument = "-reset-tmdb-api-key"
    private let keychain: TMDbAPIKeyStorageKeychainClient
    var key: String?
    var lookupState: TMDbAPIKeyLookupState = .checking

    init(
        keychain: TMDbAPIKeyStorageKeychainClient = .system,
        processArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.keychain = keychain
        if processArguments.contains(Self.resetArgument) {
            deleteKey()
            lookupState = .missing
            return
        }
        loadStoredKey()
    }

    func retryInitialLookupIfNeeded() {
        guard lookupState == .checking else { return }

        switch retrieveKeyResult() {
        case .found(let storedKey):
            key = storedKey
            lookupState = .available
        case .missing:
            key = nil
            lookupState = .missing
        case .failure(let status):
            key = nil
            lookupState = .checking
            logger.error(
                "TMDb API key remained unavailable after retry. Keeping lookup pending. Status code: \(status)"
            )
        }
    }

    func saveKey(_ newKey: String) -> Bool {
        let trimmedKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(trimmedKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = keychain.update(query, attributes)
        let status: OSStatus
        if updateStatus == errSecSuccess {
            status = updateStatus
        } else if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            status = keychain.add(addQuery)
        } else {
            status = updateStatus
        }

        if status == errSecSuccess {
            key = trimmedKey
            lookupState = .available
            logger.info("Successfully saved TMDb API key to keychain.")
        } else {
            logger.error("Failed to save TMDb API key to keychain. Status code: \(status)")
        }
        return status == errSecSuccess
    }

    func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]

        let status = keychain.delete(query)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            key = nil
            lookupState = .missing
            logger.info("Removed TMDb API key from keychain.")
        default:
            logger.error("Failed to remove TMDb API key from keychain. Status code: \(status)")
        }
    }

    func retrieveKey() -> String? {
        guard case .found(let key) = retrieveKeyResult() else {
            return nil
        }
        return key
    }

    private func loadStoredKey() {
        switch retrieveKeyResult() {
        case .found(let storedKey):
            key = storedKey
            lookupState = .available
        case .missing, .failure:
            key = nil
            lookupState = .checking
        }
    }

    private enum KeyLookupResult {
        case found(String)
        case missing
        case failure(OSStatus)
    }

    private func retrieveKeyResult() -> KeyLookupResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let (status, result) = keychain.copyMatching(query)
        if status == errSecItemNotFound {
            logger.info("No TMDb API key found in keychain.")
            return .missing
        }
        if status != errSecSuccess {
            logger.error("Failed to retrieve TMDb API key from keychain. Status code: \(status)")
            return .failure(status)
        }

        guard status == errSecSuccess,
            let data = result as? Data,
            let key = String(data: data, encoding: .utf8)
        else {
            return .failure(errSecDecode)
        }

        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedKey.isEmpty ? .missing : .found(trimmedKey)
    }
}
