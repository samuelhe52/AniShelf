//
//  MacLibraryCategoryManagerSheet.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

import SwiftUI

#if os(macOS)
    /// Creates, renames, deletes, and reorders library categories in a fixed-width Mac sheet.
    ///
    /// Anime join categories through multi-selection in List or Grid, not here.
    struct MacLibraryCategoryManagerSheet: View {
        @Environment(LibraryStore.self) private var store
        @Environment(\.dismiss) private var dismiss

        @State private var namePrompt: LibraryCategoryNamePrompt?
        @State private var deletingCategory: LibraryCategory?
        @State private var selection: LibraryCategory.ID?

        var body: some View {
            content
                .libraryCategoryEditing(namePrompt: $namePrompt, deletingCategory: $deletingCategory)
        }

        private var content: some View {
            let counts = store.categoryEntryCounts
            return VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Categories")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button(LocalizedStringResource("New Category…"), systemImage: "plus") {
                        namePrompt = .init(purpose: .create(memberCount: 0))
                    }
                    .buttonStyle(.bordered)
                }

                Text(LocalizedStringResource("Select anime in List or Grid view, then choose Category in the toolbar."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    List(selection: $selection) {
                        ForEach(store.categories) { category in
                            HStack(spacing: 10) {
                                Image(systemName: "folder")
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                                Text(verbatim: category.name)
                                    .lineLimit(1)
                                Spacer(minLength: 12)
                                Text("\(counts[category.id, default: 0]) anime")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .tag(category.id)
                            .accessibilityHint(
                                Text(LocalizedStringResource("Double-click to rename. Drag to reorder.")))
                        }
                        .onMove { source, destination in
                            store.moveCategories(fromOffsets: source, toOffset: destination)
                        }
                    }
                    .listStyle(.inset)
                    .environment(\.defaultMinListRowHeight, 44)
                    .scrollContentBackground(.hidden)
                    // Show a few rows without making a small collection fill a large sheet.
                    // Larger collections scroll within the same bounded list.
                    .frame(height: CGFloat(min(max(store.categories.count, 3), 7)) * 44 + 16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
                    .contextMenu(forSelectionType: LibraryCategory.ID.self) { ids in
                        if let category = category(in: ids) {
                            Button("Rename…", systemImage: "pencil") {
                                namePrompt = .init(purpose: .rename(category))
                            }
                            Button("Delete Category…", systemImage: "trash", role: .destructive) {
                                deletingCategory = category
                            }
                        }
                    } primaryAction: { ids in
                        if let category = category(in: ids) {
                            namePrompt = .init(purpose: .rename(category))
                        }
                    }
                    .onDeleteCommand {
                        deletingCategory = selectedCategory
                    }
                    .overlay {
                        if store.categories.isEmpty {
                            ContentUnavailableView {
                                Label("No Categories", systemImage: "folder")
                            }
                        }
                    }

                    if !store.categories.isEmpty {
                        Text(LocalizedStringResource("Double-click to rename. Drag to reorder."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    Button(LocalizedStringResource("Rename…"), systemImage: "pencil") {
                        if let category = selectedCategory {
                            namePrompt = .init(purpose: .rename(category))
                        }
                    }
                    .disabled(selectedCategory == nil)

                    Button(LocalizedStringResource("Delete…"), systemImage: "trash", role: .destructive) {
                        deletingCategory = selectedCategory
                    }
                    .disabled(selectedCategory == nil)

                    Spacer()

                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(width: 480)
            .fixedSize(horizontal: false, vertical: true)
            .onExitCommand { dismiss() }
        }

        private var selectedCategory: LibraryCategory? {
            selection.flatMap { id in store.categories.first { $0.id == id } }
        }

        private func category(in ids: Set<LibraryCategory.ID>) -> LibraryCategory? {
            guard ids.count == 1, let id = ids.first else { return nil }
            return store.categories.first { $0.id == id }
        }
    }
#endif
