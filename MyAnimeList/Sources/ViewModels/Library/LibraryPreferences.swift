import DataProvider
import Foundation

@MainActor
struct LibraryPreferences {
    struct Snapshot {
        let groupStrategy: LibraryStore.LibraryGroupStrategy
        let sortStrategy: LibraryStore.AnimeSortStrategy
        let sortReversed: Bool
        let hideDroppedByDefault: Bool
        let defaultWatchStatus: AnimeEntry.WatchStatus
        let defaultFilters: Set<LibraryStore.AnimeFilter>
        let autoPrefetchImagesOnAddAndRestore: Bool
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Snapshot {
        Snapshot(
            groupStrategy: loadGroupStrategy(),
            sortStrategy: loadSortStrategy(),
            sortReversed: loadBool(forKey: .librarySortReversed, defaultValue: true),
            hideDroppedByDefault: loadBool(forKey: .libraryHideDroppedByDefault, defaultValue: false),
            defaultWatchStatus: loadDefaultWatchStatus(),
            defaultFilters: loadDefaultFilters(),
            autoPrefetchImagesOnAddAndRestore: loadBool(
                forKey: .libraryAutoPrefetchImagesOnAddAndRestore,
                defaultValue: false
            )
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

    private func loadGroupStrategy() -> LibraryStore.LibraryGroupStrategy {
        defaults
            .string(forKey: .libraryGroupStrategy)
            .flatMap(LibraryStore.LibraryGroupStrategy.init(rawValue:))
            ?? .none
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

    private func loadBool(forKey key: String, defaultValue: Bool) -> Bool {
        if defaults.object(forKey: key) != nil {
            defaults.bool(forKey: key)
        } else {
            defaultValue
        }
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
