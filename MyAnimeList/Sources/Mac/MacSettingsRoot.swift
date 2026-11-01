//
//  MacSettingsRoot.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/15.
//

#if os(macOS)
    import SwiftUI

    /// Content of the Settings window (⌘,), which hosts the library profile and settings hub.
    struct MacSettingsRoot: View {
        /// Recovery, a newer store, or a missing TMDb key keeps the library closed.
        let isLibraryBlocked: Bool

        var body: some View {
            Group {
                if isLibraryBlocked {
                    ContentUnavailableView(
                        "Settings Unavailable",
                        systemImage: "gearshape",
                        description: Text("Finish setting up your library in the main window first.")
                    )
                } else {
                    LibraryProfileSettingsView()
                }
            }
            // A fixed width with a resizable height, as System Settings has. The Settings scene
            // sizes its window to this content.
            .frame(width: 900)
            .frame(minHeight: 560, idealHeight: 720)
        }
    }
#endif
