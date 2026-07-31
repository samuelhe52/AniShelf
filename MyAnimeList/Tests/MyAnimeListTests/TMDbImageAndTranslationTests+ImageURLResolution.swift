//
//  TMDbImageAndTranslationTests+ImageURLResolution.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import Foundation
import Kingfisher
import TMDb
import Testing

@testable import DataProvider
@testable import MyAnimeList

extension TMDbImageAndTranslationTests {
    @Test func persistedEntryImageURLsUseExpectedRenditions() throws {
        let detail = AnimeEntryDetail(
            language: "en-US",
            title: "Image URL Entry",
            logoImagePath: "/logo.png"
        )
        let entry = AnimeEntry(
            name: "Image URL Entry",
            type: .series,
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            tmdbID: 12_800,
            detail: detail
        )
        detail.entry = entry

        #expect(entry.posterURL?.absoluteString == "https://image.tmdb.org/t/p/original/poster.jpg")
        #expect(entry.backdropURL?.absoluteString == "https://image.tmdb.org/t/p/w1280/backdrop.jpg")
        #expect(entry.backdropURL?.absoluteString == "https://image.tmdb.org/t/p/w1280/backdrop.jpg")
        #expect(detail.heroImageURL?.absoluteString == "https://image.tmdb.org/t/p/w1280/backdrop.jpg")
        #expect(detail.logoImageURL?.absoluteString == "https://image.tmdb.org/t/p/w500/logo.png")

        let svgDetail = AnimeEntryDetail(
            language: "en-US",
            title: "SVG Logo Entry",
            logoImagePath: "/logo.svg"
        )
        #expect(svgDetail.logoImageURL?.absoluteString == "https://image.tmdb.org/t/p/original/logo.svg")
    }

    @Test func fetchDTOImageURLsResolveFromPathsBeforeLegacyURLs() throws {
        let legacyURL = try #require(URL(string: "https://example.com/legacy.jpg"))

        let detail = AnimeEntryDetailDTO(
            language: "en-US",
            title: "Path Detail",
            logoImageURL: legacyURL,
            logoImagePath: "/logos/title.png"
        )
        let character = AnimeEntryCharacterDTO(
            id: 1,
            characterName: "Character",
            actorName: "Actor",
            profileURL: legacyURL,
            profilePath: "/profiles/character.jpg"
        )
        let staff = AnimeEntryStaffDTO(
            id: 2,
            name: "Staff",
            role: "Director",
            profileURL: legacyURL,
            profilePath: "/profiles/staff.jpg"
        )
        let season = AnimeEntrySeasonSummaryDTO(
            id: 3,
            seasonNumber: 1,
            title: "Season 1",
            posterURL: legacyURL,
            posterPath: "/seasons/one.jpg"
        )
        let episode = AnimeEntryEpisodeSummaryDTO(
            id: 4,
            episodeNumber: 1,
            title: "Episode 1",
            imageURL: legacyURL,
            imagePath: "/episodes/still.jpg"
        )

        #expect(
            detail.resolvedLogoImageURL?.absoluteString
                == "https://image.tmdb.org/t/p/w500/logos/title.png"
        )
        #expect(
            AnimeEntryDetailDTO(
                language: "en-US",
                title: "SVG Path Detail",
                logoImagePath: "/logos/title.svg"
            ).resolvedLogoImageURL?.absoluteString
                == "https://image.tmdb.org/t/p/original/logos/title.svg"
        )
        #expect(
            character.resolvedProfileURL?.absoluteString
                == "https://image.tmdb.org/t/p/w185/profiles/character.jpg"
        )
        #expect(
            staff.resolvedProfileURL?.absoluteString
                == "https://image.tmdb.org/t/p/w185/profiles/staff.jpg"
        )
        #expect(
            season.resolvedPosterURL?.absoluteString
                == "https://image.tmdb.org/t/p/w342/seasons/one.jpg"
        )
        #expect(
            episode.resolvedImageURL?.absoluteString
                == "https://image.tmdb.org/t/p/original/episodes/still.jpg"
        )
    }

    @Test func fetchDTOImageURLsFallBackToLegacyURLsWhenPathIsMissing() throws {
        let legacyURL = try #require(URL(string: "https://example.com/legacy.jpg"))

        #expect(
            AnimeEntryCharacterDTO(
                id: 1,
                characterName: "Character",
                actorName: "Actor",
                profileURL: legacyURL
            ).resolvedProfileURL == legacyURL
        )
        #expect(
            AnimeEntrySeasonSummaryDTO(
                id: 2,
                seasonNumber: 1,
                title: "Season",
                posterURL: legacyURL
            ).resolvedPosterURL == legacyURL
        )
        #expect(
            AnimeEntryEpisodeSummaryDTO(
                id: 3,
                episodeNumber: 1,
                title: "Episode",
                imageURL: legacyURL
            ).resolvedImageURL == legacyURL
        )
    }

    @Test func lazySeasonEpisodeMappingUsesResolvedStillURL() {
        let card = SeriesSeasonEpisodeGroupView.episodeCard(
            from: AnimeEntryEpisodeSummaryDTO(
                id: 1,
                episodeNumber: 1,
                title: "The Still Path",
                imagePath: "/episodes/still.jpg"
            )
        )

        #expect(card.imageURL?.absoluteString == "https://image.tmdb.org/t/p/original/episodes/still.jpg")
    }

    @Test func displayPosterURLResolvesContextSizedRenditions() throws {
        let entry = AnimeEntry(
            name: "Display Poster Entry",
            type: .series,
            posterPath: "/poster.jpg",
            tmdbID: 12_801
        )
        let snapshot = LibraryEntrySnapshot(entry: entry)

        #expect(snapshot.posterMissing == false)
        #expect(
            snapshot.displayPosterURL(for: .list)?.absoluteString
                == "https://image.tmdb.org/t/p/w342/poster.jpg"
        )
        #expect(
            snapshot.displayPosterURL(for: .grid)?.absoluteString
                == "https://image.tmdb.org/t/p/w500/poster.jpg"
        )
        #expect(
            snapshot.displayPosterURL(for: .gallery)?.absoluteString
                == "https://image.tmdb.org/t/p/original/poster.jpg"
        )
    }

    @Test func displayPosterURLHonorsCustomPosterSelection() throws {
        let entry = AnimeEntry(
            name: "Custom Poster Entry",
            type: .series,
            posterPath: "/default.jpg",
            customPosterPath: "/custom.jpg",
            tmdbID: 12_802,
            usingCustomPoster: true
        )
        let snapshot = LibraryEntrySnapshot(entry: entry)

        #expect(snapshot.posterMissing == false)
        #expect(
            snapshot.displayPosterURL(for: .grid)?.absoluteString
                == "https://image.tmdb.org/t/p/w500/custom.jpg"
        )
    }

    @Test func displayPosterURLReportsMissingWhenNoSelectedPoster() throws {
        let entry = AnimeEntry(
            name: "No Poster Entry",
            type: .series,
            tmdbID: 12_803
        )
        let snapshot = LibraryEntrySnapshot(entry: entry)

        #expect(snapshot.posterMissing == true)
        #expect(snapshot.displayPosterURL(for: .gallery) == nil)
    }
}
