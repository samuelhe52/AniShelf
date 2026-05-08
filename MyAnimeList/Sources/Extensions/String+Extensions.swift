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
    static let librarySortStrategy = "LibrarySortStrategy"
    static let librarySortReversed = "LibrarySortReversed"
    static let libraryViewStyle = "LibraryViewStyle"
    static let libraryOpenDetailWithSingleTap = "LibraryOpenDetailWithSingleTap"
    static let libraryHideDroppedByDefault = "LibraryHideDroppedByDefault"
    static let libraryDefaultWatchStatus = "LibraryDefaultWatchStatus"
    static let libraryDefaultFilters = "LibraryDefaultFilters"
    static let libraryDefaultFilterPreset = "LibraryDefaultFilterPreset"
    static let libraryAutoPrefetchImagesOnAddAndRestore = "LibraryAutoPrefetchImagesOnAddAndRestore"
    static let useTMDbRelayServer = "UseTMDbRelayServer"

    static let allPreferenceKeys: [String] = [
        .preferredAnimeInfoLanguage,
        .useCurrentLocaleForAnimeInfoLanguage,
        .searchTMDbLanguage,
        .searchPageQuery,
        .persistedScrolledID,
        .librarySortStrategy,
        .librarySortReversed,
        .libraryViewStyle,
        .libraryOpenDetailWithSingleTap,
        .libraryHideDroppedByDefault,
        .libraryDefaultWatchStatus,
        .libraryDefaultFilters,
        .libraryAutoPrefetchImagesOnAddAndRestore,
        .useTMDbRelayServer
    ]
}

extension String {
    static let bundleIdentifier = "com.samuelhe.MyAnimeList"
}
