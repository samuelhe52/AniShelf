//
//  ScreenSaverPublisherTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

#if os(macOS) && DEBUG
    import CryptoKit
    import DataProvider
    import Foundation
    import ImageIO
    import ScreenSaverKit
    import Testing
    import UniformTypeIdentifiers

    @testable import MyAnimeList

    @MainActor
    @Suite(.serialized)
    struct ScreenSaverPublisherTests {
        @Test
        func scopeNeverWidensAndUsesTheVisiblePreferredRow() throws {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let older = AnimeEntry(name: "Old", type: .movie, tmdbID: 1, dateSaved: .distantPast)
            older.favorite = true
            let newer = AnimeEntry(name: "Preferred", type: .movie, tmdbID: 1, dateSaved: .now)
            newer.watchStatus = .watched
            let hidden = AnimeEntry(name: "Hidden parent", type: .series, tmdbID: 2)
            hidden.setDisplayState(false)
            hidden.favorite = true
            hidden.watchStatus = .watched
            let untracked = AnimeEntry(name: "Unwatched", type: .movie, tmdbID: 3)
            try fixture.insert(older, newer, hidden, untracked)

            var settings = ScreenSaverSettings()
            settings.isEnabled = true
            #expect(fixture.draft(settings).entries.isEmpty)
            settings.scope = .watched
            #expect(fixture.draft(settings).entries.map(\.title) == ["Preferred"])
            settings.scope = .all
            #expect(fixture.draft(settings).entries.map(\.id) == ["movie:1", "movie:3"])
            newer.favorite = true
            try fixture.save()
            settings.scope = .favorites
            #expect(fixture.draft(settings).entries.map(\.id) == ["movie:1"])
        }

        @Test
        func seasonUsesParentTitleSelectedPosterAndInfoLanguage() throws {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let parent = AnimeEntry(
                name: "Library series", type: .series, tmdbID: 11,
                detail: .init(
                    language: "en", title: "Library series", status: "Returning Series", genreIDs: [16, 18, 28, 35])
            )
            parent.setDisplayState(false)
            let season = AnimeEntry(
                name: "TMDb season name", onAirDate: Date(timeIntervalSince1970: 1_685_577_600),
                type: .season(seasonNumber: 2, parentSeriesID: 11), posterPath: "/original.jpg",
                backdropPath: "/scene.jpg", customPosterPath: "/chosen.jpg", tmdbID: 12,
                detail: .init(
                    language: "en", title: "Library series", logoImagePath: "/logo.svg", genreIDs: [16, 18, 28, 35])
            )
            season.usingCustomPoster = true
            season.parentSeriesEntry = parent
            try fixture.insert(parent, season)

            var settings = ScreenSaverSettings()
            settings.isEnabled = true
            settings.scope = .all
            settings.layout = .heroStill
            fixture.defaults.set(false, forKey: .useCurrentLocaleForAnimeInfoLanguage)
            fixture.defaults.set(Language.japanese.rawValue, forKey: .preferredAnimeInfoLanguage)
            let japanese = try #require(fixture.draft(settings).entries.only)
            #expect(japanese.id == "season:11:2:12")
            #expect(japanese.title == "Library series")
            #expect(japanese.subtitle == "シーズン2")
            #expect(japanese.poster?.variant == .posterFull)
            #expect(japanese.poster?.url.lastPathComponent == "chosen.jpg")
            #expect(japanese.backdrop?.pathComponents.suffix(2) == ["original", "scene.jpg"])
            #expect(japanese.logo?.url.lastPathComponent == "logo.svg")
            #expect(
                japanese.meta?.components(separatedBy: " · ").dropFirst() == [
                    "アニメーション", "ドラマ", "アクション", "継続中"
                ])

            fixture.defaults.set(Language.chinese.rawValue, forKey: .preferredAnimeInfoLanguage)
            let chinese = try #require(fixture.draft(settings).entries.only)
            #expect(chinese.subtitle == "第2季")
            #expect(chinese.meta?.hasSuffix("动画 · 剧情 · 动作 · 连载中") == true)

            settings.showsTitles = false
            let hiddenTitles = try #require(fixture.draft(settings).entries.only)
            #expect(hiddenTitles.title == nil && hiddenTitles.subtitle == nil && hiddenTitles.logo == nil)
        }

        @Test
        func manifestReplacementAndPruningKeepTheCurrentAndPreviousImages() async throws {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let writer = ScreenSaverSnapshotWriter(directory: fixture.snapshot)
            let a = try fixture.stageImage(1)
            let b = try fixture.stageImage(2)
            let c = try fixture.stageImage(3)
            let initial = fixture.manifest(images: [a, b])
            try await writer.publish(initial, stagedImages: fixture.staging)
            let originalFile =
                try FileManager.default.attributesOfItem(atPath: fixture.manifestURL.path())[.systemFileNumber]
                as? NSNumber
            let originalBytes = try Data(contentsOf: fixture.manifestURL)
            let missing = ScreenSaverImageExporter.Image(
                filename: String(repeating: "0", count: 64) + ".heic", pixelSize: a.pixelSize)
            await #expect(throws: CocoaError.self) {
                try await writer.publish(fixture.manifest(images: [c, missing]), stagedImages: fixture.staging)
            }
            #expect(try Data(contentsOf: fixture.manifestURL) == originalBytes)
            #expect(!fixture.hasImage(c))

            let userFile = fixture.snapshot.appending(component: "images").appending(component: "keep.txt")
            try Data().write(to: userFile)
            let second = fixture.manifest(images: [b])
            try await writer.publish(second)
            #expect(await writer.readManifest() == second)
            let replacedFile =
                try FileManager.default.attributesOfItem(atPath: fixture.manifestURL.path())[.systemFileNumber]
                as? NSNumber
            #expect(originalFile != nil && replacedFile != nil && originalFile != replacedFile)
            #expect(fixture.hasImage(a) && fixture.hasImage(b))

            let third = fixture.manifest(images: [c])
            try await writer.publish(third, stagedImages: fixture.staging)
            #expect(await writer.readManifest() == third)
            #expect(!fixture.hasImage(a) && fixture.hasImage(b) && fixture.hasImage(c))
            #expect(FileManager.default.fileExists(atPath: userFile.path()))
        }

        @Test
        func changesDebounceAndUnchangedDraftsDoNotExportOrPublish() async throws {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let entry = AnimeEntry(name: "One", type: .movie, posterPath: "/one.jpg", tmdbID: 1)
            entry.favorite = true
            try fixture.insert(entry)
            var settings = ScreenSaverSettings()
            settings.isEnabled = true
            settings.save(to: fixture.defaults)

            var builds = 0
            var exports = 0
            let publisher = ScreenSaverPublisher(
                defaults: fixture.defaults, directory: fixture.snapshot, debounce: .milliseconds(60),
                buildDraft: { settings, language in
                    builds += 1
                    return ScreenSaverSnapshotBuilder.build(from: fixture.store, settings: settings, language: language)
                },
                exportImage: { request, staging in
                    exports += 1
                    return try fixture.stageImage(for: request, to: staging)
                }
            )
            let writer = ScreenSaverSnapshotWriter(directory: fixture.snapshot)
            try await waitUntil { publisher.status.lastPublication != nil && !publisher.status.isPublishing }
            let generation = try #require(await writer.readManifest()).generation
            #expect(builds == 1 && exports == 1)

            for _ in 0..<3 { publisher.libraryDidChange() }
            #expect(builds == 1)
            try await waitUntil { builds == 2 }
            #expect(exports == 1)
            #expect(await writer.readManifest()?.generation == generation)

            await publisher.refreshNow()
            #expect(exports == 1)
            #expect(await writer.readManifest()?.generation != generation)

            entry.name = "Renamed"
            try fixture.save()
            publisher.libraryDidChange()
            try await waitUntil { await writer.readManifest()?.entries.first?.title == "Renamed" }
            #expect(exports == 1)

            let originalPoster = try #require(await writer.readManifest()?.entries.first?.poster)
            entry.posterPath = "/replacement.jpg"
            try fixture.save()
            publisher.libraryDidChange()
            try await waitUntil { await writer.readManifest()?.entries.first?.poster != originalPoster }
            #expect(exports == 2)

            settings.scope = .watched
            settings.save(to: fixture.defaults)
            try await waitUntil { await writer.readManifest()?.entries.isEmpty == true }

            settings.scope = .favorites
            settings.save(to: fixture.defaults)
            try await waitUntil { await writer.readManifest()?.entries.count == 1 }
            settings.isEnabled = false
            settings.save(to: fixture.defaults)
            try await waitUntil { await writer.readManifest()?.entries.isEmpty == true }
            #expect(exports == 2)
        }

        @Test
        func scopeReductionLandsWhileNewImagesArePendingAndFailedArtIsCounted() async throws {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let kept = AnimeEntry(name: "Keep", type: .movie, posterPath: "/keep.jpg", tmdbID: 1)
            let removed = AnimeEntry(name: "Remove", type: .movie, posterPath: "/remove.jpg", tmdbID: 2)
            kept.favorite = true
            try fixture.insert(kept, removed)
            var settings = ScreenSaverSettings()
            settings.isEnabled = true
            settings.scope = .all
            settings.save(to: fixture.defaults)
            let gate = ImageGate()
            let publisher = ScreenSaverPublisher(
                defaults: fixture.defaults, directory: fixture.snapshot, debounce: .milliseconds(30),
                buildDraft: { settings, language in
                    ScreenSaverSnapshotBuilder.build(from: fixture.store, settings: settings, language: language)
                },
                exportImage: { request, staging in
                    if case .poster(let image) = request, image.url.lastPathComponent == "slow.jpg" {
                        await gate.wait()
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    return try fixture.stageImage(for: request, to: staging)
                }
            )
            defer { gate.release() }
            let writer = ScreenSaverSnapshotWriter(directory: fixture.snapshot)
            try await waitUntil { await writer.readManifest()?.entries.count == 2 }

            let slow = AnimeEntry(name: "Slow", type: .movie, posterPath: "/slow.jpg", tmdbID: 3)
            slow.favorite = true
            try fixture.insert(slow)
            settings.scope = .favorites
            settings.save(to: fixture.defaults)

            try await waitUntil { gate.isWaiting }
            #expect(await writer.readManifest()?.entries.map(\.id) == ["movie:1"])
            gate.release()
            try await waitUntil { !publisher.status.isPublishing }
            #expect(publisher.status.eligibleCount == 2)
            #expect(publisher.status.unavailableImageCount == 1)
            #expect(await writer.readManifest()?.entries.map(\.id) == ["movie:1"])
        }

        @Test
        func fixtureSettingsPreserveExistingSnapshotUntilEnabled() async throws {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let writer = ScreenSaverSnapshotWriter(directory: fixture.snapshot)
            let image = try fixture.stageImage(1)
            let existing = fixture.manifest(images: [image])
            try await writer.publish(existing, stagedImages: fixture.staging)

            let publisher = ScreenSaverPublisher(
                defaults: fixture.defaults, directory: fixture.snapshot, debounce: .milliseconds(30),
                preserveSnapshotUntilEnabled: true,
                buildDraft: { settings, language in
                    ScreenSaverSnapshotBuilder.build(from: fixture.store, settings: settings, language: language)
                }
            )
            await publisher.refreshNow()
            #expect(await writer.readManifest() == existing)
            #expect(publisher.status.generation == nil)

            publisher.settings.isEnabled = true
            #expect(fixture.defaults.bool(forKey: ScreenSaverSettings.enabledKey))
            try await waitUntil {
                await writer.readManifest()?.entries.isEmpty == true && !publisher.status.isPublishing
            }
            #expect(publisher.status.generation != nil)
            #expect(publisher.status.generation == (await writer.readManifest())?.generation)
        }

        @Test
        func enablingAnEmptyScopePublishesItsFirstManifest() async throws {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            var draftsBuilt = 0
            let publisher = ScreenSaverPublisher(
                defaults: fixture.defaults, directory: fixture.snapshot, debounce: .milliseconds(30),
                buildDraft: { settings, language in
                    draftsBuilt += 1
                    return ScreenSaverSnapshotBuilder.build(from: fixture.store, settings: settings, language: language)
                },
                exportImage: { _, _ in
                    Issue.record("An empty scope has no images to export")
                    throw CocoaError(.fileReadNoSuchFile)
                }
            )
            let writer = ScreenSaverSnapshotWriter(directory: fixture.snapshot)
            try await waitUntil { draftsBuilt == 1 && !publisher.status.isPublishing }
            #expect(!(await writer.hasManifest()))
            fixture.defaults.set(true, forKey: ScreenSaverSettings.enabledKey)
            try await waitUntil { await writer.readManifest()?.entries.isEmpty == true }
        }

        @Test
        func revertingScopeWhileAPartialPublicationIsActiveRestoresThePriorDraft() async throws {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let kept = AnimeEntry(name: "Keep", type: .movie, posterPath: "/keep.jpg", tmdbID: 1)
            let removed = AnimeEntry(name: "Remove", type: .movie, posterPath: "/remove.jpg", tmdbID: 2)
            kept.favorite = true
            try fixture.insert(kept, removed)
            var settings = ScreenSaverSettings()
            settings.isEnabled = true
            settings.scope = .all
            settings.save(to: fixture.defaults)
            let gate = ImageGate()
            var pauseNextImage = false
            let publisher = ScreenSaverPublisher(
                defaults: fixture.defaults, directory: fixture.snapshot, debounce: .milliseconds(30),
                buildDraft: { settings, language in
                    ScreenSaverSnapshotBuilder.build(from: fixture.store, settings: settings, language: language)
                },
                exportImage: { request, staging in
                    if pauseNextImage {
                        pauseNextImage = false
                        await gate.wait()
                    }
                    try Task.checkCancellation()
                    return try fixture.stageImage(for: request, to: staging)
                }
            )
            defer { gate.release() }
            let writer = ScreenSaverSnapshotWriter(directory: fixture.snapshot)
            try await waitUntil { publisher.status.lastPublication != nil && !publisher.status.isPublishing }

            pauseNextImage = true
            kept.posterPath = "/replacement.jpg"
            try fixture.save()
            fixture.defaults.set(ScreenSaverSettings.Scope.favorites.rawValue, forKey: ScreenSaverSettings.scopeKey)
            try await waitUntil { gate.isWaiting }
            #expect(await writer.readManifest()?.entries.map(\.id) == ["movie:1"])

            kept.posterPath = "/keep.jpg"
            try fixture.save()
            fixture.defaults.set(ScreenSaverSettings.Scope.all.rawValue, forKey: ScreenSaverSettings.scopeKey)
            try await waitUntil { await writer.readManifest()?.entries.map(\.id) == ["movie:1", "movie:2"] }
            gate.release()
            try await waitUntil { !publisher.status.isPublishing }
        }

        @Test
        func optionalArtworkFailuresKeepTheEntryAndRequiredPosterFailureDropsIt() async throws {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let noBackdrop = AnimeEntry(
                name: "No backdrop", type: .movie, posterPath: "/portrait.jpg",
                backdropPath: "/broken.jpg", tmdbID: 1
            )
            let noLogo = AnimeEntry(
                name: "Text instead", type: .series, posterPath: "/portrait.jpg",
                backdropPath: "/landscape.jpg", tmdbID: 2,
                detail: .init(language: "en", title: "Text instead", logoImagePath: "/broken.svg")
            )
            let noPoster = AnimeEntry(
                name: "No poster", type: .movie, posterPath: "/broken.jpg", tmdbID: 3
            )
            try fixture.insert(noBackdrop, noLogo, noPoster)
            var settings = ScreenSaverSettings()
            settings.isEnabled = true
            settings.scope = .all
            settings.layout = .heroStill
            settings.save(to: fixture.defaults)
            let publisher = ScreenSaverPublisher(
                defaults: fixture.defaults, directory: fixture.snapshot,
                buildDraft: { settings, language in
                    ScreenSaverSnapshotBuilder.build(from: fixture.store, settings: settings, language: language)
                },
                exportImage: { request, staging in
                    switch request {
                    case .poster(let image) where image.url.lastPathComponent == "broken.jpg",
                        .logo(let image) where image.url.lastPathComponent == "broken.svg":
                        throw CocoaError(.fileReadCorruptFile)
                    case .backdrop(let url) where url.lastPathComponent == "broken.jpg":
                        throw CocoaError(.fileReadCorruptFile)
                    default:
                        return try fixture.stageImage(for: request, to: staging)
                    }
                }
            )
            try await waitUntil { publisher.status.lastPublication != nil && !publisher.status.isPublishing }
            let writer = ScreenSaverSnapshotWriter(directory: fixture.snapshot)
            let entries = try #require(await writer.readManifest()?.entries)
            #expect(entries.map(\.id) == ["movie:1", "series:2"])
            #expect(entries.first?.backdrop == nil)
            #expect(entries.last?.backdrop != nil && entries.last?.logo == nil)
            #expect(entries.last?.title == "Text instead")
            #expect(publisher.status.unavailableImageCount == 1)
        }

        private func waitUntil(_ predicate: () async -> Bool) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(4)
            while !(await predicate()) {
                try #require(clock.now < deadline, "Timed out waiting for the publisher")
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    @MainActor
    fileprivate final class ImageGate {
        private var continuation: CheckedContinuation<Void, Never>?
        var isWaiting: Bool { continuation != nil }

        func wait() async {
            await withCheckedContinuation { continuation = $0 }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    @MainActor
    fileprivate struct Fixture {
        let directory: URL
        let suite = "AniShelf.ScreenSaverTests.\(UUID())"
        let defaults: UserDefaults
        let store: LibraryStore

        init() throws {
            let library = try #require(LibraryFixture.fromLaunchArguments(["test", "-library-fixture", "0"]))
            directory = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
            defaults = try #require(UserDefaults(suiteName: suite))
            store = LibraryStore(
                dataProvider: library.makeBootstrap().provider, preferences: LibraryPreferences(defaults: defaults),
                allowsCloudSync: false
            )
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        }

        var staging: URL { directory.appending(component: "staging") }
        var snapshot: URL { directory.appending(component: "snapshot") }
        var manifestURL: URL { snapshot.appending(component: "manifest.json") }

        func insert(_ entries: AnimeEntry...) throws {
            let context = store.dataProvider.dataHandler.modelContext
            for entry in entries { context.insert(entry) }
            try save()
        }

        func save() throws {
            try store.dataProvider.dataHandler.modelContext.save()
            try store.refreshLibrary()
        }

        func draft(_ settings: ScreenSaverSettings) -> ScreenSaverSnapshotDraft {
            ScreenSaverSnapshotBuilder.build(
                from: store, settings: settings, language: .resolvedAnimeInfoLanguage(defaults: defaults)
            )
        }

        func stageImage(_ value: UInt8, to location: URL? = nil) throws -> ScreenSaverImageExporter.Image {
            let data = Data([value])
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let filename = "\(hash).heic"
            try data.write(to: (location ?? staging).appending(component: filename), options: .atomic)
            return .init(filename: filename, pixelSize: .init(width: 10, height: 15))
        }

        func stageImage(
            for request: ScreenSaverImageExporter.Request, to location: URL
        ) throws -> ScreenSaverImageExporter.Image {
            let context = try #require(
                CGContext(
                    data: nil, width: 64, height: 96, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ))
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 96))
            let pixels = try #require(context.makeImage())
            let filename = request.filename
            let url = location.appending(component: filename)
            let type: UTType = url.pathExtension == "heic" ? .heic : .png
            let destination = try #require(
                CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
            )
            CGImageDestinationAddImage(destination, pixels, nil)
            try #require(CGImageDestinationFinalize(destination))
            return .init(filename: filename, pixelSize: .init(width: 64, height: 96))
        }

        func manifest(images: [ScreenSaverImageExporter.Image]) -> ScreenSaverManifest {
            ScreenSaverManifest(
                settings: ScreenSaverSettings().manifestSettings,
                entries: images.map { .init(id: $0.filename, poster: $0.path, posterPixelSize: $0.pixelSize) }
            )
        }

        func hasImage(_ image: ScreenSaverImageExporter.Image) -> Bool {
            let url = snapshot.appending(component: "images").appending(component: image.filename)
            return FileManager.default.fileExists(atPath: url.path())
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    extension Array {
        fileprivate var only: Element? { count == 1 ? first : nil }
    }
#endif
