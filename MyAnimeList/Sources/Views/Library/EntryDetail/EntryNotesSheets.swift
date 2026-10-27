//
//  EntryNotesSheets.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/26.
//

import DataProvider
import SwiftUI

/// Chooses an episode to open or move a note to.
///
/// Lists metadata episodes when known and always offers inline number entry for specials,
/// renumbered, or offline episodes.
struct EpisodeNotePicker: View {
    enum Purpose: Hashable {
        case open
        case move(EpisodeNoteAnchor)
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage(.preferredAnimeInfoLanguage) private var preferredLanguage: Language = .english
    @AppStorage(.useCurrentLocaleForAnimeInfoLanguage) private var followsSystemLanguage: Bool =
        Language.followsSystemPreference()
    let entry: AnimeEntry
    let purpose: Purpose
    let suggestion: EpisodeNoteAnchor?
    let select: (EpisodeNoteAnchor) -> Void
    @State private var season: Int
    @State private var seriesEpisodes = SeriesSeasonEpisodeLoader()

    init(
        entry: AnimeEntry,
        purpose: Purpose,
        suggestion: EpisodeNoteAnchor?,
        select: @escaping (EpisodeNoteAnchor) -> Void
    ) {
        self.entry = entry
        self.purpose = purpose
        self.suggestion = suggestion
        self.select = select
        let source: EpisodeNoteAnchor? =
            if case .move(let anchor) = purpose { anchor } else { nil }
        _season = State(
            initialValue: entry.type.seasonNumber ?? source?.seasonNumber ?? suggestion?.seasonNumber
                ?? EntryNoteEpisodes.defaultSeason(for: entry))
    }

    private struct Episode: Identifiable {
        let number: Int
        let title: String?
        let airDate: Date?
        var id: Int { number }
    }

    private var source: EpisodeNoteAnchor? {
        if case .move(let anchor) = purpose { return anchor }
        return nil
    }

    private var title: LocalizedStringKey {
        source == nil ? "Choose Episode" : "Move to Episode"
    }

    private var language: Language { followsSystemLanguage ? .current : preferredLanguage }
    private var seriesRequestKey: String { "\(entry.tmdbID)-\(season)-\(language.rawValue)" }

    /// A series fetches titles per season; rows keep their loaded shape until they arrive.
    private var isFetchingTitles: Bool {
        entry.type.seasonNumber == nil && seriesEpisodes.loadedRequestKey != seriesRequestKey
            && !seriesEpisodes.loadFailed
    }

    private var seasons: [(number: Int, title: String)] {
        guard entry.type.seasonNumber == nil else { return [] }
        return (entry.detail?.seasons ?? [])
            .sorted { $0.seasonNumber < $1.seasonNumber }
            .map { ($0.seasonNumber, $0.title) }
    }

    /// Stored episodes for a season entry; fetched titles for a series, with numbered placeholders
    /// until they arrive.
    ///
    /// Nil when metadata gives no episode count.
    private var episodes: [Episode]? {
        if entry.type.seasonNumber == season, let stored = entry.detail?.orderedEpisodes, !stored.isEmpty {
            return stored.map { Episode(number: $0.episodeNumber, title: $0.title, airDate: $0.airDate) }
        }
        if entry.type.seasonNumber == nil, seriesEpisodes.loadedRequestKey == seriesRequestKey,
            !seriesEpisodes.episodes.isEmpty
        {
            return seriesEpisodes.episodes.map {
                Episode(number: $0.episodeNumber, title: $0.name, airDate: $0.airDate)
            }
        }
        return EntryNoteEpisodes.count(in: entry, season: season).map { count in
            (1...count).map { Episode(number: $0, title: nil, airDate: nil) }
        }
    }

    var body: some View {
        #if os(macOS)
            macBody
        #else
            iOSBody
        #endif
    }

    private func loadSeriesEpisodes() async {
        guard entry.type.seasonNumber == nil else { return }
        await seriesEpisodes.load(
            requestKey: seriesRequestKey, seriesTMDbID: entry.tmdbID, seasonNumber: season, language: language)
    }

    private var seasonPicker: some View {
        Picker("Season", selection: $season.animation(.snappy)) {
            ForEach(seasons, id: \.number) { season in
                Text(verbatim: season.title).tag(season.number)
            }
        }
    }

    #if os(macOS)
        /// Laid out like the app's other Mac sheets: heading, list, then manual entry and Close.
        private var macBody: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Spacer(minLength: 12)
                    if seasons.count > 1 {
                        seasonPicker
                            .labelsHidden()
                            .fixedSize()
                    }
                }
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)

                if let episodes {
                    Divider()
                    episodeList(episodes)
                        .listStyle(.inset)
                    Divider()
                }

                VStack(alignment: .leading, spacing: 16) {
                    numberSection
                    HStack {
                        Spacer()
                        Button("Close") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .padding(20)
            }
            .frame(width: 460)
            .frame(height: episodes == nil ? nil : 560)
            .task(id: seriesRequestKey) { await loadSeriesEpisodes() }
        }
    #else
        private var iOSBody: some View {
            NavigationStack {
                Group {
                    if let episodes {
                        episodeList(episodes)
                    } else {
                        Form { numberSection }
                    }
                }
                .navigationTitle(title)
                .inlineNavigationTitle()
                .preferredNavigationBarScrollEdgeEffect()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: dismiss.callAsFunction) { SheetCloseLabel() }
                            .accessibilityLabel(Text("Close"))
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .task(id: seriesRequestKey) { await loadSeriesEpisodes() }
            }
            .presentationDetents([.medium, .large])
        }
    #endif

    private func episodeList(_ episodes: [Episode]) -> some View {
        ScrollViewReader { proxy in
            List {
                #if os(iOS)
                    if seasons.count > 1 { seasonPicker }
                #endif
                Section {
                    ForEach(episodes) { episode in
                        row(episode)
                    }
                }
                #if os(iOS)
                    // The Mac sheet places manual entry below the list.
                    numberSection
                #endif
            }
            // Rows animate their own content; List cells do not inherit this animation.
            .animation(.snappy, value: episodes.map(\.number))
            .onAppear {
                // Only scroll when the target would start below the first screenful.
                if let target = source ?? suggestion, target.seasonNumber == season, target.episodeNumber > 5 {
                    proxy.scrollTo(target.episodeNumber, anchor: .center)
                }
            }
        }
    }

    private func row(_ episode: Episode) -> some View {
        let anchor = EpisodeNoteAnchor(seasonNumber: season, episodeNumber: episode.number)
        let isPending = isFetchingTitles
        return Button {
            choose(anchor)
        } label: {
            HStack(spacing: 12) {
                let title = episode.title.flatMap { $0.isEmpty ? nil : $0 }
                if isPending || title != nil {
                    Text(verbatim: "\(episode.number)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 26, alignment: .leading)
                }
                // While pending, redacted lines hold the loaded row's height, so arriving
                // titles only swap content instead of resizing table rows.
                VStack(alignment: .leading, spacing: 2) {
                    if isPending {
                        Text(verbatim: "Episode title")
                            .redacted(reason: .placeholder)
                    } else if let title {
                        Text(verbatim: title)
                            .lineLimit(1)
                    } else {
                        Text("Episode \(episode.number)")
                    }
                    if isPending {
                        Text(Date.now, format: .dateTime.year().month().day())
                            .font(.caption)
                            .redacted(reason: .placeholder)
                    } else if let airDate = episode.airDate {
                        Text(airDate, format: .dateTime.year().month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                trailing(for: anchor)
            }
            .animation(.snappy, value: isPending)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(anchor == source)
        .id(episode.number)
    }

    @ViewBuilder
    private func trailing(for anchor: EpisodeNoteAnchor) -> some View {
        if entry.episodeNote(at: anchor)?.isEmpty == false {
            Image(systemName: "note.text")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Has Note")
        } else if EntryNoteEpisodes.watched(anchor, in: entry) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tertiary)
                .accessibilityLabel(Text(EntryDetailL10n.watched))
        }
    }

    private var numberSection: some View {
        EpisodeNumberSection(entry: entry, initial: source ?? suggestion, actionTitle: title, source: source) {
            choose($0)
        }
    }

    private func choose(_ anchor: EpisodeNoteAnchor) {
        dismiss()
        select(anchor)
    }
}

/// Inline numeric entry for episodes metadata does not list.
fileprivate struct EpisodeNumberSection: View {
    let entry: AnimeEntry
    let actionTitle: LocalizedStringKey
    let source: EpisodeNoteAnchor?
    let confirm: (EpisodeNoteAnchor) -> Void
    @State private var season: Int
    @State private var episode: Int

    init(
        entry: AnimeEntry,
        initial: EpisodeNoteAnchor?,
        actionTitle: LocalizedStringKey,
        source: EpisodeNoteAnchor?,
        confirm: @escaping (EpisodeNoteAnchor) -> Void
    ) {
        self.entry = entry
        self.actionTitle = actionTitle
        self.source = source
        self.confirm = confirm
        _season = State(
            initialValue: entry.type.seasonNumber ?? initial?.seasonNumber
                ?? EntryNoteEpisodes.defaultSeason(for: entry))
        _episode = State(initialValue: initial?.episodeNumber ?? 1)
    }

    private var anchor: EpisodeNoteAnchor { .init(seasonNumber: season, episodeNumber: episode) }

    private var isValid: Bool { season >= 0 && episode >= 1 && anchor != source }

    var body: some View {
        #if os(macOS)
            VStack(alignment: .leading, spacing: 8) {
                Text("Episode Not Listed")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    if entry.type.seasonNumber == nil {
                        numberRow("Season", prefix: "S", value: $season, minimum: 0)
                    }
                    numberRow("Episode", prefix: "E", value: $episode, minimum: 1)
                    Spacer(minLength: 8)
                    Button(actionTitle) { confirm(anchor) }
                        .disabled(!isValid)
                }
                if entry.type.seasonNumber == nil {
                    Text("Season 0 contains specials")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        #else
            Section {
                if entry.type.seasonNumber == nil {
                    numberRow("Season", prefix: "S", value: $season, minimum: 0)
                }
                numberRow("Episode", prefix: "E", value: $episode, minimum: 1)
                Button(actionTitle) { confirm(anchor) }
                    .disabled(!isValid)
            } header: {
                Text("Episode Not Listed")
            } footer: {
                if entry.type.seasonNumber == nil {
                    Text("Season 0 contains specials")
                }
            }
        #endif
    }

    /// The Mac shows both rows side by side, so it labels them with the chips' S/E prefixes;
    /// the full name stays the accessibility label.
    private func numberRow(
        _ title: LocalizedStringKey,
        prefix: String,
        value: Binding<Int>,
        minimum: Int
    ) -> some View {
        #if os(macOS)
            HStack(spacing: 4) {
                Text(verbatim: prefix)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(title, value: value, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 44)
                Stepper(title, value: value, in: minimum...9_999)
                    .labelsHidden()
            }
        #else
            LabeledContent(title) {
                HStack(spacing: 12) {
                    TextField(title, value: value, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 64)
                        .keyboardType(.numberPad)
                    Stepper(title, value: value, in: minimum...9_999)
                        .labelsHidden()
                }
            }
        #endif
    }
}

/// The expanded All view: every note in reading order.
///
/// Selecting one returns to its editor.
struct EntryNotesReader: View {
    @Environment(\.dismiss) private var dismiss
    let entry: AnimeEntry
    let onSelect: (EntryNoteScope) -> Void
    let onMove: (EpisodeNoteAnchor) -> Void

    var body: some View {
        NavigationStack {
            List {
                if !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Overall") {
                        noteRow(entry.notes) { open(.overall) }
                    }
                }
                ForEach(entry.episodeNotes.filter { !$0.isEmpty }) { note in
                    let title = EntryNoteLabels.title(note.anchor, entry: entry)
                    Section {
                        noteRow(note.text) { open(.episode(note.anchor)) }
                            .contextMenu {
                                Button("Move to Episode…", systemImage: "arrow.right") { onMove(note.anchor) }
                                Button("Delete Note", systemImage: "trash", role: .destructive) {
                                    withAnimation { _ = entry.updateEpisodeNote(at: note.anchor, text: "") }
                                }
                            }
                    } header: {
                        Text(verbatim: [title.primary, title.secondary].compactMap(\.self).joined(separator: " · "))
                    }
                }
            }
            .navigationTitle("All Notes")
            .inlineNavigationTitle()
            .preferredNavigationBarScrollEdgeEffect()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 480)
        #endif
    }

    private func noteRow(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: text)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func open(_ scope: EntryNoteScope) {
        dismiss()
        onSelect(scope)
    }
}
