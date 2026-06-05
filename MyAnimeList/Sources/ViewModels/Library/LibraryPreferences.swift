import DataProvider
import Foundation
import LibrarySync

@MainActor
struct LibraryPreferences {
    struct Snapshot {
        let resolvedAnimeInfoLanguage: Language
        let groupStrategy: LibraryStore.LibraryGroupStrategy
        let sortStrategy: LibraryStore.AnimeSortStrategy
        let sortReversed: Bool
        let hideDroppedByDefault: Bool
        let defaultWatchStatus: AnimeEntry.WatchStatus
        let defaultFilters: Set<LibraryStore.AnimeFilter>
        let autoPrefetchImagesOnAddAndRestore: Bool
        let cloudSyncStatus: LibraryCloudSyncStatus
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var notificationObject: UserDefaults {
        defaults
    }

    func load() -> Snapshot {
        Snapshot(
            resolvedAnimeInfoLanguage: .resolvedAnimeInfoLanguage(defaults: defaults),
            groupStrategy: loadGroupStrategy(),
            sortStrategy: loadSortStrategy(),
            sortReversed: loadBool(forKey: .librarySortReversed, defaultValue: true),
            hideDroppedByDefault: loadBool(forKey: .libraryHideDroppedByDefault, defaultValue: false),
            defaultWatchStatus: loadDefaultWatchStatus(),
            defaultFilters: loadDefaultFilters(),
            autoPrefetchImagesOnAddAndRestore: loadBool(
                forKey: .libraryAutoPrefetchImagesOnAddAndRestore,
                defaultValue: false
            ),
            cloudSyncStatus: loadCloudSyncStatus()
        )
    }

    func saveHideDroppedByDefault(_ value: Bool) {
        defaults.setValue(value, forKey: .libraryHideDroppedByDefault)
    }

    func saveDefaultWatchStatus(_ value: AnimeEntry.WatchStatus) {
        defaults.setValue(value.preferenceValue, forKey: .libraryDefaultWatchStatus)
    }

    func saveDefaultFilters(_ value: Set<LibraryStore.AnimeFilter>) {
        defaults.setValue(value.map(\.id).sorted(), forKey: .libraryDefaultFilters)
    }

    func saveAutoPrefetchImagesOnAddAndRestore(_ value: Bool) {
        defaults.setValue(value, forKey: .libraryAutoPrefetchImagesOnAddAndRestore)
    }

    func saveGroupStrategy(_ value: LibraryStore.LibraryGroupStrategy) {
        defaults.setValue(value.rawValue, forKey: .libraryGroupStrategy)
    }

    func saveSortStrategy(_ value: LibraryStore.AnimeSortStrategy) {
        defaults.setValue(value.rawValue, forKey: .librarySortStrategy)
    }

    func saveSortReversed(_ value: Bool) {
        defaults.setValue(value, forKey: .librarySortReversed)
    }

    func saveCloudSyncStatus(_ status: LibraryCloudSyncStatus) {
        defaults.setValue(status.isEnabled, forKey: .libraryCloudSyncEnabled)
        defaults.setValue(status.bootstrapState.rawValue, forKey: .libraryCloudSyncBootstrapState)
        defaults.setValue(status.cloudKitAvailability.rawValue, forKey: .libraryCloudSyncCloudKitAvailability)
        saveOptional(status.currentPhase?.rawValue, forKey: .libraryCloudSyncCurrentPhase)
        saveOptional(status.lastResult?.rawValue, forKey: .libraryCloudSyncLastResult)
        saveOptional(status.lastTrigger, forKey: .libraryCloudSyncLastTrigger)
        saveOptional(status.lastAttemptDate, forKey: .libraryCloudSyncLastAttemptDate)
        saveOptional(status.lastSuccessfulSyncDate, forKey: .libraryCloudSyncLastSuccessfulSyncDate)
        saveOptional(status.lastFailureReason, forKey: .libraryCloudSyncLastFailureReason)
        saveOptional(status.degradedReason, forKey: .libraryCloudSyncDegradedReason)
        saveCodable(status.pendingConflictSummary, forKey: .libraryCloudSyncConflictSummary)
        saveCodable(status.retryState, forKey: .libraryCloudSyncRetryState)
    }

    func loadCloudSyncedSettingsSnapshot(
        fallbackUpdatedAt: Date = .distantPast
    ) -> LibrarySettingsSyncSnapshot {
        .init(
            updatedAt: cloudSyncedDefaultsUpdatedAt() ?? fallbackUpdatedAt,
            payload: cloudSyncedSettingsPayload()
        )
    }

    func cloudSyncedSettingsPayloadHash() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(cloudSyncedSettingsPayload())) ?? Data()
        return data.base64EncodedString()
    }

    func cloudSyncedDefaultsUpdatedAt() -> Date? {
        defaults.object(forKey: .libraryCloudSyncedDefaultsUpdatedAt) as? Date
    }

    func saveCloudSyncedDefaultsUpdatedAt(_ date: Date?) {
        saveOptional(date, forKey: .libraryCloudSyncedDefaultsUpdatedAt)
    }

    func applyCloudSyncedSettingsSnapshot(_ snapshot: LibrarySettingsSyncSnapshot) {
        let payload = snapshot.payload
        for key in String.cloudSyncedPreferenceKeys {
            guard let value = payload[key] else {
                defaults.removeObject(forKey: key)
                continue
            }
            switch value {
            case .bool(let boolValue):
                defaults.set(boolValue, forKey: key)
            case .string(let stringValue):
                defaults.set(stringValue, forKey: key)
            case .stringArray(let stringArrayValue):
                defaults.set(stringArrayValue, forKey: key)
            }
        }
    }

    private func loadGroupStrategy() -> LibraryStore.LibraryGroupStrategy {
        let strategy =
            defaults
            .string(forKey: .libraryGroupStrategy)
            .flatMap(LibraryStore.LibraryGroupStrategy.init(rawValue:))
            ?? .none
        if strategy == .score, !defaults.isLibraryScoringEnabled {
            return .none
        }
        return strategy
    }

    private func loadSortStrategy() -> LibraryStore.AnimeSortStrategy {
        defaults
            .string(forKey: .librarySortStrategy)
            .flatMap(LibraryStore.AnimeSortStrategy.init(rawValue:))
            ?? .dateStarted
    }

    private func loadDefaultWatchStatus() -> AnimeEntry.WatchStatus {
        defaults
            .string(forKey: .libraryDefaultWatchStatus)
            .flatMap(AnimeEntry.WatchStatus.init(preferenceValue:))
            ?? .planToWatch
    }

    private func loadDefaultFilters() -> Set<LibraryStore.AnimeFilter> {
        if let storedFilterIDs = defaults.array(forKey: .libraryDefaultFilters) as? [String] {
            return Set(storedFilterIDs.compactMap(LibraryStore.AnimeFilter.init(preferenceID:)))
        }
        if let legacyPreset = defaults.string(forKey: .libraryDefaultFilterPreset) {
            return legacyDefaultFilters(for: legacyPreset)
        }
        return []
    }

    private func loadCloudSyncStatus() -> LibraryCloudSyncStatus {
        var status = LibraryCloudSyncStatus.defaultValue
        status.isEnabled = loadBool(forKey: .libraryCloudSyncEnabled, defaultValue: false)
        status.bootstrapState =
            defaults
            .string(forKey: .libraryCloudSyncBootstrapState)
            .flatMap(LibraryCloudSyncBootstrapState.init(rawValue:))
            ?? .notStarted
        status.cloudKitAvailability =
            defaults
            .string(forKey: .libraryCloudSyncCloudKitAvailability)
            .flatMap(LibraryCloudKitAvailability.init(rawValue:))
            ?? .unknown
        status.pendingConflictSummary = loadCodable(
            LibraryCloudSyncConflictSummary.self,
            forKey: .libraryCloudSyncConflictSummary
        )
        status.retryState =
            loadCodable(LibraryCloudSyncRetryState.self, forKey: .libraryCloudSyncRetryState)
            ?? .idle
        status.currentPhase =
            defaults
            .string(forKey: .libraryCloudSyncCurrentPhase)
            .flatMap(LibraryCloudSyncPhase.init(rawValue:))
        status.lastResult =
            defaults
            .string(forKey: .libraryCloudSyncLastResult)
            .flatMap(LibraryCloudSyncResultClass.init(rawValue:))
        status.lastTrigger = defaults.string(forKey: .libraryCloudSyncLastTrigger)
        status.lastAttemptDate = defaults.object(forKey: .libraryCloudSyncLastAttemptDate) as? Date
        status.lastSuccessfulSyncDate =
            defaults.object(forKey: .libraryCloudSyncLastSuccessfulSyncDate) as? Date
        status.lastFailureReason = defaults.string(forKey: .libraryCloudSyncLastFailureReason)
        status.degradedReason = defaults.string(forKey: .libraryCloudSyncDegradedReason)
        return status
    }

    private func loadBool(forKey key: String, defaultValue: Bool) -> Bool {
        defaults.bool(forKey: key, defaultValue: defaultValue)
    }

    private func cloudSyncedSettingsPayload() -> [String: LibrarySettingsSyncSnapshot.Value] {
        var payload: [String: LibrarySettingsSyncSnapshot.Value] = [:]
        for key in String.cloudSyncedPreferenceKeys {
            switch key {
            case .libraryDefaultFilters:
                if let value = defaults.array(forKey: key) as? [String] {
                    payload[key] = .stringArray(value)
                }
            case .useCurrentLocaleForAnimeInfoLanguage,
                .librarySortReversed,
                .libraryOpenDetailWithSingleTap,
                .entryDetailCharactersExpandedByDefault,
                .entryDetailStaffExpandedByDefault,
                .libraryScoringEnabled,
                .episodeProgressTrackingEnabled,
                .libraryPosterProgressBarOverlayEnabled,
                .libraryHideDroppedByDefault,
                .libraryAutoPrefetchImagesOnAddAndRestore,
                .useTMDbRelayServer:
                if defaults.object(forKey: key) != nil {
                    payload[key] = .bool(defaults.bool(forKey: key))
                }
            default:
                if let value = defaults.string(forKey: key) {
                    payload[key] = .string(value)
                }
            }
        }
        return payload
    }

    private func saveCodable<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private func saveOptional(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func loadCodable<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func legacyDefaultFilters(for preset: String) -> Set<LibraryStore.AnimeFilter> {
        switch preset {
        case "favorites":
            [.favorited]
        case "watched":
            [.watched]
        case "planToWatch":
            [.planToWatch]
        case "watching":
            [.watching]
        case "dropped":
            [.dropped]
        default:
            []
        }
    }
}

extension AnimeEntry.WatchStatus {
    var preferenceValue: String {
        switch self {
        case .planToWatch:
            "planToWatch"
        case .watching:
            "watching"
        case .watched:
            "watched"
        case .dropped:
            "dropped"
        }
    }

    init?(preferenceValue: String) {
        switch preferenceValue {
        case "planToWatch":
            self = .planToWatch
        case "watching":
            self = .watching
        case "watched":
            self = .watched
        case "dropped":
            self = .dropped
        default:
            return nil
        }
    }
}
