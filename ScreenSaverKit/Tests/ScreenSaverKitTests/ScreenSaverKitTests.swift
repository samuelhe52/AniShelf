//
//  ScreenSaverKitTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import Foundation
import ImageIO
import QuartzCore
import Testing
import UniformTypeIdentifiers

@testable import ScreenSaverKit

struct ScreenSaverKitTests {
    @Test
    func manifestRoundTrip() throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        let expected = ScreenSaverManifest(
            createdAt: Date(timeIntervalSince1970: 1_790_000_000.123),
            settings: .init(layout: .backdrop, details: [.score, .year], interval: 12, coverWallRows: 8),
            entries: [
                .init(
                    id: "fixture-1",
                    title: "銀河鉄道",
                    season: "Season 2",
                    year: "2026",
                    genres: ["Adventure"],
                    status: "Ended",
                    poster: "images/poster.heic",
                    posterPixelSize: .init(width: 600, height: 900),
                    backdrop: "images/backdrop.heic",
                    logo: "images/logo.png"
                )
            ]
        )
        try fixture.write(expected)

        #expect(fixture.reader.read() == .ready(expected))
        let encoded = try expected.encoded()
        #expect(String(decoding: encoded, as: UTF8.self).contains("2026-09-21T14:13:20Z"))
        #expect(expected.rendererVersion == ScreenSaverManifest.currentRendererVersion)

        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var legacySettings = try #require(legacy["settings"] as? [String: Any])
        legacySettings["coverWallRows"] = nil
        legacySettings["details"] = nil
        legacy["settings"] = legacySettings
        legacy["rendererVersion"] = 2
        legacy["schemaVersion"] = 2
        try JSONSerialization.data(withJSONObject: legacy).write(to: fixture.manifestURL)
        guard case .ready(let legacyManifest) = fixture.reader.read() else {
            Issue.record("The renderer should be able to read an existing snapshot")
            return
        }
        #expect(legacyManifest.entries == expected.entries)
        #expect(legacyManifest.rendererVersion == 2)
        #expect(legacyManifest.settings.coverWallRows == 4)
        #expect(legacyManifest.settings.details == [.year])
        #expect(expected.settings.details == [.year, .score])

        legacy["rendererVersion"] = nil
        legacy["schemaVersion"] = 1
        try JSONSerialization.data(withJSONObject: legacy).write(to: fixture.manifestURL)
        guard case .ready(let versionOne) = fixture.reader.read() else {
            Issue.record("The renderer should still accept schema version 1")
            return
        }
        #expect(versionOne.rendererVersion == nil)
        #expect(versionOne.settings.coverWallRows == 4)
    }

    @Test
    func readerFallbacks() throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }

        #expect(fixture.reader.read() == .empty)
        try Data("not JSON".utf8).write(to: fixture.manifestURL)
        #expect(fixture.reader.read() == .empty)
        try Data(#"{"schemaVersion":0}"#.utf8).write(to: fixture.manifestURL)
        #expect(fixture.reader.read() == .empty)
        try Data(#"{"schemaVersion":999,"payload":"future format"}"#.utf8).write(to: fixture.manifestURL)
        #expect(fixture.reader.read() == .requiresUpdate)
        try Data(#"{"schemaVersion":2,"rendererVersion":999}"#.utf8).write(to: fixture.manifestURL)
        #expect(fixture.reader.read() == .requiresUpdate)
        try fixture.write(
            ScreenSaverManifest(settings: .init(layout: .coverWall, interval: 12), entries: []))
        #expect(fixture.reader.read() == .empty)
    }

    @Test
    func imageReadingBoundsDecodeAndRejectsInvalidPaths() throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        try fixture.writeImage("poster.png", width: 240, height: 360)
        let image = try #require(fixture.reader.image(at: "images/poster.png", maximumPixelSize: 90))
        #expect(image.width == 60)
        #expect(image.height == 90)

        let images = fixture.directory.appending(component: "images")
        let original = images.appending(component: "poster.png")
        try FileManager.default.createSymbolicLink(
            at: images.appending(component: "link.png"), withDestinationURL: original)
        try Data("broken image".utf8).write(to: images.appending(component: "broken.png"))
        for path in [
            "images/missing.png", "images/link.png", "images/broken.png", "images/../images/poster.png", original.path
        ] {
            #expect(fixture.reader.image(at: path, maximumPixelSize: 90) == nil)
        }
    }

    @Test
    func wallRowsFillTheHeightAndColumnsCoverTheDrift() {
        let viewports: [(CGSize, Int)] = [
            (CGSize(width: 1920, height: 1080), 2),
            (CGSize(width: 1920, height: 1080), 4),
            (CGSize(width: 1920, height: 1080), 8),
            (CGSize(width: 3440, height: 1440), 8),
            (CGSize(width: 1080, height: 1920), 4)
        ]
        for (size, rows) in viewports {
            let grid = CoverWallGrid(viewport: size, rows: rows)
            #expect(grid.rows == rows)
            #expect(grid.tileSize.height > 0)
            let fill = CGFloat(grid.rows) * grid.tileSize.height + CGFloat(grid.rows - 1) * grid.gap
            #expect(abs(fill - size.height) < 0.0001)
            #expect(CGFloat(grid.columns - 1) * grid.stride >= size.width)
            #expect(CGFloat(grid.columns - 2) * grid.stride < size.width)
        }
    }

    @Test
    func repeatedWallArtworkAvoidsNeighboursIncludingRecycledColumns() async throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        let posters = ["one", "two", "three", "four"]
        // Each width identifies one exported path, including across separate decodes.
        for (index, name) in posters.enumerated() {
            try fixture.writeImage("\(name).png", width: 20 + index)
        }
        let names = ["one"] + posters
        let manifest = ScreenSaverManifest(
            settings: .init(layout: .coverWall, interval: 12),
            entries: names.enumerated().map { index, name in
                fixture.entry(index, poster: "images/\(name).png")
            }
        )
        let loader = ScreenSaverSceneLoader(directory: fixture.directory)
        let viewport = CGSize(width: 1920, height: 1080)
        var scene = await loader.prepare(.ready(manifest), cursor: .init(), size: viewport, scale: 1)
        guard case .wall(let grid, let images) = scene.content else {
            Issue.record("Expected a wall")
            return
        }
        #expect(images.count == grid.rows * grid.columns)
        var previous: [Int] = []
        func verifyColumn(_ images: ArraySlice<CGImage>) {
            let identities = images.map(\.width)
            #expect(identities.count == grid.rows)
            for index in identities.indices {
                if index > 0 { #expect(identities[index] != identities[index - 1]) }
                if previous.indices.contains(index) { #expect(identities[index] != previous[index]) }
            }
            previous = identities
        }
        for column in 0..<grid.columns {
            let start = column * grid.rows
            verifyColumn(images[start..<(start + grid.rows)])
        }
        for _ in 0..<8 {
            scene = await loader.prepare(.ready(manifest), cursor: scene.next, size: viewport, scale: 1)
            guard case .wallColumn(let images) = scene.content else {
                Issue.record("Expected one recycled column")
                return
            }
            verifyColumn(images[...])
        }
    }

    @Test
    func sessionShuffleIsStableForASeedAndChangesWithANewSeed() async throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        let manifest = ScreenSaverManifest(
            settings: .init(layout: .posterFocus, interval: 12),
            entries: (0..<20).map { fixture.entry($0) }
        )
        try fixture.write(manifest)
        let first = ScreenSaverSceneLoader(directory: fixture.directory, seed: 42)
        let repeatedSeed = ScreenSaverSceneLoader(directory: fixture.directory, seed: 42)
        let otherSeed = ScreenSaverSceneLoader(directory: fixture.directory, seed: 43)
        let initial = await first.read()
        guard case .ready(let shuffled) = initial else {
            Issue.record("Expected the shuffled publication")
            return
        }
        #expect(shuffled.entries.map(\.id) != manifest.entries.map(\.id))
        #expect(Set(shuffled.entries.map(\.id)) == Set(manifest.entries.map(\.id)))
        #expect(await first.read() == initial)
        #expect(await repeatedSeed.read() == initial)
        #expect(await otherSeed.read() != initial)
    }

    @Test(arguments: [ScreenSaverManifest.Layout.coverWall, .backdrop])
    func layoutFallbackUsesOnlySuppliedEntries(_ layout: ScreenSaverManifest.Layout) async throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        try fixture.writeImage("poster.png")
        let entry = fixture.entry(0, backdrop: "images/missing.png")
        let loader = ScreenSaverSceneLoader(directory: fixture.directory)
        let manifest = ScreenSaverManifest(
            settings: .init(layout: layout, interval: 7),
            entries: [entry]
        )
        let scene = await loader.prepare(
            .ready(manifest), cursor: .init(), size: CGSize(width: 180, height: 320), scale: 2)
        guard case .poster(let displayed, _, _) = scene.content else {
            Issue.record("Expected Poster Focus")
            return
        }
        #expect(displayed == entry)
        #expect(scene.next.index == 0)
        #expect(scene.duration == 7)
    }

    @Test
    func stopAndRestartInvalidateEarlierSessions() {
        var session = ScreenSaverSession()
        let first = session.start()
        #expect(session.contains(first))
        session.stop()
        #expect(!session.contains(first))
        let second = session.start()
        #expect(session.contains(second))
        let third = session.start()
        #expect(!session.contains(first))
        #expect(!session.contains(second))
        #expect(session.contains(third))
    }

    @Test
    @MainActor
    func inMemoryPreviewRespondsToPresentationChangesWithTheSameArtwork() async throws {
        let bitmap = try #require(
            CGContext(
                data: nil, width: 20, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )?.makeImage())
        let renderer = ScreenSaverRenderer { _ in "Empty" }
        defer { renderer.stop() }
        let viewport = CGSize(width: 200, height: 125)
        let layoutSize = CGSize(width: 800, height: 500)
        renderer.resize(to: viewport, scale: 2, layoutSize: layoutSize)
        let entries: [ScreenSaverManifest.Entry] = [
            .init(
                id: "first", title: "Poster title", overview: "Poster overview", poster: "memory",
                posterPixelSize: .init(width: 20, height: 30))
        ]
        renderer.updatePreview(
            .init(
                settings: .init(layout: .posterFocus, interval: 60),
                entries: entries, images: ["memory": bitmap]
            ))

        func waitForScene(after previous: CALayer?) async throws -> CALayer {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(2)
            while clock.now < deadline {
                if let scene = renderer.layer.sublayers?.last, scene !== previous { return scene }
                try await Task.sleep(for: .milliseconds(5))
            }
            throw CocoaError(.coderInvalidValue)
        }

        let withTitle = try await waitForScene(after: nil)
        #expect(withTitle.bounds.size == layoutSize)
        #expect(withTitle.frame == CGRect(origin: .zero, size: viewport))
        #expect(withTitle.sublayers?.contains { $0.name == ScreenSaverLayouts.textLayerName } == true)
        let alternate = try #require(bitmap.cropping(to: CGRect(x: 0, y: 0, width: 10, height: 15)))
        let other = ScreenSaverManifest.Entry(
            id: "other", title: "Other title", poster: "alternate", posterPixelSize: .init(width: 10, height: 15)
        )
        renderer.updatePreview(
            .init(
                settings: .init(layout: .posterFocus, details: [.overview], interval: 60),
                entries: [other] + entries, images: ["memory": bitmap, "alternate": alternate]
            ))
        // The title is always shown; the overview detail adds a second text layer.
        let withOverview = try await waitForScene(after: withTitle)
        #expect(withOverview.sublayers?.filter { $0.name == ScreenSaverLayouts.textLayerName }.count == 2)
        let layers = (withOverview.sublayers ?? []).flatMap { [$0] + ($0.sublayers ?? []) }
        #expect(layers.contains { ($0.contents as AnyObject?) === bitmap })
    }

    @Test
    @MainActor
    func stoppingRendererClearsSceneAfterPendingLoads() async throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        let renderer = ScreenSaverRenderer { _ in "Test" }
        renderer.resize(to: CGSize(width: 800, height: 600), scale: 1)
        renderer.start(in: fixture.directory)
        renderer.stop()
        // Give the pending work a chance to return to the main actor.
        try await Task.sleep(for: .milliseconds(50))
        #expect(renderer.layer.sublayers?.isEmpty != false)
    }
}

fileprivate struct SnapshotFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory.appending(component: "images"), withIntermediateDirectories: true)
    }

    var reader: ScreenSaverSnapshotReader { ScreenSaverSnapshotReader(directory: directory) }
    var manifestURL: URL { directory.appending(component: ScreenSaverSnapshotReader.manifestFilename) }

    func write(_ manifest: ScreenSaverManifest) throws {
        try manifest.encoded().write(to: manifestURL, options: .atomic)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func entry(_ index: Int, poster: String = "images/poster.png", backdrop: String? = nil) -> ScreenSaverManifest.Entry
    {
        .init(
            id: "fixture-\(index)", title: "Test \(index)", poster: poster,
            posterPixelSize: .init(width: 20, height: 30), backdrop: backdrop)
    }

    func writeImage(_ name: String, width: Int = 20, height: Int = 30) throws {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let url = directory.appending(component: "images").appending(component: name)
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
    }
}
