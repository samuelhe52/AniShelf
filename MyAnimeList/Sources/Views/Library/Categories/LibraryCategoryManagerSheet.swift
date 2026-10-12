//
//  LibraryCategoryManagerSheet.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/13.
//

import SwiftUI

/// Creates, renames, deletes, and reorders library categories.
///
/// Anime join categories through multi-selection in List or Grid, not here.
struct LibraryCategoryManagerSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var namePrompt: LibraryCategoryNamePrompt?
    @State private var deletingCategory: LibraryCategory?

    var body: some View {
        let counts = store.categoryEntryCounts
        NavigationStack {
            List {
                Section {
                    ForEach(store.categories) { category in
                        Button {
                            namePrompt = .init(purpose: .rename(category))
                        } label: {
                            HStack {
                                Text(category.name)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 12)
                                Text("\(counts[category.id, default: 0])")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Renames the category"))
                    }
                    .onMove { source, destination in
                        store.moveCategories(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        guard let index = offsets.first, store.categories.indices.contains(index) else { return }
                        deletingCategory = store.categories[index]
                    }
                } footer: {
                    Text("Add anime with Select in List or Grid view. Drag to reorder categories.")
                }
            }
            .overlay {
                if store.categories.isEmpty {
                    ContentUnavailableView {
                        Label("No Categories", systemImage: "folder")
                    } description: {
                        Text("Select anime in List or Grid view to create a category from them.")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New Category", systemImage: "plus") {
                        namePrompt = .init(purpose: .create(memberCount: 0))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .libraryCategoryNamePrompt($namePrompt) { prompt, name in
                switch prompt.purpose {
                case .create:
                    withAnimation { _ = store.createCategory(named: name) }
                case .rename(let category):
                    store.renameCategory(category.id, to: name)
                }
            }
            .libraryCategoryDeleteConfirmation($deletingCategory)
        }
    }
}
