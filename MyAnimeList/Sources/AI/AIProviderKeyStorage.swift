//
//  AIProviderKeyStorage.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/28.
//

import Foundation
import Security

/// Uses the same injectable client as TMDb; fixture launches inherit its isolation.
struct AIProviderKeyStorage {
    private let keychain: TMDbAPIKeyStorageKeychainClient

    init(keychain: TMDbAPIKeyStorageKeychainClient = TMDbAPIKeyStorage.defaultKeychain) {
        self.keychain = keychain
    }

    private func query(for backend: AIBackend) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(String.bundleIdentifier).ai-provider",
            kSecAttrAccount as String: backend.rawValue,
            kSecAttrSynchronizable as String: false
        ]
    }

    func key(for backend: AIBackend) -> String? {
        guard backend != .apple else { return nil }
        var query = query(for: backend)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = keychain.copyMatching(query)
        guard status == errSecSuccess, let data = result as? Data,
            let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !key.isEmpty
        else { return nil }
        return key
    }

    @discardableResult
    func save(_ key: String, for backend: AIBackend) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard backend != .apple, !key.isEmpty else { return false }
        let query = query(for: backend)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = keychain.update(query, attributes)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return keychain.add(query.merging(attributes) { _, new in new }) == errSecSuccess
    }

    @discardableResult
    func delete(for backend: AIBackend) -> Bool {
        guard backend != .apple else { return false }
        let status = keychain.delete(query(for: backend))
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
