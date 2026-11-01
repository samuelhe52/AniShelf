//
//  LibraryCategoryStrip.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/10/13.
//

import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// A pinned category switcher.
///
/// Its lifetime follows the library's browse mode,
/// so leaving List/Grid or entering multi-selection also ends reordering.
struct LibraryCategoryStrip: View {
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryBrowseScope.self) private var scope
    let openCategoryManager: () -> Void
    let allowsCategoryActions: Bool

    @Binding var isReordering: Bool

    @State private var draftOrder: [LibraryCategory.ID]?
    @State private var draggedCategoryID: LibraryCategory.ID?
    @State private var draggedCenter: CGFloat = 0
    @State private var fingerOffset: CGFloat = 0
    @State private var fingerLocation: CGFloat = 0
    @State private var tabWidths: [String: CGFloat] = [:]
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollOffset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @Namespace private var viewport
    @State private var namePrompt: LibraryCategoryNamePrompt?
    @State private var deletingCategory: LibraryCategory?
    @State private var viewportWidth: CGFloat = 0

    private var selectedTabID: String { scope.activeCategoryID ?? "all" }
    private var reorderAnimation: Animation { .bouncy }
    private var displayedCategories: [LibraryCategory] {
        guard let draftOrder else { return store.categories }
        let categories = Dictionary(uniqueKeysWithValues: store.categories.map { ($0.id, $0) })
        return draftOrder.compactMap { categories[$0] }
    }

    private var minimumTabWidth: CGFloat {
        let tabCount = store.categories.count + 1
        // Share spare space equally; long names keep their intrinsic width and scroll.
        let spacing = CGFloat(tabCount - 1) * 4
        return max(64, (viewportWidth - 8 - spacing) / CGFloat(tabCount))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    if isReordering {
                        tabLabel(Text("All"), isSelected: scope.activeCategoryID == nil)
                            .accessibilityAddTraits(scope.activeCategoryID == nil ? .isSelected : [])
                            .measureTabWidth("all", in: $tabWidths)
                            .id("all")
                    } else {
                        menuTab(nil, title: Text("All"))
                            .measureTabWidth("all", in: $tabWidths)
                            .id("all")
                    }

                    ForEach(displayedCategories) { category in
                        categoryTab(category)
                            .measureTabWidth(category.id, in: $tabWidths)
                            .offset(x: draggedCategoryID == category.id ? draggedCenter - tabCenter(category.id) : 0)
                            .zIndex(draggedCategoryID == category.id ? 1 : 0)
                            .transaction { transaction in
                                // The held tab tracks the finger while its neighbors animate.
                                if draggedCategoryID == category.id { transaction.animation = nil }
                            }
                            .id(category.id)
                    }
                }
                .background(alignment: .leading) { selectionHighlight }
                .padding(.horizontal, 4)
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollIndicators(.hidden)
            .scrollPosition($scrollPosition)
            .scrollDisabled(draggedCategoryID != nil)
            .onScrollGeometryChange(for: CategoryScrollGeometry.self) { geometry in
                CategoryScrollGeometry(offset: geometry.contentOffset.x, width: geometry.contentSize.width)
            } action: { _, geometry in
                scrollOffset = geometry.offset
                contentWidth = geometry.width
                updateDraftOrder()
            }
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { width in
                viewportWidth = width
            }
            .coordinateSpace(name: viewport)
            .gesture(
                CategoryReorderGesture(
                    isEnabled: isReordering && allowsCategoryActions,
                    coordinateSpace: viewport,
                    canBegin: { point in category(at: point.x) != nil },
                    began: beginDrag,
                    moved: moveDrag,
                    ended: { finishDrag(commit: $0) }
                )
            )
            .onChange(of: scope.activeCategoryID, initial: true) {
                withAnimation(.snappy) { proxy.scrollTo(selectedTabID, anchor: .center) }
            }
            .onChange(of: store.categories) {
                // A remote/window edit invalidates the draft instead of overwriting it.
                finishDrag(commit: false)
                if !isReordering {
                    withAnimation(.snappy) { proxy.scrollTo(selectedTabID, anchor: .center) }
                }
            }
            .onChange(of: isReordering) {
                finishDrag(commit: false)
                withAnimation(.snappy) { proxy.scrollTo(selectedTabID, anchor: .center) }
            }
            .onChange(of: viewportWidth) {
                if draggedCategoryID == nil { proxy.scrollTo(selectedTabID, anchor: .center) }
            }
        }
        .clipShape(.capsule)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .animation(.snappy, value: scope.activeCategoryID)
        .animation(reorderAnimation, value: store.categories)
        // Keep page-style transactions out of the strip's glass subtree.
        .animation(nil, value: scope.viewStyle)
        .sensoryFeedback(.impact(weight: .light), trigger: draggedCategoryID) { _, newValue in
            newValue != nil
        }
        .task(id: draggedCategoryID) {
            while draggedCategoryID != nil && !Task.isCancelled {
                edgeScroll()
                do { try await Task.sleep(for: .milliseconds(16)) } catch { break }
            }
        }
        .onDisappear { finishDrag(commit: false) }
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
            tabLabel(Text(category.name), isSelected: scope.activeCategoryID == category.id)
                .modifier(CategoryTabWiggle(isActive: draggedCategoryID != category.id))
                .accessibilityAddTraits(scope.activeCategoryID == category.id ? .isSelected : [])
                .accessibilityHint(Text("Hold and drag to reorder."))
                .accessibilityAction(named: Text("Move Left")) {
                    moveAccessibly(category.id, by: -1)
                }
                .accessibilityAction(named: Text("Move Right")) {
                    moveAccessibly(category.id, by: 1)
                }
        } else {
            menuTab(category, title: Text(category.name))
        }
    }

    /// Tap selects; long press opens the category actions.
    private func menuTab(_ category: LibraryCategory?, title: Text) -> some View {
        let isSelected = scope.activeCategoryID == category?.id
        return Button {
            select(category?.id)
        } label: {
            tabLabel(title, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .contextMenu {
            // Selection mode keeps category switching without long-press actions.
            if allowsCategoryActions {
                categoryMenu(for: category)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ id: LibraryCategory.ID?) {
        withAnimation(.snappy) { scope.activeCategoryID = id }
    }

    private func tabLabel(_ title: Text, isSelected: Bool) -> some View {
        title
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .frame(minWidth: minimumTabWidth, minHeight: 36)
            // Keep the selection fill compact while the whole 44-point row is tappable.
            .padding(.vertical, 4)
            .contentShape(.rect)
    }

    /// One capsule slides between the tabs.
    ///
    /// Not a `matchedGeometryEffect`: with one on screen, the library's view-style switch lost
    /// its page transitions, so the incoming page popped in.
    private var selectionHighlight: some View {
        let width = tabWidth(selectedTabID)
        let isDragged = draggedCategoryID != nil && draggedCategoryID == scope.activeCategoryID
        // The row's leading padding sits outside this background.
        let minX = isDragged ? draggedCenter + scrollOffset - 4 - width / 2 : tabMinX(selectedTabID)
        return Capsule()
            .fill(.tint.opacity(0.14))
            .frame(width: width, height: 36)
            .offset(x: minX)
            .opacity(tabWidths[selectedTabID] == nil ? 0 : 1)
            .transaction { transaction in
                if isDragged { transaction.animation = nil }
            }
    }

    private func tabWidth(_ id: String) -> CGFloat {
        tabWidths[id] ?? minimumTabWidth
    }

    /// The tab's leading edge within the tab row, before the row's padding.
    private func tabMinX(_ id: String) -> CGFloat {
        var x: CGFloat = 0
        for tabID in ["all"] + displayedCategories.map(\.id) {
            if tabID == id { return x }
            x += tabWidth(tabID) + 4
        }
        return x
    }

    private func tabCenter(_ id: LibraryCategory.ID) -> CGFloat {
        4 + tabMinX(id) + tabWidth(id) / 2 - scrollOffset
    }

    private func category(at x: CGFloat) -> LibraryCategory? {
        displayedCategories.first { category in
            let halfWidth = (tabWidths[category.id] ?? minimumTabWidth) / 2
            return abs(tabCenter(category.id) - x) <= halfWidth
        }
    }

    private func beginDrag(_ point: CGPoint) {
        guard isReordering, let category = category(at: point.x) else { return }
        draftOrder = store.categories.map(\.id)
        draggedCenter = tabCenter(category.id)
        fingerOffset = draggedCenter - point.x
        fingerLocation = point.x
        draggedCategoryID = category.id
    }

    private func moveDrag(_ point: CGPoint) {
        guard draggedCategoryID != nil else { return }
        fingerLocation = point.x
        draggedCenter = point.x + fingerOffset
        updateDraftOrder()
    }

    private func updateDraftOrder() {
        guard let draggedCategoryID, var order = draftOrder,
            let source = order.firstIndex(of: draggedCategoryID)
        else { return }
        // Compare stable layout centers, never animated presentation frames.
        // Only cross a neighbor's center to prevent oscillation at slot boundaries.
        var destination = source
        for (index, id) in order.enumerated() where id != draggedCategoryID {
            let center = tabCenter(id)
            if index < source && draggedCenter < center { destination = min(destination, index) }
            if index > source && draggedCenter > center { destination = max(destination, index) }
        }
        guard destination != source else { return }
        order.remove(at: source)
        order.insert(draggedCategoryID, at: destination)
        withAnimation(reorderAnimation) { draftOrder = order }
    }

    private func edgeScroll() {
        guard draggedCategoryID != nil else { return }
        let edge: CGFloat = 28
        let delta: CGFloat
        if fingerLocation < edge {
            delta = -3
        } else if fingerLocation > viewportWidth - edge {
            delta = 3
        } else {
            return
        }
        let offset = min(max(0, scrollOffset + delta), max(0, contentWidth - viewportWidth))
        if offset != scrollOffset { scrollPosition.scrollTo(x: offset) }
    }

    private func finishDrag(commit: Bool) {
        let id = draggedCategoryID
        let order = draftOrder
        withAnimation(reorderAnimation) {
            draggedCategoryID = nil
            draftOrder = nil
            if commit, let id, let order,
                Set(order) == Set(store.categories.map(\.id)),
                let destination = order.firstIndex(of: id)
            {
                store.moveCategory(id, to: store.categories[destination].id)
            }
        }
    }

    private func moveAccessibly(_ id: LibraryCategory.ID, by offset: Int) {
        guard draggedCategoryID == nil,
            let index = store.categories.firstIndex(where: { $0.id == id }),
            store.categories.indices.contains(index + offset)
        else { return }
        withAnimation(reorderAnimation) { store.moveCategory(id, to: store.categories[index + offset].id) }
        withAnimation(.snappy) { scrollPosition.scrollTo(id: id, anchor: .center) }
    }

    @ViewBuilder
    private func categoryMenu(for category: LibraryCategory?) -> some View {
        Section {
            if let category {
                Button("Rename", systemImage: "pencil") {
                    namePrompt = .init(purpose: .rename(category))
                }
            }
            Button("Edit Categories…", systemImage: "list.bullet") {
                isReordering = false
                openCategoryManager()
            }
            if let category {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    deletingCategory = category
                }
            }
        }
        Section {
            Button("Reorder Tabs", systemImage: "arrow.left.arrow.right") {
                withAnimation(.snappy) { isReordering = true }
            }
            .disabled(store.categories.count < 2)
        }
    }
}

fileprivate struct CategoryScrollGeometry: Equatable {
    let offset: CGFloat
    let width: CGFloat
}

fileprivate struct CategoryTabWiggle: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content.phaseAnimator([-1.0, 1.0]) { content, phase in
            content.rotationEffect(.degrees(isActive ? phase * 1.2 : 0))
        } animation: { _ in
            .easeInOut(duration: 0.13)
        }
    }
}

extension View {
    fileprivate func measureTabWidth(_ id: String, in widths: Binding<[String: CGFloat]>) -> some View {
        onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            widths.wrappedValue[id] = width
        }
    }
}

/// A short hold claims the pan; swiping before the hold still scrolls normally.
#if os(macOS)
    fileprivate struct CategoryReorderGesture: Gesture {
        let isEnabled: Bool
        let coordinateSpace: Namespace.ID
        let canBegin: (CGPoint) -> Bool
        let began: (CGPoint) -> Void
        let moved: (CGPoint) -> Void
        let ended: (Bool) -> Void
        @State private var dragging = false

        var body: some Gesture {
            DragGesture(minimumDistance: 4, coordinateSpace: .named(coordinateSpace))
                .onChanged { value in
                    guard isEnabled, canBegin(value.startLocation) else { return }
                    if !dragging {
                        dragging = true
                        began(value.startLocation)
                    }
                    moved(value.location)
                }
                .onEnded { _ in
                    guard dragging else { return }
                    dragging = false
                    ended(true)
                }
        }
    }
#else
    fileprivate struct CategoryReorderGesture: UIGestureRecognizerRepresentable {
        let isEnabled: Bool
        let coordinateSpace: Namespace.ID
        let canBegin: (CGPoint) -> Bool
        let began: (CGPoint) -> Void
        let moved: (CGPoint) -> Void
        let ended: (Bool) -> Void

        func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
            Coordinator(canBegin: canBegin, converter: converter, coordinateSpace: coordinateSpace)
        }

        func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
            let recognizer = UILongPressGestureRecognizer()
            recognizer.minimumPressDuration = 0.2
            recognizer.allowableMovement = 4
            recognizer.delegate = context.coordinator
            recognizer.isEnabled = isEnabled
            return recognizer
        }

        func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
            context.coordinator.canBegin = canBegin
            recognizer.isEnabled = isEnabled
        }

        func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
            let location = context.converter.location(in: .named(coordinateSpace))
            switch recognizer.state {
            case .began: began(location)
            case .changed: moved(location)
            case .ended: ended(true)
            case .cancelled, .failed: ended(false)
            default: break
            }
        }

        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            var canBegin: (CGPoint) -> Bool
            let converter: CoordinateSpaceConverter
            let coordinateSpace: Namespace.ID

            init(
                canBegin: @escaping (CGPoint) -> Bool, converter: CoordinateSpaceConverter,
                coordinateSpace: Namespace.ID
            ) {
                self.canBegin = canBegin
                self.converter = converter
                self.coordinateSpace = coordinateSpace
            }

            func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
                canBegin(converter.location(in: .named(coordinateSpace)))
            }
        }
    }

#endif
