//
//  AppIntentLibraryContext.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/14.
//

import AppIntents
import DataProvider
import Foundation

/// Library access shared by every intent and entity query.
///
/// `MyAnimeListApp` registers one instance with `AppDependencyManager`; intents read it
/// through `@Dependency`. Intents run in the app process, so this is the same store the
/// windows use.
@MainActor
final class AppIntentLibraryContext {
    let store: LibraryStore
    /// Reads the scoring and episode-tracking switches the detail view also honors.
    let defaults: UserDefaults
    private let allowsLibraryActivity: @MainActor () -> Bool
    private let hasTMDbAPIKey: @MainActor () -> Bool

    init(
        store: LibraryStore,
        defaults: UserDefaults = .standard,
        allowsLibraryActivity: @escaping @MainActor () -> Bool,
        hasTMDbAPIKey: @escaping @MainActor () -> Bool
    ) {
        self.store = store
        self.defaults = defaults
        self.allowsLibraryActivity = allowsLibraryActivity
        self.hasTMDbAPIKey = hasTMDbAPIKey
    }

    /// Throws when the app-level gates block library work.
    func requireUsableLibrary() throws {
        guard allowsLibraryActivity() else { throw LibraryIntentError.recoveryPending }
        guard !store.requiresDuplicateRepair else { throw LibraryIntentError.duplicateRepairRequired }
        guard hasTMDbAPIKey() else { throw LibraryIntentError.setupIncomplete }
    }

    /// The visible library entry an entity refers to.
    func entry(for entityID: LibraryEntryEntity.ID) throws -> AnimeEntry {
        try requireUsableLibrary()
        guard let identity = LibraryEntryIdentity(rawID: entityID),
            let entry = store.library.first(where: { $0.libraryIdentity == identity })
        else {
            throw LibraryIntentError.entryNotFound
        }
        return entry
    }
}

enum LibraryIntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case recoveryPending
    case duplicateRepairRequired
    case setupIncomplete
    case entryNotFound
    case notEpisodic
    case episodeTrackingDisabled
    case scoringDisabled
    case allEpisodesWatched

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .recoveryPending:
            "Open AniShelf to finish recovering your library first."
        case .duplicateRepairRequired:
            "Open AniShelf to repair duplicate library entries first."
        case .setupIncomplete:
            "Open AniShelf to finish setting up your TMDb API key first."
        case .entryNotFound:
            "This entry is no longer in your library."
        case .notEpisodic:
            "Movies don't have episode progress."
        case .episodeTrackingDisabled:
            "Episode progress tracking is turned off in AniShelf settings."
        case .scoringDisabled:
            "Scoring is turned off in AniShelf settings."
        case .allEpisodesWatched:
            "All known episodes are already watched."
        }
    }
}
