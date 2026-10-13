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

    @Namespace private var selectionHighlight
    @State private var isReordering = false
    @State private var reorderSession = UUID()
    @State private var targetedCategoryID: LibraryCategory.ID?
    @State private var namePrompt: LibraryCategoryNamePrompt?
    @State private var deletingCategory: LibraryCategory?
    @State private var viewportWidth: CGFloat = 0

    private var selectedTabID: String { store.activeCategoryID ?? "all" }
    private var dragPrefix: String { "anishelf-category:\(reorderSession):" }

    private var minimumTabWidth: CGFloat {
        let tabCount = store.categories.count + 1
        // Share spare space equally; long names keep their intrinsic width and scroll.
        let spacing = CGFloat(tabCount - 1) * 4
        return max(64, (viewportWidth - 8 - spacing) / CGFloat(tabCount))
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        tab(id: nil, title: Text(LocalizedStringResource("All")))
                            .contextMenu { categoryMenu(for: nil) }
                            .id("all")

                        ForEach(store.categories) { category in
                            categoryTab(category)
                                .id(category.id)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollIndicators(.hidden)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.width
                } action: { width in
                    viewportWidth = width
                }
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
                .onChange(of: viewportWidth) {
                    proxy.scrollTo(selectedTabID, anchor: .center)
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
        .clipShape(.capsule)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
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
                        Capsule().fill(.tint.opacity(0.12))
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
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .frame(minWidth: minimumTabWidth, minHeight: 36)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.tint.opacity(0.14))
                            .matchedGeometryEffect(id: "selection", in: selectionHighlight)
                    }
                }
                // Keep the selection fill compact while the whole 44-point row is tappable.
                .padding(.vertical, 4)
                .contentShape(.rect)
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
