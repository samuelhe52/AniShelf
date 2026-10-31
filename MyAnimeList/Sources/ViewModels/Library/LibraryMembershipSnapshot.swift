//
//  LibraryMembershipSnapshot.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/31.
//

import DataProvider
import Foundation
import SwiftData

/// The inputs that decide which persisted rows the library exposes, independently of row content.
@MainActor
struct LibraryMembershipSnapshot {
    private var identities: [PersistentIdentifier: LibraryEntryIdentity] = [:]
    private var duplicateRanks: [PersistentIdentifier: DuplicateRank] = [:]

    init(entriesByIdentity: [LibraryEntryIdentity: [AnimeEntry]] = [:]) {
        for (identity, entries) in entriesByIdentity {
            for entry in entries {
                identities[entry.id] = identity
                if entries.count > 1 { duplicateRanks[entry.id] = DuplicateRank(entry) }
            }
        }
    }

    func requiresRefresh(
        after changes: ModelContextSaveChanges,
        resolveEntry: (PersistentIdentifier) throws -> AnimeEntry?
    ) rethrows -> Bool {
        if changes.invalidatedAllIdentifiers { return true }
        if changes.insertedIdentifiers.contains(where: Self.isEntry)
            || changes.deletedIdentifiers.contains(where: Self.isEntry)
        {
            return true
        }

        let updatedEntries = changes.updatedIdentifiers.filter(Self.isEntry)
        for id in updatedEntries {
            guard let entry = try resolveEntry(id) else { return true }
            if entry.onDisplay {
                if identities[id] != entry.libraryIdentity { return true }
            } else if identities[id] != nil {
                return true
            }
        }

        // A detail's presence and a season's parent can change the duplicate winner, even
        // when SwiftData reports only the inverse relationship's identifier as updated.
        let changed = changes.insertedIdentifiers.union(changes.updatedIdentifiers).union(changes.deletedIdentifiers)
        if !duplicateRanks.isEmpty,
            changed.contains(where: { Self.isEntry($0) || $0.entityName == "AnimeEntryDetail" })
        {
            for (id, previous) in duplicateRanks {
                guard let entry = try resolveEntry(id), entry.onDisplay, previous == DuplicateRank(entry) else {
                    return true
                }
            }
        }
        return false
    }

    private static func isEntry(_ id: PersistentIdentifier) -> Bool {
        id.entityName == "AnimeEntry"
    }

    /// Keep in step with `AnimeEntryDuplicateResolver.prefers`.
    private struct DuplicateRank: Equatable {
        let childSeasonCount: Int
        let hasDetail: Bool
        let dateSaved: Date
        let name: String

        init(_ entry: AnimeEntry) {
            childSeasonCount = entry.childSeasonEntries.count
            hasDetail = entry.detail != nil
            dateSaved = entry.dateSaved
            name = entry.name
        }
    }
}
