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

    init(viewport: CGSize) {
        self.viewport = viewport
        rows = max(2, Int((viewport.height / 260).rounded()))
        let gapRatio: CGFloat = 0.045
        let tileHeight = viewport.height / (CGFloat(rows) + CGFloat(rows - 1) * gapRatio)
        tileSize = CGSize(width: tileHeight * 2 / 3, height: tileHeight)
        gap = tileHeight * gapRatio
        // One extra column covers the right edge throughout a full stride.
        columns = Int(ceil(viewport.width / (tileSize.width + gap))) + 1
    }

    var stride: CGFloat { tileSize.width + gap }
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
