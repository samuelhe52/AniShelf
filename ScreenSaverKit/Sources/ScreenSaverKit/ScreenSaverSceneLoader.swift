//
//  ScreenSaverSceneLoader.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import CoreGraphics
import CryptoKit
import Foundation

struct ScreenSaverScene: Sendable {
    struct Cursor: Sendable {
        var index = 0
        var wallColumn: [CoverWallArtworkIdentity]?
    }

    enum Content: Sendable {
        case wall(CoverWallGrid, [CGImage])
        case wallColumn([CGImage])
        case poster(ScreenSaverManifest.Entry, CGImage, CGColor?)
        case hero(ScreenSaverManifest.Entry, backdrop: CGImage, logo: CGImage?)
        case notice(ScreenSaverRenderer.Notice)
    }

    let content: Content
    var showsTitles = false
    var duration: TimeInterval = 4
    var next = Cursor()
}

/// Files from different requests can still contain the same artwork.
enum CoverWallArtworkIdentity: Hashable, Sendable {
    case pixels(Data)
    case path(String)

    init(image: CGImage, path: String) {
        if let data = image.dataProvider?.data {
            self = .pixels(Data(SHA256.hash(data: data as Data)))
        } else {
            self = .path(path)
        }
    }
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

        let entries = manifest.entries
        let settings = manifest.settings
        if settings.layout == .coverWall, entries.count >= 4,
            let wall = loadWall(entries, cursor: cursor, size: size, scale: scale)
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
            if settings.layout == .heroStill, let path = entry.backdrop,
                let backdrop = reader.image(
                    at: path, maximumPixelSize: pixelLimit(max(size.width, size.height) * scale, 2_560))
            {
                let logo =
                    settings.showsTitles ? entry.logo.flatMap { reader.image(at: $0, maximumPixelSize: 1_024) } : nil
                content = .hero(entry, backdrop: backdrop, logo: logo)
            } else if let poster = reader.image(
                at: entry.poster, maximumPixelSize: pixelLimit(size.height * scale, 1_500))
            {
                content = .poster(entry, poster, averageColor(of: poster))
            } else {
                continue
            }
            return ScreenSaverScene(content: content, showsTitles: settings.showsTitles, duration: interval, next: next)
        }
        return ScreenSaverScene(content: .notice(.empty))
    }

    private func loadWall(
        _ entries: [ScreenSaverManifest.Entry],
        cursor: ScreenSaverScene.Cursor,
        size: CGSize,
        scale: CGFloat
    ) -> ScreenSaverScene? {
        let grid = CoverWallGrid(viewport: size)
        let columnCount = cursor.wallColumn == nil ? grid.columns : 1
        let pixelSize = pixelLimit(grid.tileSize.height * scale * 1.25, 1_500)
        var identityByPath: [String: CoverWallArtworkIdentity] = [:]
        var imagesByIdentity: [CoverWallArtworkIdentity: CGImage] = [:]
        var unreadable: Set<String> = []
        var readableEntries: Set<Int> = []

        func identity(at index: Int) -> CoverWallArtworkIdentity? {
            let path = entries[index].poster
            if let cached = identityByPath[path] {
                readableEntries.insert(index)
                return cached
            }
            guard !unreadable.contains(path) else { return nil }
            guard let image = reader.image(at: path, maximumPixelSize: pixelSize) else {
                unreadable.insert(path)
                return nil
            }
            let identity = CoverWallArtworkIdentity(image: image, path: path)
            if imagesByIdentity[identity] == nil { imagesByIdentity[identity] = image }
            identityByPath[path] = identity
            readableEntries.insert(index)
            return identity
        }

        var index = cursor.index
        var leftColumn = cursor.wallColumn ?? []
        var images: [CGImage] = []
        for _ in 0..<columnCount {
            var column: [CoverWallArtworkIdentity] = []
            for row in 0..<grid.rows {
                let horizontal = leftColumn.indices.contains(row) ? leftColumn[row] : nil
                let vertical = column.last
                var candidate: (index: Int, artwork: CoverWallArtworkIdentity)?
                for offset in entries.indices {
                    guard !Task.isCancelled else { return nil }
                    let nextIndex = (index + offset) % entries.count
                    guard let artwork = identity(at: nextIndex) else { continue }
                    if artwork != horizontal, artwork != vertical {
                        candidate = (nextIndex, artwork)
                        break
                    }
                    if candidate == nil { candidate = (nextIndex, artwork) }
                }
                guard let candidate, let image = imagesByIdentity[candidate.artwork] else { return nil }
                column.append(candidate.artwork)
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

    private func pixelLimit(_ size: CGFloat, _ limit: Int) -> Int {
        Int(ceil(min(max(size, 1), CGFloat(limit))))
    }

    private func averageColor(of image: CGImage) -> CGColor? {
        var pixel = [UInt8](repeating: 0, count: 4)
        let drewPixel = pixel.withUnsafeMutableBytes { bytes in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drewPixel else { return nil }
        // Keep the wash muted even when the original poster is very light.
        return CGColor(
            red: 0.04 + CGFloat(pixel[0]) / 255 * 0.29,
            green: 0.04 + CGFloat(pixel[1]) / 255 * 0.29,
            blue: 0.04 + CGFloat(pixel[2]) / 255 * 0.29,
            alpha: 1
        )
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
