//
//  LibraryProfileSettingsSections.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on 2026/5/3.
//

import DataProvider
import SwiftUI

struct LibraryProfileHeroCard: View {
    let stats: LibraryProfileStats
    let animeTitleResource: LocalizedStringResource

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack(alignment: .bottomTrailing) {
                Image(.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)

                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.orange.gradient, in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.7), lineWidth: 1)
                    }
                    .offset(x: 6, y: 6)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(stats.totalCount)")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(animeTitleResource)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(20)
        .popupGlassPanel(cornerRadius: 30, tint: .white.opacity(0.045))
    }
}

struct LibraryProfilePrimaryStatsGrid: View {
    let stats: LibraryProfileStats

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            LibraryProfileMetricCard(
                title: "Watched",
                value: stats.watchedCount,
                systemImage: "checkmark.circle.fill",
                tint: AnimeEntry.WatchStatus.watched.libraryTintColor
            )
            LibraryProfileMetricCard(
                title: "Watching",
                value: stats.watchingCount,
                systemImage: "play.circle.fill",
                tint: AnimeEntry.WatchStatus.watching.libraryTintColor
            )
            LibraryProfileMetricCard(
                title: "Favorites",
                value: stats.favoriteCount,
                systemImage: "heart.fill",
                tint: .pink
            )
            LibraryProfileMetricCard(
                title: "Planned",
                value: stats.planToWatchCount,
                systemImage: "bookmark.fill",
                tint: AnimeEntry.WatchStatus.planToWatch.libraryTintColor
            )
        }
    }
}

struct LibraryProfileLibraryDetailsCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let stats: LibraryProfileStats
    let runtimeDescription: String

    var body: some View {
        PopupSectionCard(
            "Library Details",
            systemImage: "sparkles.rectangle.stack",
            spacing: 14,
            panelTint: sectionCardTint
        ) {
            VStack(spacing: 10) {
                LibraryProfileDetailRow(title: "Movies", value: "\(stats.movieCount)", systemImage: "film")
                LibraryProfileDetailRow(title: "Series", value: "\(stats.seriesCount)", systemImage: "tv")
                LibraryProfileDetailRow(
                    title: "Seasons",
                    value: "\(stats.seasonCount)",
                    systemImage: "square.stack.3d.up"
                )
                LibraryProfileDetailRow(
                    title: "With Notes",
                    value: "\(stats.entriesWithNotesCount)",
                    systemImage: "note.text"
                )
                LibraryProfileDetailRow(title: "Runtime", value: runtimeDescription, systemImage: "clock")
            }
        }
    }

    private var sectionCardTint: Color {
        colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.05)
    }
}

struct LibraryProfileSettingsCard: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var followsSystemLanguage: Bool
    @Binding var hideDroppedByDefault: Bool
    @Binding var defaultNewEntryWatchStatus: AnimeEntry.WatchStatus
    @Binding var defaultFilters: Set<LibraryStore.AnimeFilter>
    @Binding var autoPrefetchImagesOnAddAndRestore: Bool
    @Binding var preferredLanguage: Language

    let restoreCompleted: Bool
    let createBackupItems: () -> [Any]?
    let onRestore: () -> Void
    let onChangeAPIKey: () -> Void
    let onCheckMetadataCacheSize: () -> Void
    let onRefreshInfos: () -> Void
    let onPrefetchImages: () -> Void
    let onShowAbout: () -> Void
    let onDeleteAllAnimes: () -> Void

    var body: some View {
        PopupSectionCard(
            "Settings",
            systemImage: "gearshape.2",
            spacing: 14,
            panelTint: sectionCardTint
        ) {
            VStack(spacing: 14) {
                languagePickerRow
                defaultLibraryBehaviorRow
                backupManagementRow
                maintenanceActions
            }
        }
    }

    private var languagePickerRow: some View {
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

    private var defaultLibraryBehaviorRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryProfileSettingHeader(
                title: "Library Defaults",
                systemImage: "line.3.horizontal.decrease.circle",
                tint: .mint
            )

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("New Entries Start As")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Menu {
                    ForEach(AnimeEntry.WatchStatus.allCases, id: \.self) { status in
                        Button {
                            defaultNewEntryWatchStatus = status
                        } label: {
                            if status == defaultNewEntryWatchStatus {
                                Label(status.localizedStringResource, systemImage: "checkmark")
                            } else {
                                Text(status.localizedStringResource)
                            }
                        }
                    }
                } label: {
                    LibraryProfileSelectionCapsule(
                        title: defaultNewEntryWatchStatus.localizedStringResource,
                        tint: defaultNewEntryWatchStatus.defaultPickerTintColor
                    )
                }
            }
            .padding(.vertical, 2)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Default Filters")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 12)
                Menu {
                    ForEach(LibraryStore.AnimeFilter.allCases, id: \.self) { filter in
                        Toggle(
                            isOn: defaultFilterBinding(for: filter),
                            label: { Text(filter.name) }
                        )
                    }
                    Toggle(
                        "All",
                        isOn: .init(
                            get: { defaultFilters.isEmpty },
                            set: {
                                if $0 {
                                    defaultFilters.removeAll()
                                }
                            }
                        )
                    )
                } label: {
                    LibraryProfileSelectionCapsule(
                        title: defaultFiltersSummaryResource,
                        tint: .mint
                    )
                }
                .menuActionDismissBehavior(.disabled)
            }
            .padding(.vertical, 2)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hide Dropped Entries")
                        .font(.subheadline.weight(.semibold))
                    Text("Only show dropped entries after you explicitly enable the Dropped filter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle("Hide Dropped Entries", isOn: $hideDroppedByDefault)
                    .labelsHidden()
                    .tint(.mint)
                    .scaleEffect(0.78, anchor: .trailing)
                    .frame(width: 42, height: 26, alignment: .trailing)
            }
            .padding(.vertical, 2)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Auto Prefetch Images")
                        .font(.subheadline.weight(.semibold))
                    Text("Prefetch images when adding titles or restoring a backup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle("Auto Prefetch Images", isOn: $autoPrefetchImagesOnAddAndRestore)
                    .labelsHidden()
                    .tint(.mint)
                    .scaleEffect(0.78, anchor: .trailing)
                    .frame(width: 42, height: 26, alignment: .trailing)
            }
            .padding(.vertical, 2)
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .mint)
    }

    private var backupManagementRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibraryProfileSettingHeader(
                title: "Backup & Restore",
                subtitle: "Export or restore your local library.",
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                tint: .orange
            )

            HStack(spacing: 10) {
                exportButton
                    .frame(maxWidth: .infinity)
                restoreButton
                    .frame(maxWidth: .infinity)
            }
            .disabled(restoreCompleted)

            if restoreCompleted {
                HStack {
                    Spacer()
                    Text("Restore completed!")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                    Spacer()
                }
            }

            Text("* For security reasons, your TMDb API Key will not be exported.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .orange)
    }

    private var maintenanceActions: some View {
        VStack(spacing: 0) {
            LibraryProfileActionRow(
                title: "Change API Key",
                subtitle: "Update the TMDb key used for metadata.",
                systemImage: "person.badge.key",
                tint: LibraryProfileMaintenancePalette.apiKey,
                action: onChangeAPIKey
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "Check Metadata Cache Size",
                subtitle: "Review image and metadata cache usage.",
                systemImage: "archivebox",
                tint: LibraryProfileMaintenancePalette.cache,
                action: onCheckMetadataCacheSize
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "Refresh Infos",
                subtitle: "Fetch latest TMDb metadata for every entry.",
                systemImage: "arrow.clockwise",
                tint: LibraryProfileMaintenancePalette.refresh,
                action: onRefreshInfos
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "Prefetch Images",
                subtitle: "Cache posters and artwork without refreshing metadata.",
                systemImage: "photo.stack",
                tint: LibraryProfileMaintenancePalette.prefetch,
                action: onPrefetchImages
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "About AniShelf",
                subtitle: "Version, links, and credits.",
                systemImage: "info.circle",
                tint: LibraryProfileMaintenancePalette.about,
                action: onShowAbout
            )
            LibraryProfileActionDivider()
            LibraryProfileActionRow(
                title: "Delete All Animes",
                subtitle: "Remove every saved library entry.",
                systemImage: "trash",
                role: .destructive,
                tint: .red,
                action: onDeleteAllAnimes
            )
        }
        .padding(.vertical, 4)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: LibraryProfileMaintenancePalette.panel)
    }

    @ViewBuilder
    private var exportButton: some View {
        LazyShareLink(prepareData: createBackupItems) {
            Label("Export", systemImage: "document.badge.arrow.up")
        }
        .buttonStyle(LibraryProfileCommandButtonStyle(tint: .blue, filled: false))
    }

    private var restoreButton: some View {
        Button("Restore", systemImage: "document.badge.clock", role: .destructive, action: onRestore)
            .buttonStyle(LibraryProfileCommandButtonStyle(tint: .red, filled: false))
    }

    private var sectionCardTint: Color {
        colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.05)
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
}
