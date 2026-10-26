//
//  EntryNotesSection.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/26.
//

import DataProvider
import SwiftUI

/// Design A: the editor stays in place while chips inside its box select the note scope.
struct EntryNotesSection: View {
    let entry: AnimeEntry
    let originalNotes: String?
    let originalEpisodeNotes: [EpisodeNote]

    @State private var selectedScope: EntryNoteScope
    @State private var sheet: NotesSheet?
    @State private var pendingCombine: PendingCombine?
    @Namespace private var chipSelection

    init(entry: AnimeEntry, originalNotes: String? = nil, originalEpisodeNotes: [EpisodeNote] = []) {
        self.entry = entry
        self.originalNotes = originalNotes
        self.originalEpisodeNotes = originalEpisodeNotes
        _selectedScope = State(initialValue: EntryNoteScopeMemory.validScope(for: entry))
    }

    private enum NotesSheet: Identifiable, Hashable {
        case picker(EpisodeNotePicker.Purpose)
        case all
        var id: Self { self }
    }

    private struct PendingCombine {
        let source: EpisodeNoteAnchor
        let target: EpisodeNoteAnchor
    }

    private var selectedAnchor: EpisodeNoteAnchor? {
        if case .episode(let anchor) = selectedScope { return anchor }
        return nil
    }
    private var visibleNotes: [EpisodeNote] { entry.episodeNotes.filter { !$0.isEmpty } }
    private var supportsEpisodes: Bool { entry.supportsEpisodeNotes }
    private var isAll: Bool { selectedScope == .all && supportsEpisodes }
    private var contentHeight: CGFloat = 200

    /// Notes with text plus a selected empty draft, so a new note keeps its chip while typing.
    private var chipAnchors: [EpisodeNoteAnchor] {
        var anchors = Set(visibleNotes.map(\.anchor))
        if let selectedAnchor { anchors.insert(selectedAnchor) }
        return anchors.sorted()
    }

    private var suggestion: EpisodeNoteAnchor? {
        EntryNoteEpisodes.suggestion(for: entry, excluding: Set(chipAnchors))
    }

    private var currentText: String {
        if let selectedAnchor, supportsEpisodes { return entry.episodeNote(at: selectedAnchor)?.text ?? "" }
        return entry.notes
    }

    private var originalText: String? {
        if let selectedAnchor {
            return originalEpisodeNotes.first { $0.anchor == selectedAnchor }?.text ?? ""
        }
        return originalNotes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            VStack(alignment: .leading, spacing: 8) {
                if supportsEpisodes { scopeChips }
                content
                    .frame(height: contentHeight)
            }
            .modifier(EntryNotesBoxStyle())
        }
        .animation(.snappy, value: selectedScope)
        .animation(.snappy, value: chipAnchors)
        // The first note's text adds All without changing the chip anchors.
        .animation(.snappy, value: visibleNotes.isEmpty)
        .onChange(of: selectedScope) { _, scope in
            EntryNoteScopeMemory.remember(scope, for: entry)
        }
        .sheet(item: $sheet) { destination in
            Group {
                switch destination {
                case .picker(let purpose):
                    EpisodeNotePicker(entry: entry, purpose: purpose, suggestion: suggestion) { anchor in
                        choose(anchor, for: purpose)
                    }
                case .all:
                    EntryNotesReader(entry: entry, onSelect: select, onMove: { sheet = .picker(.move($0)) })
                }
            }
            .modifier(EntryNotesPresentationLifecycle())
        }
        .confirmationDialog(
            combineTitle,
            isPresented: Binding(get: { pendingCombine != nil }, set: { if !$0 { pendingCombine = nil } }),
            titleVisibility: .visible
        ) {
            Button("Combine Notes") {
                if let pendingCombine { move(pendingCombine.source, to: pendingCombine.target, combining: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The moved note is added after the existing text.")
        }
    }

    private var header: some View {
        HStack {
            Text(EntryDetailL10n.notes)
                #if !os(macOS)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                #endif
            Spacer(minLength: 8)
            #if os(macOS)
                // iOS covers this with Done › Discard Changes and text undo.
                let canRevert = !isAll && originalText.map { currentText != $0 } == true
                Button("Revert Notes") {
                    if let originalText { setText(originalText) }
                }
                .font(.caption)
                .controlSize(.small)
                // Keep the header height stable when the revert action becomes available.
                .opacity(canRevert ? 1 : 0)
                .disabled(!canRevert)
                .accessibilityHidden(!canRevert)
            #endif
        }
    }

    // MARK: Chips

    private var scopeChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if !visibleNotes.isEmpty || isAll {
                        chip(.all, title: String(localized: "All"), hasText: false)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    chip(
                        .overall, title: String(localized: "Overall"),
                        hasText: !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && !visibleNotes.isEmpty)
                    ForEach(chipAnchors) { anchor in
                        let hasText = entry.episodeNote(at: anchor)?.isEmpty == false
                        chip(.episode(anchor), title: EntryNoteLabels.short(anchor, entry: entry), hasText: hasText)
                            .contextMenu { episodeMenu(for: anchor, hasText: hasText) }
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    if let suggestion, !chipAnchors.contains(suggestion) {
                        suggestedChip(suggestion)
                            .transition(.opacity)
                    }
                    Button {
                        sheet = .picker(.open)
                    } label: {
                        Text("Other…")
                            .chipText()
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("entryNotes.other")
                }
                .padding(.vertical, 1)
            }
            // `.hidden` still shows a scroller on macOS when a mouse is connected.
            .scrollIndicators(.never)
            // Run the row to the box edges so chips scroll under them instead of clipping early.
            .contentMargins(.horizontal, EntryNotesBoxStyle.inset, for: .scrollContent)
            .padding(.horizontal, -EntryNotesBoxStyle.inset)
            .onAppear { proxy.scrollTo(selectedScope, anchor: .center) }
            .onChange(of: selectedScope) { _, scope in
                withAnimation(.snappy) { proxy.scrollTo(scope, anchor: .center) }
            }
        }
    }

    private func chip(_ scope: EntryNoteScope, title: String, hasText: Bool) -> some View {
        let isSelected = selectedScope == scope
        return Button {
            select(scope)
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: title)
                if hasText {
                    Circle()
                        .frame(width: 4, height: 4)
                        .opacity(0.6)
                        .accessibilityHidden(true)
                }
            }
            .chipText()
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(.fill.tertiary)
                if isSelected {
                    Capsule()
                        .fill(.tint)
                        .matchedGeometryEffect(id: "selection", in: chipSelection)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(scope)
    }

    private func suggestedChip(_ anchor: EpisodeNoteAnchor) -> some View {
        Button {
            select(.episode(anchor))
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.caption2.weight(.bold))
                Text(verbatim: EntryNoteLabels.short(anchor, entry: entry))
            }
            .chipText()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay {
                Capsule().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("New Note for \(EntryNoteLabels.title(anchor, entry: entry).primary)"))
        .accessibilityIdentifier("entryNotes.suggested")
    }

    @ViewBuilder
    private func episodeMenu(for anchor: EpisodeNoteAnchor, hasText: Bool) -> some View {
        if hasText {
            Button("Move to Episode…", systemImage: "arrow.right") { sheet = .picker(.move(anchor)) }
            Button("Delete Note", systemImage: "trash", role: .destructive) { delete(anchor) }
        }
    }

    // MARK: Content

    private var content: some View {
        ZStack(alignment: .topLeading) {
            if isAll {
                EntryNotesOverview(
                    entry: entry,
                    onSelect: select,
                    onExpand: { sheet = .all },
                    menu: { anchor in episodeMenu(for: anchor, hasText: true) }
                )
                .transition(.blurReplace)
            } else {
                editor
                    .id(selectedScope)
                    .transition(.blurReplace)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            if supportsEpisodes, scopeTitle.secondary != nil || isStranded { scopeLabel }
            ScrollIsolatedPlaceholderTextEditor(
                text: Binding(get: { currentText }, set: setText),
                placeholder: selectedAnchor == nil ? EntryDetailL10n.writeSomeThoughts : "Write an episode note…"
            )
            .font(.body)
            .accessibilityLabel(Text(verbatim: scopeTitle.primary))
            .accessibilityIdentifier("entryNotes.editor")
        }
    }

    private var scopeTitle: (primary: String, secondary: String?) {
        selectedAnchor.map { EntryNoteLabels.title($0, entry: entry) } ?? (String(localized: "Overall"), nil)
    }

    private var isStranded: Bool {
        guard let selectedAnchor else { return false }
        return EntryNoteEpisodes.isStranded(selectedAnchor, in: entry)
            && entry.episodeNote(at: selectedAnchor)?.isEmpty == false
    }

    /// The selected chip already names the episode, so this line only adds its title or the
    /// stranded hint.
    private var scopeLabel: some View {
        HStack(spacing: 4) {
            if let secondary = scopeTitle.secondary {
                Text(verbatim: secondary)
                    .foregroundStyle(EntryNotesStyle.secondaryText)
            }
            Spacer(minLength: 4)
            if isStranded, let selectedAnchor {
                Button {
                    sheet = .picker(.move(selectedAnchor))
                } label: {
                    Text("Not in Episode List · Move…")
                }
                .buttonStyle(.plain)
                .foregroundStyle(EntryNotesStyle.secondaryText)
            }
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 4)
    }

    // MARK: Actions

    private func select(_ scope: EntryNoteScope) {
        withAnimation(.snappy) { selectedScope = scope }
    }

    private func setText(_ text: String) {
        if let selectedAnchor, supportsEpisodes {
            entry.updateEpisodeNote(at: selectedAnchor, text: text)
        } else {
            entry.updateNotes(text)
        }
    }

    private func choose(_ anchor: EpisodeNoteAnchor, for purpose: EpisodeNotePicker.Purpose) {
        switch purpose {
        case .open:
            select(.episode(anchor))
        case .move(let source):
            if entry.episodeNote(at: anchor)?.isEmpty == false {
                pendingCombine = .init(source: source, target: anchor)
            } else {
                move(source, to: anchor, combining: false)
            }
        }
    }

    private var combineTitle: Text {
        guard let pendingCombine else { return Text(verbatim: "") }
        return Text("\(EntryNoteLabels.title(pendingCombine.target, entry: entry).primary) already has a note")
    }

    /// A move leaves a deletion marker on the old anchor so other devices drop it too.
    private func move(_ source: EpisodeNoteAnchor, to target: EpisodeNoteAnchor, combining: Bool) {
        guard let text = entry.episodeNote(at: source)?.text, source != target else { return }
        let existing = entry.episodeNote(at: target)?.text ?? ""
        withAnimation(.snappy) {
            entry.updateEpisodeNote(at: target, text: combining && !existing.isEmpty ? existing + "\n\n" + text : text)
            entry.updateEpisodeNote(at: source, text: "")
            selectedScope = .episode(target)
        }
        pendingCombine = nil
    }

    private func delete(_ anchor: EpisodeNoteAnchor) {
        withAnimation(.snappy) {
            entry.updateEpisodeNote(at: anchor, text: "")
            if selectedAnchor == anchor || (selectedScope == .all && visibleNotes.isEmpty) {
                selectedScope = .overall
            }
        }
    }
}

// MARK: - Scope

enum EntryNoteScope: Hashable {
    case all
    case overall
    case episode(EpisodeNoteAnchor)

    var storageValue: String {
        switch self {
        case .all: "all"
        case .overall: "overall"
        case .episode(let anchor): "\(anchor.seasonNumber):\(anchor.episodeNumber)"
        }
    }

    init?(storageValue: String) {
        switch storageValue {
        case "all": self = .all
        case "overall": self = .overall
        default:
            let numbers = storageValue.split(separator: ":").compactMap { Int($0) }
            guard numbers.count == 2, numbers[0] >= 0, numbers[1] > 0 else { return nil }
            self = .episode(.init(seasonNumber: numbers[0], episodeNumber: numbers[1]))
        }
    }
}

/// The last chip per entry on this device. Only non-Overall choices are kept, most recent last.
enum EntryNoteScopeMemory {
    private static let key = "entryNotes.lastScopes"
    private static let limit = 200

    static func validScope(for entry: AnimeEntry) -> EntryNoteScope {
        guard entry.supportsEpisodeNotes,
            let stored = entries().last(where: { $0.id == entry.libraryIdentity.rawID }),
            let scope = EntryNoteScope(storageValue: stored.scope)
        else { return .overall }
        switch scope {
        case .all:
            return entry.episodeNotes.contains { !$0.isEmpty } ? .all : .overall
        case .episode(let anchor):
            return entry.episodeNote(at: anchor)?.isEmpty == false ? scope : .overall
        case .overall:
            return .overall
        }
    }

    static func remember(_ scope: EntryNoteScope, for entry: AnimeEntry) {
        let id = entry.libraryIdentity.rawID
        var stored = entries().filter { $0.id != id }
        if scope != .overall { stored.append((id, scope.storageValue)) }
        UserDefaults.standard.set(stored.suffix(limit).map { "\($0.id)\t\($0.scope)" }, forKey: key)
    }

    private static func entries() -> [(id: String, scope: String)] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }
    }
}

// MARK: - Labels and metadata

enum EntryNoteLabels {
    static func short(_ anchor: EpisodeNoteAnchor, entry: AnimeEntry) -> String {
        if anchor.seasonNumber == 0, entry.type.seasonNumber == nil {
            return String(localized: "SP \(anchor.episodeNumber)")
        }
        if !showsSeason(anchor, entry: entry) { return String(localized: "E\(anchor.episodeNumber)") }
        return String(localized: "S\(anchor.seasonNumber) E\(anchor.episodeNumber)")
    }

    /// Season entries and single-season series need no season in their labels.
    private static func showsSeason(_ anchor: EpisodeNoteAnchor, entry: AnimeEntry) -> Bool {
        guard entry.type.seasonNumber == nil else { return false }
        let regularSeasons = (entry.detail?.seasons ?? []).filter { $0.seasonNumber > 0 }
        return regularSeasons.count != 1 || regularSeasons[0].seasonNumber != anchor.seasonNumber
    }

    /// The episode reference, and its title when metadata has one.
    static func title(_ anchor: EpisodeNoteAnchor, entry: AnimeEntry) -> (primary: String, secondary: String?) {
        let primary =
            !showsSeason(anchor, entry: entry)
            ? String(localized: "Episode \(anchor.episodeNumber)")
            : String(localized: "Season \(anchor.seasonNumber) · Episode \(anchor.episodeNumber)")
        return (primary, EntryNoteEpisodes.title(of: anchor, in: entry))
    }
}

enum EntryNoteEpisodes {
    /// Known episode count for a season, or nil when metadata has not loaded.
    static func count(in entry: AnimeEntry, season: Int) -> Int? {
        if entry.type.seasonNumber == season, let episodes = entry.detail?.episodes, !episodes.isEmpty {
            return episodes.map(\.episodeNumber).max()
        }
        guard let count = entry.detail?.seasons.first(where: { $0.seasonNumber == season })?.episodeCount, count > 0
        else { return nil }
        return count
    }

    static func title(of anchor: EpisodeNoteAnchor, in entry: AnimeEntry) -> String? {
        guard entry.type.seasonNumber == anchor.seasonNumber,
            let title = entry.detail?.episodes.first(where: { $0.episodeNumber == anchor.episodeNumber })?.title,
            !title.isEmpty
        else { return nil }
        return title
    }

    /// True only when metadata is loaded and lacks the episode, e.g. after TMDb renumbering.
    static func isStranded(_ anchor: EpisodeNoteAnchor, in entry: AnimeEntry) -> Bool {
        guard let count = count(in: entry, season: anchor.seasonNumber) else {
            let seasons = entry.detail?.seasons ?? []
            return entry.type.seasonNumber == nil && !seasons.isEmpty
                && !seasons.contains { $0.seasonNumber == anchor.seasonNumber }
        }
        return anchor.episodeNumber > count
    }

    static func watched(_ anchor: EpisodeNoteAnchor, in entry: AnimeEntry) -> Bool {
        (entry.episodeProgress(forSeason: anchor.seasonNumber)?.watchedThroughEpisode ?? 0) >= anchor.episodeNumber
    }

    static func defaultSeason(for entry: AnimeEntry) -> Int {
        entry.type.seasonNumber
            ?? entry.orderedEpisodeProgresses.last?.seasonNumber
            ?? entry.detail?.seasons.map(\.seasonNumber).filter { $0 > 0 }.min()
            ?? 1
    }

    /// The first unwritten episode after watched progress, wrapping to the start of the season.
    static func suggestion(for entry: AnimeEntry, excluding taken: Set<EpisodeNoteAnchor>) -> EpisodeNoteAnchor? {
        guard entry.supportsEpisodeNotes else { return nil }
        let season = defaultSeason(for: entry)
        let watched = entry.episodeProgress(forSeason: season)?.watchedThroughEpisode ?? 0
        let count = count(in: entry, season: season)
        let start = min(max(1, watched + 1), count ?? Int.max)
        let isFree = { (episode: Int) in
            !taken.contains(.init(seasonNumber: season, episodeNumber: episode))
        }
        guard let count else {
            var episode = start
            while !isFree(episode) { episode += 1 }
            return .init(seasonNumber: season, episodeNumber: episode)
        }
        let episode = (start...count).first(where: isFree) ?? (1..<start).first(where: isFree)
        return episode.map { .init(seasonNumber: season, episodeNumber: $0) }
    }
}

// MARK: - Overview

/// The read-only All view inside the notes box; selecting a section edits that note.
fileprivate struct EntryNotesOverview<Menu: View>: View {
    let entry: AnimeEntry
    let onSelect: (EntryNoteScope) -> Void
    let onExpand: () -> Void
    @ViewBuilder let menu: (EpisodeNoteAnchor) -> Menu

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        section(title: String(localized: "Overall"), text: entry.notes) { onSelect(.overall) }
                    }
                    ForEach(entry.episodeNotes.filter { !$0.isEmpty }) { note in
                        let title = EntryNoteLabels.title(note.anchor, entry: entry)
                        section(
                            title: [title.primary, title.secondary].compactMap(\.self).joined(separator: " · "),
                            text: note.text
                        ) { onSelect(.episode(note.anchor)) }
                        .contextMenu { menu(note.anchor) }
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack {
                Text("Select a note to edit")
                    .font(.caption2)
                    .foregroundStyle(EntryNotesStyle.tertiaryText)
                Spacer(minLength: 4)
                Button("Expand", systemImage: "arrow.up.left.and.arrow.down.right", action: onExpand)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 4)
        }
    }

    private func section(title: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(EntryNotesStyle.secondaryText)
                    .lineLimit(1)
                Text(verbatim: text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(EntryNoteSectionButtonStyle())
    }
}

/// Plain opacities instead of `.secondary`: the semantic styles render vibrantly on the
/// material box and are not drawn until a blur transition finishes.
enum EntryNotesStyle {
    static let secondaryText = Color.primary.opacity(0.5)
    static let tertiaryText = Color.primary.opacity(0.35)
}

struct EntryNoteSectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                .fill.tertiary.opacity(configuration.isPressed ? 1 : 0),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

fileprivate struct EntryNotesBoxStyle: ViewModifier {
    #if os(macOS)
        static let inset: CGFloat = 8
    #else
        static let inset: CGFloat = 10
    #endif

    func body(content: Content) -> some View {
        content
            #if os(macOS)
                .padding(Self.inset)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator, lineWidth: 0.5)
                }
            #else
                .padding(Self.inset)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.5)
                }
            #endif
    }
}

extension View {
    fileprivate func chipText() -> some View {
        font(.footnote.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
    }
}

/// Keep the detail host stable while a notes sheet owns a picker or unsaved draft.
struct EntryNotesPresentationLifecycle: ViewModifier {
    @Environment(EntryDetailSession.self) private var session: EntryDetailSession?

    func body(content: Content) -> some View {
        content
            .onAppear { session?.isPresentingNotes = true }
            .onDisappear { session?.isPresentingNotes = false }
    }
}
