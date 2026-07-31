//
//  EntryDetailViewModelTestSupport.swift
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

struct EntryDetailLoaderError: Error {}

struct EntryDetailPersistenceError: LocalizedError {
    var errorDescription: String? { "The detail could not be saved." }
}

actor FailingEntryDetailLoader {
    private(set) var requestCount = 0

    func load(entryType: AnimeType, tmdbID: Int, language: MyAnimeList.Language) async throws
        -> AnimeEntryDetailDTO
    {
        requestCount += 1
        throw EntryDetailLoaderError()
    }
}

actor RetryingPersistedEntryDetailLoader {
    private(set) var requestCount = 0

    func load(entryType: AnimeType, tmdbID: Int, language: MyAnimeList.Language) async throws
        -> AnimeEntryDetailDTO
    {
        requestCount += 1
        return AnimeEntryDetailDTO(
            language: language.rawValue,
            title: requestCount == 1 ? "Failed Detail" : "Retried Detail",
            overview: requestCount == 1 ? "Failed overview" : "Retried overview",
            logoImagePath: requestCount == 1 ? "/failed-logo.png" : "/retried-logo.png",
            characters: [
                AnimeEntryCharacterDTO(
                    id: requestCount + 1,
                    characterName: requestCount == 1 ? "Failed Character" : "Retried Character",
                    actorName: "Actor"
                )
            ]
        )
    }
}

actor CancellableEntryDetailLoader {
    private(set) var requestCount = 0

    func load(entryType: AnimeType, tmdbID: Int, language: MyAnimeList.Language) async throws
        -> AnimeEntryDetailDTO
    {
        requestCount += 1
        if requestCount == 1 {
            try? await Task.sleep(for: .seconds(30))
            return AnimeEntryDetailDTO(
                language: language.rawValue,
                title: "Cancelled Detail",
                logoImagePath: "/cancelled-logo.png"
            )
        }
        return AnimeEntryDetailDTO(
            language: language.rawValue,
            title: "Retried Detail",
            logoImagePath: "/retried-logo.png"
        )
    }
}

actor DelayedLanguageEntryDetailLoader {
    private(set) var requestCount = 0

    func load(entryType: AnimeType, tmdbID: Int, language: MyAnimeList.Language) async throws
        -> AnimeEntryDetailDTO
    {
        requestCount += 1
        if language == .japanese {
            try await Task.sleep(for: .milliseconds(200))
        }
        return AnimeEntryDetailDTO(
            language: language.rawValue,
            title: language == .japanese ? "Japanese Detail" : "English Detail",
            logoImagePath: "/\(language.rawValue)-logo.png"
        )
    }
}

actor ImmediateLanguageEntryDetailLoader {
    private(set) var requestCount = 0

    func load(entryType: AnimeType, tmdbID: Int, language: MyAnimeList.Language) async throws
        -> AnimeEntryDetailDTO
    {
        requestCount += 1
        return AnimeEntryDetailDTO(
            language: language.rawValue,
            title: language == .japanese ? "Japanese Detail" : "English Detail",
            logoImagePath: "/\(language.rawValue)-logo.png"
        )
    }
}

actor RetryingEpisodePreviewLoader {
    enum FailureMode {
        case error
        case cancellation
        case urlCancellation
    }

    private let failureMode: FailureMode
    private(set) var requestCount = 0

    init(failureMode: FailureMode) {
        self.failureMode = failureMode
    }

    func load(context: EpisodePreviewContext, episodeNumber: Int) async throws -> TVEpisode {
        requestCount += 1
        if requestCount == 1 {
            switch failureMode {
            case .error:
                throw EntryDetailLoaderError()
            case .cancellation:
                try await Task.sleep(for: .seconds(30))
            case .urlCancellation:
                throw URLError(.cancelled)
            }
        }
        return makeEpisodePreviewDetail(overview: "Retried preview", crew: [])
    }
}

actor DelayedLanguageEpisodePreviewLoader {
    private(set) var requestCount = 0

    func load(context: EpisodePreviewContext, episodeNumber: Int) async throws -> TVEpisode {
        requestCount += 1
        if context.language == .japanese {
            try await Task.sleep(for: .milliseconds(200))
        }
        let overview = context.language == .japanese ? "Japanese preview" : "English preview"
        return makeEpisodePreviewDetail(overview: overview, crew: [])
    }
}

actor RetryingSeasonEpisodeLoader {
    private(set) var requestCount = 0

    func load(seriesID: Int, seasonNumber: Int, language: MyAnimeList.Language) async throws
        -> [AnimeEntryEpisodeSummaryDTO]
    {
        requestCount += 1
        if requestCount == 1 {
            try await Task.sleep(for: .seconds(30))
        }
        return [
            AnimeEntryEpisodeSummaryDTO(
                id: 1,
                episodeNumber: 1,
                title: "Retried episode"
            )
        ]
    }
}

actor DelayedLanguageSeasonEpisodeLoader {
    private(set) var requestCount = 0

    func load(seriesID: Int, seasonNumber: Int, language: MyAnimeList.Language) async throws
        -> [AnimeEntryEpisodeSummaryDTO]
    {
        requestCount += 1
        if language == .japanese {
            try await Task.sleep(for: .milliseconds(200))
        }
        let title = language == .japanese ? "Japanese episode" : "English episode"
        return [AnimeEntryEpisodeSummaryDTO(id: 1, episodeNumber: 1, title: title)]
    }
}

actor URLCancelledSeasonEpisodeLoader {
    private(set) var requestCount = 0

    func load(seriesID: Int, seasonNumber: Int, language: MyAnimeList.Language) async throws
        -> [AnimeEntryEpisodeSummaryDTO]
    {
        requestCount += 1
        if requestCount == 1 {
            throw URLError(.cancelled)
        }
        return [AnimeEntryEpisodeSummaryDTO(id: 1, episodeNumber: 1, title: "Retried episode")]
    }
}

func makeEpisodePreviewContext(
    language: MyAnimeList.Language = .english
) -> EpisodePreviewContext {
    .init(seriesTMDbID: 1429, seasonNumber: 1, language: language)
}

func makeEpisodePreviewCard() -> EntryDetailEpisodeCard {
    .init(
        id: 65_480,
        episodeNumber: 1,
        title: "1. Preview",
        subtitle: "Apr 7, 2013",
        imageURL: nil
    )
}

func makeEpisodePreviewDetail(
    overview: String? = "Episode overview",
    crew: [CrewMember]
) -> TVEpisode {
    TVEpisode(
        id: 65_480,
        name: "Preview",
        episodeNumber: 1,
        seasonNumber: 1,
        overview: overview,
        crew: crew
    )
}

func makeCrewMember(id: Int, name: String, job: String) -> CrewMember {
    CrewMember(
        id: id,
        creditID: "\(job)-\(id)",
        name: name,
        job: job,
        department: "Directing"
    )
}
