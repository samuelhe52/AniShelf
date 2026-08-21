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

        let result = try await resolver.resolve(
            entryType: .series,
            tmdbID: 10,
            externalIDs: TMDbSeriesExternalIDs(tvdbID: nil, imdbID: nil)
        )

        #expect(result == .resolved(expectedShow))
        #expect(await probe.savedMappings.isEmpty)
    }

    @Test func automaticResolutionUsesSeasonParentAndFallsBackFromTVDBToIMDb() async throws {
        let expectedShow = makeTVMazeResolverTestShow(id: 80)
        let probe = TVMazeResolverProbe(
            imdbShowIDs: ["tt40": 80],
            shows: [80: expectedShow]
        )
        let resolver = makeTVMazeResolver(probe: probe)

        let result = try await resolver.resolve(
            entryType: .season(seasonNumber: 2, parentSeriesID: 20),
            tmdbID: 21,
            externalIDs: TMDbSeriesExternalIDs(tvdbID: 30, imdbID: "tt40")
        )

        #expect(result == .resolved(expectedShow))
        #expect(await probe.lookedUpTVDBIDs == [30])
        #expect(await probe.lookedUpIMDbIDs == ["tt40"])
        #expect(await probe.savedMappings == [TVMazeResolverProbe.Mapping(tmdbSeriesID: 20, showID: 80)])
    }

    @Test func automaticResolutionPersistsHydratedTVDBMatch() async throws {
        let expectedShow = makeTVMazeResolverTestShow(id: 70)
        let replacementProbe = TVMazeMappingReplacementProbe()
        let probe = TVMazeResolverProbe(
            tvdbShowIDs: [30: 70],
            shows: [70: expectedShow]
        )
        let resolver = makeTVMazeResolver(
            probe: probe,
            replacementProbe: replacementProbe
        )

        let result = try await resolver.resolve(
            entryType: .series,
            tmdbID: 10,
            externalIDs: TMDbSeriesExternalIDs(tvdbID: 30, imdbID: "tt40")
        )

        #expect(result == .resolved(expectedShow))
        #expect(await probe.lookedUpIMDbIDs.isEmpty)
        #expect(await probe.savedMappings == [TVMazeResolverProbe.Mapping(tmdbSeriesID: 10, showID: 70)])
        #expect(await replacementProbe.replacements.isEmpty)
    }

    @Test func automaticResolutionReportsReplacementAfterSavedShowStopsHydrating() async throws {
        let replacementShow = makeTVMazeResolverTestShow(id: 90)
        let replacementProbe = TVMazeMappingReplacementProbe()
        let probe = TVMazeResolverProbe(
            mappedShowIDs: [10: 70],
            tvdbShowIDs: [30: 90],
            shows: [90: replacementShow]
        )
        let resolver = makeTVMazeResolver(
            probe: probe,
            replacementProbe: replacementProbe
        )

        let result = try await resolver.resolve(
            entryType: .series,
            tmdbID: 10,
            externalIDs: TMDbSeriesExternalIDs(tvdbID: 30, imdbID: nil)
        )

        #expect(result == .resolved(replacementShow))
        #expect(
            await replacementProbe.replacements
                == [.init(tmdbSeriesID: 10, previousShowID: 70, newShowID: 90)]
        )
    }

    @Test func automaticIDMissRequestsUserAssistanceWithoutTitleSearch() async throws {
        let probe = TVMazeResolverProbe()
        let resolver = makeTVMazeResolver(probe: probe)

        let result = try await resolver.resolve(
            entryType: .series,
            tmdbID: 10,
            externalIDs: TMDbSeriesExternalIDs(tvdbID: nil, imdbID: nil)
        )

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
        #expect(await probe.savedMappings.isEmpty)

        let didConfirm = try await resolver.confirmTitleFallbackCandidate(
            expectedShow,
            entryType: .season(seasonNumber: 2, parentSeriesID: 10),
            tmdbID: 11
        )

        #expect(didConfirm)
        #expect(await probe.savedMappings == [TVMazeResolverProbe.Mapping(tmdbSeriesID: 10, showID: 90)])
    }

    @Test func moviesCannotConfirmTitleFallbackCandidates() async throws {
        let candidate = makeTVMazeResolverTestShow(id: 90)
        let probe = TVMazeResolverProbe()
        let resolver = makeTVMazeResolver(probe: probe)

        let didConfirm = try await resolver.confirmTitleFallbackCandidate(
            candidate,
            entryType: .movie,
            tmdbID: 10
        )

        #expect(!didConfirm)
        #expect(await probe.savedMappings.isEmpty)
    }
}

private actor TVMazeResolverProbe {
    struct Mapping: Equatable, Sendable {
        let tmdbSeriesID: Int
        let showID: Int
    }

    private var mappedShowIDs: [Int: Int]
    private let tvdbShowIDs: [Int: Int]
    private let imdbShowIDs: [String: Int]
    private let titleShowIDs: [String: Int]
    private let shows: [Int: TVMazeShow]

    private(set) var lookedUpTVDBIDs: [Int] = []
    private(set) var lookedUpIMDbIDs: [String] = []
    private(set) var searchedTitles: [String] = []
    private(set) var savedMappings: [Mapping] = []

    init(
        mappedShowIDs: [Int: Int] = [:],
        tvdbShowIDs: [Int: Int] = [:],
        imdbShowIDs: [String: Int] = [:],
        titleShowIDs: [String: Int] = [:],
        shows: [Int: TVMazeShow] = [:]
    ) {
        self.mappedShowIDs = mappedShowIDs
        self.tvdbShowIDs = tvdbShowIDs
        self.imdbShowIDs = imdbShowIDs
        self.titleShowIDs = titleShowIDs
        self.shows = shows
    }

    func mappedShowID(tmdbSeriesID: Int) -> Int? {
        mappedShowIDs[tmdbSeriesID]
    }

    func saveMappedShowID(
        tmdbSeriesID: Int,
        showID: Int
    ) -> TVMazeConfirmedMappingWriteResult {
        let previousShowID = mappedShowIDs[tmdbSeriesID]
        guard previousShowID != showID else { return .unchanged }

        mappedShowIDs[tmdbSeriesID] = showID
        savedMappings.append(Mapping(tmdbSeriesID: tmdbSeriesID, showID: showID))
        guard let previousShowID else { return .inserted }
        return .replaced(
            .init(
                tmdbSeriesID: tmdbSeriesID,
                previousShowID: previousShowID,
                newShowID: showID
            )
        )
    }

    func lookupTVDBShowID(tvdbID: Int) -> Int? {
        lookedUpTVDBIDs.append(tvdbID)
        return tvdbShowIDs[tvdbID]
    }

    func lookupIMDbShowID(imdbID: String) -> Int? {
        lookedUpIMDbIDs.append(imdbID)
        return imdbShowIDs[imdbID]
    }

    func searchShows(title: String) -> [TVMazeShow] {
        searchedTitles.append(title)
        guard
            let showID = titleShowIDs[title],
            let show = shows[showID]
        else {
            return []
        }
        return [show]
    }

    func show(id: Int) -> TVMazeShow? {
        shows[id]
    }
}

fileprivate actor TVMazeMappingReplacementProbe {
    private(set) var replacements: [TVMazeConfirmedMappingReplacement] = []

    func record(_ replacement: TVMazeConfirmedMappingReplacement) {
        replacements.append(replacement)
    }
}

fileprivate func makeTVMazeResolver(
    probe: TVMazeResolverProbe,
    replacementProbe: TVMazeMappingReplacementProbe? = nil
) -> TVMazeResolver {
    TVMazeResolver(
        loadMappedShowID: { tmdbSeriesID in
            await probe.mappedShowID(tmdbSeriesID: tmdbSeriesID)
        },
        saveMappedShowID: { tmdbSeriesID, showID in
            await probe.saveMappedShowID(tmdbSeriesID: tmdbSeriesID, showID: showID)
        },
        lookupTVDBShowID: { tvdbID in
            await probe.lookupTVDBShowID(tvdbID: tvdbID)
        },
        lookupIMDbShowID: { imdbID in
            await probe.lookupIMDbShowID(imdbID: imdbID)
        },
        searchShows: { title in
            await probe.searchShows(title: title)
        },
        fetchShow: { showID in
            await probe.show(id: showID)
        },
        onConfirmedMappingReplacement: { replacement in
            await replacementProbe?.record(replacement)
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
