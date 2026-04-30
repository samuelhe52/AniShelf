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
    static let searchTMDbLanguage = "SearchTMDbLanguage"
    static let searchPageQuery = "SearchPageQuery"
    static let searchMode = "SearchMode"
    static let persistedScrolledID = "PersistedScrolledID"
    static let librarySortStrategy = "LibrarySortStrategy"
    static let librarySortReversed = "LibrarySortReversed"
    static let libraryViewStyle = "LibraryViewStyle"

    static let allPreferenceKeys: [String] = [
        .preferredAnimeInfoLanguage,
        .searchTMDbLanguage,
        .searchPageQuery,
        .persistedScrolledID,
        .librarySortStrategy,
        .librarySortReversed,
        .libraryViewStyle
    ]
}

extension String {
    static let bundleIdentifier = "com.samuelhe.MyAnimeList"
}
