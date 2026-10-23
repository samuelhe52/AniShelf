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
    static let defaultPosterLanguage = "DefaultPosterLanguage"
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
    // Mac-only presentation. Keep out of backup and CloudKit allowlists.
    static let macEntryDetailHeaderStyle = "MacEntryDetailHeaderStyle"
    static let showProductionCompanyInsteadOfRuntime = "ShowProductionCompanyInsteadOfRuntime"
    static let libraryScoringEnabled = "LibraryScoringEnabled"
    // Device-local. Keep out of backup and CloudKit allowlists.
    static let entryScoreHalfHintSeen = "EntryScoreHalfHintSeen"
    static let episodeProgressTrackingEnabled = "EpisodeProgressTrackingEnabled"
    static let broadcastScheduleEnabled = "BroadcastScheduleEnabled"
    // Device-local airing reminder state. Keep these out of backup and CloudKit allowlists.
    static let airingReminderSubscriptions = "AiringReminderSubscriptions"
    static let airingReminderDefaultTimingOffsetMinutes = "AiringReminderDefaultTimingOffsetMinutes"
    static let legacyAiringReminderLeadTimeMinutes = "AiringReminderLeadTimeMinutes"
    static let airingReminderWarning = "AiringReminderWarning"
    static let libraryPosterProgressBarOverlayEnabled = "LibraryPosterProgressBarOverlayEnabled"
    static let libraryHideDroppedByDefault = "LibraryHideDroppedByDefault"
    static let libraryDefaultWatchStatus = "LibraryDefaultWatchStatus"
    static let libraryDefaultFilters = "LibraryDefaultFilters"
    static let libraryDefaultFilterPreset = "LibraryDefaultFilterPreset"
    static let libraryCategoriesEnabled = "LibraryCategoriesEnabled"
    static let libraryCategoryStripEnabled = "LibraryCategoryStripEnabled"
    static let libraryCategories = "LibraryCategories"
    static let libraryAutoPrefetchImagesOnAddAndRestore = "LibraryAutoPrefetchImagesOnAddAndRestore"
    static let libraryLongTermGalleryPosterCachingEnabled = "LibraryLongTermGalleryPosterCachingEnabled"
    static let useSoftNavigationBarEdges = "UseSoftNavigationBarEdges"
    // Device-local share-sheet settings. Keep these out of the backup and CloudKit allowlists below.
    static let rememberShareSheetSettings = "RememberShareSheetSettings"
    static let shareSheetLanguage = "ShareSheetLanguage"
    static let shareSheetUsesRoundedCorners = "ShareSheetUsesRoundedCorners"
    static let shareSheetRoundedExportFormat = "ShareSheetRoundedExportFormat"
    static let shareSheetExportSize = "ShareSheetExportSize"
    // Device-local, since installed apps differ per device. Keep out of backup and CloudKit allowlists.
    static let libraryOpenInSwipeDestination = "LibraryOpenInSwipeDestination"
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
    static let libraryCloudSyncRestoration = "LibraryCloudSyncRestoration"
    static let libraryCloudSyncPendingReconstruction = "LibraryCloudSyncPendingReconstruction"
    static let libraryCloudSyncQuarantinedRecordCount = "LibraryCloudSyncQuarantinedRecordCount"
    static let libraryCloudSyncRejectedUploadCount = "LibraryCloudSyncRejectedUploadCount"
    static let libraryCloudSyncLastFailurePhase = "LibraryCloudSyncLastFailurePhase"
    static let libraryCloudSyncLastFailureReason = "LibraryCloudSyncLastFailureReason"
    static let libraryCloudSyncDegradedReason = "LibraryCloudSyncDegradedReason"
    static let libraryCloudSyncCloudLibraryDeletedByUser = "LibraryCloudSyncCloudLibraryDeletedByUser"
    static let libraryCloudSyncLastCompletedScope = "LibraryCloudSyncLastCompletedScope"
    static let libraryCloudSyncedDefaultsUpdatedAt = "LibraryCloudSyncedDefaultsUpdatedAt"
    static let useTMDbRelayServer = "UseTMDbRelayServer"
    static let lastSeenWhatsNewVersion = "LastSeenWhatsNewVersion"

    static let allPreferenceKeys: [String] = [
        .preferredAnimeInfoLanguage,
        .useCurrentLocaleForAnimeInfoLanguage,
        .defaultPosterLanguage,
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
        .libraryCategoriesEnabled,
        .libraryCategoryStripEnabled,
        .libraryCategories,
        .useSoftNavigationBarEdges,
        .useTMDbRelayServer,
        .lastSeenWhatsNewVersion
    ]

    // Sort, group and sort direction are per-window browse state, so they stay on this device.
    static let cloudSyncedPreferenceKeys: [String] = [
        .preferredAnimeInfoLanguage,
        .useCurrentLocaleForAnimeInfoLanguage,
        .defaultPosterLanguage,
        .searchTMDbLanguage,
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
        .useTMDbRelayServer,
        .libraryCategoriesEnabled,
        .libraryCategoryStripEnabled,
        .libraryCategories
    ]
}

extension String {
    static let bundleIdentifier = "com.samuelhe.MyAnimeList"
}
