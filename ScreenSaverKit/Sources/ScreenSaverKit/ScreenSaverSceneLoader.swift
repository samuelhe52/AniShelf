//
//  ScreenSaverSceneLoader.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import CoreGraphics
import CoreImage
import Foundation

struct ScreenSaverScene: Sendable {
    struct Cursor: Sendable {
        var startIndex = 0
        var slides: ScreenSaverSlideOrder?
        var wall: CoverWallShuffleBag?
        var stage: (any ScreenSaverStageDirector)?
    }

    enum Content: Sendable {
        case wall(CoverWallGrid, [CGImage])
        case wallColumn([CGImage])
        case poster(ScreenSaverManifest.Entry, CGImage, wash: ScreenSaverMesh)
        case backdrop(ScreenSaverManifest.Entry, image: CGImage, logo: CGImage?)
        case stage(any ScreenSaverStageStep)
        case fusion(ScreenSaverManifest.Entry, poster: CGImage, posterRatio: CGFloat, wash: ScreenSaverMesh)
        case editorial(ScreenSaverManifest.Entry, poster: CGImage, accent: ScreenSaverColor, wash: ScreenSaverMesh)
        case notice(ScreenSaverRenderer.Notice)
    }

    let content: Content
    var details: Set<ScreenSaverManifest.Detail> = []
    var duration: TimeInterval = 4
    var next = Cursor()
    var washFlows = true
    var washSpeed: Double = 1
}

struct ScreenSaverSlideOrder: Sendable {
    private var order: [Int]
    private var position = 0
    private var lastDisplayed: Int?
    private var random: ScreenSaverRandomGenerator

    init(count: Int, startingAt startIndex: Int, seed: UInt64) {
        order = (0..<count).map { (startIndex + $0) % count }
        random = ScreenSaverRandomGenerator(state: seed)
    }

    mutating func next(load: (Int) -> ScreenSaverScene.Content?) -> ScreenSaverScene.Content? {
        var openedNewPass = false
        while !order.isEmpty, !Task.isCancelled {
            if position == order.count {
                // Try at most the rest of the current pass and one full new pass.
                guard lastDisplayed != nil, !openedNewPass else { return nil }
                order.shuffle(using: &random)
                position = 0
                openedNewPass = true
            }

            // Defer the previous slide until another readable slide opens the pass.
            // Unreadable candidates may bring it to the front more than once.
            if openedNewPass, order[position] == lastDisplayed, position + 1 < order.count {
                order.swapAt(position, Int.random(in: (position + 1)..<order.count, using: &random))
            }
            let index = order[position]
            position += 1
            if let slide = load(index) {
                lastDisplayed = index
                return slide
            }
        }
        return nil
    }
}

actor ScreenSaverSceneLoader {
    private let reader: ScreenSaverSnapshotReader
    private let seed: UInt64
    private let draft: ScreenSaverDraft?
    private var orderedSnapshot: ScreenSaverSnapshotReader.Snapshot = .empty

    init(directory: URL, build: String? = nil, seed: UInt64 = 0, draft: ScreenSaverDraft? = nil) {
        reader = ScreenSaverSnapshotReader(directory: directory, build: build)
        self.seed = seed
        self.draft = draft
    }

    func read() -> ScreenSaverSnapshotReader.Snapshot {
        let current = reader.read()
        guard !current.isSamePublication(as: orderedSnapshot) else { return orderedSnapshot }

        if case .ready(let manifest) = current {
            var random = ScreenSaverRandomGenerator(state: seed)
            var entries = manifest.entries
            if let draft, draft.layout == .timeline, draft.entryLimit != nil {
                entries = entries.filter { draft.timelineDateSource.date(for: $0) != nil }
            }
            entries.shuffle(using: &random)
            if let limit = draft?.entryLimit { entries = Array(entries.prefix(max(limit, 1))) }
            orderedSnapshot = .ready(
                ScreenSaverManifest(
                    generation: manifest.generation, createdAt: manifest.createdAt,
                    settings: draft?.settings ?? manifest.settings, entries: entries
                ))
        } else {
            orderedSnapshot = current
        }
        return orderedSnapshot
    }

    func prepare(
        _ snapshot: ScreenSaverSnapshotReader.Snapshot,
        cursor: ScreenSaverScene.Cursor,
        size: CGSize,
        scale: CGFloat
    ) -> ScreenSaverScene {
        let manifest: ScreenSaverManifest
        switch snapshot {
        case .empty: return ScreenSaverScene(content: .notice(.empty))
        case .requiresUpdate: return ScreenSaverScene(content: .notice(.requiresUpdate))
        case .ready(let value): manifest = value
        }

        return Self.prepare(
            entries: manifest.entries, settings: manifest.settings, cursor: cursor, size: size, scale: scale,
            seed: seed, draft: draft,
            image: reader.image(at:maximumPixelSize:)
        )
    }

    static func prepare(
        entries: [ScreenSaverManifest.Entry],
        settings: ScreenSaverManifest.Settings,
        cursor: ScreenSaverScene.Cursor,
        size: CGSize,
        scale: CGFloat,
        seed: UInt64 = 0,
        draft: ScreenSaverDraft? = nil,
        image: (String, Int) -> CGImage?
    ) -> ScreenSaverScene {
        var scene = prepareContent(
            entries: entries, settings: settings, cursor: cursor, size: size, scale: scale, seed: seed, draft: draft,
            image: image)
        scene.washFlows = settings.washFlows
        scene.washSpeed = settings.washSpeed
        return scene
    }

    private static func prepareContent(
        entries: [ScreenSaverManifest.Entry],
        settings: ScreenSaverManifest.Settings,
        cursor: ScreenSaverScene.Cursor,
        size: CGSize,
        scale: CGFloat,
        seed: UInt64,
        draft: ScreenSaverDraft?,
        image: (String, Int) -> CGImage?
    ) -> ScreenSaverScene {
        if let layout = draft?.layout {
            return prepareDraft(
                layout, draft: draft!, entries: entries, settings: settings, cursor: cursor, size: size, scale: scale,
                seed: seed, image: image)
        }
        if settings.layout == .coverWall, entries.count >= 4,
            let wall = loadWall(
                entries, cursor: cursor, size: size, scale: scale, rows: settings.coverWallRows, seed: seed,
                image: image
            )
        {
            return wall
        }

        return slideScene(entries: entries, settings: settings, cursor: cursor, seed: seed) { entry in
            if settings.layout == .backdrop, let path = entry.backdrop,
                let backdrop = image(path, pixelLimit(max(size.width, size.height) * scale, 2_560))
            {
                let logo = entry.logo.flatMap { image($0, 1_024) }
                return .backdrop(entry, image: backdrop, logo: logo)
            }
            if let poster = image(entry.poster, pixelLimit(size.height * scale, 1_500)) {
                return .poster(
                    entry, poster,
                    wash: .shaded(
                        ScreenSaverArt.samples(of: poster, columns: 3, rows: 3), columns: 3, rows: 3,
                        brightness: 0.5))
            }
            return nil
        }
    }

    /// The next readable slide, in shuffled passes, held for the settings' interval.
    private static func slideScene(
        entries: [ScreenSaverManifest.Entry],
        settings: ScreenSaverManifest.Settings,
        cursor: ScreenSaverScene.Cursor,
        seed: UInt64,
        load: (ScreenSaverManifest.Entry) -> ScreenSaverScene.Content?
    ) -> ScreenSaverScene {
        var slides =
            cursor.slides ?? ScreenSaverSlideOrder(count: entries.count, startingAt: cursor.startIndex, seed: seed)
        guard let content = slides.next(load: { load(entries[$0]) }) else {
            return ScreenSaverScene(content: .notice(.empty))
        }
        return ScreenSaverScene(
            content: content, details: Set(settings.details), duration: settings.interval, next: .init(slides: slides))
    }

    private static func loadWall(
        _ entries: [ScreenSaverManifest.Entry],
        cursor: ScreenSaverScene.Cursor,
        size: CGSize,
        scale: CGFloat,
        rows: Int,
        seed: UInt64,
        image: (String, Int) -> CGImage?
    ) -> ScreenSaverScene? {
        let grid = CoverWallGrid(viewport: size, rows: rows)
        let initial = cursor.wall == nil
        var bag = cursor.wall ?? CoverWallShuffleBag(entries: entries, grid: grid, seed: seed)
        let tileCount = (initial ? grid.columns : 1) * grid.rows
        let pixelSize = pixelLimit(grid.tileSize.height * scale * 1.25, 1_500)
        var imagesByPath: [String: CGImage] = [:]
        var images: [CGImage] = []
        images.reserveCapacity(tileCount)
        for _ in 0..<tileCount {
            let poster = bag.draw { path in
                if let cached = imagesByPath[path] { return cached }
                guard let decoded = image(path, pixelSize) else { return nil }
                imagesByPath[path] = decoded
                return decoded
            }
            guard let poster else { return nil }
            images.append(poster)
        }
        return ScreenSaverScene(
            content: initial ? .wall(grid, images) : .wallColumn(images),
            duration: CoverWall.driftDuration,
            next: .init(wall: bag)
        )
    }

    private static func prepareDraft(
        _ layout: ScreenSaverDraftLayout,
        draft: ScreenSaverDraft,
        entries: [ScreenSaverManifest.Entry],
        settings: ScreenSaverManifest.Settings,
        cursor: ScreenSaverScene.Cursor,
        size: CGSize,
        scale: CGFloat,
        seed: UInt64,
        image: (String, Int) -> CGImage?
    ) -> ScreenSaverScene {
        if layout.isStage {
            let context = ScreenSaverDraftContext(
                entries: entries, settings: settings, draft: draft, size: size, scale: scale, seed: seed)
            guard var director = cursor.stage ?? context.makeDirector(layout),
                let next = director.next(image: image)
            else { return ScreenSaverScene(content: .notice(.empty)) }
            return ScreenSaverScene(content: .stage(next.step), duration: next.duration, next: .init(stage: director))
        }

        return slideScene(entries: entries, settings: settings, cursor: cursor, seed: seed) { entry in
            switch layout {
            case .coverFusion:
                let canvasScale = min(scale, 3_000 / max(size.width, size.height, 1))
                let canvas = CGSize(
                    width: (size.width * canvasScale).rounded(), height: (size.height * canvasScale).rounded())
                guard let poster = image(entry.poster, pixelLimit(size.height * scale, 1_500)),
                    let feathered = ScreenSaverArt.fusion(poster: poster, canvas: canvas)
                else { return nil }
                let ratio = CGFloat(poster.width) / CGFloat(poster.height)
                let wash = ScreenSaverMesh.fusion(
                    poster: poster, frame: ScreenSaverArt.fusionPosterFrame(in: size, ratio: ratio), canvas: size)
                return .fusion(entry, poster: feathered, posterRatio: ratio, wash: wash)
            default:
                guard let poster = image(entry.poster, pixelLimit(size.height * scale, 1_500)) else { return nil }
                // A dark ground in the poster's own shades, so the accent type stands out.
                return .editorial(
                    entry, poster: poster, accent: ScreenSaverArt.accent(of: poster),
                    wash: .shaded(
                        ScreenSaverArt.samples(of: poster, columns: 3, rows: 3), columns: 3, rows: 3,
                        brightness: 0.2))
            }
        }
    }

    static func pixelLimit(_ size: CGFloat, _ limit: Int) -> Int {
        Int(ceil(min(max(size, 1), CGFloat(limit))))
    }
}

/// SplitMix64 keeps a session's shuffle reproducible for any given seed.
struct ScreenSaverRandomGenerator: RandomNumberGenerator, Sendable {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
