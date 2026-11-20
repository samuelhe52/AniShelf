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
    }

    enum Content: Sendable {
        case wall(CoverWallGrid, [CGImage])
        case wallColumn([CGImage])
        case poster(ScreenSaverManifest.Entry, CGImage, background: CGImage?)
        case backdrop(ScreenSaverManifest.Entry, image: CGImage, logo: CGImage?)
        case notice(ScreenSaverRenderer.Notice)
    }

    let content: Content
    var details: Set<ScreenSaverManifest.Detail> = []
    var duration: TimeInterval = 4
    var next = Cursor()
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
    private var orderedSnapshot: ScreenSaverSnapshotReader.Snapshot = .empty

    init(directory: URL, build: String? = nil, seed: UInt64 = 0) {
        reader = ScreenSaverSnapshotReader(directory: directory, build: build)
        self.seed = seed
    }

    func read() -> ScreenSaverSnapshotReader.Snapshot {
        let current = reader.read()
        guard !current.isSamePublication(as: orderedSnapshot) else { return orderedSnapshot }

        if case .ready(let manifest) = current {
            var random = ScreenSaverRandomGenerator(state: seed)
            orderedSnapshot = .ready(
                ScreenSaverManifest(
                    generation: manifest.generation, createdAt: manifest.createdAt, settings: manifest.settings,
                    entries: manifest.entries.shuffled(using: &random)
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
            seed: seed,
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
        image: (String, Int) -> CGImage?
    ) -> ScreenSaverScene {
        if settings.layout == .coverWall, entries.count >= 4,
            let wall = loadWall(
                entries, cursor: cursor, size: size, scale: scale, rows: settings.coverWallRows, seed: seed, image: image
            )
        {
            return wall
        }

        var slides = cursor.slides ?? ScreenSaverSlideOrder(
            count: entries.count, startingAt: cursor.startIndex, seed: seed)
        let content = slides.next { index in
            let entry = entries[index]
            if settings.layout == .backdrop, let path = entry.backdrop,
                let backdrop = image(path, pixelLimit(max(size.width, size.height) * scale, 2_560))
            {
                let logo = entry.logo.flatMap { image($0, 1_024) }
                return .backdrop(entry, image: backdrop, logo: logo)
            }
            if let poster = image(entry.poster, pixelLimit(size.height * scale, 1_500)) {
                return .poster(entry, poster, background: blurredBackground(of: poster))
            }
            return nil
        }
        guard let content else { return ScreenSaverScene(content: .notice(.empty)) }
        let interval = settings.interval.isFinite ? min(max(settings.interval, 1), 3_600) : 12
        return ScreenSaverScene(
            content: content, details: Set(settings.details), duration: interval, next: .init(slides: slides))
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

    private static func pixelLimit(_ size: CGFloat, _ limit: Int) -> Int {
        Int(ceil(min(max(size, 1), CGFloat(limit))))
    }

    // CIContext is thread-safe; one shared context avoids rebuilding its caches for every slide.
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    /// A small, heavily blurred copy of the poster that the layout stretches across the screen.
    private static func blurredBackground(of poster: CGImage) -> CGImage? {
        let width = 96
        let height = max(1, Int((CGFloat(poster.height) / CGFloat(max(poster.width, 1)) * CGFloat(width)).rounded()))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(poster, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage() else { return nil }

        let input = CIImage(cgImage: small)
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: 7)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.25])
            .cropped(to: input.extent)
        return imageContext.createCGImage(output, from: input.extent)
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
