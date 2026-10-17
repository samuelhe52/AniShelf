//
//  AniShelfShortcuts.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/14.
//

import AppIntents

/// App Shortcuts available without any setup.
///
/// Phrases are localized in `AppShortcuts.xcstrings`. No phrase takes a library entry:
/// Spotlight lists an App Shortcut once per suggested value of an entity parameter, which
/// duplicated every indexed entry. Siri asks for the entry instead, and the indexed
/// entries themselves open the entry from Spotlight.
struct AniShelfShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenLibraryEntryIntent(),
            phrases: ["Open an entry in \(.applicationName)"],
            shortTitle: "Open Entry",
            systemImageName: "rectangle.portrait.on.rectangle.portrait"
        )
        AppShortcut(
            intent: MarkNextEpisodeWatchedIntent(),
            phrases: ["Watched the next episode in \(.applicationName)"],
            shortTitle: "Watched Next Episode",
            systemImageName: "play.square.stack"
        )
        AppShortcut(
            intent: SetWatchStatusIntent(),
            phrases: [
                "Mark an entry as \(\.$status) in \(.applicationName)",
                "Set watch status in \(.applicationName)"
            ],
            shortTitle: "Set Status",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: FindLibraryEntriesIntent(),
            phrases: [
                "Find \(\.$status) entries in \(.applicationName)",
                "Find entries in \(.applicationName)"
            ],
            shortTitle: "Find Entries",
            systemImageName: "magnifyingglass"
        )
    }
}

/// Lists entries with one status. The App Shortcut for finding entries.
///
/// The native Find action from `LibraryEntryQuery` covers richer filters, but App Shortcuts
/// need a concrete intent.
struct FindLibraryEntriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Entries by Status"
    static let description = IntentDescription("Lists the library entries with a watch status.")

    @Parameter(title: "Status")
    var status: WatchStatusAppEnum

    @Dependency private var context: AppIntentLibraryContext

    static var parameterSummary: some ParameterSummary {
        Summary("Find \(\.$status) entries")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[LibraryEntryEntity]> & ProvidesDialog {
        let entities = try context.entities(
            matching: [.status(status)],
            requiringAll: true,
            sortedBy: [LibraryEntrySortDescriptor(key: .name, ascending: true)],
            limit: nil
        )
        return .result(
            value: entities,
            dialog: "Here are your \(status.watchStatus.localizedStringResource) entries."
        )
    }
}
