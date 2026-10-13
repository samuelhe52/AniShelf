//
//  LibraryProfilePreferenceSections.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import DataProvider
import SwiftUI

/// Hub row; the language picker is short enough to stay inline instead of pushing a page.
struct LibraryProfileLanguageSettingsRow: View {
    @Binding var followsSystemLanguage: Bool
    @Binding var preferredLanguage: Language

    private var tint: Color { LibraryProfileSettingsPalette.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                LibraryProfileSettingIcon(systemImage: "globe", tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Anime Info Language")
                        .font(.subheadline.weight(.semibold))
                    Text("Follow System")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Toggle("Follow System", isOn: $followsSystemLanguage)
                    .labelsHidden()
                    .tint(tint)
                    .scaleEffect(0.78, anchor: .trailing)
                    .frame(width: 42, height: 26, alignment: .trailing)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)

            if !followsSystemLanguage {
                Picker("Anime Info Language", selection: $preferredLanguage) {
                    ForEach(Language.allCases, id: \.rawValue) { language in
                        Text(language.localizedStringResource).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 12)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    )
                )
            }
        }
    }
}

struct LibraryProfilePreferencesSection: View {
    @Binding var hideDroppedByDefault: Bool
    @Binding var defaultNewEntryWatchStatus: AnimeEntry.WatchStatus
    @Binding var defaultFilters: Set<LibraryStore.AnimeFilter>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(
                title: "Defaults",
                systemImage: "slider.horizontal.3",
                tint: LibraryProfileSettingsDestination.libraryTracking.tint
            )

            defaultWatchStatusRow
            defaultFiltersRow

            LibraryProfileSettingsToggleRow(
                title: "Hide Dropped Entries",
                subtitle: "Only show dropped entries after you explicitly enable the Dropped filter.",
                isOn: $hideDroppedByDefault
            )
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: LibraryProfileSettingsDestination.libraryTracking.tint)
    }

    private var defaultWatchStatusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("New Entries Start As")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            Menu {
                Picker("New Entries Start As", selection: $defaultNewEntryWatchStatus) {
                    ForEach(AnimeEntry.WatchStatus.allCases, id: \.self) { status in
                        Text(status.localizedStringResource).tag(status)
                    }
                }
            } label: {
                LibraryProfileSelectionCapsule(
                    title: defaultNewEntryWatchStatus.localizedStringResource,
                    tint: LibraryProfileSettingsDestination.libraryTracking.tint
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var defaultFiltersRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Default Filters")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            Menu {
                Toggle("All", isOn: allDefaultFiltersBinding)
                ForEach(LibraryStore.AnimeFilter.typeCases, id: \.self) { filter in
                    defaultFilterToggle(for: filter)
                }
                Menu("Watch Status") {
                    ForEach(LibraryStore.AnimeFilter.watchStatusCases, id: \.self) { filter in
                        defaultFilterToggle(for: filter)
                    }
                }
                defaultFilterToggle(for: .favorited)
            } label: {
                LibraryProfileSelectionCapsule(
                    title: defaultFiltersSummaryResource,
                    tint: LibraryProfileSettingsDestination.libraryTracking.tint
                )
            }
            .menuActionDismissBehavior(.disabled)
        }
        .padding(.vertical, 2)
    }

    private var orderedDefaultFilters: [LibraryStore.AnimeFilter] {
        LibraryStore.AnimeFilter.allCases.filter { defaultFilters.contains($0) }
    }

    private var defaultFiltersSummaryResource: LocalizedStringResource {
        switch orderedDefaultFilters.count {
        case 0:
            return "All"
        case 1:
            return defaultFilterSummaryResource(for: orderedDefaultFilters[0])
        default:
            return "\(orderedDefaultFilters.count) Filters"
        }
    }

    private var allDefaultFiltersBinding: Binding<Bool> {
        .init(
            get: { defaultFilters.isEmpty },
            set: {
                if $0 {
                    defaultFilters.removeAll()
                }
            }
        )
    }

    private func defaultFilterBinding(for filter: LibraryStore.AnimeFilter) -> Binding<Bool> {
        .init(
            get: { defaultFilters.contains(filter) },
            set: {
                if $0 {
                    defaultFilters.insert(filter)
                } else {
                    defaultFilters.remove(filter)
                }
            }
        )
    }

    private func defaultFilterSummaryResource(
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
    private func defaultFilterToggle(for filter: LibraryStore.AnimeFilter) -> some View {
        Toggle(
            isOn: defaultFilterBinding(for: filter),
            label: { Text(filter.name) }
        )
    }
}

/// Opt-in switch for library categories and the entry to the category manager.
struct LibraryProfileCategorySettingsRows: View {
    @Environment(LibraryStore.self) private var store
    @State private var showCategoryManager = false

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingsToggleRow(
                title: "Library Categories",
                subtitle: "Group anime into your own categories and switch between them in the library.",
                isOn: categoriesEnabledBinding
            )

            if store.categoriesEnabled {
                LibraryProfileSettingsToggleRow(
                    title: "Sticky Category Strip",
                    subtitle: "Keep category tabs below the navigation bar in List and Grid views.",
                    isOn: $store.categoryStripEnabled
                )
                .transition(.opacity)

                Button {
                    showCategoryManager = true
                } label: {
                    HStack(spacing: 8) {
                        Text("Manage Categories")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 12)
                        Text("\(store.categories.count)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .sheet(isPresented: $showCategoryManager) {
                    LibraryCategoryManagerSheet()
                        .presentationDetents([.medium, .large])
                }
            }
        }
    }

    private var categoriesEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.categoriesEnabled },
            set: { newValue in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    store.categoriesEnabled = newValue
                }
            }
        )
    }
}
