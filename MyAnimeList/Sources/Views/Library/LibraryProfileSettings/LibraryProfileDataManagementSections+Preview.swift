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

#Preview("Discard Failed iCloud Entries") {
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
                        failureInjectionEnabled: failureInjectionBinding
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
                        onDiscardFailedRestorationEntry: cloudSyncManager.discard
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

    private var failureInjectionBinding: Binding<Bool> {
        Binding(
            get: { cloudSyncManager.failureInjectionEnabled },
            set: { cloudSyncManager.setFailureInjectionEnabled($0) }
        )
    }
}

fileprivate struct PreviewSyntheticLibrarySummary: View {
    let library: PreviewSyntheticLibrary
    @Binding var failureInjectionEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Synthetic iCloud Library")
                .font(.headline)
            Text(
                failureInjectionEnabled
                    ? "\(library.activeEntries.count) entries. Two entries deliberately fail every metadata restoration attempt. Use Retry three times to expose their discard actions."
                    : "Injected failures are off. The next Retry will restore the two pending entries and complete bootstrap."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(library.activeEntries.map(\.identity.rawID).joined(separator: " · "))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(2)

            Toggle("Inject restoration failures", isOn: $failureInjectionEnabled)
                .font(.caption.weight(.semibold))
                .tint(.orange)
        }
        .padding(14)
        .libraryProfileInsetPanel(cornerRadius: 22, tint: .gray)
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

    var failureInjectionEnabled: Bool {
        library.failureInjectionEnabled
    }

    init() {
        var status = LibraryCloudSyncStatus.defaultValue
        status.isEnabled = true
        status.cloudKitAvailability = .available
        self.status = status
    }

    func bootstrap() async {
        await synchronize(isUserRetry: false)
    }

    func retry() {
        guard !isSyncing else { return }
        Task { await synchronize(isUserRetry: true) }
    }

    func setFailureInjectionEnabled(_ isEnabled: Bool) {
        library.setFailureInjectionEnabled(isEnabled)
    }

    func discard(_ failure: LibraryRestorationFailure) {
        guard failure.canDiscard(at: .now) else { return }
        library.discardFromCloud(failure.snapshot.identity)
        status.restoration?.failures.removeAll { $0.snapshot.identity == failure.snapshot.identity }
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
        status.bootstrapState = .running
        status.currentPhase = .hydrationApply
        status.lastResult = nil
        status.lastAttemptDate = .now
        try? await Task.sleep(for: .milliseconds(300))

        var restoration = status.restoration ?? .init(scope: Self.scope)
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

        status.currentPhase = nil
        status.lastAttemptDate = .now
        if restoration.failures.isEmpty {
            status.bootstrapState = .completed
            status.lastResult = .success
            status.lastSuccessfulSyncDate = .now
            status.lastFailurePhase = nil
            status.lastFailureReason = nil
            status.restoration = nil
        } else {
            status.bootstrapState = .failed
            status.lastResult = .retryableFailure
            status.lastFailurePhase = .hydrationApply
            status.lastFailureReason =
                "\(restoration.failures.count) synthetic entries could not be restored."
            status.restoration = restoration
        }
        isSyncing = false
    }
}

fileprivate struct PreviewSyntheticLibrary {
    private(set) var cloudEntries: [LibraryEntrySyncSnapshot] = Self.entries
    private(set) var restoredEntryIDs: Set<LibraryEntryIdentity> = []
    private var discardedEntryIDs: Set<LibraryEntryIdentity> = []
    private(set) var failureInjectionEnabled = true

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

    private static let unavailableIDs: Set<Int> = [10_003, 10_006]

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
