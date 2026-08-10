//
//  TVMazeResolverTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/8/10.
//

import Foundation
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct TVMazeResolverTests {
    @Test func automaticResolutionUsesSavedMappingAndHydratesIt() async throws {
        let expectedShow = makeTVMazeResolverTestShow(id: 70)
        let probe = TVMazeResolverProbe(
            mappedShowIDs: [10: 70],
            shows: [70: expectedShow]
        )
        let resolver = makeTVMazeResolver(probe: probe)

        let result = try await resolver.resolve(entryType: .series, tmdbID: 10)

        #expect(result == .resolved(expectedShow))
        #expect(await probe.externalIDTMDbIDs.isEmpty)
    }

    @Test func automaticResolutionUsesSeasonParentAndFallsBackFromTVDBToIMDb() async throws {
        let expectedShow = makeTVMazeResolverTestShow(id: 80)
        let probe = TVMazeResolverProbe(
            externalIDs: [20: TMDbSeriesExternalIDs(tvdbID: 30, imdbID: "tt40")],
            imdbShowIDs: ["tt40": 80],
            shows: [80: expectedShow]
        )
        let resolver = makeTVMazeResolver(probe: probe)

        let result = try await resolver.resolve(
            entryType: .season(seasonNumber: 2, parentSeriesID: 20),
            tmdbID: 21
        )

        #expect(result == .resolved(expectedShow))
        #expect(await probe.externalIDTMDbIDs == [20])
        #expect(await probe.lookedUpTVDBIDs == [30])
        #expect(await probe.lookedUpIMDbIDs == ["tt40"])
    }

    @Test func automaticIDMissRequestsUserAssistanceWithoutTitleSearch() async throws {
        let probe = TVMazeResolverProbe(
            externalIDs: [10: TMDbSeriesExternalIDs(tvdbID: nil, imdbID: nil)]
        )
        let resolver = makeTVMazeResolver(probe: probe)

        let result = try await resolver.resolve(entryType: .series, tmdbID: 10)

        #expect(result == .requiresUserAssistance)
        #expect(await probe.searchedTitles.isEmpty)
    }

    @Test func titleFallbackSearchesAndHydratesAsOneOperation() async throws {
        let expectedShow = makeTVMazeResolverTestShow(id: 90)
        let probe = TVMazeResolverProbe(
            titleShowIDs: ["Frieren": 90],
            shows: [90: expectedShow]
        )
        let resolver = makeTVMazeResolver(probe: probe)

        let result = try await resolver.resolveTitleFallback(named: "Frieren")

        #expect(result == expectedShow)
        #expect(await probe.searchedTitles == ["Frieren"])
    }
}

private actor TVMazeResolverProbe {
    private let mappedShowIDs: [Int: Int]
    private let externalIDs: [Int: TMDbSeriesExternalIDs]
    private let tvdbShowIDs: [Int: Int]
    private let imdbShowIDs: [String: Int]
    private let titleShowIDs: [String: Int]
    private let shows: [Int: TVMazeShow]

    private(set) var externalIDTMDbIDs: [Int] = []
    private(set) var lookedUpTVDBIDs: [Int] = []
    private(set) var lookedUpIMDbIDs: [String] = []
    private(set) var searchedTitles: [String] = []

    init(
        mappedShowIDs: [Int: Int] = [:],
        externalIDs: [Int: TMDbSeriesExternalIDs] = [:],
        tvdbShowIDs: [Int: Int] = [:],
        imdbShowIDs: [String: Int] = [:],
        titleShowIDs: [String: Int] = [:],
        shows: [Int: TVMazeShow] = [:]
    ) {
        self.mappedShowIDs = mappedShowIDs
        self.externalIDs = externalIDs
        self.tvdbShowIDs = tvdbShowIDs
        self.imdbShowIDs = imdbShowIDs
        self.titleShowIDs = titleShowIDs
        self.shows = shows
    }

    func mappedShowID(tmdbSeriesID: Int) -> Int? {
        mappedShowIDs[tmdbSeriesID]
    }

    func externalIDs(tmdbSeriesID: Int) -> TMDbSeriesExternalIDs {
        externalIDTMDbIDs.append(tmdbSeriesID)
        return externalIDs[tmdbSeriesID] ?? TMDbSeriesExternalIDs(tvdbID: nil, imdbID: nil)
    }

    func lookupTVDBShowID(tvdbID: Int) -> Int? {
        lookedUpTVDBIDs.append(tvdbID)
        return tvdbShowIDs[tvdbID]
    }

    func lookupIMDbShowID(imdbID: String) -> Int? {
        lookedUpIMDbIDs.append(imdbID)
        return imdbShowIDs[imdbID]
    }

    func searchShowID(title: String) -> Int? {
        searchedTitles.append(title)
        return titleShowIDs[title]
    }

    func show(id: Int) -> TVMazeShow? {
        shows[id]
    }
}

fileprivate func makeTVMazeResolver(probe: TVMazeResolverProbe) -> TVMazeResolver {
    TVMazeResolver(
        loadMappedShowID: { tmdbSeriesID in
            await probe.mappedShowID(tmdbSeriesID: tmdbSeriesID)
        },
        fetchExternalIDs: { tmdbSeriesID in
            await probe.externalIDs(tmdbSeriesID: tmdbSeriesID)
        },
        lookupTVDBShowID: { tvdbID in
            await probe.lookupTVDBShowID(tvdbID: tvdbID)
        },
        lookupIMDbShowID: { imdbID in
            await probe.lookupIMDbShowID(imdbID: imdbID)
        },
        searchShowID: { title in
            await probe.searchShowID(title: title)
        },
        fetchShow: { showID in
            await probe.show(id: showID)
        }
    )
}

fileprivate func makeTVMazeResolverTestShow(id: Int) -> TVMazeShow {
    TVMazeShow(
        id: id,
        name: "Test Show",
        language: "Japanese",
        premiered: "2026-01-01",
        providerLocalSchedule: TVMazeSchedule(
            days: [.friday],
            time: TVMazeTimeOfDay(hour: 1, minute: 30, context: .provider),
            dayOffsetFromBroadcastDay: 1
        ),
        timeZone: TimeZone(identifier: "Asia/Tokyo"),
        fullImageURL: nil,
        nextEpisodeAiring: nil
    )
}
