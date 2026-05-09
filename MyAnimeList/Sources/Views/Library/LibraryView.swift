//
//  LibraryView.swift
//  MyAnimeList
//
//  Created by Samuel He on 2024/12/8.
//

import Collections
import DataProvider
import SwiftData
import SwiftUI

// MARK: - Environment Keys

extension EnvironmentValues {
    @Entry var toggleFavorite: (AnimeEntry) -> Void = { _ in }
}

struct LibraryView: View {
    // MARK: - Stored Properties

    @Environment(LibraryStore.self) private var store
    @State private var interaction = LibraryEntryInteractionState()
    @Environment(\.dataHandler) var dataHandler
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // UI state
    @State private var isSearching = false
    @State private var showProfileSettings = false
    @State private var scrollState = ScrollState()
    @State private var newEntriesAddedToggle = false
    @State private var highlightedEntryID: Int?

    // Persistent UI preference
    @AppStorage(.libraryViewStyle) var libraryViewStyle: LibraryViewStyle = .gallery

    // MARK: - Body

    var body: some View {
        ZStack {
            libraryNavigation
                .opacity(showProfileSettings ? 0 : 1)
                .allowsHitTesting(!showProfileSettings)
                .accessibilityHidden(showProfileSettings)

            if showProfileSettings {
                LibraryProfileSettingsView {
                    closeProfileSettings()
                }
                .transition(profileSettingsTransition)
                .zIndex(1)
            }
        }
        .animation(profileSettingsAnimation, value: showProfileSettings)
    }

    private var libraryNavigation: some View {
        NavigationStack {
            ZStack {
                libraryView
            }
            .environment(\.toggleFavorite, toggleFavorite)
            .environment(interaction)
            .toolbar(content: { toolbarContent })
            .sensoryFeedback(.success, trigger: newEntriesAddedToggle)
            .allowsHitTesting(!showProfileSettings)
            .accessibilityHidden(showProfileSettings)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var libraryView: some View {
        switch libraryViewStyle {
        case .gallery:
            libraryViewPage(id: .gallery) {
                LibraryGalleryView(
                    scrolledID: $scrollState.scrolledID
                )
                .scenePadding(.vertical)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        case .list:
            libraryViewPage(id: .list) {
                LibraryListView(
                    scrolledID: $scrollState.scrolledID,
                    highlightedEntryID: $highlightedEntryID
                )
                .safeAreaPadding(.bottom, 20)
            }
        case .grid:
            libraryViewPage(id: .grid) {
                LibraryGridView(
                    scrolledID: $scrollState.scrolledID,
                    highlightedEntryID: $highlightedEntryID
                )
                .safeAreaPadding(.bottom, 20)
            }
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
        ToolbarItem(placement: .status) {
            libraryBrowseSummaryMenu
        }
        ToolbarItem(placement: .bottomBar) {
            searchButton
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            profileSettingsButton
        }
    }

    @ViewBuilder
    private var libraryBrowseSummaryMenu: some View {
        @Bindable var store = store

        Menu {
            Section("Group By") {
                Picker(
                    "Group By",
                    systemImage: "square.grid.2x2",
                    selection: $store.groupStrategy
                ) {
                    ForEach(LibraryStore.LibraryGroupStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.localizedStringResource).tag(strategy)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Sort") {
                Toggle(
                    "Reversed",
                    systemImage: "arrow.counterclockwise.circle",
                    isOn: $store.sortReversed
                )
                Picker(
                    "Sort",
                    systemImage: "arrow.up.arrow.down",
                    selection: $store.sortStrategy
                ) {
                    ForEach(LibraryStore.AnimeSortStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.localizedStringResource).tag(strategy)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Filter") {
                ForEach(LibraryStore.AnimeFilter.allCases, id: \.self) { filter in
                    Toggle(
                        isOn: binding(for: filter),
                        label: { Text(filter.name) }
                    )
                }
                Toggle(
                    "All",
                    isOn: .init(
                        get: { store.filters.isEmpty },
                        set: {
                            if $0 {
                                store.filters.removeAll()
                            }
                        }
                    )
                )
            }
        } label: {
            LibraryToolbarSummaryCapsule(
                primary: filterSummaryResource
            )
        }
        .menuActionDismissBehavior(.disabled)
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

    private var profileSettingsAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0)
    }

    private var profileSettingsTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: LibraryProfileSettingsBlendModifier(
                    opacity: 0,
                    blurRadius: 22
                ),
                identity: LibraryProfileSettingsBlendModifier(
                    opacity: 1,
                    blurRadius: 0
                )
            ),
            removal: .modifier(
                active: LibraryProfileSettingsBlendModifier(
                    opacity: 0,
                    blurRadius: 14
                ),
                identity: LibraryProfileSettingsBlendModifier(
                    opacity: 1,
                    blurRadius: 0
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

    // MARK: - Profile Settings

    private var profileSettingsButton: some View {
        Button {
            openProfileSettings()
        } label: {
            LibraryProfileLauncherBadge()
        }
        .accessibilityLabel(Text("Open Library Profile"))
    }

    private var activeFilters: [LibraryStore.AnimeFilter] {
        LibraryStore.AnimeFilter.allCases.filter { store.filters.contains($0) }
    }

    private var filterSummaryResource: LocalizedStringResource {
        switch activeFilters.count {
        case 0:
            return "All"
        case 1:
            return filterSummaryResource(for: activeFilters[0])
        default:
            return "\(activeFilters.count) Filters"
        }
    }

    private func filterSummaryResource(
        for filter: LibraryStore.AnimeFilter
    ) -> LocalizedStringResource {
        switch filter.id {
        case LibraryStore.AnimeFilter.favorited.id:
            return "Favorites"
        case LibraryStore.AnimeFilter.watched.id:
            return "Watched"
        case LibraryStore.AnimeFilter.planToWatch.id:
            return "Planned"
        case LibraryStore.AnimeFilter.watching.id:
            return "Watching"
        case LibraryStore.AnimeFilter.dropped.id:
            return "Dropped"
        default:
            return filter.name
        }
    }

    // MARK: - Entry Actions

    private func toggleFavorite(_ entry: AnimeEntry) {
        dataHandler?.toggleFavorite(entry: entry)
    }

    private func jumpToEntryInLibrary(withID id: Int) {
        scrollState.scrolledID = id
        highlightedEntryID = id
    }

    private func openProfileSettings() {
        withAnimation(profileSettingsAnimation) {
            showProfileSettings = true
        }
    }

    private func closeProfileSettings() {
        withAnimation(profileSettingsAnimation) {
            showProfileSettings = false
        }
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

    private func binding(for filter: LibraryStore.AnimeFilter) -> Binding<Bool> {
        .init(
            get: { store.filters.contains(filter) },
            set: {
                if $0 {
                    store.filters.insert(filter)
                } else {
                    store.filters.remove(filter)
                }
            }
        )
    }

    private func libraryViewPage<Content: View>(
        id: LibraryViewStyle,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .id(id)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .transition(libraryViewTransition)
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

fileprivate struct LibraryProfileLauncherBadge: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.monochrome)

            Image(systemName: "gearshape.fill")
                .font(.system(size: 6.5, weight: .bold))
                .background(.primary.opacity(0.30), in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.4), lineWidth: 0.7)
                }
                .offset(x: 4, y: 4)
        }
    }
}

fileprivate struct LibraryProfileSettingsBlendModifier: ViewModifier {
    let opacity: Double
    let blurRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blurRadius)
            .opacity(opacity)
            .compositingGroup()
    }
}

fileprivate struct LibraryViewTransitionModifier: ViewModifier {
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
    LibraryView()
        .onAppear {
            DataProvider.forPreview.generateEntriesForPreview()
        }
        .environment(store)
        .environment(\.dataHandler, DataProvider.forPreview.dataHandler)
}
