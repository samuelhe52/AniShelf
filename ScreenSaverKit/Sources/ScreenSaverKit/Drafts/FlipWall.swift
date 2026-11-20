//
//  FlipWall.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import QuartzCore

/// A still grid that fills the screen edge to edge; outer columns may be cut by the border.
struct FlipWallGrid: Equatable, Sendable {
    let rows: Int
    let columns: Int
    let tileSize: CGSize
    let stride: CGSize
    let origin: CGPoint

    init(viewport: CGSize, rows: Int) {
        let wall = CoverWallGrid(viewport: viewport, rows: rows)
        self.rows = rows
        tileSize = wall.tileSize
        stride = CGSize(width: wall.stride, height: wall.tileSize.height + wall.gap)
        columns = max(1, Int(ceil((viewport.width + wall.gap) / wall.stride)))
        let width = CGFloat(columns) * wall.stride - wall.gap
        origin = CGPoint(x: (viewport.width - width) / 2, y: 0)
    }

    var count: Int { rows * columns }

    func frame(of tile: Int) -> CGRect {
        CGRect(
            x: origin.x + CGFloat(tile / rows) * stride.width, y: origin.y + CGFloat(tile % rows) * stride.height,
            width: tileSize.width, height: tileSize.height)
    }

    func neighbors(of tile: Int) -> [Int] {
        let column = tile / rows
        let row = tile % rows
        return [(column - 1, row), (column + 1, row), (column, row - 1), (column, row + 1)]
            .filter { (0..<columns).contains($0.0) && (0..<rows).contains($0.1) }
            .map { $0.0 * rows + $0.1 }
    }
}

enum FlipWallStep: ScreenSaverStageStep {
    case open(FlipWallGrid, [CGImage])
    case flip(tile: Int, image: CGImage)

    @MainActor func makeStage(size: CGSize, scale: CGFloat, wash: ScreenSaverWash) -> (any ScreenSaverStage)? {
        guard case .open(let grid, let images) = self else { return nil }
        return FlipWallStage(grid: grid, images: images, size: size)
    }
}

struct FlipWallDirector: ScreenSaverStageDirector {
    private let entries: [ScreenSaverManifest.Entry]
    private let grid: FlipWallGrid
    private let pixelSize: Int
    private let delay: TimeInterval
    private var cycle: ScreenSaverEntryCycle
    private var random: ScreenSaverRandomGenerator
    /// The poster path on each tile.
    private var tiles: [String] = []
    private var recentTiles: [Int] = []

    init(_ context: ScreenSaverDraftContext) {
        entries = context.entries
        grid = FlipWallGrid(viewport: context.size, rows: context.settings.coverWallRows)
        pixelSize = ScreenSaverSceneLoader.pixelLimit(grid.tileSize.height * context.scale * 1.1, 1_500)
        delay = ScreenSaverDraft.flipDelayRange.clamp(context.draft.flipDelay)
        cycle = ScreenSaverEntryCycle(
            count: context.entries.count, spacing: min(grid.count, context.entries.count - 1), seed: context.seed)
        random = ScreenSaverRandomGenerator(state: context.seed ^ 0x5F1D)
    }

    mutating func next(image: ScreenSaverImageLoader) -> (step: any ScreenSaverStageStep, duration: TimeInterval)? {
        let size = pixelSize
        return tiles.isEmpty ? open(image: { image($0, size) }) : flip(image: { image($0, size) })
    }

    private mutating func open(image: (String) -> CGImage?) -> (step: any ScreenSaverStageStep, duration: TimeInterval)?
    {
        var loaded: [String: CGImage] = [:]
        var images: [CGImage] = []
        for tile in 0..<grid.count {
            let blocked = Set(grid.neighbors(of: tile).filter { $0 < tile }.map { tiles[$0] })
            // A small library cannot always avoid a matching neighbour; a few tries are enough.
            var choice: (path: String, image: CGImage)?
            for _ in 0..<3 {
                guard
                    let drawn = cycle.nextLoaded(
                        entries, load: { entry in loaded[entry.poster] ?? image(entry.poster) })
                else { return nil }
                let path = entries[drawn.index].poster
                loaded[path] = drawn.image
                choice = (path, drawn.image)
                if !blocked.contains(path) { break }
            }
            guard let choice else { return nil }
            tiles.append(choice.path)
            images.append(choice.image)
        }
        return (FlipWallStep.open(grid, images), delay)
    }

    private mutating func flip(image: (String) -> CGImage?) -> (step: any ScreenSaverStageStep, duration: TimeInterval)?
    {
        // Never the same tile twice in a row, and not one of the last few either.
        let held = Set(recentTiles)
        let candidates = (0..<grid.count).filter { !held.contains($0) }
        guard let tile = candidates.randomElement(using: &random) else { return nil }
        recentTiles.append(tile)
        if recentTiles.count > min(4, grid.count - 1) { recentTiles.removeFirst() }

        // Prefer a poster that is not on screen; a small library settles for one that is not a neighbour.
        let onScreen = Set(tiles)
        let nearby = Set(grid.neighbors(of: tile).map { tiles[$0] } + [tiles[tile]])
        var fallback: (index: Int, image: CGImage)?
        for _ in 0..<max(entries.count, 1) {
            guard let drawn = cycle.nextLoaded(entries, load: { image($0.poster) }) else { break }
            let path = entries[drawn.index].poster
            if !onScreen.contains(path) {
                fallback = drawn
                break
            }
            if fallback == nil, !nearby.contains(path) { fallback = drawn }
        }
        guard let fallback else { return nil }
        tiles[tile] = entries[fallback.index].poster
        return (FlipWallStep.flip(tile: tile, image: fallback.image), delay)
    }
}

@MainActor
final class FlipWallStage: ScreenSaverStage {
    let layer = CALayer()
    private var cards: [CALayer] = []

    init(grid: FlipWallGrid, images: [CGImage], size: CGSize) {
        layer.frame = CGRect(origin: .zero, size: size)
        layer.backgroundColor = CGColor(gray: 0.035, alpha: 1)
        layer.masksToBounds = true

        let radius = grid.tileSize.width * 0.03
        for (tile, image) in images.enumerated() {
            // Each tile has its own perspective, so a flip looks the same anywhere on the wall.
            let holder = CALayer()
            holder.frame = grid.frame(of: tile)
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / (grid.tileSize.height * 3.2)
            holder.sublayerTransform = perspective

            let card = CALayer()
            card.frame = holder.bounds
            card.contents = image
            card.contentsGravity = .resizeAspectFill
            card.cornerRadius = radius
            card.masksToBounds = true
            let shade = CALayer()
            shade.frame = card.bounds
            shade.backgroundColor = CGColor(gray: 0, alpha: 1)
            shade.opacity = 0
            card.addSublayer(shade)

            holder.addSublayer(card)
            layer.addSublayer(holder)
            cards.append(card)
        }
    }

    func apply(_ step: any ScreenSaverStageStep) {
        guard case .flip(let tile, let image) = step as? FlipWallStep, cards.indices.contains(tile) else { return }
        let card = cards[tile]
        let duration: TimeInterval = 1.3
        let edgeOn = CATransform3DScale(CATransform3DMakeRotation(.pi / 2, 0, 1, 0), 1.05, 1.05, 1)
        let otherSide = CATransform3DScale(CATransform3DMakeRotation(-.pi / 2, 0, 1, 0), 1.05, 1.05, 1)

        // Turn edge-on, swap the poster while it is invisible, and turn back.
        let turn = CAKeyframeAnimation(keyPath: "transform")
        turn.values = [CATransform3DIdentity, edgeOn, otherSide, CATransform3DIdentity].map {
            NSValue(caTransform3D: $0)
        }
        turn.keyTimes = [0, 0.5, 0.5, 1]
        turn.timingFunctions = [
            CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeOut)
        ]
        turn.duration = duration
        let swap = CAKeyframeAnimation(keyPath: "contents")
        swap.values = [card.contents as Any, image]
        swap.keyTimes = [0, 0.5, 1]
        swap.calculationMode = .discrete
        swap.duration = duration
        let group = CAAnimationGroup()
        group.animations = [turn, swap]
        group.duration = duration
        card.contents = image
        card.add(group, forKey: "flip")

        // The tile darkens as it turns away from the light.
        let dim = CAKeyframeAnimation(keyPath: "opacity")
        dim.values = [0, 0.55, 0.55, 0]
        dim.keyTimes = [0, 0.5, 0.5, 1]
        dim.duration = duration
        card.sublayers?.first?.add(dim, forKey: "flip")
    }
}
