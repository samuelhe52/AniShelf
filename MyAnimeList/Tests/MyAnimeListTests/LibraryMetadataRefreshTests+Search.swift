//
//  LibraryMetadataRefreshTests+Search.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import Foundation
import SwiftData
import TMDb
import Testing

@testable import DataProvider
@testable import MyAnimeList

extension LibraryMetadataRefreshTests {
    @Test @MainActor func testLibrarySearchServiceKeepsCrossTypeTMDbCollisions() {
        let movie = AnimeEntry(name: "Collision Movie", type: .movie, tmdbID: 500_003)
        let series = AnimeEntry(name: "Collision Series", type: .series, tmdbID: 500_003)
        let service = LibrarySearchService(entriesProvider: { [movie, series] })

        service.updateResults(query: "collision")

        #expect(Set(service.results.map(\.libraryIdentity)) == Set([movie.libraryIdentity, series.libraryIdentity]))
    }

    @Test @MainActor func testLibrarySearchServiceUsesCurrentLibraryStoreEntries() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        store.newEntryFromEntryMetadata(
            EntryMetadata(
                name: "First Match",
                nameTranslations: [:],
                overview: nil,
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 500_001,
                onAirDate: nil,
                linkToDetails: nil,
                type: .movie
            )
        )
        try store.refreshLibrary()

        let service = LibrarySearchService(
            entriesProvider: { store.library }
        )

        service.updateResults(query: "first")
        #expect(service.results.map(\.tmdbID) == [500_001])

        store.newEntryFromEntryMetadata(
            EntryMetadata(
                name: "Second Match",
                nameTranslations: [:],
                overview: nil,
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 500_002,
                onAirDate: nil,
                linkToDetails: nil,
                type: .movie
            )
        )
        try store.refreshLibrary()

        service.updateResults(query: "second")
        #expect(service.results.map(\.tmdbID) == [500_002])
    }

}
