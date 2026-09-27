//
//  LibraryProfileDataManagementSections+Preview.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of samuelhe52 on 2026/9/12.
//

import DataProvider
import Foundation
import LibrarySync
import Observation
import SwiftUI

/// One interactive preview for every iCloud sync notice.
///
/// Switch scenarios to see first-enable restoration failures, or a completed
/// sync that left unloaded entries, rejected uploads, and unreadable records.
#Preview("iCloud Sync") {
    LibraryProfileICloudSyncSectionPreviewHost()
}

@MainActor
fileprivate struct LibraryProfileICloudSyncSectionPreviewHost: View {
    @State private var cloudSyncManager = PreviewCloudSyncManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PreviewSyntheticLibrarySummary(
                        library: cloudSyncManager.library,
                        scenario: scenarioBinding,
                        failureInjectionEnabled: failureInjectionBinding,
                        holdsDeletionsUntilRetry: holdsDeletionsBinding
                    )

                    LibraryProfileICloudSyncSection(
                        libraryCloudSyncStatus: cloudSyncManager.status,
                        cloudSyncToggleBinding: cloudSyncToggleBinding,
                        cloudSyncToggleDisabled: cloudSyncManager.isSyncing,
                        cloudSyncToggleSubtitle: "Existing iCloud data stays untouched.",
                        cloudSyncIsBusy: cloudSyncManager.isSyncing,
                        cloudSyncStatusTitleColor: cloudSyncStatusTitleColor,
                        cloudSyncManualRetryDisabled: cloudSyncManager.isSyncing,
                        onRetryLibraryCloudSync: cloudSyncManager.retry,
                        onDiscardFailedEntry: cloudSyncManager.discard
                    )
                }
                .padding()
            }
            .navigationTitle("iCloud Sync Preview")
        }
        .task {
            await cloudSyncManager.bootstrap()
        }
    }

    private var cloudSyncToggleBinding: Binding<Bool> {
        Binding(
            get: { cloudSyncManager.status.isEnabled },
            set: { cloudSyncManager.setEnabled($0) }
        )
    }

    private var cloudSyncStatusTitleColor: Color {
        cloudSyncManager.status.isFailureDisplay ? .red : .secondary
    }

    private var scenarioBinding: Binding<PreviewCloudSyncScenario> {
        Binding(
            get: { cloudSyncManager.scenario },
            set: { cloudSyncManager.setScenario($0) }
        )
    }

    private var failureInjectionBinding: Binding<Bool> {
        Binding(
            get: { cloudSyncManager.library.failureInjectionEnabled },
            set: { cloudSyncManager.setFailureInjectionEnabled($0) }
        )
    }

    private var holdsDeletionsBinding: Binding<Bool> {
        Binding(
            get: { cloudSyncManager.holdsDeletionsUntilRetry },
            set: { cloudSyncManager.holdsDeletionsUntilRetry = $0 }
        )
    }
}

fileprivate enum PreviewCloudSyncScenario: Hashable, CaseIterable {
    /// First-enable bootstrap with entries that fail metadata restoration.
    case restoration
    /// A completed sync that left entries pending.
    case completedSync
}

fileprivate struct PreviewSyntheticLibrarySummary: View {
    let library: PreviewSyntheticLibrary
    @Binding var scenario: PreviewCloudSyncScenario
    @Binding var failureInjectionEnabled: Bool
    @Binding var holdsDeletionsUntilRetry: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Synthetic iCloud Library")
                .font(.headline)
            Picker("Scenario", selection: $scenario) {
                Text("Restoration").tag(PreviewCloudSyncScenario.restoration)
                Text("Completed Sync").tag(PreviewCloudSyncScenario.completedSync)
            }
            .pickerStyle(.segmented)
            Text(scenarioDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(library.activeEntries.map(\.identity.rawID).joined(separator: " · "))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2)

            Toggle("Inject failures", isOn: $failureInjectionEnabled)
                .font(.caption.weight(.semibold))
                .tint(.orange)
            Toggle("Hold deletions until Retry", isOn: $holdsDeletionsUntilRetry)
                .font(.caption.weight(.semibold))
                .tint(.orange)
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .gray)
    }

    private var scenarioDescription: LocalizedStringResource {
        switch (scenario, failureInjectionEnabled) {
        case (.restoration, true):
            "\(library.activeEntries.count) entries. Two entries deliberately fail every metadata restoration attempt. Use Retry three times to expose their discard actions."
        case (.restoration, false):
            "Injected failures are off. The next Retry will restore the two pending entries and complete bootstrap."
        case (.completedSync, true):
            "Sync succeeded, but two entries couldn't be loaded, two changes weren't uploaded, and one record is unreadable. The entry TMDb no longer lists can be discarded right away."
        case (.completedSync, false):
            "Injected failures are off. The next Retry will load the pending entries and clear the other notices."
        }
    }
}

@MainActor
@Observable
fileprivate final class PreviewCloudSyncManager {
    private static let scope = LibraryCloudSyncScope(
        namespace: .init(
            containerIdentifier: "iCloud.com.samuelhe.AniShelf.preview",
            accountIdentifier: "preview-account"
        )
    )

    private(set) var library = PreviewSyntheticLibrary()
    private(set) var status: LibraryCloudSyncStatus
    private(set) var isSyncing = false
    private(set) var scenario = PreviewCloudSyncScenario.restoration
    /// Keeps a discard pending, as when iCloud has not confirmed the deletion yet.
    var holdsDeletionsUntilRetry = false

    init() {
        status = Self.initialStatus
    }

    private static var initialStatus: LibraryCloudSyncStatus {
        var status = LibraryCloudSyncStatus.defaultValue
        status.isEnabled = true
        status.cloudKitAvailability = .available
        return status
    }

    func bootstrap() async {
        await synchronize(isUserRetry: false)
    }

    func retry() {
        guard !isSyncing else { return }
        Task { await synchronize(isUserRetry: true) }
    }

    func setScenario(_ scenario: PreviewCloudSyncScenario) {
        guard !isSyncing, scenario != self.scenario else { return }
        self.scenario = scenario
        library = PreviewSyntheticLibrary(failureInjectionEnabled: library.failureInjectionEnabled)
        status = Self.initialStatus
        Task { await bootstrap() }
    }

    func setFailureInjectionEnabled(_ isEnabled: Bool) {
        library.setFailureInjectionEnabled(isEnabled)
    }

    func discard(_ entry: LibraryCloudSyncFailedEntry) {
        switch entry.source {
        case .restoration(let failure):
            guard failure.canDiscard(at: .now),
                let index = status.restoration?.failures.firstIndex(of: failure)
            else { return }
            status.restoration?.failures[index].discardDate = .now
        case .pendingReconstruction(let failure):
            guard failure.canDiscard,
                let pendingIndex = status.pendingReconstructions.firstIndex(where: { $0.scope == Self.scope }),
                let index = status.pendingReconstructions[pendingIndex].failures.firstIndex(of: failure)
            else { return }
            status.pendingReconstructions[pendingIndex].failures[index].discardDate = .now
        }
        guard !holdsDeletionsUntilRetry else { return }
        Task { await synchronize(isUserRetry: false) }
    }

    func setEnabled(_ isEnabled: Bool) {
        status.isEnabled = isEnabled
        guard isEnabled else {
            status.bootstrapState = .notStarted
            status.currentPhase = nil
            status.lastResult = nil
            return
        }
        Task { await bootstrap() }
    }

    private func synchronize(isUserRetry: Bool) async {
        guard status.isEnabled, !isSyncing else { return }

        isSyncing = true
        // Ordinary passes run only after bootstrap has completed.
        status.bootstrapState = scenario == .restoration ? .running : .completed
        status.currentPhase = .hydrationApply
        status.lastResult = nil
        status.lastAttemptDate = .now
        try? await Task.sleep(for: .milliseconds(300))

        switch scenario {
        case .restoration:
            restoreLibrary(isUserRetry: isUserRetry)
        case .completedSync:
            syncCompletedLibrary()
        }
        status.currentPhase = nil
        status.lastAttemptDate = .now
        isSyncing = false
    }

    private func restoreLibrary(isUserRetry: Bool) {
        var restoration = status.restoration ?? .init(scope: Self.scope)
        // Each pass first sends the deletions the user asked for.
        for failure in restoration.failures where failure.discardDate != nil {
            library.discardFromCloud(failure.snapshot.identity)
        }
        restoration.failures.removeAll { $0.discardDate != nil }
        restoration.totalEntries = library.activeEntries.count
        for snapshot in library.activeEntries {
            if library.alwaysFailsToRestore(snapshot) {
                let error = LibrarySyncHydrationError(
                    identity: snapshot.identity,
                    underlyingError: PreviewMetadataError.unavailable
                )
                restoration.recordFailure(
                    snapshot: snapshot,
                    error: error,
                    isUserRetry: isUserRetry,
                    at: .now
                )
                if let index = restoration.failures.firstIndex(where: { $0.snapshot == snapshot }) {
                    let retryCount = restoration.failures[index].retryDates.count
                    restoration.failures[index].reason =
                        "Synthetic TMDb failure. Manual retries: \(retryCount)/3."
                }
            } else {
                library.restore(snapshot)
                restoration.failures.removeAll { $0.snapshot.identity == snapshot.identity }
            }
        }
        restoration.restoredEntries = library.restoredEntryIDs.count

        if restoration.failures.isEmpty {
            recordSuccess()
            status.restoration = nil
        } else {
            status.bootstrapState = .failed
            status.lastResult = .retryableFailure
            status.lastFailurePhase = .hydrationApply
            status.lastFailureReason =
                "\(restoration.failures.count) synthetic entries could not be restored."
            status.restoration = restoration
        }
    }

    /// Mirrors an ordinary pass: entry-level problems stay pending while the
    /// pass itself succeeds.
    private func syncCompletedLibrary() {
        let previousFailures =
            status.pendingReconstructions.first { $0.scope == Self.scope }?.failures ?? []
        for failure in previousFailures where failure.discardDate != nil {
            library.discardFromCloud(failure.snapshot.identity)
        }

        var pending = LibraryPendingReconstructionState(scope: Self.scope)
        for snapshot in library.activeEntries where !library.restoredEntryIDs.contains(snapshot.identity) {
            guard library.alwaysFailsToRestore(snapshot) else {
                library.restore(snapshot)
                continue
            }
            let isPermanent = snapshot.tmdbID == PreviewSyntheticLibrary.removedFromTMDbID
            pending.failures.append(
                .init(
                    snapshot: snapshot,
                    metadataIdentity: snapshot.identity,
                    reason: isPermanent
                        ? "The resource you requested could not be found."
                        : "The network connection was lost.",
                    lastAttempt: .now,
                    isPermanent: isPermanent
                )
            )
        }

        status.pendingReconstructions = pending.failures.isEmpty ? [] : [pending]
        status.rejectedUploadCount = library.failureInjectionEnabled ? 2 : 0
        status.quarantinedRecordCount = library.failureInjectionEnabled ? 1 : 0
        recordSuccess()
    }

    private func recordSuccess() {
        status.bootstrapState = .completed
        status.lastCompletedScope = Self.scope
        status.lastResult = .success
        status.lastSuccessfulSyncDate = .now
        status.lastFailurePhase = nil
        status.lastFailureReason = nil
    }
}

fileprivate struct PreviewSyntheticLibrary {
    private(set) var cloudEntries: [LibraryEntrySyncSnapshot] = Self.entries
    private(set) var restoredEntryIDs: Set<LibraryEntryIdentity> = []
    private var discardedEntryIDs: Set<LibraryEntryIdentity> = []
    private(set) var failureInjectionEnabled: Bool

    init(failureInjectionEnabled: Bool = true) {
        self.failureInjectionEnabled = failureInjectionEnabled
    }

    var activeEntries: [LibraryEntrySyncSnapshot] {
        cloudEntries.filter { !discardedEntryIDs.contains($0.identity) }
    }

    mutating func restore(_ snapshot: LibraryEntrySyncSnapshot) {
        restoredEntryIDs.insert(snapshot.identity)
    }

    mutating func discardFromCloud(_ identity: LibraryEntryIdentity) {
        discardedEntryIDs.insert(identity)
        restoredEntryIDs.remove(identity)
    }

    mutating func setFailureInjectionEnabled(_ isEnabled: Bool) {
        failureInjectionEnabled = isEnabled
    }

    func alwaysFailsToRestore(_ snapshot: LibraryEntrySyncSnapshot) -> Bool {
        failureInjectionEnabled && Self.unavailableIDs.contains(snapshot.tmdbID)
    }

    /// The failing entry TMDb no longer lists, which can be discarded right away.
    static let removedFromTMDbID = 10_003
    private static let unavailableIDs: Set<Int> = [removedFromTMDbID, 10_006]

    private static let entries: [LibraryEntrySyncSnapshot] = (10_001...10_006).map {
        let identity = LibraryEntryIdentity(entryType: .series, tmdbID: $0)
        return LibraryEntrySyncSnapshot(
            identity: identity,
            tmdbID: $0,
            parentSeriesID: nil,
            seasonNumber: nil,
            entryType: .series,
            onDisplay: true,
            dateSaved: .now,
            watchStatus: .planToWatch,
            dateStarted: nil,
            dateFinished: nil,
            isDateTrackingEnabled: true,
            score: nil,
            favorite: false,
            notes: "",
            usingCustomPoster: false,
            customPosterPath: nil,
            episodeProgresses: [],
            libraryUpdatedAt: .now,
            trackingUpdatedAt: .now
        )
    }
}

fileprivate enum PreviewMetadataError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "The requested TMDb entry is unavailable."
    }
}
