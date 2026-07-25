//
//  LibraryInspectorDetailWorkspaceState.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/25.
//

import LibrarySync

enum LibraryInspectorDetailPersistenceAction: Equatable {
    case clear
    case persist(LibraryEntrySyncIdentity)
    case preserve
}

enum LibraryInspectorDetailLaunchRestorationAction: Equatable {
    case clearInvalidSavedIdentity
    case none
    case restore(String)
}

struct LibraryInspectorDetailWorkspaceState {
    private(set) var hasCompletedLaunchRestoration = false

    static func persistenceAction(
        for presentedDetailEntryIdentity: LibraryEntrySyncIdentity?,
        committedHostPresentation: LibraryEntryDetailHostPresentation?
    ) -> LibraryInspectorDetailPersistenceAction {
        guard let presentedDetailEntryIdentity else { return .clear }
        guard committedHostPresentation?.host == .inspector,
            committedHostPresentation?.isHostPresented == true
        else { return .preserve }
        return .persist(presentedDetailEntryIdentity)
    }

    mutating func initialRestorationAction(
        for host: LibraryEntryDetailHost,
        presentedDetailEntryIdentity: LibraryEntrySyncIdentity?,
        savedIdentityRawID: String?,
        isRestorableIdentity: (String) -> Bool
    ) -> LibraryInspectorDetailLaunchRestorationAction {
        guard !hasCompletedLaunchRestoration else { return .none }
        hasCompletedLaunchRestoration = true

        guard host == .inspector,
            presentedDetailEntryIdentity == nil,
            let savedIdentityRawID,
            !savedIdentityRawID.isEmpty
        else { return .none }
        guard isRestorableIdentity(savedIdentityRawID) else {
            return .clearInvalidSavedIdentity
        }
        return .restore(savedIdentityRawID)
    }
}
