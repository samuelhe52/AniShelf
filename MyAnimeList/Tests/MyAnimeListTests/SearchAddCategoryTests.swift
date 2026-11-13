//
//  SearchAddCategoryTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/13.
//

import Foundation
import SwiftData
import Testing

@testable import DataProvider
@testable import MyAnimeList

@MainActor
struct SearchAddCategoryTests {
    @Test func sessionSnapshotsItsWindowAndKeepsOverridesLocal() {
        var firstWindow = SearchAddCategorySelection(defaultRule: .currentCategory, currentCategoryID: "A")
        let secondWindow = SearchAddCategorySelection(defaultRule: .currentCategory, currentCategoryID: "B")
        let uncategorized = SearchAddCategorySelection(defaultRule: .noCategory, currentCategoryID: "A")
        let all = SearchAddCategorySelection(defaultRule: .currentCategory, currentCategoryID: nil)
        firstWindow.categoryID = "C"
        #expect(firstWindow.categoryID == "C")
        #expect(secondWindow.categoryID == "B")
        #expect(uncategorized.categoryID == nil)
        #expect(all.categoryID == nil)
        #expect(SearchAddCategorySelection(defaultRule: .currentCategory, currentCategoryID: "A").categoryID == "A")
    }

    @Test func searchAddPersistsMembershipOnlyOnNewEntriesAndKeepsCategoryVisible() async throws {
        let context = Context()
        defer { context.cleanUp() }
        let store = context.store
        let category = try #require(store.createCategory(named: "A"))
        let existing = AnimeEntry(name: "Existing", type: .movie, tmdbID: 41)
        existing.updateCategoryMembership("other", isMember: true)
        try store.repository.newEntry(existing)

        let results = [
            SearchResult(tmdbID: 41, type: .movie),
            SearchResult(tmdbID: 42, type: .movie),
            SearchResult(tmdbID: 43, type: .season(seasonNumber: 1, parentSeriesID: 44))
        ]
        #expect(await store.newEntryFromSearchResults(results, categoryID: category.id, latestInfoFetcher: fetcher))
        try store.refreshLibrary()

        // Read through a fresh context, so this checks the saved payload as well as live models.
        let persisted = try ModelContext(store.dataProvider.sharedModelContainer).fetch(FetchDescriptor<AnimeEntry>())
        #expect(persisted.first { $0.tmdbID == 41 }?.categoryIDs == ["other"])
        #expect(persisted.first { $0.tmdbID == 42 }?.categoryIDs == [category.id])
        #expect(persisted.first { $0.tmdbID == 43 }?.categoryIDs == [category.id])
        #expect(persisted.first { $0.tmdbID == 44 }?.categoryIDs.isEmpty == true)
        #expect(persisted.first { $0.tmdbID == 44 }?.onDisplay == false)

        let scope = LibraryBrowseScope(store: store)
        scope.activeCategoryID = category.id
        scope.leaveCategoryToReveal(results[1].libraryIdentity)
        #expect(scope.activeCategoryID == category.id)
    }

    @Test(arguments: [false, true], [false, true])
    func invalidatedDestinationIsIgnoredAfterMetadataFetch(disableCategories: Bool, restoringHidden: Bool) async throws
    {
        let context = Context()
        defer { context.cleanUp() }
        let store = context.store
        let category = try #require(store.createCategory(named: "A"))
        if restoringHidden {
            let hidden = AnimeEntry(name: "Hidden", type: .movie, tmdbID: 42)
            hidden.setDisplayState(false)
            try store.repository.newEntry(hidden)
        }
        let entry = try #require(
            try await store.createNewEntry(
                tmdbID: 42, type: .movie, categoryID: category.id,
                latestInfoFetcher: { type, id, language in
                    await Task.yield()
                    await MainActor.run {
                        if disableCategories {
                            store.categoriesEnabled = false
                        } else {
                            store.deleteCategory(category.id)
                        }
                    }
                    return try await fetcher(type, id, language)
                }
            )
        )
        #expect(entry.categoryIDs.isEmpty)
    }

    @Test(arguments: [false, true])
    func concurrentDuplicateDoesNotAcquireTheLosingWindowsCategory(restoringHidden: Bool) async throws {
        let context = Context()
        defer { context.cleanUp() }
        let store = context.store
        let category = try #require(store.createCategory(named: "A"))
        let otherCategory = try #require(store.createCategory(named: "B"))
        if restoringHidden {
            let hidden = AnimeEntry(name: "Hidden", type: .movie, tmdbID: 42)
            hidden.setDisplayState(false)
            try store.repository.newEntry(hidden)
        }
        let result = try await store.createNewEntry(
            tmdbID: 42, type: .movie, categoryID: category.id,
            latestInfoFetcher: { type, id, language in
                // Simulate a second window inserting the same title while this add awaits metadata.
                try await MainActor.run {
                    if let existing = store.repository.existingEntry(identity: .init(entryType: type, tmdbID: id)) {
                        existing.updateCategoryMembership(otherCategory.id, isMember: true)
                        existing.updateDisplayState(true)
                        try store.repository.save()
                    } else {
                        let existing = AnimeEntry(name: "Other window", type: .movie, tmdbID: id)
                        existing.updateCategoryMembership(otherCategory.id, isMember: true)
                        try store.repository.newEntry(existing)
                    }
                }
                return try await fetcher(type, id, language)
            }
        )
        #expect(result == nil)
        #expect(
            store.repository.existingEntry(identity: .init(entryType: .movie, tmdbID: 42))?.categoryIDs == [
                otherCategory.id
            ])
        try store.refreshLibrary()
        let scope = LibraryBrowseScope(store: store)
        scope.activeCategoryID = otherCategory.id
        let browse = LibraryBrowseState()
        browse.jumpAfterAdd(
            to: .init(entryType: .movie, tmdbID: 42), categoryID: category.id, scope: scope, reveal: { _ in })
        #expect(scope.activeCategoryID == nil)
    }

    @Test(arguments: [false, true])
    func restoringHiddenEntryAppliesDestinationBeforeSaving(insertedDuringFetch: Bool) async throws {
        let context = Context()
        defer { context.cleanUp() }
        let store = context.store
        let oldCategory = try #require(store.createCategory(named: "Existing membership"))
        let destination = try #require(store.createCategory(named: "Destination"))
        if !insertedDuringFetch {
            let hidden = AnimeEntry(name: "Hidden parent", type: .series, tmdbID: 44)
            hidden.setDisplayState(false)
            hidden.updateCategoryMembership(oldCategory.id, isMember: true)
            try store.repository.newEntry(hidden)
        }
        let restored = try #require(
            try await store.createNewEntry(
                tmdbID: 44, type: .series, categoryID: destination.id,
                latestInfoFetcher: { type, id, language in
                    if insertedDuringFetch {
                        try await MainActor.run {
                            let hidden = AnimeEntry(name: "Concurrent hidden parent", type: .series, tmdbID: id)
                            hidden.setDisplayState(false)
                            hidden.updateCategoryMembership(oldCategory.id, isMember: true)
                            try store.repository.newEntry(hidden)
                        }
                    }
                    return try await fetcher(type, id, language)
                }
            )
        )
        #expect(restored.onDisplay)
        let persisted = try ModelContext(store.dataProvider.sharedModelContainer).fetch(FetchDescriptor<AnimeEntry>())
        #expect(persisted.count == 1)
        #expect(Set(persisted[0].categoryIDs) == [oldCategory.id, destination.id])
        #expect(persisted[0].onDisplay)
    }

    @Test(arguments: [false, true])
    func postAddJumpFollowsDestinationAndRevealsThroughFilters(deferred: Bool) async throws {
        let context = Context()
        defer { context.cleanUp() }
        let store = context.store
        let source = try #require(store.createCategory(named: "A"))
        let destination = try #require(store.createCategory(named: "B"))
        store.defaultNewEntryWatchStatus = .planToWatch
        let added = try #require(
            try await store.createNewEntry(
                tmdbID: 42, type: .movie, categoryID: destination.id, latestInfoFetcher: fetcher
            ))
        try store.refreshLibrary()
        let scope = LibraryBrowseScope(store: store)
        scope.activeCategoryID = source.id
        scope.filters = [.watched]
        let browse = LibraryBrowseState()
        var revealed: [LibraryEntryIdentity] = []
        let reveal: (LibraryEntryIdentity) -> Void = { id in
            #expect(scope.activeCategoryID == destination.id)
            #expect(scope.displayedEntry(for: id) != nil)
            revealed.append(id)
        }
        if deferred { browse.searchDidPresent() }
        browse.jumpAfterAdd(to: added.libraryIdentity, categoryID: destination.id, scope: scope, reveal: reveal)
        if deferred {
            #expect(revealed.isEmpty)
            #expect(scope.activeCategoryID == source.id)
            browse.searchSheetDidDismiss(scope: scope, reveal: reveal)
        }
        #expect(scope.activeCategoryID == destination.id)
        #expect(revealed == [added.libraryIdentity])
        #expect(browse.scrollRequest?.entryID == added.libraryIdentity)
        #expect(scope.filters.isEmpty)

        // Finding an existing entry uses the original All fallback, without following its category.
        scope.activeCategoryID = source.id
        browse.jump(to: added.libraryIdentity, scope: scope, reveal: { _ in })
        #expect(scope.activeCategoryID == nil)
    }

    @Test(arguments: [false, true])
    func postAddJumpUsesAllForNoneOrDeletedDestination(deletedDestination: Bool) async throws {
        let context = Context()
        defer { context.cleanUp() }
        let store = context.store
        let source = try #require(store.createCategory(named: "A"))
        let destination = try #require(store.createCategory(named: "B"))
        let added = try #require(
            try await store.createNewEntry(
                tmdbID: 42, type: .movie, categoryID: destination.id, latestInfoFetcher: fetcher
            ))
        try store.refreshLibrary()
        let scope = LibraryBrowseScope(store: store)
        scope.activeCategoryID = source.id
        let browse = LibraryBrowseState()
        browse.searchDidPresent()
        browse.jumpAfterAdd(
            to: added.libraryIdentity, categoryID: deletedDestination ? destination.id : nil,
            scope: scope, reveal: { _ in }
        )
        if deletedDestination { store.deleteCategory(destination.id) }
        browse.searchSheetDidDismiss(scope: scope, reveal: { _ in })
        #expect(scope.activeCategoryID == nil)
        #expect(scope.displayedEntry(for: added.libraryIdentity) != nil)
    }

    @Test func noDestinationLeavesNewEntriesUncategorized() async throws {
        let context = Context()
        defer { context.cleanUp() }
        let entry = try #require(
            try await context.store.createNewEntry(tmdbID: 42, type: .movie, latestInfoFetcher: fetcher)
        )
        #expect(entry.categoryIDs.isEmpty)
    }
}

@MainActor
fileprivate struct Context {
    let suiteName = "MyAnimeListTests.SearchAddCategory.\(UUID())"
    let store: LibraryStore

    init() {
        let defaults = UserDefaults(suiteName: suiteName)!
        store = LibraryStore(
            dataProvider: DataProvider(inMemory: true), preferences: LibraryPreferences(defaults: defaults))
        store.categoriesEnabled = true
    }

    func cleanUp() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

fileprivate let fetcher: LibraryEntryLatestInfoFetcher = { type, id, _ in
    (
        EntryMetadata(
            name: "Entry \(id)", nameTranslations: [:], overview: nil, overviewTranslations: [:],
            posterURL: nil, backdropURL: nil, logoURL: nil, tmdbID: id, onAirDate: nil, linkToDetails: nil, type: type
        ),
        AnimeEntryDetailDTO(language: "en-US", title: "Entry \(id)")
    )
}
