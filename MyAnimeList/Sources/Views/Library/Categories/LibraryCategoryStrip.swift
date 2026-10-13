//
//  LibraryCategoryStrip.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/10/13.
//

import SwiftUI

/// A pinned category switcher.
///
/// Its lifetime follows the library's browse mode,
/// so leaving List/Grid or entering multi-selection also ends reordering.
struct LibraryCategoryStrip: View {
    @Environment(LibraryStore.self) private var store
    let openCategoryManager: () -> Void

    @Namespace private var selectionUnderline
    @State private var isReordering = false
    @State private var reorderSession = UUID()
    @State private var targetedCategoryID: LibraryCategory.ID?
    @State private var namePrompt: LibraryCategoryNamePrompt?
    @State private var deletingCategory: LibraryCategory?

    private var selectedTabID: String { store.activeCategoryID ?? "all" }
    private var dragPrefix: String { "anishelf-category:\(reorderSession):" }

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 20) {
                        tab(id: nil, title: Text(LocalizedStringResource("All")))
                            .contextMenu { categoryMenu(for: nil) }
                            .id("all")

                        ForEach(store.categories) { category in
                            categoryTab(category)
                                .id(category.id)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollIndicators(.hidden)
                .onChange(of: store.activeCategoryID, initial: true) {
                    withAnimation(.snappy) {
                        proxy.scrollTo(selectedTabID, anchor: .center)
                    }
                }
                .onChange(of: store.categories) {
                    withAnimation(.snappy) {
                        proxy.scrollTo(selectedTabID, anchor: .center)
                    }
                }
                .onChange(of: isReordering) {
                    withAnimation(.snappy) {
                        proxy.scrollTo(selectedTabID, anchor: .center)
                    }
                }
            }

            if isReordering {
                Button(LocalizedStringResource("Done")) {
                    withAnimation(.snappy) {
                        isReordering = false
                        targetedCategoryID = nil
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
            }
        }
        .background(.bar)
        .animation(.snappy, value: store.activeCategoryID)
        .animation(.snappy, value: store.categories)
        .libraryCategoryNamePrompt($namePrompt) { prompt, name in
            if case .rename(let category) = prompt.purpose {
                store.renameCategory(category.id, to: name)
            }
        }
        .libraryCategoryDeleteConfirmation($deletingCategory)
    }

    @ViewBuilder
    private func categoryTab(_ category: LibraryCategory) -> some View {
        if isReordering {
            tab(id: category.id, title: Text(category.name))
                .background {
                    if targetedCategoryID == category.id {
                        Rectangle().fill(.tint.opacity(0.12))
                    }
                }
                .draggable(dragPrefix + category.id)
                .dropDestination(for: String.self) { items, _ in
                    // Commit only on drop: cancelled drags never change persisted order.
                    // A per-mode token rejects text and drags from another window/session.
                    guard isReordering, items.count == 1,
                        let payload = items.first, payload.hasPrefix(dragPrefix)
                    else { return false }
                    let sourceID = String(payload.dropFirst(dragPrefix.count))
                    guard store.categories.contains(where: { $0.id == sourceID }),
                        store.categories.contains(where: { $0.id == category.id })
                    else { return false }
                    withAnimation(.snappy) {
                        store.moveCategory(sourceID, to: category.id)
                        targetedCategoryID = nil
                    }
                    return true
                } isTargeted: { targeted in
                    if targeted {
                        targetedCategoryID = category.id
                    } else if targetedCategoryID == category.id {
                        targetedCategoryID = nil
                    }
                }
                .accessibilityHint(Text(LocalizedStringResource("Drag onto another category to reorder.")))
        } else {
            tab(id: category.id, title: Text(category.name))
                .contextMenu { categoryMenu(for: category) }
        }
    }

    private func tab(id: LibraryCategory.ID?, title: Text) -> some View {
        let isSelected = store.activeCategoryID == id
        return Button {
            withAnimation(.snappy) { store.activeCategoryID = id }
        } label: {
            title
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 2)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    if isSelected {
                        UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                            .fill(.tint)
                            .frame(height: 3)
                            .matchedGeometryEffect(id: "selection", in: selectionUnderline)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func categoryMenu(for category: LibraryCategory?) -> some View {
        Button(LocalizedStringResource("Reorder"), systemImage: "arrow.left.arrow.right") {
            withAnimation(.snappy) {
                reorderSession = UUID()
                isReordering = true
            }
        }
        if let category {
            Button(LocalizedStringResource("Rename"), systemImage: "pencil") {
                namePrompt = .init(purpose: .rename(category))
            }
        }
        Button(LocalizedStringResource("Edit Categories…"), systemImage: "list.bullet") {
            isReordering = false
            openCategoryManager()
        }
        if let category {
            Button(LocalizedStringResource("Delete"), systemImage: "trash", role: .destructive) {
                deletingCategory = category
            }
        }
    }
}
