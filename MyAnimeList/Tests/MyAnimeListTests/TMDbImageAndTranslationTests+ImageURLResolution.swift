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
        #expect(entry.backdropImage?.url.absoluteString == "https://image.tmdb.org/t/p/w1280/backdrop.jpg")
        #expect(detail.logoImage?.url.absoluteString == "https://image.tmdb.org/t/p/w500/logo.png")

        let svgDetail = AnimeEntryDetail(
            language: "en-US",
            title: "SVG Logo Entry",
            logoImagePath: "/logo.svg"
        )
        #expect(svgDetail.logoImage?.url.absoluteString == "https://image.tmdb.org/t/p/original/logo.svg")
    }

    /// A variant whose rendition is missing from the size catalog resolves no URL at all, so
    /// every variant must resolve.
    @Test func everyImageVariantResolvesItsRendition() {
        for variant in TMDbImageVariant.allCases {
            #expect(TMDbImage(path: "/image.jpg", variant: variant) != nil, "\(variant)")
        }
        #expect(
            TMDbImage(path: "/image.jpg", variant: .still)?.url.absoluteString
                == "https://image.tmdb.org/t/p/w300/image.jpg"
        )
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
            detail.resolvedLogoImage?.url.absoluteString
                == "https://image.tmdb.org/t/p/w500/logos/title.png"
        )
        #expect(
            AnimeEntryDetailDTO(
                language: "en-US",
                title: "SVG Path Detail",
                logoImagePath: "/logos/title.svg"
            ).resolvedLogoImage?.url.absoluteString
                == "https://image.tmdb.org/t/p/original/logos/title.svg"
        )
        #expect(
            character.resolvedProfileImage?.url.absoluteString
                == "https://image.tmdb.org/t/p/w185/profiles/character.jpg"
        )
        #expect(
            staff.resolvedProfileImage?.url.absoluteString
                == "https://image.tmdb.org/t/p/w185/profiles/staff.jpg"
        )
        #expect(
            season.resolvedPosterImage?.url.absoluteString
                == "https://image.tmdb.org/t/p/w500/seasons/one.jpg"
        )
        #expect(
            episode.resolvedStillImage?.url.absoluteString
                == "https://image.tmdb.org/t/p/w300/episodes/still.jpg"
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
            ).resolvedProfileImage?.url == legacyURL
        )
        #expect(
            AnimeEntrySeasonSummaryDTO(
                id: 2,
                seasonNumber: 1,
                title: "Season",
                posterURL: legacyURL
            ).resolvedPosterImage?.url == legacyURL
        )
        #expect(
            AnimeEntryEpisodeSummaryDTO(
                id: 3,
                episodeNumber: 1,
                title: "Episode",
                imageURL: legacyURL
            ).resolvedStillImage?.url == legacyURL
        )
    }

    @Test func lazySeasonEpisodeMappingUsesResolvedStillImage() {
        let card = SeriesSeasonEpisodeGroupView.episodeCard(
            from: AnimeEntryEpisodeSummaryDTO(
                id: 1,
                episodeNumber: 1,
                title: "The Still Path",
                imagePath: "/episodes/still.jpg"
            )
        )

        #expect(card.stillImage?.url.absoluteString == "https://image.tmdb.org/t/p/w300/episodes/still.jpg")
    }

    @Test func displayPosterImageResolvesVariantRenditions() throws {
        let entry = AnimeEntry(
            name: "Display Poster Entry",
            type: .series,
            posterPath: "/poster.jpg",
            tmdbID: 12_801
        )
        let snapshot = LibraryEntrySnapshot(entry: entry)

        #expect(snapshot.posterMissing == false)
        #expect(
            snapshot.displayPosterImage(.posterThumbnail)?.url.absoluteString
                == "https://image.tmdb.org/t/p/w500/poster.jpg"
        )
        #expect(
            snapshot.displayPosterImage(.posterFull)?.url.absoluteString
                == "https://image.tmdb.org/t/p/original/poster.jpg"
        )
    }

    @Test func displayPosterImageHonorsCustomPosterSelection() throws {
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
            snapshot.displayPosterImage(.posterThumbnail)?.url.absoluteString
                == "https://image.tmdb.org/t/p/w500/custom.jpg"
        )
    }

    @Test func displayPosterImageReportsMissingWhenNoSelectedPoster() throws {
        let entry = AnimeEntry(
            name: "No Poster Entry",
            type: .series,
            tmdbID: 12_803
        )
        let snapshot = LibraryEntrySnapshot(entry: entry)

        #expect(snapshot.posterMissing == true)
        #expect(snapshot.displayPosterImage(.posterFull) == nil)
    }
}
