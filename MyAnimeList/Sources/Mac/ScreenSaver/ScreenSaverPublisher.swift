//
//  ScreenSaverPublisher.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

#if os(macOS)
    import Combine
    import Foundation
    import Observation
    import OSLog
    import ScreenSaverKit

    @MainActor @Observable
    final class ScreenSaverPublisher {
        struct Status {
            var isPublishing = false
            var eligibleCount = 0
            var unavailableImageCount = 0
            var lastPublication: Date?
            var generation: UUID?
            var error: (any Error)?
        }

        private struct Preferences: Equatable {
            let settings: ScreenSaverSettings
            let language: Language

            init(defaults: UserDefaults) {
                settings = ScreenSaverSettings(defaults: defaults)
                language = .resolvedAnimeInfoLanguage(defaults: defaults)
            }
        }

        typealias BuildDraft = @MainActor (ScreenSaverSettings, Language) -> ScreenSaverSnapshotDraft
        typealias ExportImage =
            @MainActor (ScreenSaverImageExporter.Request, URL) async throws -> ScreenSaverImageExporter.Image

        let directory: URL
        private(set) var status = Status()

        var settings: ScreenSaverSettings {
            get { observedPreferences.settings }
            set {
                guard newValue != observedPreferences.settings else { return }
                newValue.save(to: defaults)
                preferencesDidChange()
            }
        }

        private let defaults: UserDefaults
        private let builder: BuildDraft
        private let exportImage: ExportImage
        private let writer: ScreenSaverSnapshotWriter
        private let debounce: Duration
        private var observedPreferences: Preferences
        @ObservationIgnored private var canManageSnapshot: Bool
        @ObservationIgnored private var preferenceObserver: AnyCancellable?
        @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
        @ObservationIgnored private var requestID = 0
        @ObservationIgnored private var forceRequested = false
        @ObservationIgnored private var lastDraft: ScreenSaverSnapshotDraft?

        init(
            defaults: UserDefaults,
            directory: URL,
            debounce: Duration = .seconds(5),
            preserveSnapshotUntilEnabled: Bool = false,
            buildDraft: @escaping BuildDraft,
            exportImage: @escaping ExportImage = ScreenSaverImageExporter.export
        ) {
            self.defaults = defaults
            self.directory = directory
            self.canManageSnapshot = !preserveSnapshotUntilEnabled
            self.builder = buildDraft
            self.exportImage = exportImage
            self.debounce = debounce
            writer = ScreenSaverSnapshotWriter(directory: directory)
            observedPreferences = Preferences(defaults: defaults)
            preferenceObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .merge(with: NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification))
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.preferencesDidChange() }
                }
            scheduleRefresh(after: .zero)
        }

        deinit {
            pendingRefresh?.cancel()
        }

        func libraryDidChange() {
            scheduleRefresh(after: debounce)
        }

        func refreshNow() async {
            forceRequested = true
            scheduleRefresh(after: .zero)
            await pendingRefresh?.value
        }

        private func preferencesDidChange() {
            let preferences = Preferences(defaults: defaults)
            guard preferences != observedPreferences else { return }
            observedPreferences = preferences
            scheduleRefresh(after: debounce)
        }

        private func scheduleRefresh(after delay: Duration) {
            pendingRefresh?.cancel()
            requestID &+= 1
            let request = requestID
            pendingRefresh = Task { [weak self] in
                do {
                    if delay > .zero { try await Task.sleep(for: delay) }
                    try Task.checkCancellation()
                    await self?.publish(request: request)
                } catch {}
            }
        }

        private func publish(request: Int) async {
            let preferences = Preferences(defaults: defaults)
            observedPreferences = preferences
            let draft = builder(preferences.settings, preferences.language)
            let force = forceRequested
            defer {
                if requestID == request {
                    status.isPublishing = false
                    forceRequested = false
                }
            }
            canManageSnapshot = canManageSnapshot || preferences.settings.isEnabled
            guard canManageSnapshot, force || draft != lastDraft else { return }

            status.isPublishing = true
            status.eligibleCount = draft.entries.count
            status.error = nil

            do {
                let previous = await writer.readManifest()
                let shouldPublish =
                    if preferences.settings.isEnabled || previous != nil {
                        true
                    } else {
                        await writer.hasManifest()
                    }
                try Task.checkCancellation()
                guard shouldPublish else {
                    status.unavailableImageCount = 0
                    return
                }

                let baseline = try await publishReduction(of: previous, to: draft)
                try Task.checkCancellation()
                let staging: URL?
                if draft.entries.isEmpty {
                    staging = nil
                } else {
                    let directory = FileManager.default.temporaryDirectory
                        .appending(component: "AniShelfScreenSaver-\(UUID())", directoryHint: .isDirectory)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                    staging = directory
                }
                defer {
                    if let staging { try? FileManager.default.removeItem(at: staging) }
                }
                let entries =
                    if let staging {
                        try await exportEntries(draft.entries, to: staging)
                    } else {
                        [ScreenSaverManifest.Entry]()
                    }
                try await commitIfNeeded(entries, draft: draft, baseline: baseline, force: force, staging: staging)

                try Task.checkCancellation()
                status.unavailableImageCount = draft.entries.count - entries.count
                lastDraft = draft
            } catch {
                guard !Task.isCancelled else { return }
                status.error = error
                Logger(subsystem: .bundleIdentifier, category: "ScreenSaver").error(
                    "Could not publish the screen saver snapshot: \(error.localizedDescription, privacy: .private)"
                )
            }
        }

        private func publishReduction(
            of previous: ScreenSaverManifest?,
            to draft: ScreenSaverSnapshotDraft
        ) async throws -> ScreenSaverManifest? {
            guard let previous, !draft.entries.isEmpty else { return previous }
            let wanted = Set(draft.entries.map(\.id))
            let retained = previous.entries.filter { wanted.contains($0.id) }
            guard retained.count < previous.entries.count else { return previous }

            let reduced = ScreenSaverManifest(settings: previous.settings, entries: retained)
            try await write(reduced)
            return reduced
        }

        private func commitIfNeeded(
            _ entries: [ScreenSaverManifest.Entry],
            draft: ScreenSaverSnapshotDraft,
            baseline: ScreenSaverManifest?,
            force: Bool,
            staging: URL?
        ) async throws {
            if !force, let baseline, baseline.settings == draft.settings, baseline.entries == entries {
                recordPublication(baseline)
                return
            }
            let manifest = ScreenSaverManifest(settings: draft.settings, entries: entries)
            try await write(manifest, staging: staging)
        }

        private func write(_ manifest: ScreenSaverManifest, staging: URL? = nil) async throws {
            // The writer may commit before cancellation reaches the publisher.
            // Reevaluate the next draft against disk whenever a write has started.
            lastDraft = nil
            try await writer.publish(manifest, stagedImages: staging)
            try Task.checkCancellation()
            recordPublication(manifest)
        }

        private func recordPublication(_ manifest: ScreenSaverManifest) {
            status.lastPublication = manifest.createdAt
            status.generation = manifest.generation
        }

        private func exportEntries(
            _ entries: [ScreenSaverSnapshotDraft.Entry],
            to staging: URL
        ) async throws -> [ScreenSaverManifest.Entry] {
            var published: [ScreenSaverManifest.Entry] = []
            var images: [ScreenSaverImageExporter.Request: ScreenSaverImageExporter.Image] = [:]
            var failed: Set<ScreenSaverImageExporter.Request> = []

            func image(_ request: ScreenSaverImageExporter.Request) async throws -> ScreenSaverImageExporter.Image? {
                try Task.checkCancellation()
                if let cached = images[request] { return cached }
                guard !failed.contains(request) else { return nil }
                do {
                    let existing = await writer.existingImage(named: request.filename)
                    try Task.checkCancellation()
                    let result = if let existing { existing } else { try await exportImage(request, staging) }
                    try Task.checkCancellation()
                    images[request] = result
                    return result
                } catch {
                    try Task.checkCancellation()
                    failed.insert(request)
                    return nil
                }
            }

            for entry in entries {
                try Task.checkCancellation()
                guard let poster = entry.poster, let exportedPoster = try await image(.poster(poster)) else { continue }
                var backdrop: String?
                if let source = entry.backdrop {
                    backdrop = try await image(.backdrop(source))?.path
                }
                var logo: String?
                if backdrop != nil, let source = entry.logo {
                    logo = try await image(.logo(source))?.path
                }
                published.append(
                    .init(
                        id: entry.id,
                        title: entry.title,
                        subtitle: entry.subtitle,
                        meta: entry.meta,
                        poster: exportedPoster.path,
                        posterPixelSize: exportedPoster.pixelSize,
                        backdrop: backdrop,
                        logo: logo
                    ))
            }
            return published
        }
    }
#endif
