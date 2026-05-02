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

@Observable
class TMDbAPIKeyStorage {
    private let account = "TMDbAPIKey"
    private static let resetArgument = "-reset-tmdb-api-key"
    var key: String?

    init() {
        if ProcessInfo.processInfo.arguments.contains(Self.resetArgument) {
            deleteKey()
        }
        let key: String? = retrieveKey()
        self.key = key
    }

    func saveKey(_ newKey: String) -> Bool {
        let data = Data(newKey.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)  // Remove any existing item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            self.key = newKey
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

        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            self.key = nil
            logger.info("Removed TMDb API key from keychain.")
        default:
            logger.error("Failed to remove TMDb API key from keychain. Status code: \(status)")
        }
    }

    func retrieveKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess {
            logger.error("Failed to retrieve TMDb API key from keychain. Status code: \(status)")
        }

        guard status == errSecSuccess,
            let data = result as? Data,
            let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
