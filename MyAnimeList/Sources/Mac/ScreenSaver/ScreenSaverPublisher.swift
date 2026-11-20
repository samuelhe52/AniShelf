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
        /// The saver AniShelf installs, inside the app bundle.
        static let embeddedSaverURL = Bundle.main.bundleURL
            .appending(path: "Contents/Library/Screen Savers/AniShelf.saver", directoryHint: .isDirectory)

        /// Build ID of the embedded saver, written into each snapshot so an installed saver built
        /// from other code asks to be reinstalled.
        static let embeddedSaverBuild =
            Bundle(url: embeddedSaverURL)?.object(forInfoDictionaryKey: ScreenSaverManifest.buildInfoKey) as? String

        struct Status {
            var isPublishing = false
            var availableCount = 0
            var unavailableImageCount = 0
            var hasPublished = false
            var error: (any Error)?
            var failedPosterCount = 0
            var hasFailedArtwork = false
        }

        private struct Preferences: Equatable {
            let settings: ScreenSaverSettings
            let language: Language
            let scoringEnabled: Bool

            init(defaults: UserDefaults) {
                settings = ScreenSaverSettings(defaults: defaults)
                language = .resolvedAnimeInfoLanguage(defaults: defaults)
                scoringEnabled = defaults.isLibraryScoringEnabled
            }
        }

        private typealias Request = ScreenSaverImageExporter.Request
        private typealias Image = ScreenSaverImageExporter.Image
        typealias BuildDraft = @MainActor (ScreenSaverSettings, Language) -> ScreenSaverSnapshotDraft
        typealias ExportImage =
            @MainActor @Sendable (ScreenSaverImageExporter.Request) async throws
            -> ScreenSaverImageExporter.EncodedImage

        private struct Artwork: Equatable {
            let posters: Set<Request>
            let backdropArt: Set<Request>

            init(_ draft: ScreenSaverSnapshotDraft) {
                posters = Set(draft.entries.compactMap { $0.poster.map(Request.poster) })
                backdropArt = Set(
                    draft.entries.flatMap { entry -> [Request] in
                        guard entry.poster != nil, let backdrop = entry.backdrop else { return [] }
                        return [.backdrop(backdrop)] + (entry.logo.map { [.logo($0)] } ?? [])
                    })
            }

            var requests: Set<Request> { posters.union(backdropArt) }
        }

        private(set) var status = Status()
        private(set) var draft: ScreenSaverSnapshotDraft

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
        @ObservationIgnored private var shouldCleanDisabledSnapshot: Bool
        @ObservationIgnored private var preferenceObserver: AnyCancellable?
        @ObservationIgnored private var libraryRefresh: Task<Void, Never>?
        @ObservationIgnored private var artworkTask: Task<Void, Never>?
        @ObservationIgnored private var manifestTask: Task<Void, Never>?
        @ObservationIgnored private var loadingPosters = false
        @ObservationIgnored private var artwork: Artwork?
        @ObservationIgnored private var images: [Request: Image] = [:]
        @ObservationIgnored private var failed: Set<Request> = []
        @ObservationIgnored private var displayed: [String: ScreenSaverManifest.Entry] = [:]
        @ObservationIgnored private var needsPruning = false

        init(
            defaults: UserDefaults,
            directory: URL,
            debounce: Duration = .seconds(5),
            preserveSnapshotUntilEnabled: Bool = false,
            buildDraft: @escaping BuildDraft,
            exportImage: @escaping ExportImage = ScreenSaverImageExporter.export
        ) {
            self.defaults = defaults
            self.shouldCleanDisabledSnapshot = !preserveSnapshotUntilEnabled
            self.builder = buildDraft
            self.exportImage = exportImage
            self.debounce = debounce
            writer = ScreenSaverSnapshotWriter(directory: directory)
            let preferences = Preferences(defaults: defaults)
            observedPreferences = preferences
            draft = .init(settings: preferences.settings.manifestSettings, entries: [])
            preferenceObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .merge(with: NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification))
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.preferencesDidChange() }
                }
            scheduleLibraryRefresh(after: .zero)
        }

        deinit {
            libraryRefresh?.cancel()
            artworkTask?.cancel()
            manifestTask?.cancel()
        }

        func libraryDidChange() {
            scheduleLibraryRefresh(after: debounce)
        }

        func retryUpdate() {
            if !settings.isEnabled {
                removeArtwork()
            } else {
                failed.removeAll()
                reconcile(retry: true)
            }
        }

        private func preferencesDidChange() {
            let preferences = Preferences(defaults: defaults)
            guard preferences != observedPreferences else { return }
            let wasEnabled = settings.isEnabled
            observedPreferences = preferences
            reconcile(stopping: wasEnabled && !settings.isEnabled)
        }

        private func scheduleLibraryRefresh(after delay: Duration) {
            libraryRefresh?.cancel()
            libraryRefresh = Task { [weak self] in
                if delay > .zero { try? await Task.sleep(for: delay) }
                guard !Task.isCancelled else { return }
                self?.reconcile()
            }
        }

        private func reconcile(stopping: Bool = false, retry: Bool = false) {
            let next = builder(settings, observedPreferences.language)
            let previousDraft = draft
            if draft != next { draft = next }

            guard settings.isEnabled else {
                if stopping || shouldCleanDisabledSnapshot {
                    shouldCleanDisabledSnapshot = false
                    removeArtwork()
                }
                return
            }

            shouldCleanDisabledSnapshot = false
            let previousArtwork = artwork
            let nextArtwork = Artwork(draft)
            artwork = nextArtwork
            if previousArtwork != nextArtwork || retry {
                needsPruning = true
                failed.formIntersection(nextArtwork.requests)
                if previousArtwork?.posters != nextArtwork.posters || !loadingPosters {
                    cancelArtwork()
                }
            }

            if artworkTask == nil,
                !pending(nextArtwork.posters).isEmpty || !pending(backdropArtRequests()).isEmpty
            {
                startArtwork()
            }
            guard retry || previousDraft != next || previousArtwork != nextArtwork else { return }
            // On launch, let the first batch of cached artwork arrive before replacing the existing snapshot.
            if previousArtwork == nil, artworkTask != nil, !retry { return }
            commit()
        }

        private func cancelArtwork() {
            artworkTask?.cancel()
            artworkTask = nil
            loadingPosters = false
        }

        private func removeArtwork() {
            cancelArtwork()
            artwork = nil
            images.removeAll()
            displayed.removeAll()
            failed.removeAll()
            needsPruning = false
            manifestTask?.cancel()
            status = Status(isPublishing: true)
            manifestTask = Task { [weak self, writer, settings = draft.settings] in
                do {
                    try await writer.removeArtwork(settings: settings)
                    guard !Task.isCancelled else { return }
                    self?.status = Status()
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.report(error)
                }
            }
        }

        private func pending(_ requests: Set<Request>) -> Set<Request> {
            requests.filter { images[$0] == nil && !failed.contains($0) }
        }

        private func backdropArtRequests() -> Set<Request> {
            Set(
                draft.entries.flatMap { entry -> [Request] in
                    guard let poster = entry.poster, images[.poster(poster)] != nil, let backdrop = entry.backdrop
                    else {
                        return []
                    }
                    let request = Request.backdrop(backdrop)
                    if images[request] != nil, let logo = entry.logo {
                        return [request, .logo(logo)]
                    }
                    return [request]
                })
        }

        private func startArtwork() {
            guard let artwork else { return }
            loadingPosters = true
            status.isPublishing = true
            status.error = nil
            let posters = pending(artwork.posters)
            artworkTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await load(posters)
                    try Task.checkCancellation()
                    loadingPosters = false
                    while !Task.isCancelled {
                        let requests = pending(backdropArtRequests())
                        if requests.isEmpty { break }
                        try await load(requests)
                    }
                    try Task.checkCancellation()
                    artworkTask = nil
                    commit()
                } catch {
                    // A replaced task is always cancelled first, so it stops here.
                    guard !Task.isCancelled else { return }
                    loadingPosters = false
                    artworkTask = nil
                    manifestTask?.cancel()
                    report(error)
                }
            }
        }

        private func load(_ requests: Set<Request>) async throws {
            let writer = writer
            let exportImage = exportImage
            let clock = ContinuousClock()
            var lastCommit: ContinuousClock.Instant?
            var remaining = requests.makeIterator()

            try await withThrowingTaskGroup(of: (Request, Image?).self) { group in
                func enqueue(_ request: Request) {
                    group.addTask {
                        let filename = request.filename
                        if let existing = try await writer.existingImage(named: filename) { return (request, existing) }
                        let encoded: ScreenSaverImageExporter.EncodedImage
                        do {
                            encoded = try await exportImage(request)
                        } catch {
                            try Task.checkCancellation()
                            return (request, nil)
                        }
                        try await writer.store(encoded)
                        return (request, encoded.image)
                    }
                }

                // Bound retrieval and encoding together. Refill slots as soon as a request completes.
                for _ in 0..<6 {
                    guard let request = remaining.next() else { break }
                    enqueue(request)
                }
                while let (request, image) = try await group.next() {
                    try Task.checkCancellation()
                    if let image {
                        images[request] = image
                        let now = clock.now
                        if lastCommit.map({ $0.duration(to: now) >= .milliseconds(150) }) ?? true {
                            lastCommit = now
                            commit()
                        }
                    } else {
                        failed.insert(request)
                    }
                    if let request = remaining.next() { enqueue(request) }
                }
            }

            if lastCommit != nil { commit() }
        }

        private func commit() {
            guard let artwork else { return }
            manifestTask?.cancel()
            let draft = draft
            let entries = resolvedEntries()
            let manifest = ScreenSaverManifest(
                settings: draft.settings, entries: entries, saverBuild: Self.embeddedSaverBuild)
            let complete = needsPruning && artworkTask == nil
            let extraFiles = Set(artwork.requests.compactMap { images[$0]?.filename })
            let hasFailedArtwork = !failed.isDisjoint(with: artwork.requests)
            var readyCount = 0
            var failedPosterCount = 0
            for entry in draft.entries {
                guard let poster = entry.poster else { continue }
                let request = Request.poster(poster)
                if images[request] != nil { readyCount += 1 }
                if failed.contains(request) { failedPosterCount += 1 }
            }
            status.availableCount = readyCount
            if complete {
                images = images.filter { artwork.requests.contains($0.key) }
            }
            manifestTask = Task { [weak self, writer] in
                do {
                    let written = try await writer.publish(manifest, complete: complete, keeping: extraFiles)
                    guard let self, !Task.isCancelled else { return }
                    if complete { needsPruning = false }
                    displayed = Dictionary(uniqueKeysWithValues: written.entries.map { ($0.id, $0) })
                    status = Status(
                        isPublishing: artworkTask != nil,
                        availableCount: readyCount,
                        unavailableImageCount: draft.entries.count - written.entries.count,
                        hasPublished: true,
                        failedPosterCount: failedPosterCount,
                        hasFailedArtwork: hasFailedArtwork
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.report(error)
                }
            }
        }

        private func resolvedEntries() -> [ScreenSaverManifest.Entry] {
            draft.entries.compactMap { entry in
                guard let source = entry.poster else { return nil }
                let request = Request.poster(source)
                guard let poster = images[request] else {
                    // Keep artwork already being shown while a replacement for the same entry is prepared.
                    guard artworkTask != nil, !failed.contains(request), let prior = displayed[entry.id] else {
                        return nil
                    }
                    return entry.manifestEntry(poster: prior.poster, posterPixelSize: prior.posterPixelSize)
                }
                let backdrop = entry.backdrop.flatMap { images[.backdrop($0)] }
                return entry.manifestEntry(
                    poster: poster.path, posterPixelSize: poster.pixelSize, backdrop: backdrop?.path,
                    logo: backdrop != nil ? entry.logo.flatMap { images[.logo($0)]?.path } : nil)
            }
        }

        private func report(_ error: any Error) {
            status.isPublishing = false
            status.error = error
            Logger(subsystem: .bundleIdentifier, category: "ScreenSaver").error(
                "Could not update screen saver artwork: \(error.localizedDescription, privacy: .private)"
            )
        }
    }
#endif
