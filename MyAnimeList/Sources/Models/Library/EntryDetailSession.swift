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
    let entry: AnimeEntry
    let entryIdentity: LibraryEntrySyncIdentity
    let model: EntryDetailViewModel
    let startsInEditingMode: Bool

    var presentation = EntryDetailPresentationState()
    var isEditingDetails: Bool
    var originalUserInfo: UserEntryInfo
    var originalTrackingUpdatedAt: Date?
    var conversion = EntryDetailConversionState()
    var didAutoScrollToEditingSection = false
    var hasPendingWatchedReviewOpportunity = false
    var isCharacterExpanded: Bool
    var isStaffExpanded: Bool
    var scrollPosition = ScrollPosition()

    var blocksHostMigration: Bool {
        presentation.blocksHostMigration || conversion.inProgress
    }

    init(
        entry: AnimeEntry,
        repository: LibraryRepository,
        startsInEditingMode: Bool = false,
        isCharacterExpanded: Bool? = nil,
        isStaffExpanded: Bool? = nil
    ) {
        self.entry = entry
        self.entryIdentity = entry.syncIdentity
        self.model = EntryDetailViewModel(repository: repository)
        self.startsInEditingMode = startsInEditingMode
        self.isEditingDetails = startsInEditingMode
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
}

@Observable
@MainActor
final class EntryDetailSessionStore {
    private(set) var presentedSession: EntryDetailSession?

    @discardableResult
    func synchronizePresentedDetail(
        identity: LibraryEntrySyncIdentity?,
        repository: LibraryRepository,
        resolveEntry: (LibraryEntrySyncIdentity) -> AnimeEntry?
    ) -> Bool {
        guard let identity else {
            presentedSession = nil
            return true
        }

        guard let entry = resolveEntry(identity) else {
            presentedSession = nil
            return false
        }
        guard presentedSession?.entry === entry else {
            presentedSession = EntryDetailSession(
                entry: entry,
                repository: repository
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
