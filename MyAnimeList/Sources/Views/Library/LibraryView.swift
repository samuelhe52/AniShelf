//
//  LibraryView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2024/12/8.
//

import Collections
import DataProvider
import Kingfisher
import SwiftData
import SwiftUI

// MARK: - Environment Keys

extension EnvironmentValues {
    @Entry var toggleFavorite: (AnimeEntry) -> Void = { _ in }
    @Entry var libraryStore: LibraryStore? = nil
}

struct LibraryView: View {
    // MARK: - Stored Properties

    @Bindable var store: LibraryStore
    @State private var interaction = LibraryEntryInteractionState()
    @Environment(\.dataHandler) var dataHandler
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // UI state
    @State private var isSearching = false
    @State private var changeAPIKey = false
    @State private var showCacheAlert = false
    @State private var showClearAllAlert = false
    @State private var showRefreshInfoOnLanguageUpdateAlert = false
    @State private var showRefreshInfoAlert = false
    @State private var cacheSizeResult: Result<UInt, KingfisherError>? = nil
    @SceneStorage("LibraryView.showBackupManager") private var showBackupManager = false
    @State private var scrollState = ScrollState()
    @State private var newEntriesAddedToggle = false
    @State private var highlightedEntryID: Int?

    // Persistent UI preference
    @AppStorage(.libraryViewStyle) var libraryViewStyle: LibraryViewStyle = .gallery

    // Language tracking
    @State private var lastUsedlanguage: Language = .english

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                libraryView
            }
                .environment(\.toggleFavorite, toggleFavorite)
                .environment(\.libraryStore, store)
                .environment(interaction)
                .toolbar(content: { toolbarContent })
                .sensoryFeedback(.success, trigger: newEntriesAddedToggle)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var libraryView: some View {
        switch libraryViewStyle {
        case .gallery:
            LibraryGalleryView(
                store: store,
                scrolledID: $scrollState.scrolledID
            )
            .id(LibraryViewStyle.gallery)
            .scenePadding(.vertical)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .transition(libraryViewTransition)
        case .list:
            LibraryListView(
                store: store,
                scrolledID: $scrollState.scrolledID,
                highlightedEntryID: $highlightedEntryID
            )
            .id(LibraryViewStyle.list)
            .safeAreaPadding(.bottom, 20)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .transition(libraryViewTransition)
        case .grid:
            LibraryGridView(
                store: store,
                scrolledID: $scrollState.scrolledID,
                highlightedEntryID: $highlightedEntryID
            )
            .id(LibraryViewStyle.grid)
            .safeAreaPadding(.bottom, 20)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .transition(libraryViewTransition)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            LibraryNavigationTitleCapsule(count: store.libraryOnDisplay.count)
        }
        ToolbarItem(placement: .bottomBar) {
            Picker("View Style", selection: libraryViewStyleBinding) {
                ForEach(LibraryViewStyle.allCases, id: \.self) { style in
                    Label(style.nameKey, systemImage: style.systemImageName).tag(style)
                }
            }
            .labelsHidden()
        }
        ToolbarItemGroup(placement: .status) {
            sortOptions
            if let scrolledID = scrollState.scrolledID,
                let entry = store.libraryOnDisplay.entryWithTMDbID(scrolledID)
            {
                toggleFavoriteButton(for: entry)
                    .disabled(libraryViewStyle != .gallery)
            } else {
                Button {
                } label: {
                    Image(systemName: "heart")
                }
                .disabled(true)
            }
            filterOptions
        }
        ToolbarItem(placement: .bottomBar) {
            searchButton
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            settings
        }
    }

    private var sortOptions: some View {
        Menu {
            Toggle(
                "Reversed", systemImage: "arrow.counterclockwise.circle", isOn: $store.sortReversed)
            Picker("Sort", systemImage: "arrow.up.arrow.down", selection: $store.sortStrategy) {
                ForEach(LibraryStore.AnimeSortStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.localizedStringResource).tag(strategy)
                }
            }
            .pickerStyle(.menu)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 16))
                .padding(1.5)
        }
        .menuActionDismissBehavior(.disabled)
    }

    private var filterOptions: some View {
        Menu("Filter", systemImage: "line.3.horizontal.decrease") {
            ForEach(LibraryStore.AnimeFilter.allCases, id: \.self) { filter in
                Toggle(
                    isOn: .init(
                        get: {
                            store.filters.contains(filter)
                        },
                        set: {
                            if $0 {
                                store.filters.insert(filter)
                            } else {
                                store.filters.remove(filter)
                            }
                        }), label: { Text(filter.name) })
            }
            Divider()
            Toggle(
                "All",
                isOn: .init(
                    get: { store.filters.isEmpty },
                    set: {
                        if $0 { store.filters.removeAll() }
                    }))
        }
    }

    private var libraryViewStyleBinding: Binding<LibraryViewStyle> {
        Binding(
            get: { libraryViewStyle },
            set: { newValue in
                guard newValue != libraryViewStyle else { return }
                withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                    libraryViewStyle = newValue
                }
            }
        )
    }

    private var libraryViewTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: LibraryViewTransitionModifier(
                    opacity: 0,
                    scale: 0.975,
                    blurRadius: 8,
                    yOffset: 14
                ),
                identity: LibraryViewTransitionModifier(
                    opacity: 1,
                    scale: 1,
                    blurRadius: 0,
                    yOffset: 0
                )
            ),
            removal: .modifier(
                active: LibraryViewTransitionModifier(
                    opacity: 0,
                    scale: 1.018,
                    blurRadius: 5,
                    yOffset: -10
                ),
                identity: LibraryViewTransitionModifier(
                    opacity: 1,
                    scale: 1,
                    blurRadius: 0,
                    yOffset: 0
                )
            )
        )
    }

    // MARK: - Search

    private var searchButton: some View {
        Button("Search...", systemImage: "magnifyingglass") { isSearching = true }
            .sheet(isPresented: $isSearching) {
                NavigationStack {
                    SearchPage(
                        onDuplicateTapped: { tappedID in
                            isSearching = false
                            scrollState.scrolledID = tappedID
                            highlightedEntryID = tappedID
                        },
                        checkDuplicate: { store.libraryOnDisplay.map(\.tmdbID).contains($0) },
                        processTMDbSearchResults: processTMDbSearchResults,
                        jumpToEntryInLibrary: { tmdbID in
                            isSearching = false
                            scrollState.scrolledID = tmdbID
                            highlightedEntryID = tmdbID
                        }
                    )
                    .navigationTitle("Search")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
    }

    // MARK: - Settings Menu

    @ViewBuilder
    private var settings: some View {
        Menu {
            preferredAnimeInfoLanguagePicker
            Divider()
            backupManagement
            Divider()
            apiConfiguration
            checkCacheSizeButton
            refreshInfosButton
            Divider()
            deleteAllButton
        } label: {
            Image(systemName: "ellipsis.circle").padding(.vertical, 7.5)
        }
        .menuOrder(.priority)
        .alert("Delete all animes?", isPresented: $showClearAllAlert) {
            Button("Delete", role: .destructive) {
                store.clearLibrary()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Refresh Info Language?",
            isPresented: $showRefreshInfoOnLanguageUpdateAlert
        ) {
            Button("Refresh") {
                store.refreshInfos()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let message: LocalizedStringResource = """
                Changing the preferred language will not refresh existing infos.
                Refresh all anime infos now? This may take considerable time.
                """

            Text(message)
        }
        .alert(
            "Refresh all anime infos?",
            isPresented: $showRefreshInfoAlert
        ) {
            Button("Refresh") {
                store.refreshInfos()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This may take considerable time.")
        }
        .alert(
            "Metadata Cache Size", isPresented: $showCacheAlert, presenting: cacheSizeResult,
            actions: { result in
                switch result {
                case .success:
                    Button("Clear Cache") {
                        KingfisherManager.shared.cache.clearCache()
                    }
                    Button("Cancel", role: .cancel) {}
                case .failure:
                    Button("OK") {}
                }
            },
            message: { result in
                switch result {
                case .success(let size):
                    Text("Size: \(Double(size) / 1024 / 1024, specifier: "%.2f") MB")
                case .failure(let error):
                    Text(error.localizedDescription)
                }
            }
        )
        .sheet(isPresented: $changeAPIKey) {
            TMDbAPIConfigurator(isEditing: true)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showBackupManager) {
            BackupManagerView(backupManager: store.backupManager)
                .presentationDetents([.medium])
        }
    }

    private var backupManagement: some View {
        Button(
            "Backup & Restore", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        ) {
            showBackupManager = true
        }
    }

    // MARK: - Language

    private var isLanguageFollowingSystem: Binding<Bool> {
        Binding(
            get: {
                store.language == .current
            },
            set: {
                if $0 {
                    lastUsedlanguage = store.language
                    store.language = .current
                } else {
                    store.language = lastUsedlanguage
                }
            })
    }

    private var preferredAnimeInfoLanguagePicker: some View {
        Menu("Anime Info Language", systemImage: "globe") {
            Toggle("Follow System", isOn: isLanguageFollowingSystem)
            ForEach(Language.allCases, id: \.rawValue) { language in
                Toggle(
                    language.localizedStringResource,
                    isOn: Binding(
                        get: {
                            store.language == language
                        },
                        set: {
                            if $0 {
                                store.language = language
                            }
                        }
                    )
                )
                .disabled(isLanguageFollowingSystem.wrappedValue)
            }
        }
        .menuActionDismissBehavior(.disabled)
        .onChange(of: store.language) { old, new in
            if old != new {
                showRefreshInfoOnLanguageUpdateAlert = true
            }
        }
    }

    // MARK: - Settings Actions

    private var deleteAllButton: some View {
        Button("Delete All Animes", systemImage: "trash", role: .destructive) {
            showClearAllAlert = true
        }
    }

    private var checkCacheSizeButton: some View {
        Button("Check Metadata Cache Size", systemImage: "archivebox") {
            KingfisherManager.shared.cache.calculateDiskStorageSize { result in
                DispatchQueue.main.async {
                    cacheSizeResult = result
                    showCacheAlert = true
                }
            }
        }
    }

    private var apiConfiguration: some View {
        Button("Change API Key", systemImage: "person.badge.key") { changeAPIKey = true }
    }

    private var refreshInfosButton: some View {
        Button("Refresh Infos", systemImage: "arrow.clockwise") {
            showRefreshInfoAlert = true
        }
    }

    // MARK: - Entry Actions

    private func toggleFavoriteButton(for entry: AnimeEntry) -> some View {
        Button {
            toggleFavorite(entry)
        } label: {
            if entry.favorite {
                Image(systemName: "heart.fill")
            } else {
                Image(systemName: "heart")
            }
        }
    }

    private func toggleFavorite(_ entry: AnimeEntry) {
        dataHandler?.toggleFavorite(entry: entry)
    }

    private func jumpToEntryInLibrary(withID id: Int) {
        scrollState.scrolledID = id
        highlightedEntryID = id
    }

    private func processTMDbSearchResults(_ results: OrderedSet<SearchResult>) {
        isSearching = false
        Task {
            ToastCenter.global.loadingMessage = .message("Loading...")
            let success = await store.newEntryFromSearchResults(results)
            if success {
                ToastCenter.global.loadingMessage = nil
                withAnimation {
                    newEntriesAddedToggle.toggle()
                    if let id = results.first?.tmdbID {
                        scrollState.scrolledID = id
                        highlightedEntryID = id
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func customButtonStyle<S: Shape>(in shape: S)
        -> CustomBGBorderedButtonStyle<Material, S>
    {
        CustomBGBorderedButtonStyle(.ultraThinMaterial, backgroundIn: shape)
    }

    // MARK: - Types

    enum LibraryViewStyle: String, CaseIterable {
        case gallery
        case list
        case grid

        var nameKey: LocalizedStringKey {
            switch self {
            case .gallery: "Gallery"
            case .list: "List"
            case .grid: "Grid"
            }
        }

        var systemImageName: String {
            switch self {
            case .gallery: "photo.on.rectangle.angled"
            case .list: "list.bullet.rectangle.portrait"
            case .grid: "rectangle.grid.3x2.fill"
            }
        }
    }
}

private struct LibraryViewTransitionModifier: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let blurRadius: CGFloat
    let yOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(y: yOffset)
            .blur(radius: blurRadius)
            .opacity(opacity)
            .compositingGroup()
    }
}

#Preview {
    // dataProvider could be changed to .forPreview for memory-only storage.
    // Uncomment the task below to generate template entries.
    @Previewable let store = LibraryStore(dataProvider: .forPreview)
    LibraryView(store: store)
        .onAppear {
            DataProvider.forPreview.generateEntriesForPreview()
        }
        .environment(\.dataHandler, DataProvider.forPreview.dataHandler)
}
