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
    #if os(macOS)
        @State private var selection: LibraryCategory.ID?
    #endif

    var body: some View {
        #if os(macOS)
            macBody
                .categoryEditing(namePrompt: $namePrompt, deletingCategory: $deletingCategory)
        #else
            mobileBody
        #endif
    }

    #if os(macOS)
        private var macBody: some View {
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
    #else
        private var mobileBody: some View {
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
                .categoryEditing(namePrompt: $namePrompt, deletingCategory: $deletingCategory)
            }
        }
    #endif
}

extension View {
    fileprivate func categoryEditing(
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
