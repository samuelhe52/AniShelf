//
//  DepthDrift.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import QuartzCore

/// One depth plane. Far posters are small, slow, dim, and slightly soft; near ones large, fast,
/// and soft but still recognizable; the focus plane in between is sharp.
struct DepthDriftLevel: Sendable {
    /// Poster height as a fraction of the screen's base size.
    let height: CGFloat
    /// Seconds to cross the screen from bottom to top.
    let crossing: TimeInterval
    /// Blur radius as a fraction of the poster width, prepared ahead of time.
    let blur: CGFloat
    let brightness: CGFloat
    let opacity: Float
    let weight: Double
    let capacity: Int

    static let all: [DepthDriftLevel] = [
        .init(height: 0.15, crossing: 80, blur: 0.012, brightness: 0.5, opacity: 0.85, weight: 0.34, capacity: 24),
        .init(height: 0.23, crossing: 58, blur: 0.004, brightness: 0.72, opacity: 1, weight: 0.3, capacity: 18),
        .init(height: 0.33, crossing: 42, blur: 0, brightness: 1, opacity: 1, weight: 0.22, capacity: 4),
        .init(height: 0.56, crossing: 26, blur: 0.03, brightness: 0.75, opacity: 0.9, weight: 0.14, capacity: 2)
    ]
    static let focus = 2
    static let foreground = 3
}

struct DepthDriftSpawn: Sendable {
    let image: CGImage
    /// The blur's margin on each side, as a fraction of the poster width.
    let margin: CGFloat
    let level: Int
    let slot: Int
    /// Horizontal placement within this plane's available range.
    let x: CGFloat
    /// How far along its path the poster already is; 0 starts below the screen.
    let progress: Double
    /// For a poster on the focus plane, its colour in each cell of a 3 × 3 grid; the wash
    /// slowly takes them on.
    let samples: [ScreenSaverColor]?
}

enum DepthDriftStep: ScreenSaverStageStep {
    case open([DepthDriftSpawn])
    case spawn(DepthDriftSpawn)

    @MainActor func makeStage(size: CGSize, scale: CGFloat, wash: ScreenSaverWash) -> (any ScreenSaverStage)? {
        guard case .open(let spawns) = self else { return nil }
        let stage = DepthDriftStage(size: size, wash: wash)
        for spawn in spawns { stage.add(spawn) }
        return stage
    }
}

struct DepthDriftDirector: ScreenSaverStageDirector {
    private static let lanes = 9

    private struct Cadence {
        let period: TimeInterval
        var nextStart: TimeInterval
        var nextSlot = 0
    }

    private let entries: [ScreenSaverManifest.Entry]
    private let base: CGFloat
    private let scale: CGFloat
    private var cycle: ScreenSaverEntryCycle
    private var cadences: [Cadence]
    private var random: ScreenSaverRandomGenerator
    private var recentLanes: [Int] = []
    private var opened = false

    init(_ context: ScreenSaverStageContext) {
        entries = context.entries
        base = min(context.size.height, context.size.width * 1.25)
        scale = context.scale
        let interval = 10 / context.settings.driftRate
        cadences = DepthDriftLevel.all.enumerated().map { level, style in
            // A slot is not offered again until the previous poster has crossed the screen.
            let period = max(interval / style.weight, style.crossing / Double(style.capacity))
            let phase = (Double((level + 1) % DepthDriftLevel.all.count) + 0.5) / Double(DepthDriftLevel.all.count)
            return Cadence(period: period, nextStart: period * phase)
        }
        cycle = ScreenSaverEntryCycle(
            count: context.entries.count, spacing: min(12, context.entries.count - 1), seed: context.seed)
        random = ScreenSaverRandomGenerator(state: context.seed ^ 0xD21F7)
    }

    mutating func next(image: ScreenSaverImageLoader) -> (step: any ScreenSaverStageStep, duration: TimeInterval)? {
        let levels = DepthDriftLevel.all
        if opened {
            let level = nextLevel
            let start = cadences[level].nextStart
            let slot = cadences[level].nextSlot
            guard let poster = spawn(level: level, slot: slot, progress: 0, tint: true, image: image) else {
                return nil
            }
            cadences[level].nextStart += cadences[level].period
            cadences[level].nextSlot = (slot + 1) % levels[level].capacity
            return (DepthDriftStep.spawn(poster), cadences[nextLevel].nextStart - start)
        }

        // Reconstruct the still-active starts from each plane's cadence, oldest first.
        var spawns: [DepthDriftSpawn] = []
        spawns.reserveCapacity(levels.reduce(0) { $0 + $1.capacity })
        for (level, style) in levels.enumerated() {
            let cadence = cadences[level]
            for offset in stride(from: style.capacity, through: 1, by: -1) {
                let age = Double(offset) * cadence.period - cadence.nextStart
                guard age < style.crossing else { continue }
                guard
                    let poster = spawn(
                        level: level, slot: style.capacity - offset, progress: age / style.crossing,
                        tint: offset == 1, image: image)
                else { break }
                spawns.append(poster)
            }
        }
        guard !spawns.isEmpty else { return nil }
        opened = true
        return (DepthDriftStep.open(spawns), cadences[nextLevel].nextStart)
    }

    private var nextLevel: Int {
        var first = 0
        for level in cadences.indices.dropFirst() where cadences[level].nextStart < cadences[first].nextStart {
            first = level
        }
        return first
    }

    private mutating func spawn(
        level: Int, slot: Int, progress: Double, tint: Bool, image: ScreenSaverImageLoader
    ) -> DepthDriftSpawn? {
        let style = DepthDriftLevel.all[level]
        let pixels = ScreenSaverSceneLoader.pixelLimit(
            // Blurred planes need far fewer pixels than they cover.
            base * style.height * scale * (style.blur > 0.02 ? 0.35 : 1), 1_500)
        guard let drawn = cycle.nextLoaded(entries, load: { image($0.poster, pixels) }),
            let soft = ScreenSaverArt.softened(drawn.image, blur: style.blur, brightness: style.brightness)
        else { return nil }

        let x: CGFloat
        if level == DepthDriftLevel.focus || level == DepthDriftLevel.foreground {
            x = .random(in: 0..<1, using: &random)
        } else {
            // Background lanes keep consecutive posters from bunching.
            let free = (0..<Self.lanes).filter { !recentLanes.contains($0) }
            let lane = free.randomElement(using: &random) ?? 0
            recentLanes.append(lane)
            if recentLanes.count > 3 { recentLanes.removeFirst() }
            let jitter = CGFloat.random(in: -0.35...0.35, using: &random)
            x = (CGFloat(lane) + 0.5 + jitter) / CGFloat(Self.lanes)
        }
        let samples =
            tint && level == DepthDriftLevel.focus ? ScreenSaverArt.samples(of: drawn.image, columns: 3, rows: 3) : nil
        return DepthDriftSpawn(
            image: soft.image, margin: soft.margin, level: level, slot: slot, x: x, progress: progress, samples: samples
        )
    }
}

@MainActor
final class DepthDriftStage: ScreenSaverStage {
    let usesWash = true
    let layer = CALayer()
    private let size: CGSize
    private let base: CGFloat
    private var planes: [CALayer] = []
    private var slots: [[CALayer?]]
    private let wash: ScreenSaverWash

    /// No ground: a near-black wash flows behind, tinted by the posters on the focus plane.
    init(size: CGSize, wash: ScreenSaverWash) {
        self.size = size
        self.wash = wash
        base = min(size.height, size.width * 1.25)
        slots = DepthDriftLevel.all.map { Array(repeating: nil, count: $0.capacity) }
        layer.frame = CGRect(origin: .zero, size: size)
        layer.masksToBounds = true
        for _ in DepthDriftLevel.all {
            let plane = CALayer()
            plane.frame = layer.bounds
            layer.addSublayer(plane)
            planes.append(plane)
        }
    }

    func apply(_ step: any ScreenSaverStageStep) {
        guard case .spawn(let spawn) = step as? DepthDriftStep else { return }
        add(spawn)
    }

    func add(_ spawn: DepthDriftSpawn) {
        let level = spawn.level
        let slot = spawn.slot
        let style = DepthDriftLevel.all[level]
        // Recover the poster's own shape from the padded image.
        let imageWidth = CGFloat(spawn.image.width) / (1 + 2 * spawn.margin)
        let imageHeight = CGFloat(spawn.image.height) - 2 * spawn.margin * imageWidth
        let height = base * style.height
        let width = height * imageWidth / max(imageHeight, 1)
        let pad = width * spawn.margin
        let (x, bounds) = placement(spawn, paddedSize: CGSize(width: width + pad * 2, height: height + pad * 2))
        let poster = CALayer()
        poster.bounds = CGRect(origin: .zero, size: bounds)
        poster.contents = spawn.image
        poster.opacity = style.opacity
        if level == DepthDriftLevel.focus {
            poster.shadowColor = CGColor(gray: 0, alpha: 1)
            poster.shadowOpacity = 0.5
            poster.shadowRadius = bounds.height * 0.05
            poster.shadowOffset = CGSize(width: 0, height: -bounds.height * 0.02)
        }

        let travel = size.height + poster.bounds.height
        let start = -poster.bounds.height / 2
        let from = start + travel * spawn.progress
        let to = start + travel
        poster.position = CGPoint(x: x, y: to)
        // Core Animation can deliver the old completion after the next start. Replace only this slot.
        slots[level][slot]?.removeFromSuperlayer()
        slots[level][slot] = poster
        planes[level].addSublayer(poster)

        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = from
        rise.toValue = to
        rise.duration = style.crossing * (1 - spawn.progress)
        rise.timingFunction = CAMediaTimingFunction(name: .linear)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak poster] in
            guard let poster else { return }
            poster.removeFromSuperlayer()
            if let self, self.slots[level][slot] === poster {
                self.slots[level][slot] = nil
            }
        }
        poster.add(rise, forKey: "rise")
        CATransaction.commit()
        if let samples = spawn.samples {
            wash.show(.shaded(samples, columns: 3, rows: 3, brightness: 0.16), over: 8)
        }
    }

    private func placement(_ spawn: DepthDriftSpawn, paddedSize: CGSize) -> (x: CGFloat, bounds: CGSize) {
        let focusWidth = size.width * 0.5
        if spawn.level == DepthDriftLevel.focus {
            let bounds = paddedSize.fitting(width: focusWidth)
            let x = (size.width - focusWidth + bounds.width) / 2 + (focusWidth - bounds.width) * spawn.x
            return (x, bounds)
        }
        if spawn.level == DepthDriftLevel.foreground {
            // Keep the padded inner edge outside the focus band. Tuck wide posters past the outer
            // edge, but scale them on narrow screens so most of the artwork stays visible.
            let bounds = paddedSize.fitting(width: size.width * 0.36)
            let inset = size.width * (0.19 + 0.05 * spawn.x)
            let innerEdge = min(size.width * 0.24, max(inset, bounds.width * 0.75))
            let center = innerEdge - bounds.width / 2
            return (spawn.slot.isMultiple(of: 2) ? center : size.width - center, bounds)
        }
        return (size.width * spawn.x, paddedSize)
    }
}

extension CGSize {
    fileprivate func fitting(width limit: CGFloat) -> CGSize {
        guard width > limit else { return self }
        return CGSize(width: limit, height: height * limit / width)
    }
}
