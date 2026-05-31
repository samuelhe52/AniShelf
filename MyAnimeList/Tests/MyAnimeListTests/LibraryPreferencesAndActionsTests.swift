//
//  LibraryPreferencesAndActionsTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/5/10.
//

import Foundation
import Testing

@testable import DataProvider
@testable import LibrarySync
@testable import MyAnimeList

struct LibraryPreferencesAndActionsTests {
    @Test func testSingleTapDetailPreferenceDefaultsAndBackupInclusion() {
        let suiteName = "MyAnimeListTests.SingleTapDetailPreference"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(defaults.object(forKey: .libraryOpenDetailWithSingleTap) == nil)
        #expect(defaults.bool(forKey: .libraryOpenDetailWithSingleTap) == false)

        defaults.set(true, forKey: .libraryOpenDetailWithSingleTap)
        #expect(defaults.bool(forKey: .libraryOpenDetailWithSingleTap))

        #expect(String.allPreferenceKeys.contains(.libraryOpenDetailWithSingleTap))
    }

    @Test func testEntryDetailExpansionPreferenceDefaultsAndBackupInclusion() {
        let suiteName = "MyAnimeListTests.EntryDetailExpansionPreferences"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(defaults.object(forKey: .entryDetailCharactersExpandedByDefault) == nil)
        #expect(defaults.bool(forKey: .entryDetailCharactersExpandedByDefault) == false)
        #expect(defaults.object(forKey: .entryDetailStaffExpandedByDefault) == nil)
        #expect(defaults.bool(forKey: .entryDetailStaffExpandedByDefault) == false)

        defaults.set(false, forKey: .entryDetailCharactersExpandedByDefault)
        defaults.set(true, forKey: .entryDetailStaffExpandedByDefault)

        #expect(!defaults.bool(forKey: .entryDetailCharactersExpandedByDefault))
        #expect(defaults.bool(forKey: .entryDetailStaffExpandedByDefault))
        #expect(String.allPreferenceKeys.contains(.entryDetailCharactersExpandedByDefault))
        #expect(String.allPreferenceKeys.contains(.entryDetailStaffExpandedByDefault))
    }

    @Test func testPosterProgressBarOverlayPreferenceDefaultsAndBackupInclusion() {
        let suiteName = "MyAnimeListTests.PosterProgressBarOverlayPreference"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(defaults.object(forKey: .libraryPosterProgressBarOverlayEnabled) == nil)
        #expect(defaults.bool(forKey: .libraryPosterProgressBarOverlayEnabled) == false)
        #expect(defaults.bool(forKey: .libraryPosterProgressBarOverlayEnabled, defaultValue: true))
        #expect(defaults.isLibraryPosterProgressBarOverlayEnabled)

        defaults.set(false, forKey: .libraryPosterProgressBarOverlayEnabled)

        #expect(!defaults.isLibraryPosterProgressBarOverlayEnabled)
        #expect(String.allPreferenceKeys.contains(.libraryPosterProgressBarOverlayEnabled))
    }

    @Test @MainActor func testLibraryGroupStrategyPreferenceRoundTripAndBackupInclusion() {
        let suiteName = "MyAnimeListTests.LibraryGroupStrategy"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = LibraryPreferences(defaults: defaults)

        #expect(preferences.load().groupStrategy == .none)

        preferences.saveGroupStrategy(.score)
        #expect(preferences.load().groupStrategy == .score)

        defaults.set("invalid", forKey: .libraryGroupStrategy)
        #expect(preferences.load().groupStrategy == .none)

        #expect(String.allPreferenceKeys.contains(.libraryGroupStrategy))
    }

    @Test @MainActor func testLibraryDefaultsPersistMultipleFiltersAndNewEntryStatus() throws {
        let defaults = UserDefaults.standard
        let keys = [
            String.libraryDefaultWatchStatus,
            String.libraryDefaultFilters,
            String.libraryDefaultFilterPreset,
            String.libraryAutoPrefetchImagesOnAddAndRestore
        ]
        let originalValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })

        defer {
            for key in keys {
                if let value = originalValues[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(
            AnimeEntry.WatchStatus.watching.preferenceValue,
            forKey: .libraryDefaultWatchStatus
        )
        defaults.set(
            [
                LibraryStore.AnimeFilter.favorited.id,
                LibraryStore.AnimeFilter.watched.id
            ],
            forKey: .libraryDefaultFilters
        )
        defaults.removeObject(forKey: .libraryDefaultFilterPreset)
        defaults.set(false, forKey: .libraryAutoPrefetchImagesOnAddAndRestore)

        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))

        #expect(store.defaultFilters == Set([.favorited, .watched]))
        #expect(store.filters == Set([.favorited, .watched]))
        #expect(store.defaultNewEntryWatchStatus == .watching)

        store.newEntryFromBasicInfo(
            BasicInfo(
                name: "Defaulted Entry",
                nameTranslations: [:],
                overview: nil,
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 999_999,
                onAirDate: nil,
                linkToDetails: nil,
                type: .movie
            )
        )
        try store.refreshLibrary()

        let entry = try #require(store.library.first(where: { $0.tmdbID == 999_999 }))
        #expect(entry.watchStatus == .watching)
    }

    @Test @MainActor func testApplyNewEntryDefaultsDoesNotStampTrackingClockForUntouchedTrackingState() {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 777)

        store.defaultNewEntryWatchStatus = .planToWatch
        store.applyNewEntryDefaults(to: entry)

        #expect(entry.watchStatus == .planToWatch)
        #expect(entry.libraryUpdatedAt != nil)
        #expect(entry.trackingUpdatedAt == nil)
    }

    @Test @MainActor func testApplyNewEntryDefaultsStampsTrackingClockWhenDefaultStatusChanges() {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry.template(id: 778)

        store.defaultNewEntryWatchStatus = .watching
        store.applyNewEntryDefaults(to: entry)

        #expect(entry.watchStatus == .watching)
        #expect(entry.libraryUpdatedAt != nil)
        #expect(entry.trackingUpdatedAt != nil)
    }

    @Test @MainActor func testLibraryImageCacheCollectsRelatedDetailURLs() throws {
        let posterURL = try #require(URL(string: "https://example.com/poster.jpg"))
        let backdropURL = try #require(URL(string: "https://example.com/backdrop.jpg"))
        let heroURL = try #require(URL(string: "https://example.com/hero.jpg"))
        let logoURL = try #require(URL(string: "https://example.com/logo.png"))
        let characterURL = try #require(URL(string: "https://example.com/character.jpg"))
        let staffURL = try #require(URL(string: "https://example.com/staff.jpg"))
        let seasonURL = try #require(URL(string: "https://example.com/season.jpg"))
        let episodeURL = try #require(URL(string: "https://example.com/episode.jpg"))

        let entry = AnimeEntry(
            name: "Cache Test",
            type: .series,
            posterURL: posterURL,
            backdropURL: backdropURL,
            tmdbID: 4
        )
        entry.detail = AnimeEntryDetail(
            language: "en",
            title: "Cache Test",
            heroImageURL: heroURL,
            logoImageURL: logoURL,
            characters: [
                AnimeEntryCharacter(
                    id: 1,
                    characterName: "Character",
                    actorName: "Actor",
                    profileURL: characterURL
                )
            ],
            staff: [
                AnimeEntryStaff(
                    id: 10,
                    name: "Director",
                    role: "Director",
                    profileURL: staffURL
                )
            ],
            seasons: [
                AnimeEntrySeasonSummary(
                    id: 2,
                    seasonNumber: 1,
                    title: "Season",
                    posterURL: seasonURL
                )
            ],
            episodes: [
                AnimeEntryEpisodeSummary(
                    id: 3,
                    episodeNumber: 1,
                    title: "Episode",
                    imageURL: episodeURL
                )
            ]
        )

        let urls = LibraryImageCacheService.relatedImageURLs(for: entry)

        #expect(
            urls
                == Set([
                    posterURL,
                    backdropURL,
                    heroURL,
                    logoURL,
                    characterURL,
                    staffURL,
                    seasonURL,
                    episodeURL
                ])
        )
    }

    @Test @MainActor func testLibraryProfileSettingsActionsCreateBackupReturnsArchive() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let actions = LibraryProfileSettingsActions(store: store)

        let backupURL = try actions.createBackup()

        #expect(FileManager.default.fileExists(atPath: backupURL.path()))
    }

    @Test @MainActor func testLibraryProfileSettingsActionsClearLibraryRemovesEntries() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        store.newEntryFromBasicInfo(
            BasicInfo(
                name: "Clear Me",
                nameTranslations: [:],
                overview: nil,
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 100_001,
                onAirDate: nil,
                linkToDetails: nil,
                type: .movie
            )
        )
        try store.refreshLibrary()
        #expect(store.library.count == 1)

        let actions = LibraryProfileSettingsActions(store: store)
        actions.clearLibrary()
        try store.refreshLibrary()

        #expect(store.library.isEmpty)
    }

    @Test @MainActor func testLibrarySyncRecorderQueuesUpsertsAndIgnoresMetadataOnlySaves() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let entry = AnimeEntry(
            name: "Tracked Entry",
            type: .series,
            tmdbID: 200_001
        )
        store.applyNewEntryDefaults(to: entry)

        try store.repository.newEntry(entry)

        var queue = store.syncChangeRecorder.dirtyQueueStore.load()
        #expect(queue.entries.count == 1)
        #expect(queue.entries.first?.identity.rawID == entry.syncIdentity.rawID)

        entry.name = "Metadata Only"
        try store.repository.save()

        queue = store.syncChangeRecorder.dirtyQueueStore.load()
        #expect(queue.entries.count == 1)

        entry.updateFavorite(true)
        try store.repository.save()

        queue = store.syncChangeRecorder.dirtyQueueStore.load()
        #expect(queue.entries.count == 1)
        if case .upsert(let pendingUpsert)? = queue.entries.first {
            #expect(pendingUpsert.dirtyAt == entry.trackingUpdatedAt)
        } else {
            #expect(Bool(false))
        }
    }

    @Test @MainActor func testLibrarySyncRecorderQueuesDeleteTombstonesAndBulkDeletes() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let first = AnimeEntry(
            name: "Delete Me 1",
            type: .movie,
            tmdbID: 300_001
        )
        let second = AnimeEntry(
            name: "Delete Me 2",
            type: .movie,
            tmdbID: 300_002
        )
        store.applyNewEntryDefaults(to: first)
        store.applyNewEntryDefaults(to: second)
        try store.repository.newEntry(first)
        try store.repository.newEntry(second)

        try store.repository.deleteEntry(first)

        var queue = store.syncChangeRecorder.dirtyQueueStore.load()
        #expect(queue.entries.count == 2)
        #expect(queue.entries.contains { entry in
            guard case .delete(let pendingDelete) = entry else { return false }
            return pendingDelete.identity == first.syncIdentity
        })

        let actions = LibraryProfileSettingsActions(store: store)
        actions.clearLibrary()

        queue = store.syncChangeRecorder.dirtyQueueStore.load()
        #expect(queue.entries.count == 2)
        #expect(queue.entries.allSatisfy {
            if case .delete = $0 { return true }
            return false
        })
    }

    @Test @MainActor func testRefreshInfosIncludesSharedHiddenParentEntryOnce() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        let parent = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209_867
        )
        parent.onDisplay = false

        let firstSeason = AnimeEntry(
            name: "Season 1",
            type: .season(seasonNumber: 1, parentSeriesID: 209_867),
            tmdbID: 400_234
        )
        firstSeason.parentSeriesEntry = parent

        let secondSeason = AnimeEntry(
            name: "Season 2",
            type: .season(seasonNumber: 2, parentSeriesID: 209_867),
            tmdbID: 400_235
        )
        secondSeason.parentSeriesEntry = parent

        try store.repository.newEntry(parent)
        try store.repository.newEntry(firstSeason)
        try store.repository.newEntry(secondSeason)
        try store.refreshLibrary()

        #expect(store.library.count == 2)

        let capturedEntries = try LibraryProfileSettingsActions.getRefreshEntries(for: store)

        #expect(capturedEntries.count == 3)
        #expect(Set(capturedEntries.map(\.id)).count == 3)
        #expect(capturedEntries.filter { !$0.onDisplay && $0.tmdbID == 209_867 }.count == 1)
    }

    @Test @MainActor func testHydrateHiddenHelperParentAppliesDefaultsAndDetail() throws {
        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        store.defaultNewEntryWatchStatus = .watching

        let hiddenParent = AnimeEntry(
            name: "Frieren",
            type: .series,
            tmdbID: 209_867
        )
        hiddenParent.onDisplay = false
        try store.repository.newEntry(hiddenParent)

        try store.hydrateExistingEntry(
            hiddenParent,
            from: BasicInfo(
                name: "Frieren: Beyond Journey's End",
                nameTranslations: [:],
                overview: "Elf mage travels onward.",
                overviewTranslations: [:],
                posterURL: nil,
                backdropURL: nil,
                logoURL: nil,
                tmdbID: 209_867,
                onAirDate: nil,
                linkToDetails: nil,
                type: .series
            ),
            detail: AnimeEntryDetailDTO(
                language: "en-US",
                title: "Frieren: Beyond Journey's End",
                runtimeMinutes: 24,
                episodeCount: 28,
                seasonCount: 1
            )
        )

        #expect(hiddenParent.onDisplay)
        #expect(hiddenParent.watchStatus == .watching)
        #expect(hiddenParent.dateStarted == nil)
        #expect(hiddenParent.detail?.runtimeMinutes == 24)
        #expect(hiddenParent.detail?.episodeCount == 28)
        #expect(hiddenParent.name == "Frieren: Beyond Journey's End")

        try store.refreshLibrary()
        #expect(store.library.map(\.tmdbID) == [209_867])
    }

    @Test @MainActor func testSupportStoreOrdersProductsByCanonicalTierOrder() throws {
        let products: [any SupportStoreProduct] = [
            MockSupportProduct(id: SupportTipTier.large.productID, displayName: "Tip Large", displayPrice: "$6.99"),
            MockSupportProduct(id: SupportTipTier.small.productID, displayName: "Tip Small", displayPrice: "$0.99"),
            MockSupportProduct(id: SupportTipTier.medium.productID, displayName: "Tip Medium", displayPrice: "$2.99")
        ]

        let catalog = try SupportStore.makeCatalog(from: products)

        #expect(catalog.map(\.id) == SupportTipTier.allCases.map(\.productID))
    }

    @Test @MainActor func testSupportStorePurchaseMapsSuccessAndFinishesTransaction() async {
        let transaction = MockSupportTransaction()
        let store = SupportStore(
            provider: MockSupportProvider(
                products: [
                    MockSupportProduct(
                        id: SupportTipTier.small.productID, displayName: "Tip Small", displayPrice: "$0.99",
                        purchaseResult: .success(transaction)),
                    MockSupportProduct(
                        id: SupportTipTier.medium.productID, displayName: "Tip Medium", displayPrice: "$2.99"),
                    MockSupportProduct(
                        id: SupportTipTier.large.productID, displayName: "Tip Large", displayPrice: "$6.99")
                ]
            )
        )

        await store.loadProducts()
        let outcome = await store.purchase(id: SupportTipTier.small.productID)

        #expect(outcome == .success)
        #expect(transaction.finishCallCount == 1)
    }

    @Test @MainActor func testSupportStorePurchaseMapsUserCancelledPendingAndFailure() async {
        let cancelledStore = SupportStore(
            provider: MockSupportProvider(
                products: [
                    MockSupportProduct(
                        id: SupportTipTier.small.productID, displayName: "Tip Small", displayPrice: "$0.99",
                        purchaseResult: .userCancelled),
                    MockSupportProduct(
                        id: SupportTipTier.medium.productID, displayName: "Tip Medium", displayPrice: "$2.99"),
                    MockSupportProduct(
                        id: SupportTipTier.large.productID, displayName: "Tip Large", displayPrice: "$6.99")
                ]
            )
        )
        await cancelledStore.loadProducts()
        #expect(await cancelledStore.purchase(id: SupportTipTier.small.productID) == .userCancelled)

        let pendingStore = SupportStore(
            provider: MockSupportProvider(
                products: [
                    MockSupportProduct(
                        id: SupportTipTier.small.productID, displayName: "Tip Small", displayPrice: "$0.99",
                        purchaseResult: .pending),
                    MockSupportProduct(
                        id: SupportTipTier.medium.productID, displayName: "Tip Medium", displayPrice: "$2.99"),
                    MockSupportProduct(
                        id: SupportTipTier.large.productID, displayName: "Tip Large", displayPrice: "$6.99")
                ]
            )
        )
        await pendingStore.loadProducts()
        #expect(await pendingStore.purchase(id: SupportTipTier.small.productID) == .pending)

        let failingStore = SupportStore(
            provider: MockSupportProvider(
                products: [
                    MockSupportProduct(
                        id: SupportTipTier.small.productID, displayName: "Tip Small", displayPrice: "$0.99",
                        error: MockSupportError.purchaseFailed),
                    MockSupportProduct(
                        id: SupportTipTier.medium.productID, displayName: "Tip Medium", displayPrice: "$2.99"),
                    MockSupportProduct(
                        id: SupportTipTier.large.productID, displayName: "Tip Large", displayPrice: "$6.99")
                ]
            )
        )
        await failingStore.loadProducts()
        #expect(
            await failingStore.purchase(id: SupportTipTier.small.productID)
                == .failed(MockSupportError.purchaseFailed.localizedDescription)
        )
    }

    @Test func testSettingsPresentationStateRoutesSupportSheet() {
        var state = LibraryProfileSettingsPresentationState()

        state.presentSupportSheet()

        #expect(state.presentedSheet == .support)
    }
}

fileprivate struct MockSupportProvider: SupportStoreProviding {
    let products: [MockSupportProduct]
    var fetchError: Error?

    func fetchProducts(identifiers: [String]) async throws -> [any SupportStoreProduct] {
        if let fetchError {
            throw fetchError
        }

        return products.map { $0 as any SupportStoreProduct }
    }
}

fileprivate struct MockSupportProduct: SupportStoreProduct {
    let id: String
    let displayName: String
    let displayPrice: String
    var purchaseResult: SupportPurchaseResult = .pending
    var error: Error?

    func purchase() async throws -> SupportPurchaseResult {
        if let error {
            throw error
        }

        return purchaseResult
    }
}

fileprivate final class MockSupportTransaction: SupportTransactionFinishing {
    private(set) var finishCallCount = 0

    func finish() async {
        finishCallCount += 1
    }
}

fileprivate enum MockSupportError: LocalizedError {
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .purchaseFailed:
            "Mock purchase failed."
        }
    }
}
