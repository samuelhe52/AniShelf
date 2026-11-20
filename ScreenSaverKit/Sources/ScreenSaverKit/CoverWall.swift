//
//  CoverWall.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import QuartzCore

struct CoverWallGrid: Equatable, Sendable {
    let viewport: CGSize
    let rows: Int
    let columns: Int
    let tileSize: CGSize
    let gap: CGFloat

    init(viewport: CGSize, rows: Int) {
        self.viewport = viewport
        self.rows = rows
        let gapRatio: CGFloat = 0.045
        let tileHeight = viewport.height / (CGFloat(rows) + CGFloat(rows - 1) * gapRatio)
        tileSize = CGSize(width: tileHeight * 2 / 3, height: tileHeight)
        gap = tileHeight * gapRatio
        // One extra column covers the right edge throughout a full stride.
        columns = Int(ceil(viewport.width / (tileSize.width + gap))) + 1
    }

    var stride: CGFloat { tileSize.width + gap }
}

/// Draws each poster once per pass, favoring artwork farther from its last nearby placement.
struct CoverWallShuffleBag: Sendable {
    private struct Poster: Sendable {
        let path: String
        var entryCount = 1
    }

    private static let historyColumns = 3
    private let rows: Int
    private let rowPitchSquared: Double
    private var random: ScreenSaverRandomGenerator
    private var posters: [Poster] = []
    // The prefix is still in the bag; the suffix has already been drawn this pass.
    private var remaining: Int
    private var entryCount: Int
    private var history: [String] = []

    init(entries: [ScreenSaverManifest.Entry], grid: CoverWallGrid, seed: UInt64) {
        rows = grid.rows
        let rowPitch = Double((grid.tileSize.height + grid.gap) / grid.stride)
        rowPitchSquared = rowPitch * rowPitch
        random = ScreenSaverRandomGenerator(state: seed)
        entryCount = entries.count
        var slots: [String: Int] = [:]
        for entry in entries {
            if let slot = slots[entry.poster] {
                posters[slot].entryCount += 1
            } else {
                slots[entry.poster] = posters.count
                posters.append(Poster(path: entry.poster))
            }
        }
        remaining = posters.count
        history.reserveCapacity((Self.historyColumns + 1) * rows)
    }

    mutating func draw(load: (String) -> CGImage?) -> CGImage? {
        let row = history.count % rows
        let above = row > 0 ? history[history.count - 1] : nil
        let left = history.count >= rows ? history[history.count - rows] : nil

        func canPlace(_ slot: Int) -> Bool {
            let path = posters[slot].path
            return path != above && path != left
        }

        func hasEligiblePoster(in slots: Range<Int>) -> Bool {
            // At most two distinct posters can be blocked by the two neighbors.
            slots.count > 2 || slots.contains(where: canPlace)
        }

        while entryCount >= 4, !Task.isCancelled {
            if remaining == 0 { remaining = posters.count }
            let pending = 0..<remaining
            let used = remaining..<posters.count
            let eligible =
                if hasEligiblePoster(in: pending) { pending }
                else if hasEligiblePoster(in: used) { used }
                else { nil as Range<Int>? }

            // Borrow from the used suffix if the bag is blocked. Only allow matching
            // neighbors when the entire scope shares too few distinct posters to avoid it.
            var slot = Int.random(in: eligible ?? pending, using: &random)
            guard eligible == nil || canPlace(slot) else { continue }
            let poster = posters[slot]
            let weight = placementWeight(for: poster.path)
            // Rejection sampling gives a weighted draw without walking the whole bag.
            guard weight == 1 || Double.random(in: 0..<1, using: &random) < weight else { continue }

            if slot < remaining {
                remaining -= 1
                posters.swapAt(slot, remaining)
                slot = remaining
            }
            guard let image = load(poster.path) else {
                entryCount -= poster.entryCount
                posters.swapAt(slot, posters.count - 1)
                posters.removeLast()
                continue
            }

            history.append(poster.path)
            if history.count == (Self.historyColumns + 1) * rows {
                history.removeFirst(rows)
            }
            return image
        }
        return nil
    }

    private func placementWeight(for path: String) -> Double {
        let column = history.count / rows
        let row = history.count % rows
        let cap = Double(Self.historyColumns * Self.historyColumns)
        var nearest = cap
        for (index, placed) in history.enumerated() where placed == path {
            let dx = Double(column - index / rows)
            let dy = Double(row - index % rows)
            nearest = min(nearest, dx * dx + dy * dy * rowPitchSquared)
        }
        let spacing = nearest / cap
        // A floor preserves randomness even when every option has appeared nearby.
        return 0.15 + 0.85 * spacing * spacing
    }
}

@MainActor
final class CoverWall {
    nonisolated static let driftDuration: TimeInterval = 12

    let layer: CALayer
    private let strip = CALayer()
    private let grid: CoverWallGrid
    private var columns: [CALayer] = []

    init(grid: CoverWallGrid, images: [CGImage]) {
        self.grid = grid
        layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: grid.viewport)
        layer.backgroundColor = CGColor(gray: 0.035, alpha: 1)
        layer.masksToBounds = true

        strip.anchorPoint = .zero
        strip.bounds = CGRect(origin: .zero, size: layer.bounds.size)
        layer.addSublayer(strip)

        for columnIndex in 0..<grid.columns {
            let column = CALayer()
            let start = columnIndex * grid.rows
            for (row, image) in images[start..<(start + grid.rows)].enumerated() {
                let tile = CALayer()
                tile.frame = CGRect(
                    origin: CGPoint(x: 0, y: CGFloat(row) * (grid.tileSize.height + grid.gap)),
                    size: grid.tileSize
                )
                tile.cornerRadius = grid.gap / 3
                tile.masksToBounds = true
                tile.contentsGravity = .resizeAspectFill
                tile.contents = image
                column.addSublayer(tile)
            }
            strip.addSublayer(column)
            columns.append(column)
        }
        positionColumns()
        drift()
    }

    func advance(with images: [CGImage]) {
        let recycled = columns.removeFirst()
        for (tile, image) in zip(recycled.sublayers ?? [], images) {
            tile.contents = image
        }
        columns.append(recycled)
        positionColumns()
        drift()
    }

    private func positionColumns() {
        for (index, column) in columns.enumerated() {
            column.frame = CGRect(
                x: CGFloat(index) * grid.stride,
                y: 0,
                width: grid.tileSize.width,
                height: grid.viewport.height
            )
        }
    }

    private func drift() {
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = 0
        animation.toValue = -grid.stride
        animation.duration = Self.driftDuration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        strip.position.x = -grid.stride
        strip.add(animation, forKey: "drift")
    }
}
