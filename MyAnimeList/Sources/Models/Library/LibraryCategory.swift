//
//  LibraryCategory.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/13.
//

import Foundation
import LibrarySync

/// A user-defined library category.
///
/// Definitions live in UserDefaults and the iCloud settings record; memberships live
/// on each `AnimeEntry` as `categoryIDs`. The order of the stored list is the display order.
struct LibraryCategory: Identifiable, Hashable, Sendable {
    typealias ID = String

    static let maximumNameLength = 40

    /// UUID string.
    ///
    /// IDs are never reused, so stale memberships of a deleted category stay inert.
    let id: ID
    var name: String

    init(id: ID = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Storage

extension LibraryCategory {
    private enum StorageKey {
        static let id = "id"
        static let name = "name"
    }

    /// Property-list form, so backups can serialize the list as JSON.
    var propertyListValue: [String: String] {
        [StorageKey.id: id, StorageKey.name: name]
    }

    init?(propertyListValue: [String: String]) {
        guard let id = propertyListValue[StorageKey.id], !id.isEmpty,
            let name = propertyListValue[StorageKey.name]
        else { return nil }
        self.init(id: id, name: name)
    }

    var syncObject: [String: LibrarySettingsSyncSnapshot.Value.JSONValue] {
        [StorageKey.id: .string(id), StorageKey.name: .string(name)]
    }

    init?(syncObject: [String: LibrarySettingsSyncSnapshot.Value.JSONValue]) {
        guard case .string(let id) = syncObject[StorageKey.id], !id.isEmpty,
            case .string(let name) = syncObject[StorageKey.name]
        else { return nil }
        self.init(id: id, name: name)
    }

    /// Drops duplicate IDs, keeping the first occurrence.
    static func deduplicated(_ categories: [LibraryCategory]) -> [LibraryCategory] {
        var seen = Set<ID>()
        return categories.filter { seen.insert($0.id).inserted }
    }
}
