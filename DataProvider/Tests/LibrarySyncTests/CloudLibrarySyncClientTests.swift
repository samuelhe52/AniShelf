//
//  CloudLibrarySyncClientTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/30.
//

import CloudKit
import DataProvider
import Foundation
import ObjectiveC.runtime
import Testing

@testable import LibrarySync

struct CloudLibrarySyncClientTests {
    private let client = CloudLibrarySyncClient()

    @Test func deterministicRecordIDsUseStableZoneAndIdentityNames() {
        let movie = LibraryEntrySyncIdentity(entryType: .movie, tmdbID: 11)
        let series = LibraryEntrySyncIdentity(entryType: .series, tmdbID: 22)
        let season = LibraryEntrySyncIdentity(
            entryType: .season(seasonNumber: 3, parentSeriesID: 22),
            tmdbID: 33
        )

        #expect(client.recordID(for: movie).recordName == "movie:11")
        #expect(client.recordID(for: series).recordName == "series:22")
        #expect(client.recordID(for: season).recordName == "season:22:3:33")
        #expect(client.recordID(for: movie).zoneID == CloudLibrarySyncClient.recordZoneID)
    }

    @Test func snapshotRoundTripsThroughCloudKitRecord() throws {
        let snapshot = LibraryEntrySyncSnapshot(
            identity: LibraryEntrySyncIdentity(
                entryType: .season(seasonNumber: 2, parentSeriesID: 44),
                tmdbID: 55
            ),
            tmdbID: 55,
            parentSeriesID: 44,
            seasonNumber: 2,
            entryType: .season(seasonNumber: 2, parentSeriesID: 44),
            onDisplay: false,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1),
            watchStatus: .watched,
            dateStarted: referenceDate(year: 2026, month: 5, day: 2),
            dateFinished: referenceDate(year: 2026, month: 5, day: 9),
            isDateTrackingEnabled: false,
            score: 4,
            favorite: true,
            notes: "Round trip",
            usingCustomPoster: true,
            customPosterURL: URL(string: "https://image.tmdb.org/t/p/w500/custom.jpg"),
            episodeProgresses: [
                .init(
                    seasonNumber: 2,
                    watchedThroughEpisode: 12,
                    updatedAt: referenceDate(year: 2026, month: 5, day: 8)
                )
            ],
            libraryUpdatedAt: referenceDate(year: 2026, month: 5, day: 10),
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 11)
        )

        let record = try client.record(from: snapshot)
        let decoded = try client.snapshot(from: record)

        #expect(record.recordType == CloudLibrarySyncClient.recordType)
        #expect(record.recordID == client.recordID(for: snapshot.identity))
        #expect(record["customPosterPath"] as? String == "/custom.jpg")
        #expect(!record.allKeys().contains("customPosterURL"))
        #expect(decoded == snapshot)
    }

    @Test func legacyCustomPosterURLDecodesToPathWhenPathFieldIsAbsent() throws {
        let snapshot = makeSnapshot()
        let record = try client.record(from: snapshot)
        record["usingCustomPoster"] = true
        record["customPosterPath"] = nil
        record["customPosterURL"] = "https://image.tmdb.org/t/p/w342/legacy/custom.jpg"

        let decoded = try client.snapshot(from: record)

        #expect(decoded.usingCustomPoster)
        #expect(decoded.customPosterPath == "/legacy/custom.jpg")
    }

    @Test func leanTombstoneRoundTripsThroughRemoteChangeRecord() throws {
        let entry = AnimeEntry(name: "Deleted", type: .series, tmdbID: 56)
        let tombstone = LibraryEntrySyncTombstone(
            entry: entry,
            deletedAt: referenceDate(year: 2026, month: 5, day: 12)
        )

        let record = try client.record(from: tombstone)
        let change = try client.remoteChange(from: record)

        #expect(record.recordType == CloudLibrarySyncClient.recordType)
        #expect(record.recordID == client.recordID(for: tombstone.identity))
        #expect(record["deletedAt"] as? Date == tombstone.deletedAt)
        #expect(!record.allKeys().contains("notes"))
        #expect(!record.allKeys().contains("episodeProgresses"))
        #expect(!record.allKeys().contains("watchStatus"))
        #expect(record.changedKeys().contains("notes"))
        #expect(record.changedKeys().contains("episodeProgresses"))
        #expect(record.changedKeys().contains("watchStatus"))
        #expect(change == .tombstone(tombstone))
    }

    @Test func unknownFutureSchemaVersionThrowsTypedError() throws {
        let record = try client.record(from: makeSnapshot())
        record["schemaVersion"] = LibraryEntrySyncSnapshot.currentSchemaVersion + 1

        expectDecodeError(.unsupportedSchemaVersion(LibraryEntrySyncSnapshot.currentSchemaVersion + 1)) {
            _ = try client.snapshot(from: record)
        }
    }

    @Test func wrongRecordTypeThrowsTypedError() throws {
        let snapshot = makeSnapshot()
        let record = CKRecord(
            recordType: "OtherRecord",
            recordID: client.recordID(for: snapshot.identity)
        )

        expectDecodeError(.wrongRecordType(actual: "OtherRecord")) {
            _ = try client.snapshot(from: record)
        }
    }

    @Test func missingRequiredFieldThrowsTypedError() throws {
        let record = try client.record(from: makeSnapshot())
        record["watchStatus"] = nil

        expectDecodeError(.missingRequiredField("watchStatus")) {
            _ = try client.snapshot(from: record)
        }
    }

    @Test func corruptEpisodeProgressPayloadThrowsTypedError() throws {
        let record = try client.record(from: makeSnapshot())
        record["episodeProgresses"] = Data("not-json".utf8)

        expectDecodeError(.corruptEpisodeProgressPayload) {
            _ = try client.snapshot(from: record)
        }
    }

    @Test func invalidSeasonIdentityCombinationThrowsTypedError() throws {
        let record = try client.record(
            from: makeSnapshot(
                entryType: .season(seasonNumber: 3, parentSeriesID: 22),
                tmdbID: 33
            )
        )
        record["seasonNumber"] = 4

        expectDecodeError(.invalidIdentityCombination(recordName: "season:22:3:33")) {
            _ = try client.snapshot(from: record)
        }
    }

    @Test func changeTokenStoreRoundTripsAndClearsPerZoneToken() throws {
        let suiteName = "CloudLibrarySyncClientTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        let store = CloudLibrarySyncChangeTokenStore(userDefaults: userDefaults)
        let zoneID = CloudLibrarySyncClient.recordZoneID
        let namespace = CloudLibrarySyncChangeTokenStore.Namespace(
            containerIdentifier: "iCloud.com.samuelhe.MyAnimeList",
            accountIdentifier: "user-a"
        )
        let token = try #require(class_createInstance(CKServerChangeToken.self, 0) as? CKServerChangeToken)

        let encodedToken = try store.encodeToken(token)
        store.setToken(token, for: zoneID, namespace: namespace)

        let roundTripped = try #require(store.token(for: zoneID, namespace: namespace))
        #expect(try store.encodeToken(roundTripped) == encodedToken)

        store.removeToken(for: zoneID, namespace: namespace)
        #expect(store.token(for: zoneID, namespace: namespace) == nil)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    @Test func changeTokenStoreDoesNotReuseTokensAcrossContainersOrAccounts() throws {
        let suiteName = "CloudLibrarySyncClientTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        let store = CloudLibrarySyncChangeTokenStore(userDefaults: userDefaults)
        let zoneID = CloudLibrarySyncClient.recordZoneID
        let primaryNamespace = CloudLibrarySyncChangeTokenStore.Namespace(
            containerIdentifier: "iCloud.com.samuelhe.MyAnimeList",
            accountIdentifier: "user-a"
        )
        let otherAccountNamespace = CloudLibrarySyncChangeTokenStore.Namespace(
            containerIdentifier: "iCloud.com.samuelhe.MyAnimeList",
            accountIdentifier: "user-b"
        )
        let otherContainerNamespace = CloudLibrarySyncChangeTokenStore.Namespace(
            containerIdentifier: "iCloud.com.samuelhe.OtherBuild",
            accountIdentifier: "user-a"
        )
        let token = try #require(class_createInstance(CKServerChangeToken.self, 0) as? CKServerChangeToken)

        store.setToken(token, for: zoneID, namespace: primaryNamespace)

        #expect(store.token(for: zoneID, namespace: otherAccountNamespace) == nil)
        #expect(store.token(for: zoneID, namespace: otherContainerNamespace) == nil)
        #expect(
            store.tokenKey(for: zoneID, namespace: primaryNamespace)
                != store.tokenKey(for: zoneID, namespace: otherAccountNamespace)
        )
        #expect(
            store.tokenKey(for: zoneID, namespace: primaryNamespace)
                != store.tokenKey(for: zoneID, namespace: otherContainerNamespace)
        )
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    @Test func changeTokenStoreRemovesAllOwnedTokensOnly() throws {
        let suiteName = "CloudLibrarySyncClientTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        let store = CloudLibrarySyncChangeTokenStore(userDefaults: userDefaults)
        let zoneID = CloudLibrarySyncClient.recordZoneID
        let firstNamespace = CloudLibrarySyncChangeTokenStore.Namespace(
            containerIdentifier: "iCloud.com.samuelhe.MyAnimeList",
            accountIdentifier: "user-a"
        )
        let secondNamespace = CloudLibrarySyncChangeTokenStore.Namespace(
            containerIdentifier: "iCloud.com.samuelhe.OtherBuild",
            accountIdentifier: "user-b"
        )
        let token = try #require(class_createInstance(CKServerChangeToken.self, 0) as? CKServerChangeToken)

        store.setToken(token, for: zoneID, namespace: firstNamespace)
        store.setToken(token, for: zoneID, namespace: secondNamespace)
        userDefaults.set("keep", forKey: "AniShelf.OtherPreference")

        store.removeAllTokens()

        #expect(store.token(for: zoneID, namespace: firstNamespace) == nil)
        #expect(store.token(for: zoneID, namespace: secondNamespace) == nil)
        #expect(userDefaults.string(forKey: "AniShelf.OtherPreference") == "keep")
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    private func makeSnapshot(
        entryType: AnimeType = .series,
        tmdbID: Int = 101
    ) -> LibraryEntrySyncSnapshot {
        let identity = LibraryEntrySyncIdentity(entryType: entryType, tmdbID: tmdbID)
        return LibraryEntrySyncSnapshot(
            identity: identity,
            tmdbID: tmdbID,
            parentSeriesID: entryType.parentSeriesID,
            seasonNumber: entryType.seasonNumber,
            entryType: entryType,
            onDisplay: true,
            dateSaved: referenceDate(year: 2026, month: 5, day: 1),
            watchStatus: .watching,
            dateStarted: referenceDate(year: 2026, month: 5, day: 2),
            dateFinished: nil,
            isDateTrackingEnabled: true,
            score: 3,
            favorite: false,
            notes: "Notes",
            usingCustomPoster: false,
            customPosterURL: nil,
            episodeProgresses: [
                .init(
                    seasonNumber: 1,
                    watchedThroughEpisode: 6,
                    updatedAt: referenceDate(year: 2026, month: 5, day: 3)
                )
            ],
            libraryUpdatedAt: referenceDate(year: 2026, month: 5, day: 4),
            trackingUpdatedAt: referenceDate(year: 2026, month: 5, day: 5)
        )
    }

    private func expectDecodeError(
        _ expected: CloudLibrarySyncDecodeError,
        _ body: () throws -> Void
    ) {
        do {
            try body()
            #expect(Bool(false))
        } catch let error as CloudLibrarySyncDecodeError {
            #expect(error == expected)
        } catch {
            #expect(Bool(false))
        }
    }
}

fileprivate func referenceDate(year: Int, month: Int, day: Int) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: year, month: month, day: day)
    )!
}
