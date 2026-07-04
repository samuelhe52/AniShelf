//
//  TMDbAPIKeyStorageTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/4.
//

import Foundation
import Security
import Testing

@testable import MyAnimeList

struct TMDbAPIKeyStorageTests {
    @Test func initialMissingKeyRetriesBeforeMarkingMissing() {
        let keychain = FakeTMDbAPIKeyStorageKeychainClient(
            copyResults: [
                (errSecItemNotFound, nil),
                (errSecSuccess, Data("stored-key".utf8) as AnyObject)
            ]
        )

        let storage = TMDbAPIKeyStorage(
            keychain: keychain.client,
            processArguments: []
        )

        #expect(storage.key == nil)
        #expect(storage.lookupState == .checking)

        storage.retryInitialLookupIfNeeded()

        #expect(storage.key == "stored-key")
        #expect(storage.lookupState == .available)
    }

    @Test func retryMarksKeyMissingWhenKeychainStillDoesNotFindIt() {
        let keychain = FakeTMDbAPIKeyStorageKeychainClient(
            copyResults: [
                (errSecItemNotFound, nil),
                (errSecItemNotFound, nil)
            ]
        )

        let storage = TMDbAPIKeyStorage(
            keychain: keychain.client,
            processArguments: []
        )

        storage.retryInitialLookupIfNeeded()

        #expect(storage.key == nil)
        #expect(storage.lookupState == .missing)
    }

    @Test func retryKeepsCheckingWhenKeychainReturnsANonMissingError() {
        let keychain = FakeTMDbAPIKeyStorageKeychainClient(
            copyResults: [
                (errSecInteractionNotAllowed, nil),
                (errSecInteractionNotAllowed, nil)
            ]
        )

        let storage = TMDbAPIKeyStorage(
            keychain: keychain.client,
            processArguments: []
        )

        storage.retryInitialLookupIfNeeded()

        #expect(storage.key == nil)
        #expect(storage.lookupState == .checking)
    }

    @Test func saveFailureDoesNotDeleteExistingKey() {
        let keychain = FakeTMDbAPIKeyStorageKeychainClient(
            copyResults: [
                (errSecSuccess, Data("old-key".utf8) as AnyObject)
            ],
            updateStatus: errSecInteractionNotAllowed
        )

        let storage = TMDbAPIKeyStorage(
            keychain: keychain.client,
            processArguments: []
        )

        let saved = storage.saveKey("new-key")

        #expect(!saved)
        #expect(storage.key == "old-key")
        #expect(storage.lookupState == .available)
        #expect(keychain.deleteCallCount == 0)
        #expect(keychain.addCallCount == 0)
    }
}

fileprivate final class FakeTMDbAPIKeyStorageKeychainClient {
    private var copyResults: [(OSStatus, AnyObject?)]
    private let updateStatus: OSStatus
    private(set) var addCallCount = 0
    private(set) var deleteCallCount = 0

    init(
        copyResults: [(OSStatus, AnyObject?)] = [],
        updateStatus: OSStatus = errSecSuccess
    ) {
        self.copyResults = copyResults
        self.updateStatus = updateStatus
    }

    var client: TMDbAPIKeyStorageKeychainClient {
        TMDbAPIKeyStorageKeychainClient(
            add: { [weak self] _ in
                self?.addCallCount += 1
                return errSecSuccess
            },
            update: { [updateStatus] _, _ in
                updateStatus
            },
            delete: { [weak self] _ in
                self?.deleteCallCount += 1
                return errSecSuccess
            },
            copyMatching: { [weak self] _ in
                guard let self, !copyResults.isEmpty else {
                    return (errSecItemNotFound, nil)
                }
                return copyResults.removeFirst()
            }
        )
    }
}
