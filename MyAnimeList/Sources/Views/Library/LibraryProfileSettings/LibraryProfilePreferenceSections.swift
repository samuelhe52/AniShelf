//
//  LibraryProfilePreferenceSections.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/31.
//

import DataProvider
import SwiftUI

struct LibraryProfileLanguageSettingsSection: View {
    @Binding var followsSystemLanguage: Bool
    @Binding var preferredLanguage: Language

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(
                title: "Anime Info Language",
                subtitle: "Choose the language used for future metadata fetches.",
                systemImage: "globe",
                tint: .blue
            )

            HStack {
                Text("Follow System")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Toggle("Follow System", isOn: $followsSystemLanguage)
                    .labelsHidden()
                    .tint(.blue)
                    .scaleEffect(0.78, anchor: .trailing)
                    .frame(width: 42, height: 26, alignment: .trailing)
            }
            .padding(.vertical, 2)

            if !followsSystemLanguage {
                Picker("Anime Info Language", selection: $preferredLanguage) {
                    ForEach(Language.allCases, id: \.rawValue) { language in
                        Text(language.localizedStringResource).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 2)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    )
                )
            }
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .blue)
    }
}

struct LibraryProfilePreferencesSection: View {
    @AppStorage(.rememberShareSheetSettings) private var rememberShareSheetSettings = false
    @AppStorage(.broadcastScheduleEnabled) private var broadcastScheduleEnabled = true

    @Binding var hideDroppedByDefault: Bool
    @Binding var defaultNewEntryWatchStatus: AnimeEntry.WatchStatus
    @Binding var defaultFilters: Set<LibraryStore.AnimeFilter>
    @Binding var autoPrefetchImagesOnAddAndRestore: Bool
    @Binding var longTermGalleryPosterCachingEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(
                title: "General",
                systemImage: "slider.horizontal.3",
                tint: .mint
            )

            defaultWatchStatusRow
            defaultFiltersRow

            LibraryProfileSettingsToggleRow(
                title: "Hide Dropped Entries",
                subtitle: "Only show dropped entries after you explicitly enable the Dropped filter.",
                isOn: $hideDroppedByDefault
            )

            LibraryProfileSettingsToggleRow(
                title: "Auto Prefetch Images",
                subtitle: "Prefetch images when adding titles or restoring a backup.",
                isOn: $autoPrefetchImagesOnAddAndRestore
            )

            LibraryProfileSettingsToggleRow(
                title: "Cache Large Gallery Posters",
                subtitle:
                    "Store large Gallery posters longer. Off by default and may use more disk space.",
                isOn: $longTermGalleryPosterCachingEnabled
            )

            LibraryProfileSettingsToggleRow(
                title: "Remember Share Settings",
                subtitle:
                    "Remember language, corner style, image format, and export size preferences in the share sheet.",
                isOn: $rememberShareSheetSettings
            )

            LibraryProfileSettingsToggleRow(
                title: "Broadcast Airtimes",
                subtitle:
                    "Look up TV broadcast times when you open an eligible anime or season.",
                isOn: $broadcastScheduleEnabled
            )
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .mint)
        .onChange(of: rememberShareSheetSettings, handleRememberShareSheetSettingsChange)
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
                    tint: .mint
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
                    tint: .mint
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

    private func handleRememberShareSheetSettingsChange(old: Bool, new: Bool) {
        guard old != new, !new else { return }
        AnimeSharingPreferences().resetRememberedSettings()
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
