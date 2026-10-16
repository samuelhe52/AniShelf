//
//  SearchPage.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/3/30.
//

import Collections
import DataProvider
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

fileprivate enum TMDbContentMode {
    case search
    case batchAdd
}

enum SearchSubmissionOrigin {
    case regular
    case batch
}

/// Main search page that coordinates between TMDb and Library search modes.
struct SearchPage: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    // Query and mode stay live per window so concurrent search pages don't mirror each other;
    // the stored values only restore the last search when the page opens.
    @AppStorage(.searchMode) private var persistedMode: SearchMode = .tmdb
    @AppStorage(.searchPageQuery) private var persistedQuery: String = ""
    @State private var mode: SearchMode
    @State private var query: String
    @AppStorage(.searchTMDbLanguage) private var tmdbLanguage: Language = .english
    @State private var tmdbContentMode: TMDbContentMode = .search
    @State private var isShowingBatchAddEntryAlert = false

    // Callbacks for TMDb search interactions
    private let onDuplicateTapped: (LibraryEntryIdentity) -> Void
    private let checkDuplicate: (LibraryEntryIdentity) -> Bool
    private let processTMDbSearchResults: (OrderedSet<SearchResult>, SearchSubmissionOrigin) -> Void
    private let jumpToEntryInLibrary: (LibraryEntryIdentity) -> Void

    // View models owned by SearchPage
    @State private var tmdbSearchService = TMDbSearchService()
    @State private var librarySearchService = LibrarySearchService()

    init(
        onDuplicateTapped: @escaping (_ tappedID: LibraryEntryIdentity) -> Void,
        checkDuplicate: @escaping (_ identity: LibraryEntryIdentity) -> Bool,
        processTMDbSearchResults: @escaping (OrderedSet<SearchResult>, SearchSubmissionOrigin) -> Void,
        jumpToEntryInLibrary: @escaping (LibraryEntryIdentity) -> Void = { _ in },
        initialMode: SearchMode? = nil
    ) {
        self.onDuplicateTapped = onDuplicateTapped
        self.checkDuplicate = checkDuplicate
        self.processTMDbSearchResults = processTMDbSearchResults
        self.jumpToEntryInLibrary = jumpToEntryInLibrary
        let defaults = UserDefaults.standard
        #if os(macOS)
            // The Mac page only adds from TMDb; the toolbar's Find filters the library itself.
            _mode = State(initialValue: .tmdb)
        #else
            _mode = State(
                initialValue: initialMode
                    ?? defaults.string(forKey: .searchMode).flatMap(SearchMode.init(rawValue:))
                    ?? .tmdb
            )
        #endif
        _query = State(initialValue: defaults.string(forKey: .searchPageQuery) ?? "")
    }

    var body: some View {
        ZStack {
            if isShowingTMDbBatchAdd {
                TMDbBatchAddView(
                    language: tmdbLanguage,
                    checkDuplicate: checkDuplicate,
                    onDuplicateTapped: onDuplicateTapped,
                    onExit: { leaveTMDbBatchAdd() }
                )
                .environment(tmdbSearchService)
                .transition(.opacity)
            } else {
                regularSearchContent
                    .transition(.opacity)
            }
        }
        .onChange(of: mode) {
            if mode != .tmdb {
                leaveTMDbBatchAdd(animated: false)
            }
            performSearch()
        }
        .onChange(of: tmdbLanguage) {
            guard mode == .tmdb, !isShowingTMDbBatchAdd else { return }
            performSearch()
        }
        .onAppear {
            configureSearchServices()
            guard !query.isEmpty else { return }
            performSearch()
        }
        .onDisappear(perform: persistSearchState)
        .onChange(of: scenePhase) { _, newPhase in
            // onDisappear does not run if the app is terminated while the page is open.
            if newPhase == .background {
                persistSearchState()
            }
        }
        .alert(batchAddEntryTitleResource, isPresented: $isShowingBatchAddEntryAlert) {
            Button {
                enterTMDbBatchAdd()
            } label: {
                Text(continueTitleResource)
            }
            Button(role: .cancel) {
            } label: {
                Text(cancelTitleResource)
            }
        } message: {
            Text(batchAddEntryMessageResource)
        }
        .animation(.default, value: mode)
        .animation(.default, value: tmdbContentMode)
        .frame(maxWidth: 1_000)
        .frame(maxWidth: .infinity)
        .presentationSizing(.page)
        .macSheetFrame(width: 760, height: 680)
    }

    #if os(macOS)
        @FocusState private var isQueryFocused: Bool

        /// The Mac add page: a wide search field with the language beside it, above the results.
        private var regularSearchContent: some View {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField(text: $query, prompt: Text(searchPrompt)) {
                        Text("Search")
                    }
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($isQueryFocused)
                    .onSubmit(performSearch)

                    Picker("Language", selection: $tmdbLanguage) {
                        ForEach(Language.allCases, id: \.rawValue) { language in
                            Text(language.localizedStringResource).tag(language)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .macHelp(Text("Language"))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                TMDbSearchContent(
                    language: $tmdbLanguage,
                    onRetry: performSearch,
                    onDuplicateTapped: onDuplicateTapped,
                    checkDuplicate: checkDuplicate
                )
                .environment(tmdbSearchService)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { isQueryFocused = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: dismiss.callAsFunction) { SheetCloseLabel() }
                        .keyboardShortcut(.cancelAction)
                }
                // The leading slot keeps Batch Add secondary; the confirm slot made it look like
                // the sheet's default action.
                ToolbarItem(placement: .destructiveAction) {
                    Button {
                        isShowingBatchAddEntryAlert = true
                    } label: {
                        Label(batchAddButtonTitleResource, systemImage: "text.badge.plus")
                    }
                }
            }
        }
    #else
    private var regularSearchContent: some View {
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
            placement: .platformDrawerAutomatic,
            prompt: searchPrompt
        )
        .onSubmit(of: .search) {
            performSearch()
        }
        .toolbar {
            DefaultToolbarItem(kind: .search, placement: .platformBottomBar)
            if mode == .tmdb {
                ToolbarItem(placement: .sheetTrailing) {
                    Button {
                        isShowingBatchAddEntryAlert = true
                    } label: {
                        Label(batchAddButtonTitleResource, systemImage: "text.badge.plus")
                    }
                }
            }
        }
    }
    #endif

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

    private func persistSearchState() {
        persistedMode = mode
        persistedQuery = query
    }

    private func configureSearchServices() {
        tmdbSearchService.processResults = processTMDbSearchResults
        tmdbSearchService.checkDuplicate = checkDuplicate
        librarySearchService.entriesProvider = { store.library }
        librarySearchService.jumpToEntryInLibrary = jumpToEntryInLibrary
    }

    private var isShowingTMDbBatchAdd: Bool {
        mode == .tmdb && tmdbContentMode == .batchAdd
    }

    private func enterTMDbBatchAdd() {
        tmdbSearchService.clearBatchSession()
        withAnimation {
            tmdbContentMode = .batchAdd
        }
    }

    private func leaveTMDbBatchAdd(animated: Bool = true) {
        let exit = {
            tmdbContentMode = .search
            tmdbSearchService.clearBatchSession()
        }
        if animated {
            withAnimation {
                exit()
            }
        } else {
            exit()
        }
    }

    private var batchAddButtonTitleResource: LocalizedStringResource {
        "Batch Add"
    }

    private var batchAddEntryTitleResource: LocalizedStringResource {
        "Enter Batch Add?"
    }

    private var batchAddEntryMessageResource: LocalizedStringResource {
        "Batch add replaces the current TMDb search view until you go back."
    }

    private var continueTitleResource: LocalizedStringResource {
        "Continue"
    }

    private var cancelTitleResource: LocalizedStringResource {
        "Cancel"
    }
}

#Preview {
    NavigationStack {
        SearchPage(
            onDuplicateTapped: { _ in },
            checkDuplicate: { _ in true },
            processTMDbSearchResults: { results, _ in
                print(results)
            }
        )
    }
    .environment(LibraryStore(dataProvider: DataProvider(inMemory: true)))
}
