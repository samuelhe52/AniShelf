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
}

@Observable
@MainActor
final class EntryDetailSessionStore {
    private(set) var presentedSession: EntryDetailSession?

    func synchronizePresentedDetail(
        identity: LibraryEntrySyncIdentity?,
        repository: LibraryRepository,
        resolveEntry: (LibraryEntrySyncIdentity) -> AnimeEntry?
    ) {
        guard let identity else {
            presentedSession = nil
            return
        }

        guard presentedSession?.entryIdentity != identity else { return }
        guard let entry = resolveEntry(identity) else {
            presentedSession = nil
            return
        }

        presentedSession = EntryDetailSession(
            entry: entry,
            repository: repository
        )
    }

    func session(for identity: LibraryEntrySyncIdentity?) -> EntryDetailSession? {
        guard presentedSession?.entryIdentity == identity else { return nil }
        return presentedSession
    }
}
