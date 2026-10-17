//
//  LibraryBrowseSummaryMenu.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import SwiftUI

struct LibraryBrowseSummaryMenu: View {
    let scope: LibraryBrowseScope
    let scoringEnabled: Bool

    private var store: LibraryStore { scope.store }

    var body: some View {
        @Bindable var scope = scope

        Menu {
            Section("View") {
                Picker(
                    "Group By",
                    systemImage: "square.grid.2x2",
                    selection: groupStrategyBinding
                ) {
                    ForEach(availableGroupStrategies, id: \.self) { strategy in
                        Text(strategy.localizedStringResource).tag(strategy)
                    }
                }
                .pickerStyle(.menu)

                if store.categoriesEnabled {
                    // A category is a single-choice scope applied before the filters (AND),
                    // so it is a picker here instead of a filter toggle.
                    Picker(
                        "Category",
                        systemImage: "folder",
                        selection: categoryBinding
                    ) {
                        Text("All").tag(LibraryCategory.ID?.none)
                        ForEach(store.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("Sort") {
                Toggle(
                    "Reversed",
                    systemImage: "arrow.counterclockwise.circle",
                    isOn: $scope.sortReversed
                )
                Picker(
                    "Sort",
                    systemImage: "arrow.up.arrow.down",
                    selection: $scope.sortStrategy
                ) {
                    ForEach(LibraryStore.AnimeSortStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.localizedStringResource).tag(strategy)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Filter") {
                Toggle(
                    "All",
                    isOn: .init(
                        get: { scope.filters.isEmpty },
                        set: {
                            if $0 {
                                scope.filters.removeAll()
                            }
                        }
                    )
                )
                ForEach(LibraryStore.AnimeFilter.typeCases, id: \.self) { filter in
                    filterToggle(for: filter)
                }
                Menu("Watch Status") {
                    ForEach(LibraryStore.AnimeFilter.watchStatusCases, id: \.self) { filter in
                        filterToggle(for: filter)
                    }
                }
                filterToggle(for: .favorited)
            }
        } label: {
            #if os(macOS)
                // One toolbar glyph with the system menu indicator, filled while a filter
                // narrows the library, as in Mail.
                Label(
                    "Sort, group, and filter",
                    systemImage: activeFilters.isEmpty
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill"
                )
                .labelStyle(.iconOnly)
            #else
                LibraryToolbarSummaryCapsule(primary: filterSummaryResource)
            #endif
        }
        .keepsMenuPresentedAfterAction()
    }

    private var availableGroupStrategies: [LibraryStore.LibraryGroupStrategy] {
        if scoringEnabled {
            LibraryStore.LibraryGroupStrategy.allCases
        } else {
            LibraryStore.LibraryGroupStrategy.allCases.filter { $0 != .score }
        }
    }

    private var activeFilters: [LibraryStore.AnimeFilter] {
        LibraryStore.AnimeFilter.allCases.filter { scope.filters.contains($0) }
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

    @ViewBuilder
    private func filterToggle(for filter: LibraryStore.AnimeFilter) -> some View {
        Toggle(
            isOn: binding(for: filter),
            label: { Text(filter.name) }
        )
    }

    private func binding(for filter: LibraryStore.AnimeFilter) -> Binding<Bool> {
        .init(
            get: { scope.filters.contains(filter) },
            set: {
                if $0 {
                    scope.filters.insert(filter)
                } else {
                    scope.filters.remove(filter)
                }
            }
        )
    }

    private var categoryBinding: Binding<LibraryCategory.ID?> {
        Binding(
            get: { scope.activeCategoryID },
            set: { id in withAnimation(.snappy) { scope.activeCategoryID = id } }
        )
    }

    private var groupStrategyBinding: Binding<LibraryStore.LibraryGroupStrategy> {
        Binding(
            get: {
                if !scoringEnabled, scope.groupStrategy == .score {
                    return .none
                }
                return scope.groupStrategy
            },
            set: { scope.groupStrategy = $0 }
        )
    }
}
