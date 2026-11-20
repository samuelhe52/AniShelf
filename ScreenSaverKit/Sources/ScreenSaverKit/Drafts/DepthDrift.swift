//
//  DepthDrift.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import QuartzCore

/// One depth plane. Far posters are small, slow, dim, and slightly soft; near ones large, fast,
/// and heavily blurred; the focus plane in between is sharp.
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

    static let all: [DepthDriftLevel] = [
        .init(height: 0.15, crossing: 80, blur: 0.012, brightness: 0.5, opacity: 0.85, weight: 0.34),
        .init(height: 0.23, crossing: 58, blur: 0.004, brightness: 0.72, opacity: 1, weight: 0.3),
        .init(height: 0.33, crossing: 42, blur: 0, brightness: 1, opacity: 1, weight: 0.22),
        .init(height: 0.56, crossing: 26, blur: 0.06, brightness: 0.75, opacity: 0.9, weight: 0.14)
    ]
    static let focus = 2
    static let layerCap = 48
}

struct DepthDriftSpawn: Sendable {
    let image: CGImage
    /// The blur's margin on each side, as a fraction of the poster width.
    let margin: CGFloat
    let level: Int
    /// Horizontal centre as a fraction of the screen width.
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

    private let entries: [ScreenSaverManifest.Entry]
    private let base: CGFloat
    private let scale: CGFloat
    private let interval: TimeInterval
    private var cycle: ScreenSaverEntryCycle
    private var random: ScreenSaverRandomGenerator
    private var recentLanes: [Int] = []
    private var opened = false

    init(_ context: ScreenSaverDraftContext) {
        entries = context.entries
        base = min(context.size.height, context.size.width * 1.25)
        scale = context.scale
        interval = 10 / ScreenSaverDraft.driftRateRange.clamp(context.draft.driftRate)
        cycle = ScreenSaverEntryCycle(
            count: context.entries.count, spacing: min(12, context.entries.count - 1), seed: context.seed)
        random = ScreenSaverRandomGenerator(state: context.seed ^ 0xD21F7)
    }

    mutating func next(image: ScreenSaverImageLoader) -> (step: any ScreenSaverStageStep, duration: TimeInterval)? {
        if opened {
            return spawn(progress: 0, image: image).map { (DepthDriftStep.spawn($0), interval) }
        }
        // Start with the screen already populated, as if the drift had been running.
        let levels = DepthDriftLevel.all
        let expected = levels.reduce(0) { $0 + $1.weight * $1.crossing } / interval
        let count = min(Int(expected.rounded()), DepthDriftLevel.layerCap)
        var spawns: [DepthDriftSpawn] = []
        for _ in 0..<max(count, 1) {
            guard let next = spawn(progress: Double.random(in: 0..<1, using: &random), image: image) else { break }
            spawns.append(next)
        }
        guard !spawns.isEmpty else { return nil }
        opened = true
        return (DepthDriftStep.open(spawns), interval)
    }

    private mutating func spawn(progress: Double, image: ScreenSaverImageLoader) -> DepthDriftSpawn? {
        let levels = DepthDriftLevel.all
        var pick = Double.random(in: 0..<1, using: &random)
        var level = levels.count - 1
        for (index, candidate) in levels.enumerated() {
            if pick < candidate.weight {
                level = index
                break
            }
            pick -= candidate.weight
        }
        let style = levels[level]
        let pixels = ScreenSaverSceneLoader.pixelLimit(
            // Blurred planes need far fewer pixels than they cover.
            base * style.height * scale * (style.blur > 0.02 ? 0.35 : 1), 1_500)
        guard let drawn = cycle.nextLoaded(entries, load: { image($0.poster, pixels) }),
            let soft = ScreenSaverArt.softened(drawn.image, blur: style.blur, brightness: style.brightness)
        else { return nil }

        // Lanes keep posters from bunching; the last few lanes are skipped.
        let free = (0..<Self.lanes).filter { !recentLanes.contains($0) }
        let lane = free.randomElement(using: &random) ?? 0
        recentLanes.append(lane)
        if recentLanes.count > 3 { recentLanes.removeFirst() }
        let jitter = CGFloat.random(in: -0.35...0.35, using: &random)
        let x = (CGFloat(lane) + 0.5 + jitter) / CGFloat(Self.lanes)
        let samples =
            level == DepthDriftLevel.focus ? ScreenSaverArt.samples(of: drawn.image, columns: 3, rows: 3) : nil
        return DepthDriftSpawn(
            image: soft.image, margin: soft.margin, level: level, x: x, progress: progress, samples: samples)
    }
}

@MainActor
final class DepthDriftStage: ScreenSaverStage {
    let usesWash = true
    let layer = CALayer()
    private let size: CGSize
    private let base: CGFloat
    private var planes: [CALayer] = []
    private var count = 0
    private let wash: ScreenSaverWash

    /// No ground: a near-black wash flows behind, tinted by the posters on the focus plane.
    init(size: CGSize, wash: ScreenSaverWash) {
        self.size = size
        self.wash = wash
        base = min(size.height, size.width * 1.25)
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
        if let samples = spawn.samples {
            wash.show(.shaded(samples, columns: 3, rows: 3, brightness: 0.16), over: 8)
        }
        guard count < DepthDriftLevel.layerCap else { return }
        let style = DepthDriftLevel.all[spawn.level]
        // Recover the poster's own shape from the padded image.
        let imageWidth = CGFloat(spawn.image.width) / (1 + 2 * spawn.margin)
        let imageHeight = CGFloat(spawn.image.height) - 2 * spawn.margin * imageWidth
        let height = base * style.height
        let width = height * imageWidth / max(imageHeight, 1)
        let pad = width * spawn.margin
        let poster = CALayer()
        poster.bounds = CGRect(x: 0, y: 0, width: width + pad * 2, height: height + pad * 2)
        poster.contents = spawn.image
        poster.opacity = style.opacity
        if spawn.level == DepthDriftLevel.focus {
            poster.shadowColor = CGColor(gray: 0, alpha: 1)
            poster.shadowOpacity = 0.5
            poster.shadowRadius = height * 0.05
            poster.shadowOffset = CGSize(width: 0, height: -height * 0.02)
        }

        let travel = size.height + poster.bounds.height
        let start = -poster.bounds.height / 2
        let x = spawn.x * size.width
        let from = start + travel * spawn.progress
        let to = start + travel
        poster.position = CGPoint(x: x, y: to)
        planes[spawn.level].addSublayer(poster)
        count += 1

        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = from
        rise.toValue = to
        rise.duration = style.crossing * (1 - spawn.progress)
        rise.timingFunction = CAMediaTimingFunction(name: .linear)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            poster.removeFromSuperlayer()
            self?.count -= 1
        }
        poster.add(rise, forKey: "rise")
        CATransaction.commit()
    }
}
