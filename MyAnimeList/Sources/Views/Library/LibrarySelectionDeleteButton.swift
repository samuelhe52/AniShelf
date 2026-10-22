//
//  LibrarySelectionDeleteButton.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

import DataProvider
import SwiftUI

/// Deletes a batch selection after confirming: in the iOS selection toolbar and the Mac
/// inspector's batch panel.
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
