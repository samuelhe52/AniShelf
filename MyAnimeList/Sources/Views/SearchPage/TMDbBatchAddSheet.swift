//
//  TMDbBatchAddSheet.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/10.
//

import SwiftUI

struct TMDbBatchAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TMDbSearchService.self) private var tmdbSearchService: TMDbSearchService

    let language: Language
    let checkDuplicate: (Int) -> Bool
    let onDuplicateTapped: (Int) -> Void

    @State private var promptInput = ""
    @State private var bottomActionAreaHeight: CGFloat = 0
    @FocusState private var isPromptEditorFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    inputCard
                    resultsContent
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, bottomActionAreaHeight + 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(batchAddTitleResource)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(doneTitleResource) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActions
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: BatchAddBottomActionHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
            }
            .onPreferenceChange(BatchAddBottomActionHeightPreferenceKey.self) { height in
                bottomActionAreaHeight = height
            }
        }
    }

    private var inputCard: some View {
        TMDbSetupPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label(inputSectionTitleResource, systemImage: "text.badge.plus")
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
                        .frame(minHeight: 132)
                        .padding(12)
                        .background(
                            Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                }

                Text(titleCountDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        switch tmdbSearchService.batchStatus {
        case .idle:
            ContentUnavailableView(
                idleStateTitleResource,
                systemImage: "text.badge.plus",
                description: Text(idleStateMessageResource)
            )
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
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(tmdbSearchService.batchResults) { promptResult in
                    BatchPromptResultCard(
                        promptResult: promptResult,
                        generation: tmdbSearchService.batchSearchGeneration,
                        checkDuplicate: checkDuplicate,
                        onDuplicateTapped: onDuplicateTapped
                    )
                }
            }

        case .error(let error):
            VStack(alignment: .leading, spacing: 10) {
                Label(errorTitleResource, systemImage: "wifi.exclamationmark")
                    .font(.headline)
                Text(errorMessageResource)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .popupGlassPanel(cornerRadius: 24)
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 12) {
            if tmdbSearchService.batchRegisteredCount != 0 {
                Button(addToLibraryTitleResource) {
                    tmdbSearchService.submit()
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .shadow(color: .blue, radius: 5)
            }

            TMDbProminentButton(
                title: searchButtonTitleResource,
                systemImage: searchButtonSystemImage,
                iconPlacement: .leading,
                isEnabled: canStartBatchSearch,
                action: startBatchSearch
            )
        }
    }

    private var canStartBatchSearch: Bool {
        !TMDbSearchService.batchPrompts(from: promptInput).isEmpty
            && tmdbSearchService.batchStatus != .loading
    }

    private var titleCountDescription: String {
        let promptCount = TMDbSearchService.batchPrompts(from: promptInput).count
        return promptCount == 1 ? "1 title ready" : "\(promptCount) titles ready"
    }

    private var searchButtonTitleResource: LocalizedStringResource {
        tmdbSearchService.batchStatus == .loading ? "Searching..." : "Search Titles"
    }

    private var searchButtonSystemImage: String? {
        tmdbSearchService.batchStatus == .loading ? nil : "sparkle.magnifyingglass"
    }

    private func startBatchSearch() {
        Task {
            await tmdbSearchService.performBatchSearch(input: promptInput, language: language)
            isPromptEditorFocused = false
        }
    }

    private var batchAddTitleResource: LocalizedStringResource {
        "Batch Add"
    }

    private var doneTitleResource: LocalizedStringResource {
        "Done"
    }

    private var inputSectionTitleResource: LocalizedStringResource {
        "Batch Search"
    }

    private var inputSectionMessageResource: LocalizedStringResource {
        "Enter one title per line. AniShelf keeps only the top TMDb series and movie match for each title."
    }

    private var inputPlaceholderResource: LocalizedStringResource {
        """
        Frieren
        A Silent Voice
        Kiki's Delivery Service
        """
    }

    private var addToLibraryTitleResource: LocalizedStringResource {
        "Add To Library..."
    }

    private var idleStateTitleResource: LocalizedStringResource {
        "Ready for batch search"
    }

    private var idleStateMessageResource: LocalizedStringResource {
        "Paste a list of titles, then run a TMDb batch search."
    }

    private var loadingMessageResource: LocalizedStringResource {
        "Searching TMDb..."
    }

    private var errorTitleResource: LocalizedStringResource {
        "Batch search failed"
    }

    private var errorMessageResource: LocalizedStringResource {
        "Check your connection, then try the batch again."
    }
}

private struct BatchAddBottomActionHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

fileprivate struct BatchPromptResultCard: View {
    @Environment(TMDbSearchService.self) private var tmdbSearchService: TMDbSearchService

    let promptResult: TMDbBatchPromptResult
    let generation: Int
    let checkDuplicate: (Int) -> Bool
    let onDuplicateTapped: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(promptLabelResource)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(promptResult.prompt)
                    .font(.headline.weight(.semibold))
                    .textSelection(.enabled)
            }

            if promptResult.hasNoResults {
                Label(noResultsMessageResource, systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if let series = promptResult.series {
                    resultGroup(title: topSeriesTitleResource) {
                        let isDuplicate = checkDuplicate(series.tmdbID)
                        SeriesResultItem(
                            series: series,
                            initiallySelected: tmdbSearchService.isRegistered(info: series)
                        )
                        .id("series-\(generation)-\(promptResult.prompt)-\(series.tmdbID)")
                        .indicateAlreadyAdded(
                            added: isDuplicate,
                            message: alreadyAddedMessageResource
                        )
                        .onTapGesture {
                            if isDuplicate { onDuplicateTapped(series.tmdbID) }
                        }
                    }
                }

                if let movie = promptResult.movie {
                    resultGroup(title: topMovieTitleResource) {
                        let isDuplicate = checkDuplicate(movie.tmdbID)
                        MovieResultItem(
                            movie: movie,
                            initiallySelected: tmdbSearchService.isRegistered(info: movie)
                        )
                        .id("movie-\(generation)-\(promptResult.prompt)-\(movie.tmdbID)")
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .popupGlassPanel(cornerRadius: 24)
    }

    private func resultGroup<Content: View>(
        title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    .white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
    }

    private var promptLabelResource: LocalizedStringResource {
        "Prompt"
    }

    private var topSeriesTitleResource: LocalizedStringResource {
        "Top Series Match"
    }

    private var topMovieTitleResource: LocalizedStringResource {
        "Top Movie Match"
    }

    private var noResultsMessageResource: LocalizedStringResource {
        "No TMDb results found for this title."
    }

    private var alreadyAddedMessageResource: LocalizedStringKey {
        "Already in library."
    }
}
