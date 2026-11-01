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

/// Where a candidate stands in the check.
enum CategoryDraftVerdict: Equatable, Sendable {
    /// Not sent yet.
    case pending
    /// In a batch that is in flight.
    case checking
    case match
    case rejected
    /// Its batch failed for good, or the user stopped the run first.
    case unchecked

    var isResolved: Bool {
        switch self {
        case .pending, .checking: false
        case .match, .rejected, .unchecked: true
        }
    }
}

/// One anime that passed the plan's filters.
struct CategoryDraftCandidate: Identifiable, Equatable, Sendable {
    let id: LibraryEntryIdentity
    /// What the poster shows.
    let metadata: EntryMetadata
    var verdict: CategoryDraftVerdict
    /// Whether the review lists it under the category rather than under Not included.
    ///
    /// Set when the check settles, never by a toggle, so a tap never moves a poster.
    var isListed = false
    /// The candidate's position in the batch that resolved it, so a batch's results ripple in.
    var revealIndex = 0
}

struct CategoryDraftProposal {
    var name: String
    /// The filters the request was read as; the sieve shows them.
    let plan: CategoryQueryPlan
    /// Every candidate, sorted by name; only matches start accepted.
    var items: AIProposal<CategoryDraftCandidate>

    var uncheckedCount: Int {
        items.items.count { $0.value.verdict == .unchecked }
    }

    /// A part of the request no filter could express; the sieve shows it, so it is never
    /// dropped silently.
    var unsupportedRequest: String {
        plan.trimmedUnsupportedRequest
    }
}

/// Runs "Describe a Category": the plan step, the local filter, the batched check, and Apply.
///
/// The proposal exists from the moment the plan arrives, and each batch updates its
/// candidates' verdicts as it finishes, so the sieve shows the result forming.
/// Nothing writes to the library before `apply(in:)`.
@Observable
@MainActor
final class CategoryDraftModel {
    enum State: Equatable {
        case describing
        case planning
        case checking
        case review
        case failed(AIError)
        case applied(LibraryCategory.ID)
    }

    /// What a check needs to run again over the unchecked candidates.
    private struct CheckContext {
        let generator: any AIStructuredGenerator
        let instructions: String
        let budget: AIContextBudget
        let cards: [LibraryEntryIdentity: String]
    }

    var request = ""
    var proposal: CategoryDraftProposal?
    private(set) var state: State = .describing
    /// Whether Check Again is running over the unchecked candidates.
    private(set) var isRechecking = false

    let backend: AIBackend
    private let makeGenerator: @MainActor () -> any AIStructuredGenerator
    private let budgetOverride: AIContextBudget?
    private let retry: AIRetryPolicy
    private let calendar: Calendar
    private let now: () -> Date
    private var task: Task<Void, Never>?
    private var check: CheckContext?

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
        default: isRechecking
        }
    }

    /// Whether Check Again can run: the check got far enough to have its instructions.
    var canRecheck: Bool {
        state == .review && !isRechecking && check != nil && (proposal?.uncheckedCount ?? 0) > 0
    }

    func start(library: [AnimeEntry]) {
        guard canStart else { return }
        let request = trimmedRequest
        // Read every visible entry now: the run never touches a live model after an await.
        let entries = library.filter(\.onDisplay).map { CategoryDraftEntry($0, calendar: calendar) }
        state = .planning
        proposal = nil
        check = nil
        task = Task { [weak self] in
            await self?.run(request: request, entries: entries)
        }
    }

    /// Stops a running request and returns to the text, which stays as it was.
    func cancel() {
        task?.cancel()
        task = nil
        check = nil
        isRechecking = false
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

    /// Ends the check early and reviews what it found; the rest count as unchecked.
    func stop() {
        guard state == .checking, proposal != nil else { return }
        task?.cancel()
        task = nil
        abandonUnresolved()
        settle()
    }

    /// Checks the unchecked candidates again; new matches join the category's list.
    func recheck() {
        guard canRecheck, let check, let proposal else { return }
        let ids = proposal.items.items.map(\.value).filter { $0.verdict == .unchecked }.map(\.id)
        update(Set(ids)) { $0.verdict = .pending }
        isRechecking = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await runCheck(ids, context: check)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                abandonUnresolved()
            }
            guard !Task.isCancelled else { return }
            isRechecking = false
            settle(only: Set(ids))
        }
    }

    /// Creates the category and adds the accepted anime to it.
    ///
    /// Returns `nil` for an invalid name, or when no accepted anime is still visible in the
    /// library (for example, another window deleted them during the review).
    @discardableResult
    func apply(in store: LibraryStore) -> LibraryCategory.ID? {
        guard state == .review else { return nil }
        if isRechecking {
            task?.cancel()
            task = nil
            isRechecking = false
            abandonUnresolved()
        }
        guard let proposal else { return nil }
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
            let needsCheck = plan.needsCheck && !candidates.isEmpty
            propose(
                plan: plan, name: Self.categoryName(from: plan.name, request: request), candidates: candidates,
                verdict: needsCheck ? .pending : .match
            )
            guard needsCheck else {
                settle()
                return
            }

            state = .checking
            let instructions = plan.checkInstructions()
            let context = CheckContext(
                generator: generator, instructions: instructions,
                budget: try await budget(for: AIBatchSelection.self, instructions: instructions),
                cards: Dictionary(candidates.map { ($0.id, $0.card) }, uniquingKeysWith: { first, _ in first })
            )
            try Task.checkCancellation()
            check = context
            let result = try await runCheck(candidates.map(\.id), context: context)
            try Task.checkCancellation()

            // Every batch failed: there is no partial answer to review.
            if result.values.isEmpty, proposal?.uncheckedCount == candidates.count, let failure = result.failures.first
            {
                throw failure.reason
            }
            settle()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            state = .failed(error as? AIError ?? .requestFailed)
        }
    }

    /// Checks `ids` in library order, recording each batch's verdicts as it finishes.
    private func runCheck(
        _ ids: [LibraryEntryIdentity], context: CheckContext
    ) async throws -> AIBatchResult<LibraryEntryIdentity, Bool> {
        let runner = AIBatchRunner(
            generator: context.generator, budget: context.budget, instructions: context.instructions,
            maximumConcurrentBatches: backend.maximumConcurrentBatches, retry: retry)
        let items = ids.compactMap { id in context.cards[id].map { AIBatchItem(identity: id, text: $0) } }
        return try await runner.run(items, generating: AIBatchSelection.self) { [weak self] event in
            guard let self, !Task.isCancelled else { return }
            record(event)
        }
    }

    private func record(_ event: AIBatchEvent<LibraryEntryIdentity, Bool>) {
        switch event {
        case .started(let ids):
            update(Set(ids)) { $0.verdict = .checking }
        case .finished(let ids, let result):
            let matched = Set(result.values.map(\.identity))
            let failed = Set(result.failures.flatMap(\.identities))
            let order = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            updateItems(Set(ids)) { candidate, isAccepted in
                candidate.verdict =
                    failed.contains(candidate.id) ? .unchecked : matched.contains(candidate.id) ? .match : .rejected
                candidate.revealIndex = order[candidate.id] ?? 0
                if candidate.verdict == .match { isAccepted = true }
            }
        }
    }

    private func budget<Value: Generable>(
        for type: Value.Type, instructions: String
    ) async throws -> AIContextBudget {
        if let budgetOverride { return budgetOverride }
        return try await AIContextBudget.make(backend: backend, instructions: instructions, generating: type)
    }

    private func propose(
        plan: CategoryQueryPlan, name: String, candidates: [CategoryDraftEntry], verdict: CategoryDraftVerdict
    ) {
        guard !Task.isCancelled else { return }
        let items = candidates.map { CategoryDraftCandidate(id: $0.id, metadata: $0.metadata, verdict: verdict) }
            .sorted { $0.metadata.name.localizedStandardCompare($1.metadata.name) == .orderedAscending }
            .map { AIProposal.Item(value: $0, isAccepted: verdict == .match) }
        proposal = CategoryDraftProposal(name: name, plan: plan, items: AIProposal(items: items))
    }

    /// Lists the matches and anything the user accepted, and shows the review.
    ///
    /// With `only`, just those candidates are placed; the rest keep their place.
    private func settle(only ids: Set<LibraryEntryIdentity>? = nil) {
        if let ids {
            updateItems(ids) { candidate, _ in candidate.isListed = candidate.verdict == .match }
        } else if var proposal {
            for index in proposal.items.items.indices {
                let item = proposal.items.items[index]
                proposal.items.items[index].value.isListed = item.value.verdict == .match || item.isAccepted
            }
            self.proposal = proposal
        }
        state = .review
    }

    /// Marks every candidate still waiting for an answer as unchecked.
    private func abandonUnresolved() {
        guard let proposal else { return }
        let waiting = proposal.items.items.map(\.value).filter { !$0.verdict.isResolved }.map(\.id)
        update(Set(waiting)) { $0.verdict = .unchecked }
    }

    private func update(_ ids: Set<LibraryEntryIdentity>, _ change: (inout CategoryDraftCandidate) -> Void) {
        updateItems(ids) { candidate, _ in change(&candidate) }
    }

    /// Changes the given candidates in one write, so the sieve redraws once per batch.
    private func updateItems(
        _ ids: Set<LibraryEntryIdentity>, _ change: (inout CategoryDraftCandidate, inout Bool) -> Void
    ) {
        guard !ids.isEmpty, var proposal else { return }
        for index in proposal.items.items.indices where ids.contains(proposal.items.items[index].value.id) {
            var item = proposal.items.items[index]
            change(&item.value, &item.isAccepted)
            proposal.items.items[index] = item
        }
        self.proposal = proposal
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
