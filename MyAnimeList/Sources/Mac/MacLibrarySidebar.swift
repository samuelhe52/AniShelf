//
//  MacLibrarySidebar.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/15.
//

#if os(macOS)
    import DataProvider
    import SwiftUI

    /// One browse scope picked from the Mac sidebar.
    ///
    /// A scope is a projection of the window's browse state (filters and active category), so
    /// each window has its own sidebar selection.
    enum MacLibraryScope: Hashable {
        case all
        case filter(String)
        case category(LibraryCategory.ID)
    }

    extension LibraryBrowseScope {
        /// The sidebar row matching the current browse state, or `nil` for combinations the
        /// sidebar cannot express, such as several filters picked from the toolbar menu.
        var macLibraryScope: MacLibraryScope? {
            get {
                switch (activeCategoryID, filters.count) {
                case (nil, 0): return .all
                case (let id?, 0): return .category(id)
                case (nil, 1): return filters.first.map { .filter($0.id) }
                default: return nil
                }
            }
            set {
                guard let newValue else { return }
                switch newValue {
                case .all:
                    activeCategoryID = nil
                    filters = []
                case .filter(let id):
                    activeCategoryID = nil
                    filters = LibraryStore.AnimeFilter(preferenceID: id).map { [$0] } ?? []
                case .category(let id):
                    filters = []
                    activeCategoryID = id
                }
            }
        }
    }

    struct MacLibrarySidebar: View {
        @Environment(LibraryStore.self) private var store
        @Environment(LibraryBrowseScope.self) private var scope
        let openCategoryManager: () -> Void

        @State private var namePrompt: LibraryCategoryNamePrompt?
        @State private var deletingCategory: LibraryCategory?

        var body: some View {
            let counts = MacLibrarySidebarCounts(store: store)

            List(selection: scopeBinding) {
                Section {
                    row(.all, title: Text("All Anime"), systemImage: "books.vertical", count: counts.all)
                }

                Section("Status") {
                    filterRow(
                        .watching, systemImage: "play.circle", tint: AnimeEntry.WatchStatus.watching.libraryTintColor,
                        counts: counts)
                    filterRow(
                        .planToWatch, systemImage: "bookmark",
                        tint: AnimeEntry.WatchStatus.planToWatch.libraryTintColor, counts: counts)
                    filterRow(
                        .watched, systemImage: "checkmark.circle",
                        tint: AnimeEntry.WatchStatus.watched.libraryTintColor, counts: counts)
                    filterRow(
                        .dropped, systemImage: "xmark.circle", tint: AnimeEntry.WatchStatus.dropped.libraryTintColor,
                        counts: counts)
                }

                Section("Collections") {
                    filterRow(.favorited, systemImage: "heart", tint: .pink, counts: counts)
                    filterRow(.tvSeries, systemImage: "tv", tint: nil, counts: counts)
                    filterRow(.movies, systemImage: "film", tint: nil, counts: counts)
                }

                if store.categoriesEnabled {
                    Section {
                        ForEach(store.categories) { category in
                            row(
                                .category(category.id),
                                title: Text(verbatim: category.name),
                                systemImage: "folder",
                                count: counts.categories[category.id, default: 0]
                            )
                            .contextMenu { categoryMenu(for: category) }
                        }
                        .onMove { source, destination in
                            withAnimation(.snappy) {
                                store.moveCategories(fromOffsets: source, toOffset: destination)
                            }
                        }
                    } header: {
                        Text("Categories")
                    }
                }
            }
            .listStyle(.sidebar)
            // New Category sits at the foot of the sidebar, as Add List does in Reminders,
            // instead of a bare plus in the section header.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if store.categoriesEnabled {
                    Button {
                        namePrompt = .init(purpose: .create(memberCount: 0))
                    } label: {
                        Label("New Category…", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
            .libraryCategoryNamePrompt($namePrompt) { prompt, name in
                switch prompt.purpose {
                case .create:
                    if let category = store.createCategory(named: name) {
                        scope.macLibraryScope = .category(category.id)
                    }
                case .rename(let category):
                    _ = store.renameCategory(category.id, to: name)
                }
            }
            .libraryCategoryDeleteConfirmation($deletingCategory)
        }

        private var scopeBinding: Binding<MacLibraryScope?> {
            Binding(
                get: { scope.macLibraryScope },
                set: { newScope in
                    scope.macLibraryScope = newScope
                }
            )
        }

        private func filterRow(
            _ filter: LibraryStore.AnimeFilter,
            systemImage: String,
            tint: Color?,
            counts: MacLibrarySidebarCounts
        ) -> some View {
            row(
                .filter(filter.id),
                title: Text(filter.sidebarTitle),
                systemImage: systemImage,
                tint: tint,
                count: counts.filters[filter.id, default: 0]
            )
        }

        private func row(
            _ scope: MacLibraryScope,
            title: Text,
            systemImage: String,
            tint: Color? = nil,
            count: Int
        ) -> some View {
            Label {
                title
                    .lineLimit(1)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint ?? .accentColor)
            }
            .badge(count)
            .tag(scope)
        }

        @ViewBuilder
        private func categoryMenu(for category: LibraryCategory) -> some View {
            Button("Rename…", systemImage: "pencil") {
                namePrompt = .init(purpose: .rename(category))
            }
            Button("Edit Categories…", systemImage: "list.bullet", action: openCategoryManager)
            Divider()
            Button("Delete Category…", systemImage: "trash", role: .destructive) {
                deletingCategory = category
            }
        }
    }

    /// Entry counts for every sidebar row, computed in one pass over the library.
    fileprivate struct MacLibrarySidebarCounts {
        var all = 0
        var filters: [String: Int] = [:]
        var categories: [LibraryCategory.ID: Int] = [:]

        @MainActor
        init(store: LibraryStore) {
            let filterCases = LibraryStore.AnimeFilter.allCases
            for entry in store.library {
                // Mirrors browsing: hidden dropped entries only count under Dropped.
                let hiddenByDefault = store.hideDroppedByDefault && entry.watchStatus == .dropped
                for filter in filterCases where filter.evaluate(entry) {
                    if hiddenByDefault && filter != .dropped { continue }
                    filters[filter.id, default: 0] += 1
                }
                guard !hiddenByDefault else { continue }
                all += 1
                for categoryID in entry.categoryIDs {
                    categories[categoryID, default: 0] += 1
                }
            }
        }
    }

    extension LibraryStore.AnimeFilter {
        fileprivate var sidebarTitle: LocalizedStringResource {
            switch id {
            case Self.planToWatch.id: "Plan to Watch"
            default: name
            }
        }
    }
#endif
