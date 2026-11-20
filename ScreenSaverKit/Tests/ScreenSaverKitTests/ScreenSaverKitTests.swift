//
//  ScreenSaverKitTests.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import Foundation
import ImageIO
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
            settings: .init(layout: .heroStill, showsTitles: true, interval: 12),
            entries: [
                .init(
                    id: "fixture-1",
                    title: "銀河鉄道",
                    subtitle: "Season 2",
                    meta: "2026 · Adventure",
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
        try Data(#"{"schemaVersion":2,"payload":"future format"}"#.utf8).write(to: fixture.manifestURL)
        #expect(fixture.reader.read() == .requiresUpdate)
        try fixture.write(
            ScreenSaverManifest(settings: .init(layout: .coverWall, showsTitles: true, interval: 12), entries: []))
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
            (CGSize(width: 1440, height: 900), 3),
            (CGSize(width: 1920, height: 1080), 4),
            (CGSize(width: 3440, height: 1440), 6),
            (CGSize(width: 1080, height: 1920), 7),
            (CGSize(width: 220, height: 125), 2)
        ]
        for (size, expectedRows) in viewports {
            let grid = CoverWallGrid(viewport: size)
            #expect(grid.rows == expectedRows)
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
        let names = ["one", "alias-one", "two", "three", "four"]
        for (index, name) in names.enumerated() {
            let red = CGFloat(max(index - 1, 0)) / 4
            try fixture.writeImage("\(name).png", red: red)
        }
        let manifest = ScreenSaverManifest(
            settings: .init(layout: .coverWall, showsTitles: true, interval: 12),
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
        var previous: [CoverWallArtworkIdentity] = []
        func verifyColumn(_ images: ArraySlice<CGImage>) {
            let identities = images.map { CoverWallArtworkIdentity(image: $0, path: "") }
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
            settings: .init(layout: .posterFocus, showsTitles: true, interval: 12),
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

    @Test(arguments: [ScreenSaverManifest.Layout.coverWall, .heroStill])
    func layoutFallbackUsesOnlySuppliedEntries(_ layout: ScreenSaverManifest.Layout) async throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        try fixture.writeImage("poster.png")
        let entry = fixture.entry(0, backdrop: "images/missing.png")
        let loader = ScreenSaverSceneLoader(directory: fixture.directory)
        let manifest = ScreenSaverManifest(
            settings: .init(layout: layout, showsTitles: true, interval: 7),
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

    func writeImage(_ name: String, width: Int = 20, height: Int = 30, red: CGFloat = 0.5) throws {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let url = directory.appending(component: "images").appending(component: name)
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
    }
}
