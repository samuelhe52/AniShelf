//
//  EpisodeNote.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/26.
//

import Foundation
import Synchronization

/// A stable, metadata-independent episode anchor. Season zero denotes specials.
public struct EpisodeNoteAnchor: Codable, Hashable, Comparable, Sendable, Identifiable {
    public var seasonNumber: Int
    public var episodeNumber: Int
    public var id: Self { self }

    public init(seasonNumber: Int, episodeNumber: Int) {
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }

    /// Unlocalized label for copied text and exports, e.g. "S1 E4" or "SP E2".
    public var plainTextLabel: String {
        "\(seasonNumber == 0 ? "SP" : "S\(seasonNumber)") E\(episodeNumber)"
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.seasonNumber != rhs.seasonNumber { return lhs.seasonNumber < rhs.seasonNumber }
        return lhs.episodeNumber < rhs.episodeNumber
    }
}

/// Empty text is a clocked deletion, retained to prevent stale-device resurrection.
public struct EpisodeNote: Codable, Equatable, Sendable, Identifiable {
    public var anchor: EpisodeNoteAnchor
    public var text: String
    public var updatedAt: Date
    public var id: EpisodeNoteAnchor { anchor }
    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public init(anchor: EpisodeNoteAnchor, text: String, updatedAt: Date = .now) {
        self.anchor = anchor
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
        self.updatedAt = LibrarySyncTimestamp.normalized(updatedAt)
    }

    /// Deterministic, commutative merge. Deletion wins an equal-clock conflict;
    /// otherwise a stable text order breaks ties between two concurrent edits.
    public static func merged(_ lhs: [Self], _ rhs: [Self]) -> [Self] {
        var notes: [EpisodeNoteAnchor: Self] = [:]
        for value in lhs + rhs where value.anchor.seasonNumber >= 0 && value.anchor.episodeNumber > 0 {
            let note = Self(anchor: value.anchor, text: value.text, updatedAt: value.updatedAt)
            if let existing = notes[note.anchor] {
                if existing.updatedAt > note.updatedAt { continue }
                if existing.updatedAt == note.updatedAt {
                    if existing.isEmpty { continue }
                    if !note.isEmpty && existing.text >= note.text { continue }
                }
            }
            notes[note.anchor] = note
        }
        return notes.values.sorted { $0.anchor < $1.anchor }
    }
}

/// The most recently decoded payload. Views look notes up one anchor at a time, so
/// reusing it keeps a render pass from decoding the whole payload per lookup.
fileprivate struct DecodedEpisodeNotes: Sendable {
    let data: Data
    let notes: [EpisodeNote]
    let notesByAnchor: [EpisodeNoteAnchor: EpisodeNote]
}

fileprivate let lastDecodedEpisodeNotes = Mutex<DecodedEpisodeNotes?>(nil)

extension AnimeEntry {
    private var decodedEpisodeNotes: DecodedEpisodeNotes? {
        guard let episodeNotesData else { return nil }
        if let cached = lastDecodedEpisodeNotes.withLock({ $0 }), cached.data == episodeNotesData {
            return cached
        }
        let notes = EpisodeNote.merged(
            (try? JSONDecoder().decode([EpisodeNote].self, from: episodeNotesData)) ?? [], [])
        let decoded = DecodedEpisodeNotes(
            data: episodeNotesData,
            notes: notes,
            notesByAnchor: Dictionary(uniqueKeysWithValues: notes.map { ($0.anchor, $0) })
        )
        lastDecodedEpisodeNotes.withLock { $0 = decoded }
        return decoded
    }

    /// Storage on this concrete row, used by sync. Season UI uses `episodeNotes`.
    public var storedEpisodeNotes: [EpisodeNote] {
        get { decodedEpisodeNotes?.notes ?? [] }
        set {
            let notes = EpisodeNote.merged(newValue, [])
            // These values contain only integers, finite normalized dates, and strings.
            episodeNotesData = notes.isEmpty ? nil : try! JSONEncoder().encode(notes)
        }
    }

    /// The series row that stores episode notes. Seasons have none while their
    /// parent is missing; metadata refresh restores the parent.
    public var episodeNoteOwner: AnimeEntry? {
        switch type {
        case .movie: nil
        case .series: self
        case .season: parentSeriesEntry
        }
    }

    public var supportsEpisodeNotes: Bool { episodeNoteOwner != nil }

    /// Includes deletion markers for replay; filter `isEmpty` when rendering.
    public var episodeNotes: [EpisodeNote] {
        guard let notes = episodeNoteOwner?.storedEpisodeNotes else { return [] }
        if let season = type.seasonNumber { return notes.filter { $0.anchor.seasonNumber == season } }
        return notes
    }

    public func episodeNote(at anchor: EpisodeNoteAnchor) -> EpisodeNote? {
        guard type.seasonNumber == nil || type.seasonNumber == anchor.seasonNumber else { return nil }
        return episodeNoteOwner?.decodedEpisodeNotes?.notesByAnchor[anchor]
    }

    @discardableResult
    public func updateEpisodeNote(at anchor: EpisodeNoteAnchor, text: String, date: Date = .now) -> Bool {
        guard let owner = episodeNoteOwner, anchor.seasonNumber >= 0, anchor.episodeNumber > 0,
            type.seasonNumber == nil || type.seasonNumber == anchor.seasonNumber
        else { return false }
        let current = episodeNote(at: anchor)
        let resolvedText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
        guard (current?.text ?? "") != resolvedText else { return false }
        let note = EpisodeNote(
            anchor: anchor,
            text: resolvedText,
            updatedAt: LibrarySyncTimestamp.next(date, after: current?.updatedAt)
        )
        owner.storedEpisodeNotes = EpisodeNote.merged(owner.storedEpisodeNotes, [note])
        return true
    }

    /// Reverting is a new edit, so already-synced deletions/rewrites cannot win later.
    /// A season restore touches only that season; other seasons remain intact.
    public func restoreEpisodeNotes(_ original: [EpisodeNote], at date: Date = .now) {
        let originals = Dictionary(uniqueKeysWithValues: EpisodeNote.merged(original, []).map { ($0.anchor, $0.text) })
        let anchors = Set(episodeNotes.map(\.anchor)).union(originals.keys)
        for anchor in anchors {
            updateEpisodeNote(at: anchor, text: originals[anchor] ?? "", date: date)
        }
    }
}
