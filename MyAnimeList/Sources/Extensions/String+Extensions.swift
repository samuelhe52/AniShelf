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
    static let libraryLastInspectorDetailEntryIdentity = "LibraryLastInspectorDetailEntryIdentity"
    static let libraryGroupStrategy = "LibraryGroupStrategy"
    static let librarySortStrategy = "LibrarySortStrategy"
    static let librarySortReversed = "LibrarySortReversed"
    static let libraryViewStyle = "LibraryViewStyle"
    static let libraryOpenDetailWithSingleTap = "LibraryOpenDetailWithSingleTap"
    static let entryDetailCharactersExpandedByDefault = "EntryDetailCharactersExpandedByDefault"
    static let entryDetailStaffExpandedByDefault = "EntryDetailStaffExpandedByDefault"
    static let showProductionCompanyInsteadOfRuntime = "ShowProductionCompanyInsteadOfRuntime"
    static let libraryScoringEnabled = "LibraryScoringEnabled"
    static let episodeProgressTrackingEnabled = "EpisodeProgressTrackingEnabled"
    static let broadcastScheduleEnabled = "BroadcastScheduleEnabled"
    // Device-local notification state. Keep these out of backup and CloudKit allowlists.
    static let episodeNotificationSubscriptions = "EpisodeNotificationSubscriptions"
    static let episodeNotificationLeadTimeMinutes = "EpisodeNotificationLeadTimeMinutes"
    static let episodeNotificationWarning = "EpisodeNotificationWarning"
    static let libraryPosterProgressBarOverlayEnabled = "LibraryPosterProgressBarOverlayEnabled"
    static let libraryHideDroppedByDefault = "LibraryHideDroppedByDefault"
    static let libraryDefaultWatchStatus = "LibraryDefaultWatchStatus"
    static let libraryDefaultFilters = "LibraryDefaultFilters"
    static let libraryDefaultFilterPreset = "LibraryDefaultFilterPreset"
    static let libraryAutoPrefetchImagesOnAddAndRestore = "LibraryAutoPrefetchImagesOnAddAndRestore"
    static let libraryLongTermGalleryPosterCachingEnabled = "LibraryLongTermGalleryPosterCachingEnabled"
    static let useSoftNavigationBarEdges = "UseSoftNavigationBarEdges"
    // Device-local share-sheet settings. Keep these out of the backup and CloudKit allowlists below.
    static let rememberShareSheetSettings = "RememberShareSheetSettings"
    static let shareSheetLanguage = "ShareSheetLanguage"
    static let shareSheetUsesRoundedCorners = "ShareSheetUsesRoundedCorners"
    static let shareSheetRoundedExportFormat = "ShareSheetRoundedExportFormat"
    static let shareSheetExportSize = "ShareSheetExportSize"
    static let libraryCloudSyncEnabled = "LibraryCloudSyncEnabled"
    static let libraryCloudSyncBootstrapState = "LibraryCloudSyncBootstrapState"
    static let libraryCloudSyncCloudKitAvailability = "LibraryCloudSyncCloudKitAvailability"
    static let libraryCloudSyncConflictSummary = "LibraryCloudSyncConflictSummary"
    static let libraryCloudSyncRetryState = "LibraryCloudSyncRetryState"
    static let libraryCloudSyncCurrentPhase = "LibraryCloudSyncCurrentPhase"
    static let libraryCloudSyncLastResult = "LibraryCloudSyncLastResult"
    static let libraryCloudSyncLastTrigger = "LibraryCloudSyncLastTrigger"
    static let libraryCloudSyncLastAttemptDate = "LibraryCloudSyncLastAttemptDate"
    static let libraryCloudSyncLastSuccessfulSyncDate = "LibraryCloudSyncLastSuccessfulSyncDate"
    static let libraryCloudSyncLastReconciledCloudSyncedSettingsUpdatedAt =
        "LibraryCloudSyncLastReconciledCloudSyncedSettingsUpdatedAt"
    static let libraryCloudSyncLastFailureReason = "LibraryCloudSyncLastFailureReason"
    static let libraryCloudSyncDegradedReason = "LibraryCloudSyncDegradedReason"
    static let libraryCloudSyncedDefaultsUpdatedAt = "LibraryCloudSyncedDefaultsUpdatedAt"
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
        .showProductionCompanyInsteadOfRuntime,
        .libraryScoringEnabled,
        .episodeProgressTrackingEnabled,
        .broadcastScheduleEnabled,
        .libraryPosterProgressBarOverlayEnabled,
        .libraryHideDroppedByDefault,
        .libraryDefaultWatchStatus,
        .libraryDefaultFilters,
        .libraryAutoPrefetchImagesOnAddAndRestore,
        .libraryLongTermGalleryPosterCachingEnabled,
        .useSoftNavigationBarEdges,
        .useTMDbRelayServer,
        .lastSeenWhatsNewVersion
    ]

    static let cloudSyncedPreferenceKeys: [String] = [
        .preferredAnimeInfoLanguage,
        .useCurrentLocaleForAnimeInfoLanguage,
        .searchTMDbLanguage,
        .libraryGroupStrategy,
        .librarySortStrategy,
        .librarySortReversed,
        .libraryOpenDetailWithSingleTap,
        .entryDetailCharactersExpandedByDefault,
        .entryDetailStaffExpandedByDefault,
        .showProductionCompanyInsteadOfRuntime,
        .libraryScoringEnabled,
        .episodeProgressTrackingEnabled,
        .broadcastScheduleEnabled,
        .libraryPosterProgressBarOverlayEnabled,
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
