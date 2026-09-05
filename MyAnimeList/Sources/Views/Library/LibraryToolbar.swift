//
//  LibraryToolbar.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import Collections
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
    let enterMultiSelection: () -> Void
    let exitMultiSelection: () -> Void
    let applyBatchAction: (LibraryBatchAction) -> Void
    let deleteSelectedEntries: () -> Void
    let openProfileSettings: () -> Void
    let checkDuplicate: (LibraryEntryIdentity) -> Bool
    let processTMDbSearchResults: (OrderedSet<SearchResult>, SearchSubmissionOrigin) -> Void
    let jumpToEntryInLibrary: (LibraryEntryIdentity) -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        topBarContent
        bottomBarContent
    }

    @ToolbarContentBuilder
    private var topBarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            LibraryToolbarTitle(store: store, interaction: interaction)
        }
        if supportsMultiSelection && !interaction.isMultiSelecting {
            // Counterbalances the trailing controls so the principal title sits visually left of center.
            ToolbarItem(placement: .topBarTrailing) {
                Color.clear
                    .frame(width: 10, height: 0)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        if interaction.isMultiSelecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exitMultiSelection()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(Text("Dismiss Selection"))
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                if supportsMultiSelection {
                    Button(action: enterMultiSelection) {
                        Text("Select").font(.headline.weight(.semibold))
                    }
                    .accessibilityLabel(Text("Anime Multi-selection"))
                    .padding(.leading, 3)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                LibraryProfileSettingsButton(action: openProfileSettings)
                    .padding(.trailing, 3)
            }
        }
    }

    @ToolbarContentBuilder
    private var bottomBarContent: some ToolbarContent {
        if interaction.isMultiSelecting {
            ToolbarItem(placement: .bottomBar) {
                LibrarySelectionDeleteButton(interaction: interaction, deleteSelectedEntries: deleteSelectedEntries)
            }
            ToolbarItemGroup(placement: .status) {
                LibrarySelectionStatusMenu(interaction: interaction, applyBatchAction: applyBatchAction)
                LibrarySelectionFavoriteButton(
                    interaction: interaction,
                    entriesByID: selectionEntriesByID,
                    applyBatchAction: applyBatchAction
                )
            }
            ToolbarItem(placement: .bottomBar) {
                LibrarySelectionActionsMenu(
                    interaction: interaction,
                    scoringEnabled: scoringEnabled,
                    applyBatchAction: applyBatchAction
                )
            }
        } else {
            ToolbarItem(placement: .bottomBar) {
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
            ToolbarItem(placement: .bottomBar) {
                LibrarySearchButton(
                    isSearching: $isSearching,
                    checkDuplicate: checkDuplicate,
                    processTMDbSearchResults: processTMDbSearchResults,
                    jumpToEntryInLibrary: jumpToEntryInLibrary
                )
            }
        }
    }
}

// Keep selection reads in view bodies so taps update the controls independently
// of the library's display projection and layout animation.
fileprivate struct LibraryToolbarTitle: View {
    let store: LibraryStore
    let interaction: LibraryEntryInteractionState

    var body: some View {
        LibraryNavigationTitleCapsule(
            count: interaction.isMultiSelecting ? interaction.selectedEntryCount : store.libraryOnDisplay.count
        )
    }
}

fileprivate struct LibrarySelectionDeleteButton: View {
    let interaction: LibraryEntryInteractionState
    let deleteSelectedEntries: () -> Void
    @State private var isShowingConfirmation = false

    var body: some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            isShowingConfirmation = true
        }
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

fileprivate struct LibrarySelectionStatusMenu: View {
    let interaction: LibraryEntryInteractionState
    let applyBatchAction: (LibraryBatchAction) -> Void

    var body: some View {
        Menu("Mark Status", systemImage: "checklist") {
            ForEach(AnimeEntry.WatchStatus.allCases, id: \.self) { status in
                Button {
                    applyBatchAction(.watchStatus(status))
                } label: {
                    Label(status.localizedStringResource, systemImage: status.batchActionSystemImage)
                }
            }
        }
        .disabled(interaction.selectedEntryIDs.isEmpty)
    }
}

fileprivate struct LibrarySelectionFavoriteButton: View {
    let interaction: LibraryEntryInteractionState
    let entriesByID: [LibraryEntryIdentity: AnimeEntry]
    let applyBatchAction: (LibraryBatchAction) -> Void

    private var allFavorite: Bool {
        !interaction.selectedEntryIDs.isEmpty
            && interaction.selectedEntryIDs.allSatisfy { entriesByID[$0]?.favorite == true }
    }

    var body: some View {
        let allFavorite = allFavorite
        Button(
            allFavorite ? "Unfavorite" : "Favorite",
            systemImage: allFavorite ? "heart.slash.fill" : "heart.fill"
        ) {
            applyBatchAction(.favorite(!allFavorite))
        }
        .disabled(interaction.selectedEntryIDs.isEmpty)
        .animation(.snappy(duration: 0.3), value: allFavorite)
    }
}

fileprivate struct LibrarySelectionActionsMenu: View {
    let interaction: LibraryEntryInteractionState
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
