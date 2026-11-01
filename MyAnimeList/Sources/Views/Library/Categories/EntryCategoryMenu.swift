//
//  EntryCategoryMenu.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/30.
//

import DataProvider
import SwiftUI

#if !os(macOS)
    /// Whether all, some, or none of the anime a menu acts on are in a category.
    enum LibraryCategoryMembership {
        case all, some, none

        init(isMember: Bool) {
            self = isMember ? .all : .none
        }

        /// Every row carries an icon so menus keep the category names in one aligned column.
        var icon: Image {
            switch self {
            case .all: Image(systemName: "checkmark")
            case .some: Image(systemName: "minus")
            case .none: Image(uiImage: Self.blankIcon)
            }
        }

        /// A clear image the size of the checkmark symbol.
        private static let blankIcon: UIImage = {
            let size = UIImage(systemName: "checkmark")?.size ?? CGSize(width: 17, height: 16)
            return UIGraphicsImageRenderer(size: size).image { _ in }
        }()
    }
#endif

extension LibraryStore {
    /// Names of the categories `entry` belongs to, in display order.
    func categoryNames(of entry: AnimeEntry) -> [String] {
        let ids = Set(entry.categoryIDs)
        return categories.filter { ids.contains($0.id) }.map(\.name)
    }

    /// Creates a category and adds `entries` to it.
    func createCategory(named name: String, adding entries: [AnimeEntry]) {
        guard let category = createCategory(named: name) else { return }
        LibraryBatchAction.category(category.id, isMember: true, knownCategoryIDs: knownCategoryIDs)
            .apply(to: entries)
    }
}

/// One entry's category toggles, then New Category….
///
/// Writes go through `LibraryBatchAction.category`, the batch menus' path, so a single
/// entry needs no multi-select.
struct EntryCategoryMenuContent: View {
    let store: LibraryStore
    let entry: AnimeEntry
    /// Whether a toggle leaves the menu open. iOS draws an open context menu once, so its
    /// checkmarks would go stale; only regular menus stay open.
    var keepsPresented = true
    let requestNewCategory: () -> Void

    var body: some View {
        Section {
            // Read membership here so an open menu observes it and updates its checkmarks.
            let memberIDs = Set(entry.categoryIDs)
            ForEach(store.categories) { category in
                let item = categoryItem(category, isMember: memberIDs.contains(category.id))
                if keepsPresented {
                    // Stay open so the user sees the result and can pick more categories.
                    item.keepsMenuPresentedAfterAction()
                } else {
                    item
                }
            }
        }
        Section {
            Button("New Category…", systemImage: "plus", action: requestNewCategory)
        }
    }

    @ViewBuilder
    private func categoryItem(_ category: LibraryCategory, isMember: Bool) -> some View {
        #if os(macOS)
            Toggle(
                isOn: Binding(
                    get: { isMember },
                    set: { setMembership(category.id, isMember: $0) }
                )
            ) {
                Text(verbatim: category.name)
            }
        #else
            // A Toggle's checkmark sits outside the icon column New Category… uses, so draw
            // the checkmark as the icon, as the batch menu does.
            Button {
                setMembership(category.id, isMember: !isMember)
            } label: {
                Label {
                    Text(verbatim: category.name)
                } icon: {
                    LibraryCategoryMembership(isMember: isMember).icon
                }
            }
        #endif
    }

    private func setMembership(_ id: LibraryCategory.ID, isMember: Bool) {
        LibraryBatchAction.category(id, isMember: isMember, knownCategoryIDs: store.knownCategoryIDs)
            .apply(to: [entry])
    }
}

/// A Categories submenu of an entry's actions; hidden while categories are off.
///
/// New Category… is handed to `requestNewCategory`, because the menu's views are gone by the
/// time a name prompt could present.
struct EntryCategoriesSubmenu: View {
    @Environment(LibraryStore.self) private var store: LibraryStore?
    let entry: AnimeEntry
    var keepsPresented = true
    let requestNewCategory: () -> Void

    var body: some View {
        if let store, store.categoriesEnabled {
            Menu("Categories", systemImage: "folder") {
                EntryCategoryMenuContent(
                    store: store,
                    entry: entry,
                    keepsPresented: keepsPresented,
                    requestNewCategory: requestNewCategory
                )
            }
        }
    }
}

extension View {
    /// Asks for a category name, then creates the category and adds `entry` to it.
    ///
    /// Does nothing without a library store, as in previews.
    func entryNewCategoryPrompt(
        _ prompt: Binding<LibraryCategoryNamePrompt?>,
        entry: @escaping () -> AnimeEntry?
    ) -> some View {
        modifier(EntryNewCategoryPromptModifier(prompt: prompt, entry: entry))
    }
}

fileprivate struct EntryNewCategoryPromptModifier: ViewModifier {
    @Environment(LibraryStore.self) private var store: LibraryStore?
    @Binding var prompt: LibraryCategoryNamePrompt?
    let entry: () -> AnimeEntry?

    func body(content: Content) -> some View {
        if let store {
            content
                .libraryCategoryNamePrompt($prompt) { _, name in
                    store.createCategory(named: name, adding: entry().map { [$0] } ?? [])
                }
        } else {
            content
        }
    }
}

#if os(macOS)
    /// The Mac tracking card's Categories control: a menu labeled with the entry's categories.
    struct MacEntryCategoriesMenu: View {
        let store: LibraryStore
        let entry: AnimeEntry

        @State private var namePrompt: LibraryCategoryNamePrompt?

        /// Caps the label so many categories shorten instead of widening the inspector.
        private static let maximumLabelWidth: CGFloat = 220

        var body: some View {
            let names = store.categoryNames(of: entry)
            let summary = names.formatted(.list(type: .and, width: .narrow))
            // The full list when it fits, otherwise the first name and a count; a first name
            // too long even for that truncates.
            ViewThatFits(in: .horizontal) {
                menu(isFixedSize: true) {
                    if names.isEmpty {
                        Text("None")
                    } else {
                        Text(verbatim: summary)
                    }
                }
                if let first = names.first, names.count > 1 {
                    // The last choice is used even when it does not fit, so it may truncate.
                    menu(isFixedSize: false) { Text("\(first) and \(names.count - 1) more") }
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: Self.maximumLabelWidth, alignment: .trailing)
            .help(Text(verbatim: summary))
            .entryNewCategoryPrompt($namePrompt) { entry }
        }

        @ViewBuilder
        private func menu(isFixedSize: Bool, @ViewBuilder label: () -> some View) -> some View {
            let menu = Menu {
                EntryCategoryMenuContent(store: store, entry: entry) {
                    namePrompt = .init(purpose: .create(memberCount: 0))
                }
            } label: {
                label()
            }
            .menuStyle(.borderlessButton)
            if isFixedSize {
                menu.fixedSize()
            } else {
                menu
            }
        }
    }
#endif
