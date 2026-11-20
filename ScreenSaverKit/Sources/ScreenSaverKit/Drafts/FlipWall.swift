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

/// One tile turning over to a new poster.
struct FlipWallFlip: Sendable {
    let tile: Int
    let image: CGImage
    /// Seconds after the step begins.
    let delay: TimeInterval
    let duration: TimeInterval
    /// True to turn about the vertical axis (left–right), false to tip over top to bottom.
    let turnsSideways: Bool
    /// 1 or -1: which edge comes toward the viewer.
    let direction: CGFloat
}

enum FlipWallStep: ScreenSaverStageStep {
    case open(FlipWallGrid, [CGImage])
    case flip([FlipWallFlip])

    @MainActor func makeStage(size: CGSize, scale: CGFloat, wash: ScreenSaverWash) -> (any ScreenSaverStage)? {
        guard case .open(let grid, let images) = self else { return nil }
        return FlipWallStage(grid: grid, images: images, size: size)
    }
}

/// Decides when, where, and how tiles flip. A wall that flips one random tile on a fixed beat
/// reads as a timer; this one varies all three:
/// - When: gaps vary around the chosen interval (a triangular spread from 0.45× to 1.55×, so
///   there are neither bursts of noise nor long dead spells), and now and then two or three tiles
///   go together.
/// - Where: each flip takes the best of a few random tiles, scored by distance from the last
///   flips (so consecutive flips spread across the wall instead of clumping) and by how long the
///   tile has shown its poster (so every tile changes in time).
/// - How: most tiles turn sideways, some tip over top to bottom, in either direction, at slightly
///   different speeds. A group is either a short wave along a row or column, all turning the same
///   way, or a few scattered tiles a beat apart.
struct FlipWallDirector: ScreenSaverStageDirector {
    private let entries: [ScreenSaverManifest.Entry]
    private let grid: FlipWallGrid
    private let pixelSize: Int
    private let delay: TimeInterval
    private var cycle: ScreenSaverEntryCycle
    private var random: ScreenSaverRandomGenerator
    /// The poster path on each tile.
    private var tiles: [String] = []
    /// The director's clock, in seconds since the wall opened.
    private var clock: TimeInterval = 0
    /// When each tile last changed, and when its current flip ends.
    private var changedAt: [TimeInterval] = []
    private var busyUntil: [TimeInterval] = []
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
        // Tiles start with staggered ages, so the first flips do not sweep the wall in order.
        changedAt = (0..<grid.count).map { _ in -Double.random(in: 0..<1, using: &random) * delay * 4 }
        busyUntil = Array(repeating: 0, count: grid.count)
        let gap = nextGap()
        clock += gap
        return (FlipWallStep.open(grid, images), gap)
    }

    private mutating func flip(image: (String) -> CGImage?) -> (step: any ScreenSaverStageStep, duration: TimeInterval)?
    {
        guard let first = pickTile(excluding: []) else {
            // Every tile is mid-flip, which only happens with a tiny grid and a short interval.
            let gap = nextGap()
            clock += gap
            return (FlipWallStep.flip([]), gap)
        }
        var group = [first]
        var stagger: TimeInterval = 0
        var turnsSideways = Double.random(in: 0..<1, using: &random) < 0.7
        var sharedDirection: CGFloat?
        if grid.count >= 8, Double.random(in: 0..<1, using: &random) < 0.18 {
            let size = Int.random(in: 2...3, using: &random)
            if Bool.random(using: &random), let run = run(from: first, length: size) {
                // A wave: neighbours in a line, turning the same way, close together.
                group = run.tiles
                turnsSideways = run.alongRow
                sharedDirection = Bool.random(using: &random) ? 1 : -1
                stagger = TimeInterval.random(in: 0.12...0.2, using: &random)
            } else {
                while group.count < size, let next = pickTile(excluding: group) { group.append(next) }
                stagger = TimeInterval.random(in: 0.3...0.8, using: &random)
            }
        }

        var flips: [FlipWallFlip] = []
        for (order, tile) in group.enumerated() {
            guard let poster = nextPoster(for: tile, image: image) else { break }
            let duration = TimeInterval.random(in: 1.15...1.45, using: &random)
            let start = TimeInterval(order) * stagger
            tiles[tile] = poster.path
            changedAt[tile] = clock + start
            busyUntil[tile] = clock + start + duration
            recentTiles.append(tile)
            flips.append(
                FlipWallFlip(
                    tile: tile, image: poster.image, delay: start, duration: duration,
                    turnsSideways: sharedDirection == nil && order > 0
                        ? Double.random(in: 0..<1, using: &random) < 0.7 : turnsSideways,
                    direction: sharedDirection ?? (Bool.random(using: &random) ? 1 : -1)))
        }
        guard !flips.isEmpty else { return nil }
        if recentTiles.count > 3 { recentTiles.removeFirst(recentTiles.count - 3) }
        // A group spends some of the time the next single flips would have had.
        let gap = nextGap() * (1 + 0.6 * Double(flips.count - 1))
        clock += gap
        return (FlipWallStep.flip(flips), gap)
    }

    /// The interval varied by a triangular spread from 0.45× to 1.55×, centred on the interval.
    private mutating func nextGap() -> TimeInterval {
        let spread = (Double.random(in: 0..<1, using: &random) + Double.random(in: 0..<1, using: &random)) / 2
        return delay * (0.45 + 1.1 * spread)
    }

    /// The best of a few random idle tiles: far from the last flips, and showing its poster longest.
    private mutating func pickTile(excluding taken: [Int]) -> Int? {
        let idle = (0..<grid.count).filter { busyUntil[$0] <= clock && !taken.contains($0) }
        guard !idle.isEmpty else { return nil }
        let recent = recentTiles + taken
        let longest = grid.count > 1 ? Double(grid.count) * delay : 1
        var best: (tile: Int, score: Double)?
        for _ in 0..<min(6, idle.count) {
            guard let tile = idle.randomElement(using: &random) else { break }
            let distance = recent.map { distanceBetween(tile, $0) }.min() ?? 3
            let age = min((clock - changedAt[tile]) / longest, 1)
            let score = min(distance, 3) + 2 * age
            if best == nil || score > best!.score { best = (tile, score) }
        }
        return best?.tile
    }

    private func distanceBetween(_ one: Int, _ other: Int) -> Double {
        let dx = Double(one / grid.rows - other / grid.rows)
        let dy = Double(one % grid.rows - other % grid.rows)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Idle tiles in a straight line from `tile`, in a random direction that fits.
    private mutating func run(from tile: Int, length: Int) -> (tiles: [Int], alongRow: Bool)? {
        let column = tile / grid.rows
        let row = tile % grid.rows
        let steps = [(1, 0), (-1, 0), (0, 1), (0, -1)].shuffled(using: &random)
        for (dx, dy) in steps {
            let line = (0..<length).map { (column + dx * $0, row + dy * $0) }
            guard line.allSatisfy({ (0..<grid.columns).contains($0.0) && (0..<grid.rows).contains($0.1) }) else {
                continue
            }
            let run = line.map { $0.0 * grid.rows + $0.1 }
            if run.dropFirst().allSatisfy({ busyUntil[$0] <= clock }) { return (run, dx != 0) }
        }
        return nil
    }

    /// Prefers a poster that is not on screen; a small library settles for one that is not a neighbour.
    private mutating func nextPoster(for tile: Int, image: (String) -> CGImage?) -> (path: String, image: CGImage)? {
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
        return fallback.map { (entries[$0.index].poster, $0.image) }
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
        guard case .flip(let flips) = step as? FlipWallStep else { return }
        for flip in flips where cards.indices.contains(flip.tile) { turn(cards[flip.tile], with: flip) }
    }

    private func turn(_ card: CALayer, with flip: FlipWallFlip) {
        let (x, y): (CGFloat, CGFloat) = flip.turnsSideways ? (0, 1) : (1, 0)
        let angle = .pi / 2 * flip.direction
        let edgeOn = CATransform3DScale(CATransform3DMakeRotation(angle, x, y, 0), 1.05, 1.05, 1)
        let otherSide = CATransform3DScale(CATransform3DMakeRotation(-angle, x, y, 0), 1.05, 1.05, 1)
        // Begin times are in the layer's own time, which the demo's speed-up scales.
        let begin = card.convertTime(CACurrentMediaTime(), from: nil) + flip.delay

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
        turn.duration = flip.duration
        let swap = CAKeyframeAnimation(keyPath: "contents")
        swap.values = [card.contents as Any, flip.image]
        swap.keyTimes = [0, 0.5, 1]
        swap.calculationMode = .discrete
        swap.duration = flip.duration
        let group = CAAnimationGroup()
        group.animations = [turn, swap]
        group.duration = flip.duration
        group.beginTime = begin
        // Until a delayed flip begins, the tile keeps showing its old poster.
        group.fillMode = .backwards
        card.contents = flip.image
        card.add(group, forKey: "flip")

        // The tile darkens as it turns away from the light.
        let dim = CAKeyframeAnimation(keyPath: "opacity")
        dim.values = [0, 0.55, 0.55, 0]
        dim.keyTimes = [0, 0.5, 0.5, 1]
        dim.duration = flip.duration
        dim.beginTime = begin
        card.sublayers?.first?.add(dim, forKey: "flip")
    }
}
