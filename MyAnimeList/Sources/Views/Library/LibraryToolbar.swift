//
//  LibraryToolbar.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import DataProvider
import SwiftUI

struct LibraryToolbar: ToolbarContent {
    let store: LibraryStore
    let interaction: LibraryEntryInteractionState
    @Binding var libraryViewStyle: LibraryView.LibraryViewStyle
    let scoringEnabled: Bool
    @Binding var isSearching: Bool
    let selectionEntriesByID: [LibraryEntryIdentity: AnimeEntry]
    let supportsMultiSelection: Bool
    let showsCategoryStrip: Bool
    @Binding var isReorderingCategories: Bool
    let enterMultiSelection: () -> Void
    let exitMultiSelection: () -> Void
    let applyBatchAction: (LibraryBatchAction) -> Void
    let deleteSelectedEntries: () -> Void
    let openProfileSettings: () -> Void
    let openCategoryManager: () -> Void
    var addAnime: () -> Void = {}

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        #if os(macOS)
            macContent
        #else
            topBarContent
            bottomBarContent
        #endif
    }

    #if os(macOS)
        @ToolbarContentBuilder
        private var macContent: some ToolbarContent {
            // A batch selection keeps these browsing controls; its actions live in the
            // inspector's batch panel (`MacBatchSelectionPanel`), not in a toolbar mode.
            ToolbarItem(placement: .primaryAction) {
                Picker("View Style", selection: $libraryViewStyle) {
                    ForEach(LibraryView.LibraryViewStyle.platformCases, id: \.self) { style in
                        Label(style.nameKey, systemImage: style.systemImageName)
                            .labelStyle(.iconOnly)
                            .help(Text(style.nameKey))
                            .tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem(placement: .primaryAction) {
                LibraryBrowseSummaryMenu(store: store, scoringEnabled: scoringEnabled)
                    .help(Text("Sort, group, and filter"))
                    .accessibilityLabel(Text("Sort, group, and filter"))
            }
            // Find is the window's toolbar search field (`.searchable` in LibraryView). The
            // inspector toggle belongs to the inspector's own toolbar (`MacLibraryInspector`).
            ToolbarItem(placement: .primaryAction) {
                Button("Add Anime…", systemImage: "plus", action: addAnime)
                    .help(Text("Add anime from TMDb"))
            }
        }
    #endif

    @ToolbarContentBuilder
    private var topBarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            LibraryToolbarTitle(
                store: store,
                interaction: interaction,
                showsCategoryStrip: showsCategoryStrip,
                openCategoryManager: openCategoryManager
            )
        }
        if isReorderingCategories {
            ToolbarItem(placement: .platformTrailing) {
                Button(LocalizedStringResource("Done")) {
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
        interaction.selectedEntryIDs.compactMap { selectionEntriesByID[$0] }
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
                    ForEach(LibraryView.LibraryViewStyle.allCases, id: \.self) { style in
                        Label(style.nameKey, systemImage: style.systemImageName).tag(style)
                    }
                }
                .labelsHidden()
            }
            ToolbarItem(placement: .status) {
                LibraryBrowseSummaryMenu(store: store, scoringEnabled: scoringEnabled)
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
    let store: LibraryStore
    let interaction: LibraryEntryInteractionState
    let showsCategoryStrip: Bool
    let openCategoryManager: () -> Void

    var body: some View {
        if store.categoriesEnabled && !showsCategoryStrip {
            // Gallery and strip-off keep the capsule category switcher.
            Menu {
                Picker(
                    "Category",
                    selection: Binding(
                        get: { store.activeCategoryID },
                        set: { id in withAnimation(.snappy) { store.activeCategoryID = id } }
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
            count: interaction.isMultiSelecting ? interaction.selectedEntryCount : store.libraryOnDisplay.count,
            categoryName: interaction.isMultiSelecting || showsCategoryStrip ? nil : store.activeCategory?.name
        )
    }
}

struct LibrarySelectionDeleteButton: View {
    let selectedEntries: [AnimeEntry]
    let deleteSelectedEntries: () -> Void
    @State private var isShowingConfirmation = false

    var body: some View {
        Button(role: .destructive) {
            isShowingConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(selectedEntries.isEmpty)
        .tint(.red)
        .alert(LocalizedStringResource("Delete Selected Anime?"), isPresented: $isShowingConfirmation) {
            Button("Delete", role: .destructive, action: deleteSelectedEntries)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                LocalizedStringResource(
                    "This will delete \(selectedEntries.count) selected anime from your library."))
        }
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
        case .none:
            #if os(macOS)
                Image(nsImage: NSImage(size: CGSize(width: 17, height: 16)))
            #else
                Image(uiImage: Self.blankIcon)
            #endif
        }
    }

    /// A clear image the size of the checkmark symbol.
    #if !os(macOS)
        private static let blankIcon: UIImage = {
            let size = UIImage(systemName: "checkmark")?.size ?? CGSize(width: 17, height: 16)
            return UIGraphicsImageRenderer(size: size).image { _ in }
        }()
    #endif
}

struct LibrarySelectionActionsMenu: View {
    let selectedEntries: [AnimeEntry]
    let scoringEnabled: Bool
    let applyBatchAction: (LibraryBatchAction) -> Void

    var body: some View {
        Menu {
            Button("Track Dates", systemImage: "calendar.badge.checkmark") {
                applyBatchAction(.dateTracking(true))
            }
            Button("Hide Dates", systemImage: "calendar.badge.minus") {
                applyBatchAction(.dateTracking(false))
            }

            if scoringEnabled {
                Menu("Score", systemImage: "star") {
                    ForEach(Array(AnimeEntry.validScoreRange), id: \.self) { score in
                        Button("\(score)/5") {
                            applyBatchAction(.score(score))
                        }
                    }
                    Button("Clear Score", systemImage: "xmark.circle") {
                        applyBatchAction(.score(nil))
                    }
                }
            }
        } label: {
            Label("Actions", systemImage: "ellipsis")
        }
        .disabled(selectedEntries.isEmpty)
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
