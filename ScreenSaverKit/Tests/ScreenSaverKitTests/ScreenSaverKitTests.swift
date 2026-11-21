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
            settings: .init(
                layout: .backdrop, details: [.score, .userScore, .year], interval: 12, coverWallRows: 8,
                washFlows: false, washSpeed: 2, flipDelay: 25, driftRate: 12, deckDepth: 8, pileDepth: 11,
                timelineHold: 23, timelineDateSource: .watchDates, timelineDatePrecision: .yearAndMonth,
                backdropSubjectAwareText: false),
            entries: [
                .init(
                    id: "fixture-1",
                    title: "銀河鉄道",
                    season: "Season 2",
                    year: "2026",
                    airDate: Date(timeIntervalSince1970: 1_685_577_600.75),
                    watchStartDate: Date(timeIntervalSince1970: 1_790_000_001.25),
                    watchEndDate: Date(timeIntervalSince1970: 1_790_000_300.75),
                    dateLocaleIdentifier: "ja_JP",
                    genres: ["Adventure"],
                    status: "Ended",
                    userScore: "★ 4.5",
                    poster: "images/poster.heic",
                    posterPixelSize: .init(width: 600, height: 900),
                    backdrop: "images/backdrop.heic",
                    logo: "images/logo.png",
                    backdropRegions: [.init(bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), confidence: 0.7)]
                )
            ]
        )
        try fixture.write(expected)

        #expect(fixture.reader.read() == .ready(expected))
        let encoded = try expected.encoded()
        #expect(String(decoding: encoded, as: UTF8.self).contains("2026-09-21T14:13:20Z"))
        #expect(expected.settings.details == [.year, .score, .userScore])

        var oldManifest = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var oldEntries = try #require(oldManifest["entries"] as? [[String: Any]])
        oldEntries[0].removeValue(forKey: "backdropRegions")
        oldManifest["entries"] = oldEntries
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            ScreenSaverManifest.self, from: JSONSerialization.data(withJSONObject: oldManifest))
        #expect(decoded.entries.first?.backdropRegions == nil)
    }

    @Test
    func backdropPlacementRequiresAConfidentLeftSubjectAndAClearRightSide() {
        typealias Region = ScreenSaverManifest.Entry.SalientRegion
        let screen = CGRect(x: 0, y: 0, width: 1_600, height: 900)
        let text = CGRect(x: 60, y: 60, width: 400, height: 100)
        let left = CGRect(x: 0.02, y: 0.02, width: 0.28, height: 0.45)
        let right = CGRect(x: 0.70, y: 0.02, width: 0.28, height: 0.45)
        let centered = CGRect(x: 0.40, y: 0.05, width: 0.2, height: 0.5)
        let slightOverlap = CGRect(x: 0.25, y: 0.02, width: 0.1, height: 0.45)
        let partialLeft = CGRect(x: 0.20, y: 0.02, width: 0.1, height: 0.45)
        let partialRight = CGRect(x: 0.70, y: 0.02, width: 0.05, height: 0.45)
        func placement(_ regions: [Region]?) -> BackdropPlacement {
            BackdropPlacement(regions: regions, imageSize: screen.size, screen: screen, leftFrame: text)
        }

        #expect(placement(nil).side == .left)
        #expect(placement([.init(bounds: left, confidence: 0.64)]).side == .left)
        #expect(placement([.init(bounds: centered, confidence: 0.90)]).side == .left)
        #expect(placement([.init(bounds: slightOverlap, confidence: 0.90)]).side == .left)
        #expect(placement([.init(bounds: left, confidence: 0.65)]).side == .right)
        #expect(
            placement([.init(bounds: left, confidence: 0.95), .init(bounds: right, confidence: 0.95)]).side == .left)
        #expect(
            placement([.init(bounds: left, confidence: 0.95), .init(bounds: right, confidence: 0.50)]).side == .left)
        #expect(placement([.init(bounds: partialLeft, confidence: 0.95)]).side == .right)
        #expect(
            placement([.init(bounds: partialLeft, confidence: 0.95), .init(bounds: partialRight, confidence: 0.95)])
                .side == .left)
    }

    @Test
    func backdropPlacementMapsTheVisiblePortraitCrop() throws {
        let screen = CGRect(x: 0, y: 0, width: 900, height: 1_600)
        let text = CGRect(x: 60, y: 60, width: 300, height: 120)
        let imageSize = CGSize(width: 1_600, height: 900)
        let croppedOut = ScreenSaverManifest.Entry.SalientRegion(
            bounds: CGRect(x: 0, y: 0, width: 0.30, height: 0.5), confidence: 0.9)
        let partiallyVisible = ScreenSaverManifest.Entry.SalientRegion(
            bounds: CGRect(x: 0.30, y: 0, width: 0.15, height: 0.5), confidence: 0.9)

        let placement = BackdropPlacement(
            regions: [croppedOut, partiallyVisible], imageSize: imageSize, screen: screen, leftFrame: text)
        let mapped = try #require(placement.regions.first)
        #expect(placement.regions.count == 1)
        #expect(abs(mapped.frame.width - 307.78) < 0.01)
        #expect(mapped.frame.minX == 0)
        #expect(mapped.frame.maxY == 800)
        #expect(placement.rightFrame == CGRect(x: 540, y: 60, width: 300, height: 120))
        #expect(placement.side == .right)

        let landscape = CGRect(origin: .zero, size: imageSize)
        let uncropped = BackdropPlacement(
            regions: [croppedOut], imageSize: imageSize, screen: landscape, leftFrame: text)
        let portrait = BackdropPlacement(
            regions: [croppedOut], imageSize: imageSize, screen: screen, leftFrame: text)
        #expect(uncropped.side == .right)
        #expect(portrait.side == .left)
    }

    @Test
    func layoutSettingsDecodeWithClampingAndRequireEveryNewKey() throws {
        typealias Settings = ScreenSaverManifest.Settings
        let keys = [
            "flipDelay", "driftRate", "deckDepth", "pileDepth", "timelineHold",
            "timelineDateSource", "timelineDatePrecision"
        ]
        let input = Settings(layout: .timeline, interval: 12)
        var encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        encoded["flipDelay"] = 0
        encoded["driftRate"] = 99
        encoded["deckDepth"] = 1
        encoded["pileDepth"] = 13
        encoded["timelineHold"] = 121
        let decoder = JSONDecoder()
        let settings = try decoder.decode(Settings.self, from: JSONSerialization.data(withJSONObject: encoded))
        #expect(settings.flipDelay == 1)
        #expect(settings.driftRate == 30)
        #expect(settings.deckDepth == 2)
        #expect(settings.pileDepth == 12)
        #expect(settings.timelineHold == 120)
        #expect(settings.timelineDateSource == .airDate)
        #expect(settings.timelineDatePrecision == .fullDate)

        var beforePosterOverviewLines = encoded
        beforePosterOverviewLines.removeValue(forKey: "posterOverviewLines")
        let olderSettings = try decoder.decode(
            Settings.self, from: JSONSerialization.data(withJSONObject: beforePosterOverviewLines))
        #expect(olderSettings.posterOverviewLines == Settings.defaultPosterOverviewLines)

        var beforeBackdropSetting = encoded
        beforeBackdropSetting.removeValue(forKey: "backdropSubjectAwareText")
        let olderBackdropSettings = try decoder.decode(
            Settings.self, from: JSONSerialization.data(withJSONObject: beforeBackdropSetting))
        #expect(olderBackdropSettings.backdropSubjectAwareText)

        for key in keys {
            var incomplete = encoded
            incomplete.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: incomplete)
            #expect(throws: DecodingError.self) {
                try decoder.decode(Settings.self, from: data)
            }
        }
    }

    @Test(arguments: [4.0, 30.0])
    func depthDriftPreparesOnlyActiveSlots(rate: Double) throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        try fixture.writeImage("poster.png")
        let image = try #require(fixture.reader.image(at: "images/poster.png", maximumPixelSize: 30))
        var director = DepthDriftDirector(
            .init(
                entries: [fixture.entry(1)], settings: .init(layout: .depthDrift, interval: 12, driftRate: rate),
                size: CGSize(width: 1920, height: 1080), scale: 1, seed: 7))
        var decodes = 0
        let load: ScreenSaverImageLoader = { _, _ in
            decodes += 1
            return image
        }

        let firstStep = director.next(image: load)
        let opening = try #require(firstStep)
        guard case .open(let posters) = opening.step as? DepthDriftStep else {
            Issue.record("Expected a populated opening")
            return
        }
        #expect(decodes == posters.count)
        #expect(rate == 30 ? posters.count == 48 : (20...25).contains(posters.count))

        let focus = DepthDriftLevel.focus
        let foreground = DepthDriftLevel.foreground
        var expires = posters.map {
            (level: $0.level, time: DepthDriftLevel.all[$0.level].crossing * (1 - $0.progress))
        }
        #expect((3...4).contains(expires.count { $0.level == focus }))
        var time = opening.duration
        while time <= 85 {
            expires.removeAll { $0.time <= time + 0.000_001 }
            let before = decodes
            let step = director.next(image: load)
            let next = try #require(step)
            guard case .spawn(let poster) = next.step as? DepthDriftStep else {
                Issue.record("Expected an admitted poster")
                return
            }
            #expect(decodes == before + 1)
            expires.append((poster.level, time + DepthDriftLevel.all[poster.level].crossing))
            #expect(expires.count <= 48)
            #expect((3...4).contains(expires.count { $0.level == focus }))
            #expect(expires.count { $0.level == foreground } <= 2)
            time += next.duration
        }
    }

    @Test
    func timelineOrdersFullAirDatesAndMarksReadableYearBoundaries() throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        try fixture.writeImage("poster.png")
        let poster = try #require(fixture.reader.image(at: "images/poster.png", maximumPixelSize: 30))
        let dateParser = ISO8601DateFormatter()
        func entry(_ id: String, _ date: String?, poster: String = "images/poster.png") -> ScreenSaverManifest.Entry {
            .init(
                id: id, year: "1999年", airDate: date.flatMap { dateParser.date(from: $0) }, poster: poster,
                posterPixelSize: .init(width: 20, height: 30))
        }
        let entries: [ScreenSaverManifest.Entry] = [
            entry("b-june", "2020-06-01T00:00:00Z"),
            entry("z-january", "2020-01-01T00:00:00Z"),
            entry("undated", nil),
            entry("c-next-year", "2021-02-01T00:00:00Z"),
            entry("broken", "2021-01-01T00:00:00Z", poster: "images/broken.png"),
            entry("a-june", "2020-06-01T00:00:00Z")
        ]
        var director = TimelineDirector(
            .init(
                entries: entries, settings: .init(layout: .timeline, interval: 12),
                size: CGSize(width: 1280, height: 800), scale: 1, seed: 7))
        let image: ScreenSaverImageLoader = { path, _ in path == "images/poster.png" ? poster : nil }
        let opening = try #require(director.next(image: image)?.step as? TimelineStep)
        guard case .open(_, var slots, _) = opening else {
            Issue.record("Expected the Timeline to open")
            return
        }
        for _ in entries.indices {
            let step = try #require(director.next(image: image)?.step as? TimelineStep)
            guard case .advance(let incoming) = step else {
                Issue.record("Expected the Timeline to continue past missing artwork")
                return
            }
            slots.append(incoming)
        }
        let expected: [String: (nextID: String, marker: TimelineMarker?)] = [
            "z-january": ("a-june", nil),
            "a-june": ("b-june", nil),
            "b-june": ("c-next-year", .year(2021)),
            "c-next-year": ("z-january", .wrap(2020))
        ]
        for (left, right) in zip(slots, slots.dropFirst()) {
            let next = try #require(expected[left.entry.id])
            #expect(right.entry.id == next.nextID)
            #expect(right.marker == next.marker)
            #expect(right.position == left.position + 1)
        }
    }

    @Test
    func timelineWatchDatesShowRangesOpenOnTheMissingSide() async throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        try fixture.writeImage("poster.png")
        let calendar = Calendar(identifier: .gregorian)
        func day(_ day: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2024, month: 6, day: day)))
        }
        func entry(_ id: String, airDate: Date? = nil, start: Date? = nil, end: Date? = nil, locale: String = "ja-JP")
            -> ScreenSaverManifest.Entry
        {
            .init(
                id: id, airDate: airDate, watchStartDate: start, watchEndDate: end, dateLocaleIdentifier: locale,
                poster: "images/poster.png", posterPixelSize: .init(width: 20, height: 30))
        }
        // An entry with only an end date sorts by it.
        let entries: [ScreenSaverManifest.Entry] = [
            entry("open", start: try day(5)),
            entry("closed", start: try day(2), end: try day(10)),
            entry("endOnly", end: try day(3)),
            entry("undated", airDate: try day(4))
        ]
        let cases: [(ScreenSaverManifest.TimelineDatePrecision, [String])] = [
            (.fullDate, ["2024年6月2日～10日", "～2024年6月3日", "2024年6月5日～"]),
            (.yearAndMonth, ["2024年6月", "～2024年6月", "2024年6月～"])
        ]
        for (precision, captions) in cases {
            let settings = ScreenSaverManifest.Settings(
                layout: .timeline, interval: 12, timelineHold: 15, timelineDateSource: .watchDates,
                timelineDatePrecision: precision)
            try fixture.write(.init(settings: settings, entries: entries))
            let loader = ScreenSaverSceneLoader(directory: fixture.directory, seed: 7, entryLimit: 3)
            let snapshot = await loader.read()
            let scene = await loader.prepare(
                snapshot, cursor: .init(), size: CGSize(width: 1_280, height: 800), scale: 1)
            guard case .stage(let step) = scene.content, case .open(_, let slots, _) = step as? TimelineStep else {
                Issue.record("Expected a Timeline at \(precision)")
                continue
            }
            #expect(scene.duration == 15)
            let first = try #require(slots.firstIndex { $0.entry.id == "closed" })
            let shown = slots[first...].prefix(3)
            #expect(shown.map(\.entry.id) == ["closed", "endOnly", "open"])
            #expect(shown.map(\.dateText) == captions)
        }

        let english = TimelineDateText(source: .watchDates, precision: .fullDate)
        let started = entry("en", start: try day(5), locale: "en_US")
        #expect(english.text(for: started) == "Jun 5, 2024\u{2009}–")
    }

    @Test
    func readerFallbacks() throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }

        #expect(fixture.reader.read() == .empty)
        try Data("not JSON".utf8).write(to: fixture.manifestURL)
        #expect(fixture.reader.read() == .empty)
        try Data(#"{"schemaVersion":2}"#.utf8).write(to: fixture.manifestURL)
        #expect(fixture.reader.read() == .empty)
        try Data(#"{"schemaVersion":999,"payload":"future format"}"#.utf8).write(to: fixture.manifestURL)
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

    @Test(arguments: [4, 11])
    func repeatedWallArtworkAvoidsNeighboursAndRepeatingPatterns(posterCount: Int) async throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        let posters = (0..<posterCount).map { "poster-\($0)" }
        // Each width identifies one exported path, including across separate decodes.
        for (index, name) in posters.enumerated() {
            try fixture.writeImage("\(name).png", width: 20 + index)
        }
        let names = ["missing", posters[0]] + posters
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
        var columns: [[Int]] = []
        func verifyColumn(_ images: ArraySlice<CGImage>) {
            let identities = images.map(\.width)
            #expect(identities.count == grid.rows)
            for index in identities.indices {
                if index > 0 { #expect(identities[index] != identities[index - 1]) }
                if let previous = columns.last { #expect(identities[index] != previous[index]) }
            }
            columns.append(identities)
        }
        for column in 0..<grid.columns {
            let start = column * grid.rows
            verifyColumn(images[start..<(start + grid.rows)])
        }
        for _ in 0..<24 {
            scene = await loader.prepare(.ready(manifest), cursor: scene.next, size: viewport, scale: 1)
            guard case .wallColumn(let images) = scene.content else {
                Issue.record("Expected one recycled column")
                return
            }
            verifyColumn(images[...])
        }
        #expect(Set(columns.joined().prefix(posterCount)).count == posterCount)
        if posterCount == 11 {
            // A fixed 11-poster cycle repeats down a diagonal in a four-row wall.
            // Look in both diagonal directions and across the typical visible width.
            for dx in 1..<grid.columns {
                for dy in (1 - grid.rows)..<grid.rows {
                    let matchingTiles = (dx..<columns.count).reduce(into: 0) { count, x in
                        for y in 0..<grid.rows where (0..<grid.rows).contains(y - dy) {
                            if columns[x][y] == columns[x - dx][y - dy] { count += 1 }
                        }
                    }
                    let overlap = (columns.count - dx) * (grid.rows - abs(dy))
                    #expect(matchingTiles * 2 < overlap)
                }
            }
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

    @Test(arguments: [ScreenSaverManifest.Layout.posterFocus, .backdrop])
    func slideshowReshufflesEachPassWithoutRepeatingAcrossTheBoundary(_ layout: ScreenSaverManifest.Layout) async throws
    {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        try fixture.writeImage("poster.png")
        try fixture.writeImage("backdrop.png")
        let entries = (0..<5).map { index in
            fixture.entry(
                index, poster: index.isMultiple(of: 2) ? "images/poster.png" : "images/missing.png",
                backdrop: index == 2 ? "images/backdrop.png" : "images/missing-backdrop.png")
        }
        try fixture.write(.init(settings: .init(layout: layout, interval: 12), entries: entries))
        let loader = ScreenSaverSceneLoader(directory: fixture.directory, seed: 42)
        let snapshot = await loader.read()
        let viewport = CGSize(width: 800, height: 500)
        let expected = Set([entries[0].id, entries[2].id, entries[4].id])
        var cursor = ScreenSaverScene.Cursor()
        var previousID: String?
        var orders: Set<[String]> = []
        for _ in 0..<6 {
            var pass: [String] = []
            for _ in expected {
                let scene = await loader.prepare(snapshot, cursor: cursor, size: viewport, scale: 1)
                let entry: ScreenSaverManifest.Entry
                switch scene.content {
                case .poster(let displayed, _, _), .backdrop(let displayed, _, _): entry = displayed
                default:
                    Issue.record("Expected a readable slide")
                    return
                }
                #expect(entry.id != previousID)
                previousID = entry.id
                pass.append(entry.id)
                cursor = scene.next
            }
            #expect(Set(pass) == expected)
            orders.insert(pass)
        }
        #expect(orders.count > 1)
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
            entries: [entry, fixture.entry(1, poster: "images/missing.png")]
        )
        var cursor = ScreenSaverScene.Cursor()
        for _ in 0..<3 {
            let scene = await loader.prepare(
                .ready(manifest), cursor: cursor, size: CGSize(width: 180, height: 320), scale: 2)
            guard case .poster(let displayed, _, _) = scene.content else {
                Issue.record("Expected Poster Focus")
                return
            }
            #expect(displayed == entry)
            #expect(scene.duration == 7)
            cursor = scene.next
        }
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
    func posterOverviewLimitSurvivesSnapshotAndReachesBothPosterLayouts() throws {
        let overview = String(repeating: "A long overview with many words. ", count: 100)
        let entry = ScreenSaverManifest.Entry(
            id: "poster", title: "Title", year: "2026", overview: overview,
            poster: "memory", posterPixelSize: .init(width: 20, height: 30))
        let image = try #require(
            CGContext(data: nil, width: 20, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage())
        for layout in [ScreenSaverManifest.Layout.posterFocus, .coverFusion] {
            for limit in [3, 8, ScreenSaverManifest.Settings.unlimitedPosterOverviewLines] {
                let settings = ScreenSaverManifest.Settings(
                    layout: layout, details: [.year, .overview], interval: 12, posterOverviewLines: limit)
                let manifest = ScreenSaverManifest(settings: settings, entries: [])
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(ScreenSaverManifest.self, from: manifest.encoded())
                #expect(decoded.settings == settings)
                let scene = ScreenSaverSceneLoader.prepare(
                    entries: [entry], settings: decoded.settings, cursor: .init(),
                    size: CGSize(width: 800, height: 500), scale: 1, image: { _, _ in image })
                let layouts = ScreenSaverLayouts(
                    size: CGSize(width: 800, height: 500), scale: 1, posterOverviewLines: scene.posterOverviewLines)
                let lines = layouts.posterFocusLines(entry, details: scene.details, width: 300)
                #expect(lines.map(\.lines) == [3, 2, limit == 0 ? .max : limit])
                let rendered = try #require(layouts.fittedText(
                    overview, width: 300, size: 11, weight: .regular, lines: lines[2].lines))
                let measured = layouts.measure(
                    layouts.attributed(overview, size: 11, weight: .regular, alpha: 1), width: 300)
                if limit == 0 { #expect(rendered.height >= measured.height) }
                else { #expect(rendered.height < measured.height) }
            }
        }
    }

    @Test
    @MainActor
    func editorialCoverFitsAnOverviewBelowALargeHeadline() throws {
        let poster = try #require(
            CGContext(
                data: nil, width: 20, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )?.makeImage())
        let entry = ScreenSaverManifest.Entry(
            id: "editorial", title: "日々は過ぎれど飯うまし", season: "シーズン1", year: "2025", genres: ["コメディ"],
            watchStatus: "視聴済", userScore: "★ 4.5",
            overview: "大学に入ったばかりの五人は、授業が終わるといつも一緒に帰る。おいしいものを探したり、初めての町を散歩したりしながら、少しずつ大学生活にも慣れていく。",
            poster: "memory", posterPixelSize: .init(width: 20, height: 30))
        let layouts = ScreenSaverLayouts(size: CGSize(width: 1512, height: 982), scale: 1)
        let facts: Set<ScreenSaverManifest.Detail> = [.season, .year, .genres, .watchStatus, .userScore]
        let without = layouts.editorialCover(entry, poster: poster, accent: .paper, details: facts)
        let with = layouts.editorialCover(entry, poster: poster, accent: .paper, details: facts.union([.overview]))
        let text = (with.sublayers ?? []).filter { $0.name == ScreenSaverLayouts.textLayerName }
        let withoutText = (without.sublayers ?? []).filter { $0.name == ScreenSaverLayouts.textLayerName }
        try #require(text.count == withoutText.count + 1)
        let headline = try #require(text.first)
        let overview = try #require(text.last)
        #expect(overview.frame.maxY < headline.frame.minY)
        #expect(overview.frame.minY > 0)
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
    func backdropTextSettingRepositionsTheSamePreviewArtwork() async throws {
        let bitmap = try #require(
            CGContext(
                data: nil, width: 32, height: 18, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )?.makeImage())
        let renderer = ScreenSaverRenderer { _ in "Empty" }
        defer { renderer.stop() }
        let size = CGSize(width: 800, height: 450)
        renderer.resize(to: size, scale: 1)
        let entry = ScreenSaverManifest.Entry(
            id: "first", title: "Backdrop title", poster: "memory", posterPixelSize: .init(width: 32, height: 18),
            backdrop: "memory",
            backdropRegions: [.init(bounds: CGRect(x: 0, y: 0, width: 0.4, height: 0.4), confidence: 0.9)]
        )

        func render(subjectAwareText: Bool) async throws -> CGRect {
            let previous = renderer.layer.sublayers?.last
            renderer.updatePreview(
                .init(
                    settings: .init(layout: .backdrop, interval: 60, backdropSubjectAwareText: subjectAwareText),
                    entries: [entry], images: ["memory": bitmap]
                ))
            let deadline = ContinuousClock.now + .seconds(2)
            while ContinuousClock.now < deadline {
                if let scene = renderer.layer.sublayers?.last, scene !== previous,
                    let text = scene.sublayers?.first(where: { $0.name == ScreenSaverLayouts.textLayerName })
                {
                    return text.frame
                }
                try await Task.sleep(for: .milliseconds(5))
            }
            throw CocoaError(.coderInvalidValue)
        }

        let on = try await render(subjectAwareText: true)
        let off = try await render(subjectAwareText: false)
        #expect(abs(off.minX - size.height * 0.07) < 0.001)
        #expect(abs(on.maxX - (size.width - off.minX)) < 0.001)
        #expect(on.minX > off.minX)
        #expect(try await render(subjectAwareText: true) == on)
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

    @Test
    func aSaverBuiltFromOtherCodeAsksToBeReinstalled() throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        let settings = ScreenSaverManifest.Settings(layout: .coverWall, interval: 12)
        try fixture.write(.init(settings: settings, entries: [fixture.entry(1)], saverBuild: "new"))
        #expect(ScreenSaverSnapshotReader(directory: fixture.directory, build: "old").read() == .requiresUpdate)
        guard case .ready = ScreenSaverSnapshotReader(directory: fixture.directory, build: "new").read() else {
            Issue.record("A matching build should play the snapshot")
            return
        }
        // Snapshots from AniShelf builds before the build ID, and readers without one, skip the check.
        try fixture.write(.init(settings: settings, entries: [fixture.entry(1)]))
        guard case .ready = ScreenSaverSnapshotReader(directory: fixture.directory, build: "old").read() else {
            Issue.record("A snapshot without a build ID should play")
            return
        }
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
