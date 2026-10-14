//
//  LibrarySpotlightIndexer.swift
//  AniShelf
//
//  Created by Claude Code on behalf of samuelhe52 on 2026/10/14.
//

import AppIntents
import CoreSpotlight
import DataProvider
import Foundation
import os

fileprivate let spotlightLogger = Logger(subsystem: .bundleIdentifier, category: "LibrarySpotlightIndexer")

/// Keeps Spotlight's copy of the visible library in step with `LibraryStore.library`.
///
/// `LibraryStore.refreshLibrary()` schedules a debounced reconcile. Restore, recovery,
/// store reloads, remote sync merges, and duplicate repair all end in that refresh, so no
/// other hooks are needed. The fingerprint map lives in memory, so the first reconcile after
/// launch replaces the whole index and drops items for entries deleted while the app was closed.
@MainActor
final class LibrarySpotlightIndexer {
    struct ReconcilePlan: Equatable {
        var replacesAll = false
        var idsToIndex: Set<String> = []
        var idsToDelete: [String] = []

        var isEmpty: Bool {
            !replacesAll && idsToIndex.isEmpty && idsToDelete.isEmpty
        }
    }

    private static let indexBatchSize = 100

    private weak var store: LibraryStore?
    private let allowsLibraryActivity: @MainActor () -> Bool
    private let debounce: Duration
    /// `nil` until the first successful reconcile in this process.
    private var indexedFingerprints: [String: Int]?
    private var pendingTask: Task<Void, Never>?
    private var isReconciling = false
    private var needsAnotherPass = false

    init(
        store: LibraryStore,
        allowsLibraryActivity: @escaping @MainActor () -> Bool,
        debounce: Duration = .seconds(1)
    ) {
        self.store = store
        self.allowsLibraryActivity = allowsLibraryActivity
        self.debounce = debounce
    }

    func scheduleReconcile() {
        pendingTask?.cancel()
        pendingTask = Task { [weak self, debounce] in
            guard (try? await Task.sleep(for: debounce)) != nil else { return }
            await self?.reconcile()
        }
    }

    /// Compares the current fingerprints with what this process last indexed.
    static func plan(current: [String: Int], indexed: [String: Int]?) -> ReconcilePlan {
        guard let indexed else {
            return ReconcilePlan(replacesAll: true, idsToIndex: Set(current.keys))
        }
        return ReconcilePlan(
            idsToIndex: Set(current.compactMap { id, fingerprint in indexed[id] == fingerprint ? nil : id }),
            idsToDelete: indexed.keys.filter { current[$0] == nil }.sorted()
        )
    }

    private func reconcile() async {
        guard !isReconciling else {
            needsAnotherPass = true
            return
        }
        isReconciling = true
        defer { isReconciling = false }
        repeat {
            needsAnotherPass = false
            await reconcileOnce()
        } while needsAnotherPass
    }

    private func reconcileOnce() async {
        guard allowsLibraryActivity(), let store else { return }
        let entities = store.library.map(LibraryEntryEntity.init)
        let fingerprints = Dictionary(
            entities.map { ($0.id, $0.spotlightFingerprint) },
            uniquingKeysWith: { first, _ in first }
        )
        let plan = Self.plan(current: fingerprints, indexed: indexedFingerprints)
        guard !plan.isEmpty else { return }

        let index = CSSearchableIndex.default()
        do {
            if plan.replacesAll {
                try await index.deleteAppEntities(ofType: LibraryEntryEntity.self)
            } else if !plan.idsToDelete.isEmpty {
                try await index.deleteAppEntities(identifiedBy: plan.idsToDelete, ofType: LibraryEntryEntity.self)
            }
            let changedEntities = entities.filter { plan.idsToIndex.contains($0.id) }
            for start in stride(from: 0, to: changedEntities.count, by: Self.indexBatchSize) {
                let batch = Array(changedEntities[start..<min(start + Self.indexBatchSize, changedEntities.count)])
                try await index.indexAppEntities(batch)
            }
            indexedFingerprints = fingerprints
            spotlightLogger.debug(
                "Indexed \(changedEntities.count, privacy: .public) and removed \(plan.idsToDelete.count, privacy: .public) library entries (full pass: \(plan.replacesAll, privacy: .public))."
            )
        } catch {
            // Start over with a full pass next time rather than trust a partial update.
            indexedFingerprints = nil
            spotlightLogger.error("Failed to update the Spotlight index: \(error.localizedDescription, privacy: .public)")
        }
    }
}
