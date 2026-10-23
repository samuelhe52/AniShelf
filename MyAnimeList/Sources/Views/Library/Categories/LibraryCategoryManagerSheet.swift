//
//  LibraryCategoryManagerSheet.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/13.
//

import SwiftUI

#if !os(macOS)
    /// Creates, renames, deletes, and reorders library categories.
    ///
    /// Anime join categories through multi-selection in List or Grid, not here. The Mac
    /// counterpart is `MacLibraryCategoryManagerSheet`.
    struct LibraryCategoryManagerSheet: View {
        @Environment(LibraryStore.self) private var store
        @Environment(\.dismiss) private var dismiss

        @State private var namePrompt: LibraryCategoryNamePrompt?
        @State private var deletingCategory: LibraryCategory?

        var body: some View {
            let counts = store.categoryEntryCounts
            return NavigationStack {
                List {
                    Section {
                        ForEach(store.categories) { category in
                            Button {
                                namePrompt = .init(purpose: .rename(category))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.name)
                                        .foregroundStyle(.primary)
                                    Text("\(counts[category.id, default: 0]) anime")
                                        .font(.subheadline)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("Renames the category"))
                            .swipeActions(edge: .trailing) {
                                // Not `.destructive`: that role removes the row before the user confirms.
                                Button("Delete", systemImage: "trash") {
                                    deletingCategory = category
                                }
                                .tint(.red)
                                Button("Rename", systemImage: "pencil") {
                                    namePrompt = .init(purpose: .rename(category))
                                }
                            }
                        }
                        .onMove { source, destination in
                            store.moveCategories(fromOffsets: source, toOffset: destination)
                        }
                    } footer: {
                        // The empty state already explains how to add anime.
                        if !store.categories.isEmpty {
                            Text("Add anime with Select in List or Grid view. Touch and hold to reorder categories.")
                        }
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
                .contentMargins(.top, 8, for: .scrollContent)
                .navigationTitle("Categories")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: dismiss.callAsFunction) {
                            SheetCloseLabel()
                        }
                        .accessibilityLabel(Text("Close"))
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Category", systemImage: "plus") {
                            namePrompt = .init(purpose: .create(memberCount: 0))
                        }
                    }
                }
                .libraryCategoryEditing(namePrompt: $namePrompt, deletingCategory: $deletingCategory)
            }
        }
    }
#endif

extension View {
    /// The rename/create prompt and delete confirmation both category managers share.
    func libraryCategoryEditing(
        namePrompt: Binding<LibraryCategoryNamePrompt?>,
        deletingCategory: Binding<LibraryCategory?>
    ) -> some View {
        modifier(CategoryEditingModifier(namePrompt: namePrompt, deletingCategory: deletingCategory))
    }
}

fileprivate struct CategoryEditingModifier: ViewModifier {
    @Environment(LibraryStore.self) private var store
    @Binding var namePrompt: LibraryCategoryNamePrompt?
    @Binding var deletingCategory: LibraryCategory?

    func body(content: Content) -> some View {
        content
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
