//
//  EntryDetailViewModelTests+EpisodePreview.swift
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

extension EntryDetailViewModelTests {
    @Test @MainActor func testEpisodePreviewShowsTargetStaffRolesInConfiguredOrder() async {
        let viewModel = EpisodePreviewViewModel { _, _ in
            makeEpisodePreviewDetail(
                overview: "Episode overview",
                crew: [
                    makeCrewMember(id: 1, name: "Director Person", job: "Director"),
                    makeCrewMember(id: 2, name: "Writer Person", job: "Writer"),
                    makeCrewMember(id: 3, name: "Storyboard Person", job: "Storyboard Artist"),
                    makeCrewMember(id: 4, name: "Animation Person", job: "Animation Director"),
                    makeCrewMember(id: 5, name: "Supervising Person", job: "Supervising Animation Director")
                ]
            )
        }

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(viewModel.overviewText == "Episode overview")
        #expect(
            viewModel.staffRows.map(\.role) == [
                "Director",
                "Writer",
                "Storyboard Artist",
                "Animation Director",
                "Supervising Animation Director"
            ])
        #expect(
            viewModel.staffRows.map(\.names) == [
                "Director Person",
                "Writer Person",
                "Storyboard Person",
                "Animation Person",
                "Supervising Person"
            ])
    }

    @Test @MainActor func testEpisodePreviewOmitsMissingAndNoisyStaffRoles() async {
        let viewModel = EpisodePreviewViewModel { _, _ in
            makeEpisodePreviewDetail(
                crew: [
                    makeCrewMember(id: 1, name: "Director Person", job: "Director"),
                    makeCrewMember(id: 2, name: "Key Animator", job: "Key Animation"),
                    makeCrewMember(id: 3, name: "Compositor", job: "Compositing Artist")
                ]
            )
        }

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(viewModel.staffRows.map(\.role) == ["Director"])
        #expect(viewModel.staffRows.map(\.names) == ["Director Person"])
    }

    @Test @MainActor func testEpisodePreviewCollapsesMultipleCrewNamesPerRole() async {
        let viewModel = EpisodePreviewViewModel { _, _ in
            makeEpisodePreviewDetail(
                crew: [
                    makeCrewMember(id: 1, name: "Writer One", job: "Writer"),
                    makeCrewMember(id: 2, name: "Writer Two", job: "Writer"),
                    makeCrewMember(id: 3, name: "Writer Three", job: "Writer"),
                    makeCrewMember(id: 4, name: "Writer Four", job: "Writer")
                ]
            )
        }

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(
            viewModel.staffRows == [
                EpisodePreviewStaffRow(
                    role: "Writer",
                    names: "Writer One, Writer Two, Writer Three +1"
                )
            ])
    }

    @Test @MainActor func testEpisodePreviewUsesLocalizedRoleNames() async {
        let viewModel = EpisodePreviewViewModel { _, _ in
            makeEpisodePreviewDetail(
                crew: [makeCrewMember(id: 1, name: "Yasuko Kobayashi", job: "Writer")]
            )
        }

        await viewModel.load(
            card: makeEpisodePreviewCard(),
            context: .init(seriesTMDbID: 1429, seasonNumber: 1, language: .japanese)
        )

        #expect(
            viewModel.staffRows == [
                EpisodePreviewStaffRow(role: "脚本", names: "Yasuko Kobayashi")
            ])
    }

    @Test @MainActor func testEpisodePreviewFallsBackToOverviewOnlyWhenFetchFailsOrCrewIsEmpty() async {
        let emptyCrewViewModel = EpisodePreviewViewModel { _, _ in
            makeEpisodePreviewDetail(overview: nil, crew: [])
        }

        await emptyCrewViewModel.load(
            card: makeEpisodePreviewCard(),
            context: makeEpisodePreviewContext()
        )

        #expect(
            emptyCrewViewModel.overviewText == String(localized: EntryDetailL10n.noOverviewAvailable)
        )
        #expect(emptyCrewViewModel.staffRows.isEmpty)

        struct EpisodePreviewError: Error {}
        let failingViewModel = EpisodePreviewViewModel { _, _ in
            throw EpisodePreviewError()
        }

        await failingViewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(
            failingViewModel.overviewText == String(localized: EntryDetailL10n.noOverviewAvailable)
        )
        #expect(failingViewModel.staffRows.isEmpty)
    }

    @Test @MainActor func testEpisodePreviewRetriesSameRequestAfterFailure() async {
        let loader = RetryingEpisodePreviewLoader(failureMode: .error)
        let viewModel = EpisodePreviewViewModel { context, episodeNumber in
            try await loader.load(context: context, episodeNumber: episodeNumber)
        }

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())
        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(await loader.requestCount == 2)
        #expect(viewModel.overviewText == "Retried preview")
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testEpisodePreviewCancellationIsSilentAndRetryable() async {
        let loader = RetryingEpisodePreviewLoader(failureMode: .cancellation)
        let viewModel = EpisodePreviewViewModel { context, episodeNumber in
            try await loader.load(context: context, episodeNumber: episodeNumber)
        }

        let cancelledLoad = Task { @MainActor in
            await viewModel.load(
                card: makeEpisodePreviewCard(),
                context: makeEpisodePreviewContext()
            )
        }
        while await loader.requestCount == 0 {
            await Task.yield()
        }
        cancelledLoad.cancel()
        await cancelledLoad.value

        #expect(!viewModel.isLoading)

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(await loader.requestCount == 2)
        #expect(viewModel.overviewText == "Retried preview")
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testEpisodePreviewURLCancellationIsSilentAndRetryable() async {
        let loader = RetryingEpisodePreviewLoader(failureMode: .urlCancellation)
        let viewModel = EpisodePreviewViewModel { context, episodeNumber in
            try await loader.load(context: context, episodeNumber: episodeNumber)
        }

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(!viewModel.isLoading)

        await viewModel.load(card: makeEpisodePreviewCard(), context: makeEpisodePreviewContext())

        #expect(await loader.requestCount == 2)
        #expect(viewModel.overviewText == "Retried preview")
        #expect(!viewModel.isLoading)
    }

    @Test @MainActor func testOlderEpisodePreviewCannotOverwriteNewerLanguage() async {
        let loader = DelayedLanguageEpisodePreviewLoader()
        let viewModel = EpisodePreviewViewModel { context, episodeNumber in
            try await loader.load(context: context, episodeNumber: episodeNumber)
        }

        let olderLoad = Task { @MainActor in
            await viewModel.load(
                card: makeEpisodePreviewCard(),
                context: makeEpisodePreviewContext(language: .japanese)
            )
        }
        while await loader.requestCount == 0 {
            await Task.yield()
        }
        await viewModel.load(
            card: makeEpisodePreviewCard(),
            context: makeEpisodePreviewContext(language: .english)
        )
        await olderLoad.value

        #expect(viewModel.overviewText == "English preview")
        #expect(!viewModel.isLoading)
    }

}
