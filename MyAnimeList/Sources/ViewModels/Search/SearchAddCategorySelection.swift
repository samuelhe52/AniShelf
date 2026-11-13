//
//  SearchAddCategorySelection.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/13.
//

import Foundation

enum SearchAddCategoryDefault: String, CaseIterable {
    case noCategory
    case currentCategory

    var title: LocalizedStringResource {
        switch self {
        case .noCategory: "No Category"
        case .currentCategory: "Current Category"
        }
    }
}

/// A search session owns its destination independently of later window or preference changes.
struct SearchAddCategorySelection {
    var categoryID: LibraryCategory.ID?

    init(defaultRule: SearchAddCategoryDefault, currentCategoryID: LibraryCategory.ID?) {
        categoryID = defaultRule == .currentCategory ? currentCategoryID : nil
    }

}
