//
//  OpenLibraryEntryIntent.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/14.
//

import AppIntents

/// Opens an entry's detail.
///
/// Also runs when the user taps the entry in Spotlight. On iOS it is a `TargetContentProvidingIntent`: the scene that receives the intent handles
/// it in `libraryWindowBehaviors`' `onAppIntentExecution`, so the detail opens in exactly one
/// window. macOS has no `TargetContentProvidingIntent`, so `perform()` hands the entry to the
/// frontmost library window, the same route an airing-reminder notification takes.
struct OpenLibraryEntryIntent: OpenIntent {
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

    #if os(macOS)
        @Dependency private var context: AppIntentLibraryContext

        @MainActor
        func perform() async throws -> some IntentResult {
            let entry = try context.entry(for: target.id)
            MacLibraryWindows.openEntry(entryIdentityRawID: entry.libraryIdentity.rawID)
            return .result()
        }
    #endif
}

#if !os(macOS)
    extension OpenLibraryEntryIntent: TargetContentProvidingIntent {}
#endif
