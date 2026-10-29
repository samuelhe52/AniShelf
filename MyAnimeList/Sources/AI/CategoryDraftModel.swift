//
//  CategoryDraftModel.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/10/29.
//

import DataProvider
import Foundation
import FoundationModels
import Observation
import os

fileprivate let logger = Logger(subsystem: .bundleIdentifier, category: "CategoryDraft")

/// One anime the model proposes for the new category.
struct CategoryDraftCandidate: Identifiable, Sendable {
    let id: LibraryEntryIdentity
    let title: String
    let year: Int?
    let kind: CategoryEntryKind
}

struct CategoryDraftProposal {
    var name: String
    var items: AIProposal<CategoryDraftCandidate>
    /// Candidates whose batch failed; they are not in `items`.
    var uncheckedCount: Int
    /// A part of the request no filter could express; the review shows it, so it is never
    /// dropped silently.
    var unsupportedRequest: String = ""
}

/// Runs "Describe a Category": the plan step, the local filter, the batched check, and Apply.
///
/// Nothing writes to the library before `apply(in:)`.
@Observable
@MainActor
final class CategoryDraftModel {
    enum State: Equatable {
        case describing
        case planning
        case checking(done: Int, total: Int)
        case review
        case failed(AIError)
        case applied(LibraryCategory.ID)
    }

    var request = ""
    var proposal: CategoryDraftProposal?
    private(set) var state: State = .describing

    let backend: AIBackend
    private let makeGenerator: @MainActor () -> any AIStructuredGenerator
    private let budgetOverride: AIContextBudget?
    private let retry: AIRetryPolicy
    private let calendar: Calendar
    private let now: () -> Date
    private var task: Task<Void, Never>?

    init(
        backend: AIBackend,
        makeGenerator: (@MainActor () -> any AIStructuredGenerator)? = nil,
        budgetOverride: AIContextBudget? = nil,
        retry: AIRetryPolicy = AIRetryPolicy(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.backend = backend
        self.makeGenerator =
            makeGenerator ?? {
                AILanguageModelGenerator(
                    factory: AISessionFactory(
                        configuration: AIConfiguration(defaults: AIConfiguration.appDefaults),
                        keys: AIProviderKeyStorage()),
                    backend: backend
                )
            }
        self.budgetOverride = budgetOverride
        self.retry = retry
        self.calendar = calendar
        self.now = now
    }

    var trimmedRequest: String {
        request.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canStart: Bool {
        state == .describing && !trimmedRequest.isEmpty
            && trimmedRequest.count <= CategoryQueryPlan.maximumRequestLength
    }

    var isRunning: Bool {
        switch state {
        case .planning, .checking: true
        default: false
        }
    }

    func start(library: [AnimeEntry]) {
        guard canStart else { return }
        let request = trimmedRequest
        // Read every visible entry now: the run never touches a live model after an await.
        let entries = library.filter(\.onDisplay).map { CategoryDraftEntry($0, calendar: calendar) }
        state = .planning
        proposal = nil
        task = Task { [weak self] in
            await self?.run(request: request, entries: entries)
        }
    }

    /// Stops a running request and returns to the text, which stays as it was.
    func cancel() {
        task?.cancel()
        task = nil
        if isRunning || state == .review || isFailed {
            state = .describing
            proposal = nil
        }
    }

    /// Returns to the text from a result, for example to broaden the request.
    func edit() {
        cancel()
    }

    func retry(library: [AnimeEntry]) {
        guard isFailed else { return }
        state = .describing
        start(library: library)
    }

    /// Creates the category and adds the accepted anime to it.
    ///
    /// Returns `nil` for an invalid name, or when no accepted anime is still visible in the
    /// library (for example, another window deleted them during the review).
    @discardableResult
    func apply(in store: LibraryStore) -> LibraryCategory.ID? {
        guard state == .review, let proposal else { return nil }
        let accepted = Set(proposal.items.acceptedValues.map(\.id))
        let entries = store.library.filter { $0.onDisplay && accepted.contains($0.libraryIdentity) }
        guard !entries.isEmpty, let category = store.createCategory(named: proposal.name) else { return nil }
        LibraryBatchAction.category(category.id, isMember: true, knownCategoryIDs: store.knownCategoryIDs)
            .apply(to: entries)
        do {
            try store.repository.save()
        } catch {
            // The membership stays in the context; autosave retries, as for multi-selection.
            logger.error("Saving a described category failed: \(error.localizedDescription)")
        }
        state = .applied(category.id)
        return category.id
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func run(request: String, entries: [CategoryDraftEntry]) async {
        do {
            let generator = makeGenerator()
            let planInstructions = CategoryQueryPlan.planInstructions(
                currentYear: calendar.component(.year, from: now()))
            let planBudget = try await budget(for: CategoryQueryPlan.self, instructions: planInstructions)
            guard try await planBudget.fits(request) else { throw AIError.itemTooLarge }
            let plan = try await retry.run {
                try await generator.generate(
                    CategoryQueryPlan.self, instructions: planInstructions, prompt: request,
                    maximumResponseTokens: planBudget.maximumResponseTokens
                )
            }
            try Task.checkCancellation()

            let candidates = plan.candidates(in: entries)
            let name = Self.categoryName(from: plan.name, request: request)
            guard plan.needsCheck, !candidates.isEmpty else {
                finish(name: name, matches: candidates, uncheckedCount: 0, unsupported: plan.trimmedUnsupportedRequest)
                return
            }

            state = .checking(done: 0, total: candidates.count)
            let checkInstructions = plan.checkInstructions()
            let checkBudget = try await budget(for: AIBatchSelection.self, instructions: checkInstructions)
            let items = candidates.map { AIBatchItem(identity: $0.id, text: $0.card) }
            let runner = AIBatchRunner(
                generator: generator, budget: checkBudget, instructions: checkInstructions,
                maximumConcurrentBatches: backend.maximumConcurrentBatches, retry: retry)
            let result = try await runner.run(items, generating: AIBatchSelection.self) { [weak self] done, total in
                guard let self, !Task.isCancelled else { return }
                state = .checking(done: done, total: total)
            }
            try Task.checkCancellation()

            let uncheckedCount = result.failures.reduce(0) { $0 + $1.identities.count }
            // Every batch failed: there is no partial answer to review.
            if result.values.isEmpty, uncheckedCount == candidates.count, let failure = result.failures.first {
                throw failure.reason
            }
            let matched = Set(result.values.map(\.identity))
            finish(
                name: name, matches: candidates.filter { matched.contains($0.id) }, uncheckedCount: uncheckedCount,
                unsupported: plan.trimmedUnsupportedRequest
            )
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            state = .failed(error as? AIError ?? .requestFailed)
        }
    }

    private func budget<Value: Generable>(
        for type: Value.Type, instructions: String
    ) async throws -> AIContextBudget {
        if let budgetOverride { return budgetOverride }
        return try await AIContextBudget.make(backend: backend, instructions: instructions, generating: type)
    }

    private func finish(name: String, matches: [CategoryDraftEntry], uncheckedCount: Int, unsupported: String) {
        guard !Task.isCancelled else { return }
        let candidates = matches.map {
            CategoryDraftCandidate(id: $0.id, title: $0.title, year: $0.year, kind: $0.kind)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        proposal = CategoryDraftProposal(
            name: name,
            items: AIProposal(items: candidates.map { AIProposal.Item(value: $0) }),
            uncheckedCount: uncheckedCount,
            unsupportedRequest: unsupported
        )
        state = .review
    }

    /// The model's name, trimmed to the category limit, or the request when the model gave none.
    static func categoryName(from proposed: String, request: String) -> String {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? request : trimmed
        return String(source.prefix(LibraryCategory.maximumNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One line per candidate, with no identifier; the batch runner adds a local index.
    static func card(for entry: AnimeEntry, calendar: Calendar = .current) -> String {
        let year = entry.onAirDate.map { String(calendar.component(.year, from: $0)) }
        let kind: String =
            switch entry.type {
            case .movie: "movie"
            case .series: "TV series"
            case .season(let number, _): "season \(number)"
            }
        let genres = (entry.detail?.genreIDs ?? []).compactMap { CategoryQueryPlan.genreNames[$0] }
            .filter { $0 != "Animation" }
        let studios = (entry.detail?.productionCompanies ?? [])
            .sorted { $0.displayOrder < $1.displayOrder }
            .map(\.name)
        // Seasons often store an empty overview rather than none; both fall back to the series.
        // 500 characters keeps 99% of overviews whole; kana text costs about a token per character.
        let overview = [entry.overview, entry.parentSeriesEntry?.overview]
            .lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .map { String($0.replacingOccurrences(of: "\n", with: " ").prefix(500)) }
        let parts: [String?] = [
            entry.displayName,
            entry.name == entry.displayName ? nil : entry.name,
            year, kind,
            studios.isEmpty ? nil : "studios: " + studios.joined(separator: ", "),
            genres.isEmpty ? nil : "TMDb genres: " + genres.joined(separator: ", "),
            overview
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}
