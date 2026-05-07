//
//  SearchPage.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/3/30.
//

import Collections
import SwiftUI

enum SearchMode: String, CaseIterable, CustomLocalizedStringResourceConvertible {
    case tmdb
    case library

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .tmdb: return "TMDb"
        case .library: return "Library"
        }
    }
}

/// Main search page that coordinates between TMDb and Library search modes.
struct SearchPage: View {
    @AppStorage(.searchMode) private var mode: SearchMode = .tmdb
    @AppStorage(.searchPageQuery) private var query: String = ""
    @AppStorage(.searchTMDbLanguage) private var tmdbLanguage: Language = .english

    // Callbacks for TMDb search interactions
    private let onDuplicateTapped: (Int) -> Void
    private let checkDuplicate: (Int) -> Bool
    private let processTMDbSearchResults: (OrderedSet<SearchResult>) -> Void
    private let jumpToEntryInLibrary: (Int) -> Void

    // View models owned by SearchPage
    @State private var tmdbSearchService = TMDbSearchService()
    @State private var librarySearchService = LibrarySearchService()

    init(
        onDuplicateTapped: @escaping (_ tappedID: Int) -> Void,
        checkDuplicate: @escaping (_ tmdbID: Int) -> Bool,
        processTMDbSearchResults: @escaping (OrderedSet<SearchResult>) -> Void,
        jumpToEntryInLibrary: @escaping (Int) -> Void = { _ in }
    ) {
        self.onDuplicateTapped = onDuplicateTapped
        self.checkDuplicate = checkDuplicate
        self.processTMDbSearchResults = processTMDbSearchResults
        self.jumpToEntryInLibrary = jumpToEntryInLibrary
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scope", selection: $mode) {
                ForEach(SearchMode.allCases, id: \.self) { scope in
                    Text(scope.localizedStringResource)
                        .font(.title2)
                        .tag(scope)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .glassEffect(.regular)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch mode {
            case .tmdb:
                TMDbSearchContent(
                    language: $tmdbLanguage,
                    onRetry: performSearch,
                    onDuplicateTapped: onDuplicateTapped,
                    checkDuplicate: checkDuplicate
                )
                .environment(tmdbSearchService)
                .transition(.move(edge: .leading))

            case .library:
                LibrarySearchContent(onRetry: performSearch)
                    .environment(librarySearchService)
                    .transition(.move(edge: .trailing))
            }
        }
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: searchPrompt
        )
        .onSubmit(of: .search) {
            performSearch()
        }
        .onChange(of: mode) {
            performSearch()
        }
        .onChange(of: tmdbLanguage) {
            guard mode == .tmdb else { return }
            performSearch()
        }
        .onAppear {
            configureSearchServices()
            guard !query.isEmpty else { return }
            performSearch()
        }
        .toolbar {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }
        .animation(.default, value: mode)
    }

    private var searchPrompt: LocalizedStringKey {
        switch mode {
        case .tmdb:
            "Search TV animation or movies..."
        case .library:
            "Search in your library..."
        }
    }

    private func performSearch() {
        switch mode {
        case .tmdb:
            tmdbSearchService.updateResults(query: query, language: tmdbLanguage)
        case .library:
            librarySearchService.updateResults(query: query)
        }
    }

    private func configureSearchServices() {
        tmdbSearchService.processResults = processTMDbSearchResults
        librarySearchService.jumpToEntryInLibrary = jumpToEntryInLibrary
    }
}

#Preview {
    NavigationStack {
        SearchPage(
            onDuplicateTapped: { _ in },
            checkDuplicate: { _ in true },
            processTMDbSearchResults: { results in
                print(results)
            }
        )
    }
}
