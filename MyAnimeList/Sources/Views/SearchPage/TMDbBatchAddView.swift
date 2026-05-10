//
//  TMDbBatchAddView.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/10.
//

import SwiftUI

fileprivate enum TMDbBatchAddStep {
    case input
    case results
}

struct TMDbBatchAddView: View {
    @Environment(TMDbSearchService.self) private var tmdbSearchService: TMDbSearchService

    let language: Language
    let checkDuplicate: (Int) -> Bool
    let onDuplicateTapped: (Int) -> Void
    let onExit: () -> Void

    @State private var step: TMDbBatchAddStep = .input
    @State private var promptInput = ""
    @FocusState private var isPromptEditorFocused: Bool

    var body: some View {
        Group {
            switch step {
            case .input:
                inputStep
                    .transition(batchInputTransition)
            case .results:
                resultsStep
                    .transition(batchResultsTransition)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomAction
        }
        .animation(batchStepAnimation, value: step)
    }

    private var inputStep: some View {
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
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    exitBatchAdd()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel(Text(backTitleResource))
            }
        }
    }

    private var resultsStep: some View {
        Group {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 20)

            case .loading:
                resultsList
                    .disabled(true)
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(loadingMessageResource)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial)
                        .transition(.opacity)
                    }

            case .loaded:
                resultsList

            case .error(let error):
                ContentUnavailableView {
                    Label {
                        Text(errorTitleResource)
                    } icon: {
                        Image(systemName: "wifi.exclamationmark")
                    }
                } description: {
                    VStack(spacing: 8) {
                        Text(errorMessageResource)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 20)
            }
        }
        .navigationTitle(Text(batchResultsTitleResource))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    exitBatchAdd()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel(Text(backTitleResource))
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    returnToInputStep()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(Text(editTitleResource))
            }
        }
        .animation(batchResultsAnimation, value: tmdbSearchService.batchStatus)
        .animation(batchResultsAnimation, value: batchResultsAnimationKey)
    }

    @ViewBuilder
    private var bottomAction: some View {
        switch step {
        case .input:
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

        case .results:
            switch tmdbSearchService.batchStatus {
            case .loaded:
                if tmdbSearchService.batchRegisteredCount != 0 {
                    Button {
                        tmdbSearchService.submitBatch()
                        exitBatchAdd()
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
        withAnimation(batchStepAnimation) {
            step = .results
        }
        Task {
            await tmdbSearchService.performBatchSearch(input: promptInput, language: language)
        }
    }

    private func restartBatchSearch() {
        Task {
            await tmdbSearchService.performBatchSearch(input: promptInput, language: language)
        }
    }

    private func returnToInputStep() {
        withAnimation(batchStepAnimation) {
            step = .input
        }
    }

    private func exitBatchAdd() {
        isPromptEditorFocused = false
        onExit()
    }

    private var resultsList: some View {
        List {
            if !seriesCandidates.isEmpty {
                resultSection(title: seriesCandidatesTitleResource) {
                    ForEach(seriesCandidates) { promptResult in
                        if let series = promptResult.series {
                            candidateRow(prompt: promptResult.prompt) {
                                let isDuplicate = checkDuplicate(series.tmdbID)
                                SeriesResultItem(
                                    series: series,
                                    selectionState: tmdbSearchService.seriesSelectionState(
                                        for: series,
                                        context: .batch
                                    ),
                                    isSeriesSelected: tmdbSearchService.isBatchSelected(info: series),
                                    onSeriesSelectionChanged: { isSelected in
                                        tmdbSearchService.setSelection(
                                            isSelected,
                                            for: series,
                                            context: .batch
                                        )
                                    },
                                    onSelectionModeChanged: { mode in
                                        Task {
                                            await tmdbSearchService.setSeriesSelectionMode(
                                                mode,
                                                for: series,
                                                language: language,
                                                context: .batch
                                            )
                                        }
                                    },
                                    onSeasonSelectionChanged: { season, isSelected in
                                        tmdbSearchService.setSeasonSelection(
                                            isSelected,
                                            for: season,
                                            context: .batch
                                        )
                                    }
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
                            .transition(batchRowTransition)
                        }
                    }
                }
                .transition(batchSectionTransition)
            }

            if !movieCandidates.isEmpty {
                resultSection(title: movieCandidatesTitleResource) {
                    ForEach(movieCandidates) { promptResult in
                        if let movie = promptResult.movie {
                            candidateRow(prompt: promptResult.prompt) {
                                let isDuplicate = checkDuplicate(movie.tmdbID)
                                MovieResultItem(
                                    movie: movie,
                                    isSelected: tmdbSearchService.isBatchSelected(info: movie),
                                    onSelectionChanged: { isSelected in
                                        tmdbSearchService.setSelection(
                                            isSelected,
                                            for: movie,
                                            context: .batch
                                        )
                                    }
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
                            .transition(batchRowTransition)
                        }
                    }
                }
                .transition(batchSectionTransition)
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
                        .transition(batchRowTransition)
                    }
                }
                .transition(batchSectionTransition)
            }

            checkoutSection
        }
        .listStyle(.inset)
        .animation(batchResultsAnimation, value: batchResultsAnimationKey)
    }

    private var batchResultsAnimationKey: [Int] {
        tmdbSearchService.batchResults.map(\.id)
    }

    private var batchStepAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.88)
    }

    private var batchResultsAnimation: Animation {
        .spring(response: 0.38, dampingFraction: 0.86)
    }

    private var batchInputTransition: AnyTransition {
        .opacity
    }

    private var batchResultsTransition: AnyTransition {
        .opacity
    }

    private var batchSectionTransition: AnyTransition {
        .opacity
    }

    private var batchRowTransition: AnyTransition {
        .opacity
    }

    private func resultSection<Content: View>(
        title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            Text(title)
        }
        .textCase(nil)
    }

    private var checkoutSection: some View {
        Section {
            checkoutRow(title: tvSeriesTitleResource, count: tmdbSearchService.batchRegisteredSeriesCount)
            checkoutRow(title: seasonsTitleResource, count: tmdbSearchService.batchRegisteredSeasonCount)
            checkoutRow(title: moviesTitleResource, count: tmdbSearchService.batchRegisteredMovieCount)
        } header: {
            Text(checkoutTitleResource)
        }
        .textCase(nil)
    }

    private func checkoutRow(title: LocalizedStringResource, count: Int) -> some View {
        LabeledContent {
            Text(count.formatted())
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: count)
        } label: {
            Text(title)
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
        .padding(.vertical, 4)
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

    private var backTitleResource: LocalizedStringResource {
        "Back"
    }

    private var editTitleResource: LocalizedStringResource {
        "Edit"
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

    private var checkoutTitleResource: LocalizedStringResource {
        "Checkout"
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

    private var tvSeriesTitleResource: LocalizedStringResource {
        "TV Series"
    }

    private var moviesTitleResource: LocalizedStringResource {
        "Movies"
    }

    private var seasonsTitleResource: LocalizedStringResource {
        "Seasons"
    }
}
