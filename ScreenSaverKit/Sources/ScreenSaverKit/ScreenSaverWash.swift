//
//  ScreenSaverWash.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import AppKit
import Observation
import SwiftUI

/// The colours of a wash: a grid of colour points that SwiftUI's `MeshGradient` blends on the GPU.
struct ScreenSaverMesh: Equatable, Sendable {
    let columns: Int
    let rows: Int
    /// Row by row, top row first.
    let colors: [ScreenSaverColor]
    /// Resting position of each column, 0 at the left edge; evenly spaced when nil.
    var columnStops: [Float]?
    /// Resting position of each row, 0 at the top edge; evenly spaced when nil.
    var rowStops: [Float]?

    static let ink = ScreenSaverMesh(
        columns: 2, rows: 2, colors: Array(repeating: ScreenSaverColor(red: 0.025, green: 0.025, blue: 0.025), count: 4)
    )
}

/// Drives the flowing colour field behind the layouts that use one. The points drift on a
/// shared current; a new palette blends in over a couple of seconds.
@MainActor
@Observable
public final class ScreenSaverWash {
    private(set) var target = ScreenSaverMesh.ink
    private var previous = ScreenSaverMesh.ink
    private var transitionStart: TimeInterval = -.infinity
    private var transitionLength: TimeInterval = 1
    /// Ticks only while a scene drawn over the wash is on screen.
    private(set) var isRunning = false
    private var isStarted = false
    private var origin = Date.now
    private var timeScale: Double = 1
    private var flows = true
    private var speed: Double = 1
    /// The flow clock, which runs at `speed` times the wash's own clock, read at `flowRebase`.
    /// Rebasing on a speed change keeps every point where it is instead of jumping along its path.
    private var flowBase: TimeInterval = 0
    private var flowRebase: TimeInterval = 0

    nonisolated init() {}

    /// Begins a session; the clock keeps running across later calls until `stop()`.
    func start(timeScale: Double) {
        self.timeScale = timeScale
        guard !isStarted else { return }
        isStarted = true
        origin = .now
        flowBase = 0
        flowRebase = 0
    }

    func setFlow(_ flows: Bool, speed: Double) {
        guard flows != self.flows || speed != self.speed else { return }
        let now = time(at: .now)
        flowBase = flowTime(at: now)
        flowRebase = now
        self.flows = flows
        self.speed = speed
    }

    private func flowTime(at time: TimeInterval) -> TimeInterval {
        flowBase + (time - flowRebase) * speed
    }

    /// Scenes with a ground of their own cover the wash; it pauses under them.
    func setActive(_ active: Bool) {
        isRunning = isStarted && active
    }

    func stop() {
        isStarted = false
        isRunning = false
        previous = .ink
        target = .ink
        transitionStart = -.infinity
    }

    func show(_ mesh: ScreenSaverMesh, over length: TimeInterval = 2.4) {
        guard mesh != target else { return }
        let now = time(at: .now)
        // A grid of another shape cannot blend point by point; it replaces the old one at once.
        previous =
            mesh.columns == target.columns && mesh.rows == target.rows
            ? blended(at: now) : mesh
        target = mesh
        transitionStart = now
        transitionLength = length
    }

    func time(at date: Date) -> TimeInterval {
        date.timeIntervalSince(origin) * timeScale
    }

    func colors(at time: TimeInterval) -> [Color] {
        blended(at: time).colors.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue) }
    }

    private func blended(at time: TimeInterval) -> ScreenSaverMesh {
        let raw = min(max((time - transitionStart) / transitionLength, 0), 1)
        guard raw < 1, previous.colors.count == target.colors.count else { return target }
        let progress = CGFloat(raw * raw * (3 - 2 * raw))
        let colors = zip(previous.colors, target.colors).map { from, to in
            ScreenSaverColor(
                red: from.red + (to.red - from.red) * progress,
                green: from.green + (to.green - from.green) * progress,
                blue: from.blue + (to.blue - from.blue) * progress)
        }
        return ScreenSaverMesh(
            columns: target.columns, rows: target.rows, colors: colors, columnStops: target.columnStops,
            rowStops: target.rowStops)
    }

    private static let field = ScreenSaverFlowField()
    /// How far a point may travel, as a fraction of the gap to its nearest neighbour. Past 0.5 two
    /// neighbours could meet; `keepApart` stops them in the rare moments the current pushes them
    /// together that hard.
    private static let reach: Float = 0.65
    /// The closest two neighbours may come, as a fraction of their resting gap.
    private static let minimumGap: Float = 0.15

    /// Every point drifts with one shared current (see `ScreenSaverFlowField`). Corners stay put and
    /// border points slide along their border, so the field always covers the whole screen.
    func points(at time: TimeInterval) -> [SIMD2<Float>] {
        let mesh = target
        let flow = flowTime(at: time)
        func stops(_ given: [Float]?, _ count: Int) -> [Float] {
            given ?? (0..<count).map { Float($0) / Float(max(count - 1, 1)) }
        }
        let xs = stops(mesh.columnStops, mesh.columns)
        let ys = stops(mesh.rowStops, mesh.rows)
        var points: [SIMD2<Float>] = []
        for row in 0..<mesh.rows {
            for column in 0..<mesh.columns {
                var point = SIMD2(xs[column], ys[row])
                // A still wash rests every point at its stop.
                guard flows else {
                    points.append(point)
                    continue
                }
                let push = Self.field.displacement(x: Double(point.x), y: Double(point.y), time: flow)
                if column != 0, column != mesh.columns - 1 {
                    point.x += Float(push.x) * Self.span(xs, column) * Self.reach
                }
                if row != 0, row != mesh.rows - 1 {
                    point.y += Float(push.y) * Self.span(ys, row) * Self.reach
                }
                points.append(point)
            }
        }
        if flows { Self.keepApart(&points, xs: xs, ys: ys) }
        return points
    }

    /// Keeps every row's points in order along x and every column's along y, at least
    /// `minimumGap` of their resting gap apart, so the mesh never folds over itself. Edge points
    /// are left where they are; only inner points give way.
    private static func keepApart(_ points: inout [SIMD2<Float>], xs: [Float], ys: [Float]) {
        let (columns, rows) = (xs.count, ys.count)
        func separate(_ count: Int, _ stops: [Float], get: (Int) -> Float, set: (Int, Float) -> Void) {
            guard count > 2 else { return }
            for index in 1..<count - 1 {
                set(index, max(get(index), get(index - 1) + (stops[index] - stops[index - 1]) * minimumGap))
            }
            for index in (1..<count - 1).reversed() {
                set(index, min(get(index), get(index + 1) - (stops[index + 1] - stops[index]) * minimumGap))
            }
        }
        for row in 0..<rows {
            separate(
                columns, xs, get: { points[row * columns + $0].x }, set: { points[row * columns + $0].x = $1 })
        }
        for column in 0..<columns {
            separate(rows, ys, get: { points[$0 * columns + column].y }, set: { points[$0 * columns + column].y = $1 })
        }
    }

    private static func span(_ stops: [Float], _ index: Int) -> Float {
        let before = index > 0 ? stops[index] - stops[index - 1] : .infinity
        let after = index < stops.count - 1 ? stops[index + 1] - stops[index] : .infinity
        let span = min(before, after)
        return span.isFinite ? span : 0
    }
}

struct ScreenSaverWashView: View {
    let wash: ScreenSaverWash

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !wash.isRunning)) { context in
            let time = wash.time(at: context.date)
            let mesh = wash.target
            MeshGradient(
                width: mesh.columns, height: mesh.rows, points: wash.points(at: time), colors: wash.colors(at: time),
                background: Color(white: 0.025), smoothsColors: true, colorSpace: .perceptual)
        }
        .ignoresSafeArea()
    }
}

extension ScreenSaverRenderer {
    /// Fills `host` with the renderer: the wash view, and over it a view showing `layer`. Both
    /// follow the host's size.
    public func install(in host: NSView) {
        host.wantsLayer = true
        let washView = NSHostingView(rootView: ScreenSaverWashView(wash: wash))
        let content = NSView()
        content.layer = layer
        content.wantsLayer = true
        for view in [washView, content] {
            view.frame = host.bounds
            view.autoresizingMask = [.width, .height]
            host.addSubview(view)
        }
    }
}
