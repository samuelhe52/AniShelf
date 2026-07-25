//
//  LibraryBrowseSummaryMenu.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import SwiftUI

struct LibraryBrowseSummaryMenu: View {
    let store: LibraryStore
    let scoringEnabled: Bool

    var body: some View {
        @Bindable var store = store

        Menu {
            Section("Group By") {
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
            LibraryToolbarSummaryCapsule(primary: filterSummaryResource)
        }
        .menuActionDismissBehavior(.disabled)
    }

    private var availableGroupStrategies: [LibraryStore.LibraryGroupStrategy] {
        if scoringEnabled {
            LibraryStore.LibraryGroupStrategy.allCases
        } else {
            LibraryStore.LibraryGroupStrategy.allCases.filter { $0 != .score }
        }
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

    @ViewBuilder
    private func filterToggle(for filter: LibraryStore.AnimeFilter) -> some View {
        Toggle(
            isOn: binding(for: filter),
            label: { Text(filter.name) }
        )
    }

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

    private var groupStrategyBinding: Binding<LibraryStore.LibraryGroupStrategy> {
        Binding(
            get: {
                if !scoringEnabled, store.groupStrategy == .score {
                    return .none
                }
                return store.groupStrategy
            },
            set: { store.groupStrategy = $0 }
        )
    }
}
