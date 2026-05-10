//
//  TMDbBatchAddSheet.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/10.
//

import SwiftUI

fileprivate enum TMDbBatchAddStage: Hashable {
    case results
}

struct TMDbBatchAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TMDbSearchService.self) private var tmdbSearchService: TMDbSearchService

    let language: Language
    let checkDuplicate: (Int) -> Bool
    let onDuplicateTapped: (Int) -> Void

    @State private var navigationPath: [TMDbBatchAddStage] = []
    @State private var promptInput = ""
    @FocusState private var isPromptEditorFocused: Bool

    var body: some View {
        NavigationStack(path: $navigationPath) {
            inputStage
                .navigationDestination(for: TMDbBatchAddStage.self) { _ in
                    resultsStage
                }
        }
    }

    private var inputStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TMDbSetupPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        Label {
                            Text(inputSectionTitleResource)
                        } icon: {
                            Image(systemName: "text.badge.plus")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                        Text(inputSectionMessageResource)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ZStack(alignment: .topLeading) {
                            if promptInput.isEmpty {
                                Text(inputPlaceholderResource)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }

                            TextEditor(text: $promptInput)
                                .focused($isPromptEditorFocused)
                                .scrollContentBackground(.hidden)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .frame(minHeight: 180)
                                .padding(12)
                                .background(
                                    Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(Text(batchAddTitleResource))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Text(doneTitleResource)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            TMDbProminentButton(
                title: searchButtonTitleResource,
                systemImage: "sparkle.magnifyingglass",
                iconPlacement: .leading,
                isEnabled: canStartBatchSearch,
                action: beginBatchSearch
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .onAppear {
            isPromptEditorFocused = true
        }
    }

    private var resultsStage: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                switch tmdbSearchService.batchStatus {
                case .idle:
                    ContentUnavailableView {
                        Label {
                            Text(batchReadyTitleResource)
                        } icon: {
                            Image(systemName: "text.badge.plus")
                        }
                    } description: {
                        Text(batchReadyMessageResource)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(loadingMessageResource)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)

                case .loaded:
                    if !seriesCandidates.isEmpty {
                        resultSection(title: seriesCandidatesTitleResource) {
                            ForEach(seriesCandidates) { promptResult in
                                if let series = promptResult.series {
                                    candidateRow(prompt: promptResult.prompt) {
                                        let isDuplicate = checkDuplicate(series.tmdbID)
                                        SeriesResultItem(
                                            series: series,
                                            initiallySelected: tmdbSearchService.isRegistered(info: series),
                                            registerSelection: tmdbSearchService.registerBatchSelection,
                                            unregisterSelection: tmdbSearchService.unregisterBatchSelection
                                        )
                                        .id(
                                            "series-\(tmdbSearchService.batchSearchGeneration)-\(promptResult.id)-\(series.tmdbID)"
                                        )
                                        .indicateAlreadyAdded(
                                            added: isDuplicate,
                                            message: alreadyAddedMessageResource
                                        )
                                        .onTapGesture {
                                            if isDuplicate { onDuplicateTapped(series.tmdbID) }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !movieCandidates.isEmpty {
                        resultSection(title: movieCandidatesTitleResource) {
                            ForEach(movieCandidates) { promptResult in
                                if let movie = promptResult.movie {
                                    candidateRow(prompt: promptResult.prompt) {
                                        let isDuplicate = checkDuplicate(movie.tmdbID)
                                        MovieResultItem(
                                            movie: movie,
                                            initiallySelected: tmdbSearchService.isRegistered(info: movie),
                                            registerSelection: tmdbSearchService.registerBatchSelection,
                                            unregisterSelection: tmdbSearchService.unregisterBatchSelection
                                        )
                                        .id(
                                            "movie-\(tmdbSearchService.batchSearchGeneration)-\(promptResult.id)-\(movie.tmdbID)"
                                        )
                                        .indicateAlreadyAdded(
                                            added: isDuplicate,
                                            message: alreadyAddedMessageResource
                                        )
                                        .onTapGesture {
                                            if isDuplicate { onDuplicateTapped(movie.tmdbID) }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !noResultPrompts.isEmpty {
                        resultSection(title: noResultsTitleResource) {
                            ForEach(noResultPrompts) { promptResult in
                                candidateRow(prompt: promptResult.prompt) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                        Text(noResultsMessageResource)
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                case .error(let error):
                    TMDbSetupPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "wifi.exclamationmark")
                                Text(errorTitleResource)
                            }
                            .font(.headline)
                            Text(errorMessageResource)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(Text(batchResultsTitleResource))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Text(doneTitleResource)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomActions
        }
    }

    @ViewBuilder
    private var bottomActions: some View {
        switch tmdbSearchService.batchStatus {
        case .loaded:
            if tmdbSearchService.batchRegisteredCount != 0 {
                Button {
                    tmdbSearchService.submit()
                    dismiss()
                } label: {
                    Text(addToLibraryTitleResource)
                }
                .buttonStyle(.glassProminent)
                .shadow(color: .blue, radius: 5)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }

        case .error:
            TMDbProminentButton(
                title: retryButtonTitleResource,
                systemImage: "arrow.clockwise",
                iconPlacement: .leading,
                action: restartBatchSearch
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)

        case .idle, .loading:
            EmptyView()
        }
    }

    private var seriesCandidates: [TMDbBatchPromptResult] {
        tmdbSearchService.batchResults.filter { $0.series != nil }
    }

    private var movieCandidates: [TMDbBatchPromptResult] {
        tmdbSearchService.batchResults.filter { $0.movie != nil }
    }

    private var noResultPrompts: [TMDbBatchPromptResult] {
        tmdbSearchService.batchResults.filter(\.hasNoResults)
    }

    private var canStartBatchSearch: Bool {
        !TMDbSearchService.batchPrompts(from: promptInput).isEmpty
            && tmdbSearchService.batchStatus != .loading
    }

    private func beginBatchSearch() {
        guard canStartBatchSearch else { return }
        isPromptEditorFocused = false
        navigationPath = [.results]
        Task {
            await tmdbSearchService.performBatchSearch(input: promptInput, language: language)
        }
    }

    private func restartBatchSearch() {
        Task {
            await tmdbSearchService.performBatchSearch(input: promptInput, language: language)
        }
    }

    private func resultSection<Content: View>(
        title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) -> some View {
        TMDbSetupPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)

                content()
            }
        }
    }

    private func candidateRow<Content: View>(
        prompt: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            .white.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var alreadyAddedMessageResource: LocalizedStringKey {
        "Already in library."
    }

    private var batchAddTitleResource: LocalizedStringResource {
        "Batch Add"
    }

    private var batchResultsTitleResource: LocalizedStringResource {
        "Batch Results"
    }

    private var doneTitleResource: LocalizedStringResource {
        "Done"
    }

    private var inputSectionTitleResource: LocalizedStringResource {
        "Batch Search"
    }

    private var inputSectionMessageResource: LocalizedStringResource {
        "Enter one title per line. Only the top TMDb TV series result and top movie result are shown, so precise titles work best."
    }

    private var inputPlaceholderResource: LocalizedStringResource {
        """
        Frieren
        A Silent Voice
        Kiki's Delivery Service
        """
    }

    private var searchButtonTitleResource: LocalizedStringResource {
        "Search Titles"
    }

    private var batchReadyTitleResource: LocalizedStringResource {
        "Ready for batch search"
    }

    private var batchReadyMessageResource: LocalizedStringResource {
        "Paste a list of titles, then search TMDb."
    }

    private var loadingMessageResource: LocalizedStringResource {
        "Searching TMDb..."
    }

    private var seriesCandidatesTitleResource: LocalizedStringResource {
        "TV Series Candidates"
    }

    private var movieCandidatesTitleResource: LocalizedStringResource {
        "Movie Candidates"
    }

    private var noResultsTitleResource: LocalizedStringResource {
        "No Results"
    }

    private var noResultsMessageResource: LocalizedStringResource {
        "No TMDb result found for this prompt."
    }

    private var addToLibraryTitleResource: LocalizedStringResource {
        "Add To Library..."
    }

    private var retryButtonTitleResource: LocalizedStringResource {
        "Retry Search"
    }

    private var errorTitleResource: LocalizedStringResource {
        "Batch search failed"
    }

    private var errorMessageResource: LocalizedStringResource {
        "Check your connection, then go back or retry the batch search."
    }
}
