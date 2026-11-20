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
        var index = 0
        var wallColumn: [String]?
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

actor ScreenSaverSceneLoader {
    private let reader: ScreenSaverSnapshotReader
    private let seed: UInt64
    private var orderedSnapshot: ScreenSaverSnapshotReader.Snapshot = .empty

    init(directory: URL, seed: UInt64 = 0) {
        reader = ScreenSaverSnapshotReader(directory: directory)
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
            image: reader.image(at:maximumPixelSize:)
        )
    }

    static func prepare(
        entries: [ScreenSaverManifest.Entry],
        settings: ScreenSaverManifest.Settings,
        cursor: ScreenSaverScene.Cursor,
        size: CGSize,
        scale: CGFloat,
        image: (String, Int) -> CGImage?
    ) -> ScreenSaverScene {
        if settings.layout == .coverWall, entries.count >= 4,
            let wall = loadWall(
                entries, cursor: cursor, size: size, scale: scale, rows: settings.coverWallRows, image: image)
        {
            return wall
        }

        let interval = settings.interval.isFinite ? min(max(settings.interval, 1), 3_600) : 12
        for offset in entries.indices {
            guard !Task.isCancelled else { break }
            let index = (cursor.index + offset) % entries.count
            let entry = entries[index]
            let next = ScreenSaverScene.Cursor(index: (index + 1) % entries.count)
            let content: ScreenSaverScene.Content
            if settings.layout == .backdrop, let path = entry.backdrop,
                let backdrop = image(path, pixelLimit(max(size.width, size.height) * scale, 2_560))
            {
                let logo = entry.logo.flatMap { image($0, 1_024) }
                content = .backdrop(entry, image: backdrop, logo: logo)
            } else if let poster = image(entry.poster, pixelLimit(size.height * scale, 1_500)) {
                content = .poster(entry, poster, background: blurredBackground(of: poster))
            } else {
                continue
            }
            return ScreenSaverScene(
                content: content, details: Set(settings.details), duration: interval, next: next)
        }
        return ScreenSaverScene(content: .notice(.empty))
    }

    private static func loadWall(
        _ entries: [ScreenSaverManifest.Entry],
        cursor: ScreenSaverScene.Cursor,
        size: CGSize,
        scale: CGFloat,
        rows: Int,
        image: (String, Int) -> CGImage?
    ) -> ScreenSaverScene? {
        let grid = CoverWallGrid(viewport: size, rows: rows)
        let columnCount = cursor.wallColumn == nil ? grid.columns : 1
        let pixelSize = pixelLimit(grid.tileSize.height * scale * 1.25, 1_500)
        var imagesByPath: [String: CGImage] = [:]
        var unreadable: Set<String> = []
        var readableEntries: Set<Int> = []

        func readablePath(at index: Int) -> String? {
            let path = entries[index].poster
            if imagesByPath[path] == nil {
                guard !unreadable.contains(path) else { return nil }
                guard let image = image(path, pixelSize) else {
                    unreadable.insert(path)
                    return nil
                }
                imagesByPath[path] = image
            }
            readableEntries.insert(index)
            return path
        }

        var index = cursor.index
        var leftColumn = cursor.wallColumn ?? []
        var images: [CGImage] = []
        for _ in 0..<columnCount {
            var column: [String] = []
            for row in 0..<grid.rows {
                let horizontal = leftColumn.indices.contains(row) ? leftColumn[row] : nil
                let vertical = column.last
                var candidate: (index: Int, path: String)?
                for offset in entries.indices {
                    guard !Task.isCancelled else { return nil }
                    let nextIndex = (index + offset) % entries.count
                    guard let path = readablePath(at: nextIndex) else { continue }
                    if path != horizontal, path != vertical {
                        candidate = (nextIndex, path)
                        break
                    }
                    if candidate == nil { candidate = (nextIndex, path) }
                }
                guard let candidate, let image = imagesByPath[candidate.path] else { return nil }
                column.append(candidate.path)
                images.append(image)
                index = (candidate.index + 1) % entries.count
            }
            leftColumn = column
        }

        guard cursor.wallColumn != nil || readableEntries.count >= 4 else { return nil }
        let next = ScreenSaverScene.Cursor(index: index, wallColumn: leftColumn)
        return ScreenSaverScene(
            content: cursor.wallColumn == nil ? .wall(grid, images) : .wallColumn(images),
            duration: CoverWall.driftDuration,
            next: next
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
fileprivate struct ScreenSaverRandomGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
