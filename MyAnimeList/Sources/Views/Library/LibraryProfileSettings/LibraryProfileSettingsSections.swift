//
//  LibraryProfileSettingsSections.swift
//  MyAnimeList
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/3.
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
    enum Layout {
        case compact
        case fillsSummaryHeight
    }

    let stats: LibraryProfileStats
    let layout: Layout

    @ViewBuilder
    var body: some View {
        switch layout {
        case .compact:
            compactGrid
        case .fillsSummaryHeight:
            expandedGrid
        }
    }

    private var compactGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            watchedMetric
            watchingMetric
            favoriteMetric
            plannedMetric
        }
    }

    private var expandedGrid: some View {
        VStack(spacing: 12) {
            metricRow(watchedMetric, watchingMetric)
            metricRow(favoriteMetric, plannedMetric)
        }
        .frame(maxHeight: .infinity)
    }

    private var watchedMetric: some View {
        LibraryProfileMetricCard(
            title: "Watched",
            value: stats.watchedCount,
            systemImage: "checkmark.circle.fill",
            tint: AnimeEntry.WatchStatus.watched.libraryTintColor,
            fillsAvailableHeight: fillsAvailableHeight
        )
    }

    private var watchingMetric: some View {
        LibraryProfileMetricCard(
            title: "Watching",
            value: stats.watchingCount,
            systemImage: "play.circle.fill",
            tint: AnimeEntry.WatchStatus.watching.libraryTintColor,
            fillsAvailableHeight: fillsAvailableHeight
        )
    }

    private var favoriteMetric: some View {
        LibraryProfileMetricCard(
            title: "Favorites",
            value: stats.favoriteCount,
            systemImage: "heart.fill",
            tint: .pink,
            fillsAvailableHeight: fillsAvailableHeight
        )
    }

    private var plannedMetric: some View {
        LibraryProfileMetricCard(
            title: "Planned",
            value: stats.planToWatchCount,
            systemImage: "bookmark.fill",
            tint: AnimeEntry.WatchStatus.planToWatch.libraryTintColor,
            fillsAvailableHeight: fillsAvailableHeight
        )
    }

    private func metricRow<Leading: View, Trailing: View>(
        _ leading: Leading,
        _ trailing: Trailing
    ) -> some View {
        HStack(spacing: 12) {
            leading
                .frame(maxWidth: .infinity, alignment: .topLeading)
            trailing
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    private var fillsAvailableHeight: Bool {
        switch layout {
        case .compact:
            false
        case .fillsSummaryHeight:
            true
        }
    }
}

struct LibraryProfileLibraryDetailsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var runtimeMode: LibraryProfileRuntimeMode = .total

    let stats: LibraryProfileStats

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
                LibraryProfileDetailRow(
                    title: runtimeMode.title,
                    value: runtimeMode.description(for: stats),
                    systemImage: "clock"
                )
                .contentShape(Rectangle())
                .onTapGesture(perform: cycleRuntimeMode)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text(runtimeMode.accessibilityHint))
            }
        }
    }

    private var sectionCardTint: Color {
        colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.05)
    }

    private func cycleRuntimeMode() {
        withAnimation {
            runtimeMode.advance()
        }
    }
}
