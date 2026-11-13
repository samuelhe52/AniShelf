//
//  SearchAddCategoryPicker.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/13.
//

import SwiftUI

/// Regular and batch search edit the same session-owned destination.
struct SearchAddCategoryPicker: View {
    @Environment(LibraryStore.self) private var store
    @Binding var categoryID: LibraryCategory.ID?

    var body: some View {
        let selectedCategory = store.category(for: categoryID)
        if store.categoriesEnabled {
            Menu {
                Picker(
                    "Add to Category",
                    selection: Binding(get: { selectedCategory?.id }, set: { categoryID = $0 })
                ) {
                    Text("No Category").tag(nil as LibraryCategory.ID?)
                    ForEach(store.categories) { category in
                        Text(verbatim: category.name).tag(Optional(category.id))
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    if let selectedCategory {
                        Text(verbatim: selectedCategory.name)
                    } else {
                        Text("No Category")
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .lineLimit(1)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Add to Category")
            .accessibilityValue(
                Text(
                    verbatim: selectedCategory?.name
                        ?? String(localized: "No Category")))
        }
    }

}
