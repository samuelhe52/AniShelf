//
//  OpenLibraryEntryIntent.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/14.
//

import AppIntents

/// Opens an entry's detail. Also runs when the user taps the entry in Spotlight.
///
/// As a `TargetContentProvidingIntent`, the scene that receives the intent handles it in
/// `libraryWindowBehaviors`' `onAppIntentExecution`, so the detail opens in exactly one window.
/// macOS has no `TargetContentProvidingIntent`, so the Mac app ships without this intent.
#if !os(macOS)
    struct OpenLibraryEntryIntent: OpenIntent, TargetContentProvidingIntent {
        static let title: LocalizedStringResource = "Open Library Entry"
        static let description = IntentDescription("Opens an entry's details in AniShelf.")

        @Parameter(title: "Entry")
        var target: LibraryEntryEntity

        static var parameterSummary: some ParameterSummary {
            Summary("Open \(\.$target)")
        }

        init() {}

        init(target: LibraryEntryEntity) {
            self.target = target
        }
    }
#endif
