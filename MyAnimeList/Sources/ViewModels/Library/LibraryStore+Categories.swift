//
//  LibraryStore+Categories.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/13.
//

import Foundation

extension LibraryStore {
    var knownCategoryIDs: Set<LibraryCategory.ID> {
        Set(categories.map(\.id))
    }

    /// Number of library entries in each category.
    ///
    /// IDs of deleted categories are not counted.
    var categoryEntryCounts: [LibraryCategory.ID: Int] {
        let known = knownCategoryIDs
        var counts: [LibraryCategory.ID: Int] = [:]
        for entry in library {
            for id in entry.categoryIDs where known.contains(id) {
                counts[id, default: 0] += 1
            }
        }
        return counts
    }

    /// Returns the trimmed name, or `nil` when it is empty, too long, or already taken
    /// by another category (ignoring case).
    func validatedCategoryName(
        _ rawName: String,
        excluding excludedID: LibraryCategory.ID? = nil
    ) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= LibraryCategory.maximumNameLength else { return nil }
        let isTaken = categories.contains {
            $0.id != excludedID && $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }
        return isTaken ? nil : name
    }

    @discardableResult
    func createCategory(named rawName: String) -> LibraryCategory? {
        guard let name = validatedCategoryName(rawName) else { return nil }
        let category = LibraryCategory(name: name)
        categories.append(category)
        return category
    }

    @discardableResult
    func renameCategory(_ id: LibraryCategory.ID, to rawName: String) -> Bool {
        guard let index = categories.firstIndex(where: { $0.id == id }),
            let name = validatedCategoryName(rawName, excluding: id)
        else { return false }
        guard categories[index].name != name else { return true }
        categories[index].name = name
        return true
    }

    /// Removes only the definition.
    ///
    /// Entries keep the stale ID: reads ignore unknown IDs,
    /// and the next membership write on an entry drops them. This avoids rewriting and
    /// re-uploading every member entry.
    func deleteCategory(_ id: LibraryCategory.ID) {
        categories.removeAll { $0.id == id }
    }

    func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = categories
        reordered.move(fromOffsets: source, toOffset: destination)
        guard reordered != categories else { return }
        categories = reordered
    }

    /// Moves a category to the position of `targetID`, used by drag in the strip.
    func moveCategory(_ id: LibraryCategory.ID, to targetID: LibraryCategory.ID) {
        guard id != targetID,
            let sourceIndex = categories.firstIndex(where: { $0.id == id }),
            let targetIndex = categories.firstIndex(where: { $0.id == targetID })
        else { return }
        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        moveCategories(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
    }
}
