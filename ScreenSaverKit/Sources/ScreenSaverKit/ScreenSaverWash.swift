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

/// Drives the flowing colour field behind the layouts that use one. The points drift on slow,
/// independent orbits; a new palette blends in over a couple of seconds.
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

    nonisolated init() {}

    /// Begins a session; the clock keeps running across later calls until `stop()`.
    func start(timeScale: Double) {
        self.timeScale = timeScale
        guard !isStarted else { return }
        isStarted = true
        origin = .now
    }

    func setFlows(_ flows: Bool) {
        self.flows = flows
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

    /// Corners stay put, border points slide along their border, and inner points orbit freely,
    /// so the field always covers the whole screen.
    func points(at time: TimeInterval) -> [SIMD2<Float>] {
        let mesh = target
        func stops(_ given: [Float]?, _ count: Int) -> [Float] {
            given ?? (0..<count).map { Float($0) / Float(max(count - 1, 1)) }
        }
        let xs = stops(mesh.columnStops, mesh.columns)
        let ys = stops(mesh.rowStops, mesh.rows)
        var points: [SIMD2<Float>] = []
        for row in 0..<mesh.rows {
            for column in 0..<mesh.columns {
                var point = SIMD2(xs[column], ys[row])
                let seed = Double(row * 7 + column * 13)
                let period = 22 + (seed.truncatingRemainder(dividingBy: 9))
                let phase = seed * 1.7
                // A still wash rests every point at its stop.
                let angle = flows ? time / period * 2 * .pi + phase : 0
                let reach: Float = flows ? 0.28 : 0
                let spanX = Self.span(xs, column)
                let spanY = Self.span(ys, row)
                if column != 0, column != mesh.columns - 1 {
                    point.x += Float(sin(angle)) * spanX * reach
                }
                if row != 0, row != mesh.rows - 1 {
                    point.y += Float(cos(angle * 0.83 + 1)) * spanY * reach
                }
                points.append(point)
            }
        }
        return points
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
