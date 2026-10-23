//
//  LibraryToolbar.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import DataProvider
import SwiftUI

#if !os(macOS)
    struct LibraryToolbar: ToolbarContent {
        @Environment(\.self) private var environment
        let store: LibraryStore
        let scope: LibraryBrowseScope
        let interaction: LibraryEntryInteractionState
        @Binding var libraryViewStyle: LibraryViewStyle
        let scoringEnabled: Bool
        @Binding var isSearching: Bool
        let supportsMultiSelection: Bool
        let showsCategoryStrip: Bool
        @Binding var isReorderingCategories: Bool
        let enterMultiSelection: () -> Void
        let exitMultiSelection: () -> Void
        let applyBatchAction: (LibraryBatchAction) -> Void
        let deleteSelectedEntries: () -> Void
        let openProfileSettings: () -> Void
        let openCategoryManager: () -> Void

        @ToolbarContentBuilder
        var body: some ToolbarContent {
            if #available(iOS 27.1, *), usesVerticalToolbar {
                verticalBarContent
            } else {
                topBarContent
                bottomBarContent
            }
        }

        private var usesVerticalToolbar: Bool {
            if #available(iOS 27.1, *) {
                // Inspector pane ownership is a separate slice; preserve its existing toolbar.
                return environment.toolbarVerticalEdge != nil && interaction.inspectorPresentation == nil
            }
            return false
        }

        /// iPhone Duo's vertical bar keeps the library header horizontal, since its count and
        /// category are meaningful text, and moves the bottom controls into the vertical bar as
        /// symbols (docs-ai 031).
        @available(iOS 27.1, *)
        @ToolbarContentBuilder
        private var verticalBarContent: some ToolbarContent {
            topBarContent
            if interaction.isMultiSelecting {
                ToolbarItem(placement: .platformBottomBar) {
                    LibrarySelectionDeleteButton(
                        selectedEntries: selectedEntries,
                        deleteSelectedEntries: deleteSelectedEntries
                    )
                }
                .visibilityPriority(.low)
                ToolbarItemGroup(placement: .platformBottomBar) {
                    LibrarySelectionStatusMenu(selectedEntries: selectedEntries, applyBatchAction: applyBatchAction)
                    LibrarySelectionFavoriteButton(selectedEntries: selectedEntries, applyBatchAction: applyBatchAction)
                    if store.categoriesEnabled {
                        LibrarySelectionCategoryMenu(
                            store: store, selectedEntries: selectedEntries, applyBatchAction: applyBatchAction)
                    }
                }
                ToolbarOverflowMenu {
                    LibrarySelectionActionsMenu(
                        selectedEntries: selectedEntries, scoringEnabled: scoringEnabled,
                        applyBatchAction: applyBatchAction
                    ).actions
                        .disabled(selectedEntries.isEmpty)
                }
            } else {
                ToolbarItem(placement: .platformBottomBar) {
                    Menu {
                        Picker("View Style", selection: $libraryViewStyle) {
                            ForEach(LibraryViewStyle.allCases, id: \.self) { style in
                                Label(style.nameKey, systemImage: style.systemImageName).tag(style)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("View Style", systemImage: libraryViewStyle.systemImageName)
                    }
                }
                .visibilityPriority(.low)
                ToolbarItem(placement: .platformBottomBar) {
                    LibraryBrowseSummaryMenu(scope: scope, scoringEnabled: scoringEnabled, usesSymbolLabel: true)
                }
                ToolbarItem(placement: .platformBottomBar) {
                    LibrarySearchButton(isSearching: $isSearching)
                }
                .visibilityPriority(.high)
            }
        }

        @ToolbarContentBuilder
        private var topBarContent: some ToolbarContent {
            ToolbarItem(placement: .principal) {
                LibraryToolbarTitle(
                    scope: scope,
                    interaction: interaction,
                    showsCategoryStrip: showsCategoryStrip,
                    openCategoryManager: openCategoryManager
                )
            }
            if isReorderingCategories {
                ToolbarItem(placement: .platformTrailing) {
                    Button("Done") {
                        withAnimation(.snappy) { isReorderingCategories = false }
                    }
                    .font(.headline.weight(.semibold))
                }
            }
            if supportsMultiSelection && !interaction.isMultiSelecting && !isReorderingCategories {
                // Counterbalances the trailing controls so the principal title sits visually left of center.
                ToolbarItem(placement: .platformTrailing) {
                    Color.clear
                        .frame(width: 10, height: 0)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            if interaction.isMultiSelecting {
                ToolbarItem(placement: .platformTrailing) {
                    Button {
                        exitMultiSelection()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Dismiss Selection"))
                }
            } else if !isReorderingCategories {
                ToolbarItem(placement: .platformTrailing) {
                    if supportsMultiSelection {
                        Button(action: enterMultiSelection) {
                            Text("Select").font(.headline.weight(.semibold))
                        }
                        .accessibilityLabel(Text("Anime Multi-selection"))
                        .padding(.leading, 3)
                    }
                }
                ToolbarItem(placement: .platformTrailing) {
                    LibraryProfileSettingsButton(action: openProfileSettings)
                        .padding(.trailing, 3)
                }
            }
        }

        private var selectedEntries: [AnimeEntry] {
            interaction.selectedEntryIDs.compactMap(scope.displayedEntry(for:))
        }

        @ToolbarContentBuilder
        private var bottomBarContent: some ToolbarContent {
            if interaction.isMultiSelecting {
                ToolbarItem(placement: .platformBottomBar) {
                    LibrarySelectionDeleteButton(
                        selectedEntries: selectedEntries,
                        deleteSelectedEntries: deleteSelectedEntries
                    )
                }
                ToolbarItemGroup(placement: .status) {
                    LibrarySelectionStatusMenu(selectedEntries: selectedEntries, applyBatchAction: applyBatchAction)
                    LibrarySelectionFavoriteButton(
                        selectedEntries: selectedEntries,
                        applyBatchAction: applyBatchAction
                    )
                    if store.categoriesEnabled {
                        LibrarySelectionCategoryMenu(
                            store: store,
                            selectedEntries: selectedEntries,
                            applyBatchAction: applyBatchAction
                        )
                    }
                }
                ToolbarItem(placement: .platformBottomBar) {
                    LibrarySelectionActionsMenu(
                        selectedEntries: selectedEntries,
                        scoringEnabled: scoringEnabled,
                        applyBatchAction: applyBatchAction
                    )
                }
            } else {
                ToolbarItem(placement: .platformBottomBar) {
                    Picker("View Style", selection: $libraryViewStyle) {
                        ForEach(LibraryViewStyle.allCases, id: \.self) { style in
                            Label(style.nameKey, systemImage: style.systemImageName).tag(style)
                        }
                    }
                    .labelsHidden()
                }
                ToolbarItem(placement: .status) {
                    LibraryBrowseSummaryMenu(scope: scope, scoringEnabled: scoringEnabled)
                }
                ToolbarItem(placement: .platformBottomBar) {
                    LibrarySearchButton(isSearching: $isSearching)
                }
            }
        }
    }

    // Keep selection reads in view bodies so taps update the controls independently
    // of the library's display projection and layout animation.
    fileprivate struct LibraryToolbarTitle: View {
        let scope: LibraryBrowseScope
        let interaction: LibraryEntryInteractionState
        let showsCategoryStrip: Bool
        let openCategoryManager: () -> Void

        private var store: LibraryStore { scope.store }

        var body: some View {
            if store.categoriesEnabled && !showsCategoryStrip {
                // Gallery and strip-off keep the capsule category switcher.
                Menu {
                    Picker(
                        "Category",
                        selection: Binding(
                            get: { scope.activeCategoryID },
                            set: { id in withAnimation(.snappy) { scope.activeCategoryID = id } }
                        )
                    ) {
                        Text("All").tag(LibraryCategory.ID?.none)
                        ForEach(store.categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Edit Categories…", systemImage: "list.bullet", action: openCategoryManager)
                } label: {
                    capsule
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Switches the library category"))
            } else {
                capsule
            }
        }

        private var capsule: some View {
            LibraryNavigationTitleCapsule(
                count: interaction.isMultiSelecting ? interaction.selectedEntryCount : scope.displayIDs.count,
                categoryName: interaction.isMultiSelecting || showsCategoryStrip ? nil : scope.activeCategory?.name
            )
        }
    }

    struct LibrarySelectionStatusMenu: View {
        let selectedEntries: [AnimeEntry]
        let applyBatchAction: (LibraryBatchAction) -> Void

        var body: some View {
            Menu {
                ForEach(AnimeEntry.WatchStatus.allCases, id: \.self) { status in
                    Button {
                        applyBatchAction(.watchStatus(status))
                    } label: {
                        Label(status.localizedStringResource, systemImage: status.batchActionSystemImage)
                    }
                }
            } label: {
                Label("Mark Status", systemImage: "checklist")
            }
            .disabled(selectedEntries.isEmpty)
        }
    }

    struct LibrarySelectionFavoriteButton: View {
        let selectedEntries: [AnimeEntry]
        let applyBatchAction: (LibraryBatchAction) -> Void

        private var allFavorite: Bool {
            !selectedEntries.isEmpty && selectedEntries.allSatisfy(\.favorite)
        }

        var body: some View {
            let allFavorite = allFavorite
            let title: LocalizedStringKey = allFavorite ? "Unfavorite" : "Favorite"
            let systemImage = allFavorite ? "heart.slash.fill" : "heart.fill"
            Button {
                applyBatchAction(.favorite(!allFavorite))
            } label: {
                Label(title, systemImage: systemImage)
            }
            .accessibilityIdentifier("library-batch-favorite")
            .disabled(selectedEntries.isEmpty)
            .animation(.snappy(duration: 0.3), value: allFavorite)
        }
    }

    struct LibrarySelectionCategoryMenu: View {
        let store: LibraryStore
        let selectedEntries: [AnimeEntry]
        let applyBatchAction: (LibraryBatchAction) -> Void

        @State private var namePrompt: LibraryCategoryNamePrompt?

        var body: some View {
            Menu {
                Section {
                    ForEach(store.categories) { category in
                        let membership = membership(of: category.id, in: selectedEntries)
                        Button {
                            // A full category removes the selection; otherwise every selected anime joins.
                            apply(category.id, isMember: membership != .all)
                        } label: {
                            Label {
                                Text(category.name)
                            } icon: {
                                membership.icon
                            }
                        }
                        // Stay open so the user sees the result and can pick more categories.
                        .keepsMenuPresentedAfterAction()
                    }
                } header: {
                    Text("Add \(selectedEntries.count) Anime To")
                }
                Section {
                    Button("New Category…", systemImage: "plus") {
                        namePrompt = .init(purpose: .create(memberCount: selectedEntries.count))
                    }
                }
            } label: {
                Label("Category", systemImage: "folder")
            }
            .disabled(selectedEntries.isEmpty)
            .libraryCategoryNamePrompt($namePrompt) { _, name in
                guard let category = store.createCategory(named: name) else { return }
                apply(category.id, isMember: true)
            }
        }

        private func apply(_ id: LibraryCategory.ID, isMember: Bool) {
            applyBatchAction(.category(id, isMember: isMember, knownCategoryIDs: store.knownCategoryIDs))
        }

        private func membership(of id: LibraryCategory.ID, in entries: [AnimeEntry]) -> Membership {
            let memberCount = entries.count { $0.categoryIDs.contains(id) }
            if memberCount == 0 { return .none }
            return memberCount == entries.count ? .all : .some
        }
    }

    fileprivate enum Membership {
        case all, some, none

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

    struct LibrarySelectionActionsMenu: View {
        let selectedEntries: [AnimeEntry]
        let scoringEnabled: Bool
        let applyBatchAction: (LibraryBatchAction) -> Void

        var body: some View {
            Menu {
                actions
            } label: {
                Label("Actions", systemImage: "ellipsis")
            }
            .disabled(selectedEntries.isEmpty)
        }

        var actions: some View {
            Group {
                Button("Track Dates", systemImage: "calendar.badge.checkmark") {
                    applyBatchAction(.dateTracking(true))
                }
                Button("Hide Dates", systemImage: "calendar.badge.minus") {
                    applyBatchAction(.dateTracking(false))
                }

                if scoringEnabled {
                    Menu("Score", systemImage: "star") {
                        ForEach(EntryScore.all, id: \.self) { score in
                            Button("\(score.formatted)/5") {
                                applyBatchAction(.score(score))
                            }
                        }
                        Button("Clear Score", systemImage: "xmark.circle") {
                            applyBatchAction(.score(nil))
                        }
                    }
                }
            }
        }
    }

    fileprivate struct LibraryProfileSettingsButton: View {
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .symbolRenderingMode(.monochrome)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 6.5, weight: .bold))
                        .background(.primary.opacity(0.30), in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.4), lineWidth: 0.7)
                        }
                        .offset(x: 4, y: 4)
                }
            }
            .accessibilityLabel(Text("Open Library Profile"))
        }
    }

    extension AnimeEntry.WatchStatus {
        var batchActionSystemImage: String {
            switch self {
            case .planToWatch:
                "bookmark"
            case .watching:
                "play.circle"
            case .watched:
                "checkmark.circle"
            case .dropped:
                "xmark.circle"
            }
        }
    }

    struct LibrarySearchButton: View {
        @Binding var isSearching: Bool

        var body: some View {
            Button("Search...", systemImage: "magnifyingglass") { isSearching = true }
        }
    }
#endif
