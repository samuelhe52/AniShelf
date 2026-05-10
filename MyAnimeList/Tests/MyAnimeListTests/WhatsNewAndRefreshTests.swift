//
//  WhatsNewAndRefreshTests.swift
//  MyAnimeListTests
//
//  Created by OpenAI Codex on 2026/5/10.
//

import Foundation
import Testing

@testable import DataProvider
@testable import MyAnimeList

struct WhatsNewAndRefreshTests {
    @Test @MainActor func testWhatsNewDoesNotAutoShowWithoutRegisteredEntry() {
        let suiteName = "MyAnimeListTests.WhatsNew.NoEntry"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = makeWhatsNewController(
            defaults: defaults,
            currentVersion: "1.54",
            entries: [:]
        )

        controller.presentIfNeeded(allowsAutoPresentation: true)

        #expect(controller.currentEntry == nil)
        #expect(controller.presentedEntry == nil)
        #expect(String.allPreferenceKeys.contains(.lastSeenWhatsNewVersion))
    }

    @Test @MainActor func testWhatsNewAutoShowsOnceForRegisteredVersion() {
        let suiteName = "MyAnimeListTests.WhatsNew.AutoShow"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let entry = makeWhatsNewEntry(version: "1.54")
        let controller = makeWhatsNewController(
            defaults: defaults,
            currentVersion: "1.54",
            entries: [entry.version: entry]
        )

        controller.presentIfNeeded(allowsAutoPresentation: true)

        #expect(controller.currentEntry?.version == entry.version)
        #expect(controller.presentedEntry?.version == entry.version)
    }

    @Test @MainActor func testWhatsNewDismissalMarksSeenAndSuppressesRepeatAutoPresentation() {
        let suiteName = "MyAnimeListTests.WhatsNew.Dismissal"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let entry = makeWhatsNewEntry(version: "1.54")
        let firstController = makeWhatsNewController(
            defaults: defaults,
            currentVersion: entry.version,
            entries: [entry.version: entry]
        )
        firstController.presentIfNeeded(allowsAutoPresentation: true)
        firstController.dismissPresentedEntry()

        #expect(defaults.string(forKey: .lastSeenWhatsNewVersion) == entry.version)
        #expect(firstController.presentedEntry == nil)

        let secondController = makeWhatsNewController(
            defaults: defaults,
            currentVersion: entry.version,
            entries: [entry.version: entry]
        )
        secondController.presentIfNeeded(allowsAutoPresentation: true)

        #expect(secondController.presentedEntry == nil)
    }

    @Test @MainActor func testWhatsNewUpdateOnlyAutoShowsWhenNewVersionHasEntry() {
        let suiteName = "MyAnimeListTests.WhatsNew.VersionUpdates"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("1.53", forKey: .lastSeenWhatsNewVersion)

        let missingEntryController = makeWhatsNewController(
            defaults: defaults,
            currentVersion: "1.54",
            entries: [:]
        )
        missingEntryController.presentIfNeeded(allowsAutoPresentation: true)

        let entry = makeWhatsNewEntry(version: "1.55")
        let newVersionController = makeWhatsNewController(
            defaults: defaults,
            currentVersion: entry.version,
            entries: [entry.version: entry]
        )
        newVersionController.presentIfNeeded(allowsAutoPresentation: true)

        #expect(missingEntryController.presentedEntry == nil)
        #expect(newVersionController.presentedEntry?.version == entry.version)
    }

    @Test @MainActor func testWhatsNewManualReopenRemainsAvailableAfterDismissal() {
        let suiteName = "MyAnimeListTests.WhatsNew.ManualReopen"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let entry = makeWhatsNewEntry(version: "1.54")
        let controller = makeWhatsNewController(
            defaults: defaults,
            currentVersion: entry.version,
            entries: [entry.version: entry]
        )

        controller.presentIfNeeded(allowsAutoPresentation: true)
        controller.dismissPresentedEntry()
        controller.presentCurrentEntry()

        #expect(controller.currentEntry?.version == entry.version)
        #expect(controller.presentedEntry?.version == entry.version)
    }

    @Test @MainActor func testWhatsNewRefreshMetadataActionUsesSettingsRefreshPath() {
        let defaults = UserDefaults.standard
        let key = String.libraryHideDroppedByDefault
        let originalValue = defaults.object(forKey: key)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(true, forKey: key)

        let store = LibraryStore(dataProvider: DataProvider(inMemory: true))
        var refreshCallCount = 0
        var capturedOptions: LibraryRefreshOptions?
        var openedURL: URL?
        let actions = LibraryProfileSettingsActions(
            store: store,
            refreshInfosHandler: { _, options in
                refreshCallCount += 1
                capturedOptions = options
            }
        )

        let runner = actions.makeWhatsNewActionRunner()
        runner.run(.refreshMetadata) { url in
            openedURL = url
        }

        #expect(refreshCallCount == 1)
        #expect(capturedOptions?.prefetchImages == true)
        #expect(openedURL == nil)
        #expect(defaults.bool(forKey: key))
    }

    @Test @MainActor func testWhatsNewRefreshActionTracksInlineProgressState() {
        var capturedOptions: LibraryRefreshOptions?
        var refreshRunCount = 0
        let runner = WhatsNewActionRunner { options in
            refreshRunCount += 1
            capturedOptions = options
        }

        runner.run(.refreshMetadata) { _ in
            Issue.record("Refresh action should not open a URL.")
        }

        guard let capturedOptions else {
            Issue.record("Expected refresh options to be captured.")
            return
        }

        switch runner.refreshState {
        case .inProgress(let progress):
            #expect(progress.fractionCompleted == 0)
        default:
            Issue.record("Expected refresh to enter an in-progress state immediately.")
        }

        capturedOptions.reporter.report(
            .metadataProgress(
                current: 2,
                total: 4,
                messageResource: "Fetching Info: 2 / 4"
            )
        )

        switch runner.refreshState {
        case .inProgress(let progress):
            #expect(progress.fractionCompleted == 0.5)
        default:
            Issue.record("Expected metadata progress to keep the action in progress.")
        }

        capturedOptions.reporter.report(
            .organizingLibrary(messageResource: "Organizing Library...")
        )

        switch runner.refreshState {
        case .inProgress(let progress):
            #expect(progress.fractionCompleted == nil)
        default:
            Issue.record("Expected organizing state to be reflected inline.")
        }

        capturedOptions.reporter.report(
            .metadataPhaseComplete(
                .init(
                    state: .completed,
                    messageResource: "Refreshed infos for 4 entries.",
                    successfulItemCount: 4,
                    failedItemCount: 0
                )
            )
        )

        switch runner.refreshState {
        case .inProgress:
            break
        default:
            Issue.record("Expected metadata phase completion to remain non-terminal inline.")
        }

        capturedOptions.reporter.report(
            .imagePrefetchProgress(
                current: 3,
                total: 6,
                messageResource: "Fetching Images: 3 / 6"
            )
        )

        switch runner.refreshState {
        case .inProgress(let progress):
            #expect(progress.fractionCompleted == 0.5)
        default:
            Issue.record("Expected image prefetch progress to continue inline.")
        }

        capturedOptions.reporter.report(
            .imagePrefetchPhaseComplete(
                .init(
                    state: .completed,
                    messageResource: "Fetched: 6, failed: 0",
                    successfulItemCount: 6,
                    failedItemCount: 0
                )
            )
        )

        switch runner.refreshState {
        case .inProgress:
            break
        default:
            Issue.record("Expected image prefetch phase completion to remain non-terminal inline.")
        }

        capturedOptions.reporter.report(
            .refreshComplete(
                .init(
                    state: .completed,
                    messageResource: "Refreshed 4 entries and fetched 6 images."
                )
            )
        )

        switch runner.refreshState {
        case .completed(let completion):
            #expect(completion.state == .completed)
        default:
            Issue.record("Expected a completed inline refresh state after image prefetch completion.")
        }

        runner.run(.refreshMetadata) { _ in
            Issue.record("Completed refresh CTA should stay disabled.")
        }
        #expect(refreshRunCount == 1)

        capturedOptions.reporter.report(
            .imagePrefetchProgress(
                current: 6,
                total: 6,
                messageResource: "Fetching Images: 6 / 6"
            )
        )

        switch runner.refreshState {
        case .completed(let completion):
            #expect(completion.state == .completed)
        default:
            Issue.record("Late progress should not override completed inline refresh state.")
        }
    }

    @Test @MainActor func testToastReporterIgnoresLateProgressAfterRefreshCompletion() {
        let originalCenter = ToastCenter.global
        let center = ToastCenter()
        ToastCenter.global = center
        defer { ToastCenter.global = originalCenter }

        let reporter = LibraryRefreshReporter.toast

        reporter.report(
            .imagePrefetchProgress(
                current: 2,
                total: 4,
                messageResource: "Fetching Images: 2 / 4"
            )
        )
        #expect(center.progressState?.current == 2)

        reporter.report(
            .refreshComplete(
                .init(
                    state: .completed,
                    messageResource: "Refreshed 4 entries and fetched 6 images."
                )
            )
        )

        #expect(center.progressState == nil)
        #expect(center.loadingMessage == nil)
        #expect(center.completionState?.state == .completed)

        reporter.report(
            .imagePrefetchProgress(
                current: 4,
                total: 4,
                messageResource: "Fetching Images: 4 / 4"
            )
        )

        #expect(center.progressState == nil)
        #expect(center.completionState?.state == .completed)
    }

    @Test @MainActor func testStandaloneImagePrefetchReportsRefreshCompletion() async throws {
        func isRefreshComplete(_ event: LibraryRefreshEvent) -> Bool {
            if case .refreshComplete = event {
                true
            } else {
                false
            }
        }

        var events: [LibraryRefreshEvent] = []
        let reporter = LibraryRefreshReporter { event in
            events.append(event)
        }

        LibraryImageCacheService.prefetchImages(for: [AnimeEntry](), reporter: reporter)

        for _ in 0..<20 {
            if events.contains(where: isRefreshComplete) {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(
            events.contains { event in
                if case .imagePrefetchProgress = event {
                    true
                } else {
                    false
                }
            })
        #expect(
            events.contains { event in
                if case .imagePrefetchPhaseComplete = event {
                    true
                } else {
                    false
                }
            })

        guard
            let completion = events.compactMap({ event -> LibraryRefreshCompletion? in
                if case .refreshComplete(let completion) = event {
                    completion
                } else {
                    nil
                }
            }).first
        else {
            Issue.record("Standalone image prefetch should report overall refresh completion.")
            return
        }
        #expect(completion.state == .completed)
        #expect(completion.successfulItemCount == 0)
        #expect(completion.failedItemCount == 0)
    }

    @Test @MainActor func testStandaloneImagePrefetchToastClearsProgressOnCompletion() async throws {
        let originalCenter = ToastCenter.global
        let center = ToastCenter()
        ToastCenter.global = center
        defer { ToastCenter.global = originalCenter }

        LibraryImageCacheService.prefetchImages(for: [AnimeEntry](), reporter: .toast)

        for _ in 0..<20 {
            if center.completionState != nil {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(center.progressState == nil)
        #expect(center.loadingMessage == nil)
        #expect(center.completionState?.state == .completed)
    }
}
