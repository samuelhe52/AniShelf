//
//  ScreenSaverStage.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import CoreGraphics
import QuartzCore

/// Loads a snapshot image no larger than the given pixel size.
typealias ScreenSaverImageLoader = (String, Int) -> CGImage?

/// What a stage layout does next, decided and decoded off the main actor.
///
/// Stage layouts keep one layer tree for the whole session and change it step by step, unlike
/// slides, which replace the scene. The director owns every decision (which card leaves, which tile
/// flips, which poster comes next); the stage only animates the step it is given, so what is on
/// screen never drifts from the director's model.
protocol ScreenSaverStageStep: Sendable {
    /// Builds the stage when this step opens one; nil for a step that advances an existing stage.
    /// Stages that draw no ground of their own colour the flowing `wash` behind them.
    @MainActor func makeStage(size: CGSize, scale: CGFloat, wash: ScreenSaverWash) -> (any ScreenSaverStage)?
}

@MainActor
protocol ScreenSaverStage: AnyObject {
    var layer: CALayer { get }
    /// Whether the stage is drawn over the renderer's wash rather than a ground of its own.
    var usesWash: Bool { get }
    /// Called with each later step from the same director.
    func apply(_ step: any ScreenSaverStageStep)
}

extension ScreenSaverStage {
    var usesWash: Bool { false }
}

/// Produces a stage layout's steps. A copy travels in the scene cursor, so it must be a value type.
protocol ScreenSaverStageDirector: Sendable {
    /// The next step and how long it plays before the one after; nil when no artwork loads.
    mutating func next(image: ScreenSaverImageLoader) -> (step: any ScreenSaverStageStep, duration: TimeInterval)?
}

/// Hands out entries in shuffled passes. A new pass never starts with an entry that is still
/// among the most recent `spacing` handed out, so a reshuffle does not put a poster next to itself.
struct ScreenSaverEntryCycle: Sendable {
    private var order: [Int]
    private var position = 0
    private var recent: [Int] = []
    private let spacing: Int
    private var random: ScreenSaverRandomGenerator

    init(count: Int, spacing: Int, seed: UInt64) {
        random = ScreenSaverRandomGenerator(state: seed)
        order = Array(0..<count).shuffled(using: &random)
        self.spacing = min(max(spacing, 0), max(count - 1, 0))
    }

    var isEmpty: Bool { order.isEmpty }

    mutating func next() -> Int? {
        guard !order.isEmpty else { return nil }
        if position == order.count {
            order.shuffle(using: &random)
            position = 0
            // Move recently used entries back, keeping the rest of the new order.
            let blocked = Set(recent)
            let fresh = order.filter { !blocked.contains($0) }
            let held = order.filter { blocked.contains($0) }
            order = fresh + held
        }
        let index = order[position]
        position += 1
        if spacing > 0 {
            recent.append(index)
            if recent.count > spacing { recent.removeFirst() }
        }
        return index
    }

    /// Removes an entry whose artwork failed to load, for the rest of the session.
    mutating func drop(_ index: Int) {
        guard let at = order.firstIndex(of: index) else { return }
        order.remove(at: at)
        if at < position { position -= 1 }
        recent.removeAll { $0 == index }
    }

    /// The next entry whose poster loads; failing entries are dropped.
    mutating func nextLoaded(
        _ entries: [ScreenSaverManifest.Entry], load: (ScreenSaverManifest.Entry) -> CGImage?
    ) -> (index: Int, image: CGImage)? {
        while let index = next(), !Task.isCancelled {
            if let image = load(entries[index]) { return (index, image) }
            drop(index)
        }
        return nil
    }
}

extension CALayer {
    /// Adds an explicit animation from the current presentation value and sets the model value to its end.
    func animate(
        _ keyPath: String, to value: Any, duration: TimeInterval, timing: CAMediaTimingFunctionName = .easeInEaseOut,
        delay: TimeInterval = 0
    ) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = (presentation() ?? self).value(forKeyPath: keyPath)
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        if delay > 0 {
            // Begin times are in the layer's own time, which the demo's speed-up scales.
            animation.beginTime = convertTime(CACurrentMediaTime(), from: nil) + delay
            animation.fillMode = .backwards
        }
        setValue(value, forKeyPath: keyPath)
        add(animation, forKey: keyPath)
    }
}
