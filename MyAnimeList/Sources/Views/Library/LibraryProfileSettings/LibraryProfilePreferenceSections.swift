//
//  LibraryProfilePreferenceSections.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import DataProvider
import SwiftUI

/// The Language page's cards; onboarding reuses them for its language step.
struct LibraryProfileLanguageSettingsSections: View {
    @Binding var followsSystemLanguage: Bool
    @Binding var preferredLanguage: Language
    @Binding var posterLanguage: PosterLanguagePreference

    private var tint: Color { LibraryProfileSettingsPalette.language }

    var body: some View {
        // The pushed page and onboarding don't inherit the toggle binding's transaction, so the
        // stack animates its own layout: the picker slides in and the poster card moves with it.
        LibraryProfileSettingsRows(alignment: .center, spacing: 16) {
            LibraryProfileSettingsSection("Anime Info Language", systemImage: "globe", tint: tint) {
                #if os(macOS)
                    Toggle("Follow System", isOn: $followsSystemLanguage)
                        .toggleStyle(.switch)
                #else
                    HStack {
                        Text("Follow System")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 12)
                        Toggle("Follow System", isOn: $followsSystemLanguage)
                            .labelsHidden()
                            .tint(tint)
                            .scaleEffect(0.78, anchor: .trailing)
                            .frame(width: 42, height: 26, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                #endif

                if !followsSystemLanguage {
                    Picker("Anime Info Language", selection: $preferredLanguage) {
                        ForEach(Language.allCases, id: \.rawValue) { language in
                            Text(language.localizedStringResource).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            LibraryProfileSettingsSection("Default Poster", systemImage: "photo", tint: tint) {
                ForEach(PosterLanguagePreference.allCases, id: \.self) { preference in
                    if preference != PosterLanguagePreference.allCases.first {
                        LibraryProfileActionDivider(leadingInset: 0)
                    }
                    option(
                        preference.localizedStringResource, subtitle: preference.fallbackDescription,
                        isSelected: posterLanguage == preference
                    ) {
                        posterLanguage = preference
                    }
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: followsSystemLanguage)
    }

    private func option(
        _ title: LocalizedStringResource,
        subtitle: LocalizedStringResource? = nil,
        isSelected: Bool,
        select: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2), select)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .settingsRowTitleFont()
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension PosterLanguagePreference {
    fileprivate var fallbackDescription: LocalizedStringResource {
        switch self {
        case .originalLanguage: "Falls back to the Anime Info Language."
        case .animeInfoLanguage: "Falls back to the original language."
        }
    }
}

struct LibraryProfilePreferencesSection: View {
    @Binding var hideDroppedByDefault: Bool
    @Binding var defaultNewEntryWatchStatus: AnimeEntry.WatchStatus
    @Binding var defaultFilters: Set<LibraryStore.AnimeFilter>

    var body: some View {
        LibraryProfileSettingsGroup(
            "Defaults",
            systemImage: "slider.horizontal.3",
            tint: LibraryProfileSettingsDestination.libraryTracking.tint,
            spacing: 10
        ) {

            defaultWatchStatusRow
            defaultFiltersRow

            LibraryProfileSettingsToggleRow(
                title: "Hide Dropped Entries",
                subtitle: "Only show dropped entries after you explicitly enable the Dropped filter.",
                isOn: $hideDroppedByDefault
            )
        }
    }

    @ViewBuilder
    private var defaultWatchStatusRow: some View {
        #if os(macOS)
            Picker("New Entries Start As", selection: $defaultNewEntryWatchStatus) {
                ForEach(AnimeEntry.WatchStatus.allCases, id: \.self) { status in
                    Text(status.localizedStringResource).tag(status)
                }
            }
            .pickerStyle(.menu)
        #else
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("New Entries Start As")
                    .settingsRowTitleFont()
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
                .customLabeledMenu()
            }
            .padding(.vertical, 2)
        #endif
    }

    private var defaultFiltersRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Default Filters")
                .settingsRowTitleFont()
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
                #if os(macOS)
                    Text(defaultFiltersSummaryResource)
                #else
                    LibraryProfileSelectionCapsule(
                        title: defaultFiltersSummaryResource,
                        tint: LibraryProfileSettingsDestination.libraryTracking.tint
                    )
                #endif
            }
            #if !os(macOS)
                .customLabeledMenu()
            #endif
            .keepsMenuPresentedAfterAction()
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

        LibraryProfileSettingsRows {
            LibraryProfileSettingsToggleRow(
                title: "Library Categories",
                subtitle: "Group anime into your own categories and switch between them in the library.",
                isOn: categoriesEnabledBinding
            )

            if store.categoriesEnabled {
                // The Mac lists categories in the sidebar instead of a strip.
                #if !os(macOS)
                    LibraryProfileSettingsToggleRow(
                        title: "Sticky Category Strip",
                        subtitle: "Keep category tabs below the navigation bar in List and Grid views.",
                        isOn: $store.categoryStripEnabled
                    )
                    .transition(.opacity)
                #endif

                #if os(macOS)
                    // A push button opens the manager; a chevron row reads as navigation.
                    LabeledContent {
                        HStack(spacing: 10) {
                            Text("\(store.categories.count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button("Manage Categories") { showCategoryManager = true }
                        }
                    } label: {
                        Text("Categories")
                    }
                    .sheet(isPresented: $showCategoryManager) {
                        LibraryCategoryManagerSheet()
                    }
                #else
                    Button {
                        showCategoryManager = true
                    } label: {
                        HStack(spacing: 8) {
                            Text("Manage Categories")
                                .settingsRowTitleFont()
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
                #endif
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
