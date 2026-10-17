//
//  MacLibraryToolbar.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/17.
//

#if os(macOS)
    import DataProvider
    import SwiftUI

    struct MacLibraryToolbar: ToolbarContent {
        let store: LibraryStore
        @Binding var libraryViewStyle: LibraryViewStyle
        let scoringEnabled: Bool
        let addAnime: () -> Void

        @ToolbarContentBuilder
        var body: some ToolbarContent {
            // A batch selection keeps these browsing controls; its actions live in the
            // inspector's batch panel (`MacBatchSelectionPanel`), not in a toolbar mode.
            ToolbarItem(placement: .primaryAction) {
                Picker("View Style", selection: $libraryViewStyle) {
                    ForEach(LibraryViewStyle.macCases, id: \.self) { style in
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
            // Find is the window's toolbar search field (`.searchable` in MacLibraryView). The
            // inspector toggle belongs to the inspector's own toolbar (`MacLibraryInspector`).
            ToolbarItem(placement: .primaryAction) {
                Button("Add Anime…", systemImage: "plus", action: addAnime)
                    .help(Text("Add anime from TMDb"))
            }
        }
    }
#endif
