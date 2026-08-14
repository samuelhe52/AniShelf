//
//  EntryDetailSession.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/14.
//

import DataProvider
import LibrarySync
import Observation
import SwiftUI

enum EntryDetailSheet: Identifiable, Equatable {
    case broadcastValidation
    case changePoster
    case sharing

    var id: Self { self }
}

struct EntryDetailPresentationState {
    var activeSheet: EntryDetailSheet?
    var showSeasonPicker = false
    var showSiblingSeasonWarning = false
    var episodeProgressCompletionPrompt: AnimeEntryEpisodeProgressCompletionPrompt?
    var dateUpdateSuggestion: AnimeEntryDateUpdateSuggestion?

    var blocksHostMigration: Bool {
        activeSheet != nil
            || showSeasonPicker
            || showSiblingSeasonWarning
            || episodeProgressCompletionPrompt != nil
            || dateUpdateSuggestion != nil
    }
}

struct EntryDetailConversionState {
    var inProgress = false
    var isFetchingSeasons = false
    var seasonNumberOptions: [Int] = []
}

@Observable
@MainActor
final class EntryDetailSession {
    let instanceID = UUID()
    let entry: AnimeEntry
    let entryIdentity: LibraryEntrySyncIdentity
    let model: EntryDetailViewModel
    let broadcast: EntryDetailBroadcastModel
    private let repository: LibraryRepository

    var presentation = EntryDetailPresentationState()
    var isEditingDetails = false
    var originalUserInfo: UserEntryInfo
    var originalTrackingUpdatedAt: Date?
    var conversion = EntryDetailConversionState()
    var hasPendingWatchedReviewOpportunity = false
    var isCharacterExpanded: Bool
    var isStaffExpanded: Bool
    var scrollPosition = ScrollPosition()
    private(set) var isAwaitingActiveSheetDismissalForHostChange = false

    var blocksHostMigration: Bool {
        presentation.blocksHostMigration
            || isAwaitingActiveSheetDismissalForHostChange
            || conversion.inProgress
    }

    init(
        entry: AnimeEntry,
        repository: LibraryRepository,
        broadcastEligibilityChecker: TMDbBroadcastEligibilityChecker = .init(),
        broadcastResolver: TVMazeResolver = TVMazeResolver(),
        isCharacterExpanded: Bool? = nil,
        isStaffExpanded: Bool? = nil
    ) {
        self.entry = entry
        self.entryIdentity = entry.syncIdentity
        self.repository = repository
        self.model = EntryDetailViewModel(repository: repository)
        self.broadcast = EntryDetailBroadcastModel(
            entryType: entry.type,
            tmdbID: entry.tmdbID,
            eligibilityChecker: broadcastEligibilityChecker,
            resolver: broadcastResolver
        )
        self.originalUserInfo = entry.userInfo
        self.originalTrackingUpdatedAt = entry.trackingUpdatedAt
        self.isCharacterExpanded =
            isCharacterExpanded
            ?? UserDefaults.standard.bool(
                forKey: .entryDetailCharactersExpandedByDefault,
                defaultValue: true
            )
        self.isStaffExpanded =
            isStaffExpanded
            ?? UserDefaults.standard.bool(
                forKey: .entryDetailStaffExpandedByDefault,
                defaultValue: false
            )
    }

    func save() throws {
        try repository.save()
    }

    func toggleFavorite() {
        repository.toggleFavorite(entry)
    }

    func updatePresentation(
        from hostPresentationID: UUID?,
        ifCurrent isCurrentHostPresentation: ((UUID) -> Bool)?,
        _ update: (inout EntryDetailPresentationState) -> Void
    ) {
        if let hostPresentationID {
            guard isCurrentHostPresentation?(hostPresentationID) == true else { return }
        }
        update(&presentation)
    }

    func dismissActiveSheetForHostChange() {
        guard presentation.activeSheet != nil else { return }
        isAwaitingActiveSheetDismissalForHostChange = true
        presentation.activeSheet = nil
    }

    func activeSheetDidDismiss() {
        isAwaitingActiveSheetDismissalForHostChange = false
    }
}

@Observable
@MainActor
final class EntryDetailSessionStore {
    private(set) var presentedSession: EntryDetailSession?
    private let broadcastEligibilityChecker: TMDbBroadcastEligibilityChecker
    private let broadcastResolver: TVMazeResolver

    init(
        broadcastEligibilityChecker: TMDbBroadcastEligibilityChecker = .init(),
        broadcastResolver: TVMazeResolver = TVMazeResolver()
    ) {
        self.broadcastEligibilityChecker = broadcastEligibilityChecker
        self.broadcastResolver = broadcastResolver
    }

    @discardableResult
    func synchronizePresentedDetail(
        identity: LibraryEntrySyncIdentity?,
        repository: LibraryRepository,
        resolveEntry: (LibraryEntrySyncIdentity) -> AnimeEntry?
    ) -> Bool {
        guard let identity else {
            presentedSession?.broadcast.cancel()
            presentedSession = nil
            return true
        }

        guard let entry = resolveEntry(identity) else {
            presentedSession?.broadcast.cancel()
            presentedSession = nil
            return false
        }
        guard presentedSession?.entry === entry else {
            presentedSession?.broadcast.cancel()
            presentedSession = EntryDetailSession(
                entry: entry,
                repository: repository,
                broadcastEligibilityChecker: broadcastEligibilityChecker,
                broadcastResolver: broadcastResolver
            )
            return true
        }

        return true
    }

    func session(for identity: LibraryEntrySyncIdentity?) -> EntryDetailSession? {
        guard presentedSession?.entryIdentity == identity else { return nil }
        return presentedSession
    }
}
