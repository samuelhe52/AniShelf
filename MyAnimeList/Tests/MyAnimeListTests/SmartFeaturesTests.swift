//
//  SmartFeaturesTests.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/29.
//

import DataProvider
import Foundation
import FoundationModels
import Security
import Testing

@testable import MyAnimeList

@MainActor
struct SmartFeaturesTests {
    // MARK: - Plan filter

    @Test func onlyTheUsersOwnDataFiltersLocally() {
        let library = [
            entry(
                "Frieren", id: 1, year: 2023, genres: [10765], status: .watched, score: 5, favorite: true,
                finished: 2024),
            entry("K-On!", id: 2, year: 2009, genres: [35], status: .watched, score: 2, finished: 2019),
            entry("Horimiya", id: 3, year: 2021, genres: [], status: .watched, score: 5),
            entry("Unrated", id: 4, year: 2022, genres: [35], status: .planToWatch)
        ].map { CategoryDraftEntry($0) }
        func ids(_ plan: CategoryQueryPlan) -> [Int] { plan.candidates(in: library).compactMap(\.id.tmdbID) }

        // A genre is something the model judges: it never removes an entry before the check,
        // even one whose TMDb genres lack it (romance does not exist for TV).
        var romance = emptyPlan()
        romance.semanticCriterion = "a romance"
        #expect(romance.needsCheck)
        #expect(ids(romance) == [1, 2, 3, 4])

        var finished = emptyPlan()
        finished.earliestFinishYear = 2020
        #expect(!finished.needsCheck)
        #expect(ids(finished) == [1])
        finished.earliestFinishYear = 0
        finished.latestFinishYear = 2019
        #expect(ids(finished) == [2])

        var scores = emptyPlan()
        scores.maximumScore = 2.5
        #expect(ids(scores) == [2])
        scores.maximumScore = 0
        scores.minimumScore = 4.5
        scores.favoritesOnly = true
        scores.earliestYear = 2020
        #expect(ids(scores) == [1])
        scores.kinds = [.series]
        #expect(ids(scores).isEmpty)
    }

    @Test func cardsCarryStudiosAndLabeledGenresButNoIdentifier() {
        let long = entry(
            "Frieren", id: 777_001, year: 2023, genres: [16, 10765], overview: String(repeating: "x", count: 800),
            studios: ["Madhouse", "Toho", "Aniplex", "Dentsu"])
        let card = CategoryDraftModel.card(for: long)
        #expect(
            card.hasPrefix(
                "Frieren · 2023 · movie · studios: Madhouse, Toho, Aniplex, Dentsu · TMDb genres: Sci-Fi & Fantasy · "))
        #expect(!card.contains("777001"))
        #expect(!card.contains("Animation"))
        #expect(card.hasSuffix(" · " + String(repeating: "x", count: 500)))
        let series = entry("Frieren", id: 777_002, year: 2023, genres: nil, overview: "An elf mage outlives her party.")
        let season = AnimeEntry(
            name: "Season 2", overview: "", type: .season(seasonNumber: 2, parentSeriesID: 777_002), tmdbID: 777_003)
        season.parentSeriesEntry = series
        #expect(CategoryDraftModel.card(for: season).hasSuffix(" · An elf mage outlives her party."))
        let check = CategoryQueryPlan.checkInstructions(for: "a romance")
        #expect(check.contains("Criterion: a romance"))
        #expect(check.contains("a missing genre tag is not evidence against a match"))
        #expect(CategoryDraftModel.categoryName(from: "  ", request: "fantasy anime") == "fantasy anime")
        #expect(CategoryDraftModel.categoryName(from: String(repeating: "a", count: 60), request: "x").count == 40)
    }

    @Test func unsupportedConstraintsReachTheReview() async throws {
        let (store, _) = try makeStore()
        var plan = emptyPlan(name: "Started in 2024")
        plan.unsupportedRequest = "  started watching in 2024 "
        let draft = makeDraft(DraftFakeGenerator(plan: plan) { _ in [] })
        draft.request = "anime I started watching in 2024"
        draft.start(library: store.library)
        await settle(draft)
        #expect(draft.proposal?.unsupportedRequest == "started watching in 2024")
    }

    // MARK: - Draft flow

    @Test func filtersOnlyRequestSkipsTheModelCheck() async throws {
        let (store, entries) = try makeStore()
        var plan = emptyPlan(name: "Finished")
        plan.watchStatuses = [.watched]
        let fake = DraftFakeGenerator(plan: plan) { _ in
            Issue.record("A filters-only request must not send a batch")
            return []
        }
        let draft = makeDraft(fake)
        draft.request = "everything I finished"
        draft.start(library: store.library)
        await settle(draft)

        #expect(draft.state == .review)
        #expect(fake.prompts.count == 1)
        let proposal = try #require(draft.proposal)
        #expect(proposal.name == "Finished")
        #expect(
            Set(proposal.items.acceptedValues.map(\.id.tmdbID))
                == Set(entries.filter { $0.watchStatus == .watched }.map(\.tmdbID)))
    }

    @Test func criterionRequestKeepsEveryVerdictAndListsOnlyMatches() async throws {
        let (store, _) = try makeStore()
        var plan = emptyPlan(name: "Fantasy")
        plan.semanticCriterion = "set in a fantasy world"
        // Call 1 is the plan step. Each later call is one single-card batch: the card matches
        // (the invented index 42 is dropped), except that the second batch fails for good and
        // the third matches nothing.
        let fake = DraftFakeGenerator(plan: plan) { call in
            switch call {
            case 3: throw AIError.requestFailed
            case 4: return []
            default: return [0, 42]
            }
        }
        let draft = makeDraft(fake, budget: oneCardBudget())
        draft.request = "fantasy"
        draft.start(library: store.library)
        await settle(draft)

        #expect(draft.state == .review)
        #expect(fake.prompts.count == 5)
        let proposal = try #require(draft.proposal)
        let verdicts = proposal.items.items.map(\.value.verdict)
        #expect(verdicts.count(where: { $0 == .match }) == 2)
        #expect(verdicts.count(where: { $0 == .rejected }) == 1)
        #expect(proposal.uncheckedCount == 1)
        // Only matches start accepted and listed; the rest wait under Not included.
        for item in proposal.items.items {
            #expect(item.isAccepted == (item.value.verdict == .match))
            #expect(item.value.isListed == item.isAccepted)
        }
    }

    @Test func stopReviewsWhatWasFoundAndCheckAgainListsNewMatches() async throws {
        let (store, _) = try makeStore()
        var plan = emptyPlan(name: "Fantasy")
        plan.semanticCriterion = "set in a fantasy world"
        // The four single-card batches run at once: the first matches, the others hang until
        // the user stops. Check Again then matches the three it sends.
        let fake = DraftFakeGenerator(plan: plan) { call in call == 2 || call > 5 ? [0] : [] }
        fake.hangs = { (3...5).contains($0) }
        let draft = makeDraft(fake, budget: oneCardBudget())
        draft.request = "fantasy"
        draft.start(library: store.library)
        await waitUntil { draft.proposal?.items.items.contains { $0.value.verdict == .match } == true }

        draft.stop()
        #expect(draft.state == .review)
        var proposal = try #require(draft.proposal)
        #expect(proposal.uncheckedCount == 3)
        #expect(proposal.items.items.count(where: \.value.isListed) == 1)
        #expect(draft.canRecheck)

        fake.hangs = { _ in false }
        draft.recheck()
        await settle(draft)
        #expect(fake.prompts.count == 8)
        proposal = try #require(draft.proposal)
        #expect(proposal.uncheckedCount == 0)
        #expect(proposal.items.items.allSatisfy { $0.isAccepted && $0.value.isListed })
    }

    @Test func everyBatchFailingShowsTheError() async throws {
        let (store, _) = try makeStore()
        var plan = emptyPlan(name: "Fantasy")
        plan.semanticCriterion = "set in a fantasy world"
        let fake = DraftFakeGenerator(plan: plan) { _ in throw AIError.providerHTTPStatus(401) }
        let draft = makeDraft(fake)
        draft.request = "fantasy"
        draft.start(library: store.library)
        await settle(draft)
        #expect(draft.state == .failed(.providerHTTPStatus(401)))

        // Edit returns to the text, which stays.
        draft.edit()
        #expect(draft.state == .describing)
        #expect(draft.request == "fantasy")
    }

    @Test func applyCreatesTheCategoryWithOnlyAcceptedAnime() async throws {
        let (store, entries) = try makeStore()
        store.categoriesEnabled = true
        let existing = try #require(store.createCategory(named: "Taken"))
        let fake = DraftFakeGenerator(plan: emptyPlan(name: "Taken")) { _ in [] }
        let draft = makeDraft(fake)
        draft.request = "all of it"
        draft.start(library: store.library)
        await settle(draft)

        // A duplicate name does not apply and changes nothing.
        #expect(draft.apply(in: store) == nil)
        #expect(store.categories.map(\.id) == [existing.id])

        draft.proposal?.name = "Everything"
        draft.proposal?.items.items[0].isAccepted = false
        let rejected = try #require(draft.proposal?.items.items[0].value.id)
        let id = try #require(draft.apply(in: store))
        #expect(draft.state == .applied(id))
        let members = entries.filter { $0.categoryIDs.contains(id) }.map(\.libraryIdentity)
        #expect(members.count == entries.count - 1)
        #expect(!members.contains(rejected))
    }

    @Test func applyRefusesWhenTheAcceptedAnimeLeftTheLibrary() async throws {
        let (store, entries) = try makeStore()
        store.categoriesEnabled = true
        let draft = makeDraft(DraftFakeGenerator(plan: emptyPlan(name: "Stale")) { _ in [] })
        draft.request = "all of it"
        draft.start(library: store.library)
        await settle(draft)

        // Another window hides every proposed anime before the user taps Apply.
        for entry in entries { entry.onDisplay = false }
        #expect(draft.apply(in: store) == nil)
        #expect(store.categories.isEmpty)
        #expect(draft.state == .review)
    }

    // MARK: - Settings

    @Test func settingsModelMasksKeysAndFlagsCustomModels() throws {
        let name = "smart-settings-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let keychain = SmartKeychainFake()
        let keys = AIProviderKeyStorage(keychain: keychain.client)
        let model = AISettingsModel(
            defaults: defaults, keys: keys,
            availability: AIAvailability(
                apple: .unavailable(.deviceNotEligible), supportsProviders: true, keyedProviders: [])
        )
        #expect(model.listedBackends == [.apple, .openAI, .openRouter])
        #expect(model.activeBackend == nil)

        #expect(model.saveKey("sk-test-abcd1234", for: .openRouter))
        #expect(model.keySuffixes[.openRouter] == "1234")
        #expect(model.activeBackend == .openRouter)

        #expect(!model.usesCustomModel(for: .openRouter))
        #expect(model.setModel(" vendor/experimental ", for: .openRouter))
        #expect(model.model(for: .openRouter) == "vendor/experimental")
        #expect(model.usesCustomModel(for: .openRouter))
        #expect(!model.setModel("   ", for: .openRouter))

        // Another window's page picks up the change and drops that backend's test.
        let other = AISettingsModel(defaults: defaults, keys: keys, availability: model.availability)
        var posted: Notification?
        let observer = NotificationCenter.default.addObserver(
            forName: .aiConfigurationDidChange, object: model, queue: nil
        ) { posted = $0 }
        defer { NotificationCenter.default.removeObserver(observer) }
        #expect(model.setModel("vendor/other", for: .openRouter))
        let change = try #require(posted)
        other.configurationDidChange(change)
        #expect(other.model(for: .openRouter) == "vendor/other")
        #expect(other.testStates[.openRouter] == .idle)

        // A backend without a key cannot be selected.
        model.select(.openAI)
        #expect(model.activeBackend == .openRouter)
        // A refused deletion keeps the key and says so.
        keychain.deleteStatus = errSecInteractionNotAllowed
        #expect(!model.removeKey(for: .openRouter))
        #expect(model.keySuffixes[.openRouter] == "1234")
        keychain.deleteStatus = nil
        #expect(model.removeKey(for: .openRouter))
        #expect(model.keySuffixes[.openRouter] == nil)
        #expect(model.activeBackend == nil)
    }

    // MARK: - Helpers

    private func emptyPlan(name: String = "Category") -> CategoryQueryPlan {
        CategoryQueryPlan(
            name: name, kinds: [], watchStatuses: [], favoritesOnly: false, minimumScore: 0, maximumScore: 0,
            earliestYear: 0, latestYear: 0, earliestFinishYear: 0, latestFinishYear: 0, semanticCriterion: "",
            criterionLabel: "", unsupportedRequest: ""
        )
    }

    private func entry(
        _ name: String, id: Int, year: Int, genres: [Int]?, status: AnimeEntry.WatchStatus = .planToWatch,
        score: Int? = nil, favorite: Bool = false, overview: String? = nil, finished: Int? = nil,
        studios: [String] = []
    ) -> AnimeEntry {
        let entry = AnimeEntry(
            name: name, overview: overview, onAirDate: referenceDate(year: year, month: 6, day: 1), type: .movie,
            tmdbID: id, dateFinished: finished.map { referenceDate(year: $0, month: 3, day: 1) }, score: score
        )
        if let genres {
            let companies = studios.enumerated().map {
                AnimeEntryProductionCompany(id: $0.offset, name: $0.element, displayOrder: $0.offset)
            }
            entry.detail = AnimeEntryDetail(
                language: "en-US", title: name, genreIDs: genres, productionCompanies: companies)
        }
        entry.watchStatus = status
        entry.favorite = favorite
        return entry
    }

    private func makeStore() throws -> (LibraryStore, [AnimeEntry]) {
        let name = "smart-store-\(UUID())"
        let store = LibraryStore(
            dataProvider: DataProvider(inMemory: true),
            preferences: LibraryPreferences(defaults: UserDefaults(suiteName: name)!)
        )
        let entries = [
            entry("Frieren", id: 11, year: 2023, genres: [10765], status: .watched),
            entry("Mushoku Tensei", id: 12, year: 2021, genres: [10765], status: .watched),
            entry("K-On!", id: 13, year: 2009, genres: [35], status: .planToWatch),
            entry("Psycho-Pass", id: 14, year: 2012, genres: [80], status: .watching)
        ]
        for entry in entries { try store.repository.newEntry(entry) }
        try store.refreshLibrary()
        return (store, entries)
    }

    private func makeDraft(_ fake: DraftFakeGenerator, budget: AIContextBudget? = nil) -> CategoryDraftModel {
        CategoryDraftModel(
            backend: .openRouter, makeGenerator: { fake },
            budgetOverride: budget
                ?? AIContextBudget(contextSize: 100_000, reservedTokens: 0, maximumResponseTokens: 64)
        )
    }

    /// Fits the request, or a batch prompt with one card.
    private func oneCardBudget() -> AIContextBudget {
        AIContextBudget(
            contextSize: 2, reservedTokens: 0, maximumResponseTokens: 1,
            countPrompt: { prompt in
                // The plan step's prompt is the request; batch prompts count their card lines.
                prompt.contains("\n") ? prompt.components(separatedBy: "\n").count - 1 : 1
            }
        )
    }

    private func settle(_ draft: CategoryDraftModel) async {
        await waitUntil { !draft.isRunning }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2000 where !condition() {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

/// Answers the plan step with a fixed plan and each batch with `select(callNumber)`.
///
/// A call that `hangs` waits until its task is cancelled.
@MainActor
fileprivate final class DraftFakeGenerator: AIStructuredGenerator {
    let plan: CategoryQueryPlan
    let select: (Int) throws -> [Int]
    var hangs: (Int) -> Bool = { _ in false }
    private(set) var prompts: [String] = []

    init(plan: CategoryQueryPlan, select: @escaping (Int) throws -> [Int]) {
        self.plan = plan
        self.select = select
    }

    func generate<Value: Generable>(
        _ type: Value.Type, instructions: String, prompt: String, maximumResponseTokens: Int
    ) async throws -> Value {
        prompts.append(prompt)
        if type == CategoryQueryPlan.self { return try Value(plan.generatedContent) }
        if hangs(prompts.count) { try await Task.sleep(for: .seconds(60)) }
        return try Value(AIBatchSelection(matchingIndices: select(prompts.count)).generatedContent)
    }
}

fileprivate final class SmartKeychainFake {
    var values: [String: Data] = [:]
    var deleteStatus: OSStatus?

    var client: TMDbAPIKeyStorageKeychainClient {
        TMDbAPIKeyStorageKeychainClient(
            add: { query in
                self.values[query[kSecAttrAccount as String] as! String] = query[kSecValueData as String] as? Data
                return errSecSuccess
            },
            update: { query, attributes in
                let account = query[kSecAttrAccount as String] as! String
                guard self.values[account] != nil else { return errSecItemNotFound }
                self.values[account] = attributes[kSecValueData as String] as? Data
                return errSecSuccess
            },
            delete: { query in
                if let status = self.deleteStatus { return status }
                self.values.removeValue(forKey: query[kSecAttrAccount as String] as! String)
                return errSecSuccess
            },
            copyMatching: { query in
                guard let value = self.values[query[kSecAttrAccount as String] as! String] else {
                    return (errSecItemNotFound, nil)
                }
                return (errSecSuccess, value as AnyObject)
            }
        )
    }
}
