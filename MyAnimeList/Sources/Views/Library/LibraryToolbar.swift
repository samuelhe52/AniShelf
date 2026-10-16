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
    var isInspectorPresented = false
    var toggleInspector: () -> Void = {}

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
            // Find is the window's toolbar search field (`.searchable` in LibraryView).
            ToolbarItem(placement: .primaryAction) {
                Button("Add Anime…", systemImage: "plus", action: addAnime)
                    .help(Text("Add anime from TMDb"))
            }
            // An open inspector has its own Hide Inspector button; dropping the toggle then
            // keeps Add and Find out of the overflow menu in narrow windows.
            if !isInspectorPresented {
                ToolbarItem(placement: .primaryAction) {
                    Button("Show Inspector", systemImage: "sidebar.trailing", action: toggleInspector)
                        .help(Text("Show Inspector"))
                }
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

    @ToolbarContentBuilder
    private var bottomBarContent: some ToolbarContent {
        if interaction.isMultiSelecting {
            ToolbarItem(placement: .platformBottomBar) {
                LibrarySelectionDeleteButton(interaction: interaction, deleteSelectedEntries: deleteSelectedEntries)
            }
            ToolbarItemGroup(placement: .status) {
                LibrarySelectionStatusMenu(interaction: interaction, applyBatchAction: applyBatchAction)
                LibrarySelectionFavoriteButton(
                    interaction: interaction,
                    entriesByID: selectionEntriesByID,
                    applyBatchAction: applyBatchAction
                )
                if store.categoriesEnabled {
                    LibrarySelectionCategoryMenu(
                        store: store,
                        interaction: interaction,
                        entriesByID: selectionEntriesByID,
                        applyBatchAction: applyBatchAction
                    )
                }
            }
            ToolbarItem(placement: .platformBottomBar) {
                LibrarySelectionActionsMenu(
                    interaction: interaction,
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

/// How a batch-selection control draws: as a toolbar item, or as a full-width row in the
/// Mac inspector's batch panel.
enum LibrarySelectionControlPresentation {
    case toolbar
    case row
}

struct LibrarySelectionDeleteButton: View {
    let interaction: LibraryEntryInteractionState
    let deleteSelectedEntries: () -> Void
    var presentation: LibrarySelectionControlPresentation = .toolbar
    @State private var isShowingConfirmation = false

    var body: some View {
        Button(role: .destructive) {
            isShowingConfirmation = true
        } label: {
            switch presentation {
            case .toolbar: Label("Delete", systemImage: "trash")
            case .row: LibrarySelectionActionRow("Delete", systemImage: "trash", tint: .red)
            }
        }
        .selectionControlStyle(presentation)
        .disabled(interaction.selectedEntryIDs.isEmpty)
        .tint(.red)
        .alert(LocalizedStringResource("Delete Selected Anime?"), isPresented: $isShowingConfirmation) {
            Button("Delete", role: .destructive, action: deleteSelectedEntries)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                LocalizedStringResource(
                    "This will delete \(interaction.selectedEntryCount) selected anime from your library."))
        }
    }
}

struct LibrarySelectionStatusMenu: View {
    let interaction: LibraryEntryInteractionState
    let applyBatchAction: (LibraryBatchAction) -> Void
    var presentation: LibrarySelectionControlPresentation = .toolbar

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
            switch presentation {
            case .toolbar: Label("Mark Status", systemImage: "checklist")
            case .row: LibrarySelectionActionRow("Mark Status", systemImage: "checklist", isMenu: true)
            }
        }
        .selectionControlStyle(presentation)
        .disabled(interaction.selectedEntryIDs.isEmpty)
    }
}

struct LibrarySelectionFavoriteButton: View {
    let interaction: LibraryEntryInteractionState
    let entriesByID: [LibraryEntryIdentity: AnimeEntry]
    let applyBatchAction: (LibraryBatchAction) -> Void
    var presentation: LibrarySelectionControlPresentation = .toolbar

    private var allFavorite: Bool {
        !interaction.selectedEntryIDs.isEmpty
            && interaction.selectedEntryIDs.allSatisfy { entriesByID[$0]?.favorite == true }
    }

    var body: some View {
        let allFavorite = allFavorite
        let title: LocalizedStringKey = allFavorite ? "Unfavorite" : "Favorite"
        let systemImage = allFavorite ? "heart.slash.fill" : "heart.fill"
        Button {
            applyBatchAction(.favorite(!allFavorite))
        } label: {
            switch presentation {
            case .toolbar: Label(title, systemImage: systemImage)
            case .row: LibrarySelectionActionRow(title, systemImage: systemImage, tint: .pink)
            }
        }
        .selectionControlStyle(presentation)
        .disabled(interaction.selectedEntryIDs.isEmpty)
        .animation(.snappy(duration: 0.3), value: allFavorite)
    }
}

struct LibrarySelectionCategoryMenu: View {
    let store: LibraryStore
    let interaction: LibraryEntryInteractionState
    let entriesByID: [LibraryEntryIdentity: AnimeEntry]
    let applyBatchAction: (LibraryBatchAction) -> Void
    var presentation: LibrarySelectionControlPresentation = .toolbar

    @State private var namePrompt: LibraryCategoryNamePrompt?

    var body: some View {
        let selectedEntries = interaction.selectedEntryIDs.compactMap { entriesByID[$0] }
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
            switch presentation {
            case .toolbar: Label("Category", systemImage: "folder")
            case .row: LibrarySelectionActionRow("Category", systemImage: "folder", isMenu: true)
            }
        }
        .selectionControlStyle(presentation)
        .disabled(interaction.selectedEntryIDs.isEmpty)
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

extension View {
    @ViewBuilder
    fileprivate func selectionControlStyle(_ presentation: LibrarySelectionControlPresentation) -> some View {
        switch presentation {
        case .toolbar:
            self
        case .row:
            // A plain button-style menu draws the full-width row label as is on the Mac.
            menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
        }
    }
}

/// A full-width action row for the Mac batch panel, highlighted under the pointer.
struct LibrarySelectionActionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color? = nil
    var isMenu = false
    @State private var isHovering = false

    init(_ title: LocalizedStringKey, systemImage: String, tint: Color? = nil, isMenu: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isMenu = isMenu
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 20)
            Text(title)
                .foregroundStyle(tint == .red ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            Spacer(minLength: 8)
            if isMenu {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect(cornerRadius: 6))
        .background(
            isHovering ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: 6)
        )
        .onHover { isHovering = $0 }
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
    let interaction: LibraryEntryInteractionState
    let scoringEnabled: Bool
    let applyBatchAction: (LibraryBatchAction) -> Void
    var presentation: LibrarySelectionControlPresentation = .toolbar

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
            switch presentation {
            case .toolbar: Label("Actions", systemImage: "ellipsis")
            case .row: LibrarySelectionActionRow("Actions", systemImage: "ellipsis.circle", isMenu: true)
            }
        }
        .selectionControlStyle(presentation)
        .disabled(interaction.selectedEntryIDs.isEmpty)
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
