//
//  MacSettingsOverview.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/16.
//

#if os(macOS)
    import DataProvider
    import SwiftUI

    /// The Settings window's Overview page: library statistics and app links as a grouped
    /// form, like the other pages, instead of the iOS hero and metric cards.
    struct MacSettingsOverview: View {
        let stats: LibraryProfileStats
        let animeTitleResource: LocalizedStringResource
        let whatsNewVersion: String?
        let onShowWhatsNew: () -> Void
        let onShowSupport: () -> Void
        let onShowAbout: () -> Void

        var body: some View {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(.appIcon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                            .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(stats.totalCount)")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text(animeTitleResource)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .padding(.vertical, 4)
                }

                Section("Status") {
                    countRow("Watched", stats.watchedCount, systemImage: "checkmark.circle.fill",
                        tint: AnimeEntry.WatchStatus.watched.libraryTintColor)
                    countRow("Watching", stats.watchingCount, systemImage: "play.circle.fill",
                        tint: AnimeEntry.WatchStatus.watching.libraryTintColor)
                    countRow("Planned", stats.planToWatchCount, systemImage: "bookmark.fill",
                        tint: AnimeEntry.WatchStatus.planToWatch.libraryTintColor)
                    countRow("Favorites", stats.favoriteCount, systemImage: "heart.fill", tint: .pink)
                }

                Section("Library Details") {
                    countRow("Movies", stats.movieCount, systemImage: "film")
                    countRow("Series", stats.seriesCount, systemImage: "tv")
                    countRow("Seasons", stats.seasonCount, systemImage: "square.stack.3d.up")
                    countRow("With Notes", stats.entriesWithNotesCount, systemImage: "note.text")
                    // The iOS card cycles these on tap; a desktop page has room for all three.
                    ForEach([LibraryProfileRuntimeMode.total, .watched, .planned], id: \.self) { mode in
                        LabeledContent {
                            Text(mode.description(for: stats))
                                .monospacedDigit()
                        } label: {
                            Label {
                                Text(mode.title)
                            } icon: {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("App Info") {
                    if let whatsNewVersion {
                        linkRow("What's New", systemImage: "sparkles.rectangle.stack", value: whatsNewVersion,
                            action: onShowWhatsNew)
                    }
                    linkRow("Support AniShelf", systemImage: "heart.circle", action: onShowSupport)
                    linkRow("About AniShelf", systemImage: "info.circle", action: onShowAbout)
                }
            }
            .formStyle(.grouped)
        }

        private func countRow(
            _ title: LocalizedStringResource,
            _ count: Int,
            systemImage: String,
            tint: Color = .secondary
        ) -> some View {
            LabeledContent {
                Text("\(count)")
                    .monospacedDigit()
            } label: {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                }
            }
        }

        private func linkRow(
            _ title: LocalizedStringResource,
            systemImage: String,
            value: String? = nil,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                HStack {
                    Label {
                        Text(title)
                    } icon: {
                        Image(systemName: systemImage)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let value {
                        Text(verbatim: value)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
#endif
