//
//  String+Extensions.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/5.
//

import Foundation

// UserDefaults entry names
extension String {
    static let preferredAnimeInfoLanguage = "PreferredAnimeInfoLanguage"
    static let useCurrentLocaleForAnimeInfoLanguage = "UseCurrentLocaleForAnimeInfoLanguage"
    static let searchTMDbLanguage = "SearchTMDbLanguage"
    static let searchPageQuery = "SearchPageQuery"
    static let searchMode = "SearchMode"
    static let persistedScrolledID = "PersistedScrolledID"
    static let libraryGroupStrategy = "LibraryGroupStrategy"
    static let librarySortStrategy = "LibrarySortStrategy"
    static let librarySortReversed = "LibrarySortReversed"
    static let libraryViewStyle = "LibraryViewStyle"
    static let libraryOpenDetailWithSingleTap = "LibraryOpenDetailWithSingleTap"
    static let entryDetailCharactersExpandedByDefault = "EntryDetailCharactersExpandedByDefault"
    static let entryDetailStaffExpandedByDefault = "EntryDetailStaffExpandedByDefault"
    static let libraryScoringEnabled = "LibraryScoringEnabled"
    static let libraryHideDroppedByDefault = "LibraryHideDroppedByDefault"
    static let libraryDefaultWatchStatus = "LibraryDefaultWatchStatus"
    static let libraryDefaultFilters = "LibraryDefaultFilters"
    static let libraryDefaultFilterPreset = "LibraryDefaultFilterPreset"
    static let libraryAutoPrefetchImagesOnAddAndRestore = "LibraryAutoPrefetchImagesOnAddAndRestore"
    static let useTMDbRelayServer = "UseTMDbRelayServer"
    static let lastSeenWhatsNewVersion = "LastSeenWhatsNewVersion"

    static let allPreferenceKeys: [String] = [
        .preferredAnimeInfoLanguage,
        .useCurrentLocaleForAnimeInfoLanguage,
        .searchTMDbLanguage,
        .searchPageQuery,
        .persistedScrolledID,
        .libraryGroupStrategy,
        .librarySortStrategy,
        .librarySortReversed,
        .libraryViewStyle,
        .libraryOpenDetailWithSingleTap,
        .entryDetailCharactersExpandedByDefault,
        .entryDetailStaffExpandedByDefault,
        .libraryScoringEnabled,
        .libraryHideDroppedByDefault,
        .libraryDefaultWatchStatus,
        .libraryDefaultFilters,
        .libraryAutoPrefetchImagesOnAddAndRestore,
        .useTMDbRelayServer,
        .lastSeenWhatsNewVersion
    ]
}

extension String {
    static let bundleIdentifier = "com.samuelhe.MyAnimeList"
}
