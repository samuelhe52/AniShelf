//
//  ScreenSaverFlowField.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import Foundation

/// A smooth, ever-changing current that moves the wash's mesh points.
///
/// Points that each follow their own orbit wobble independently and repeat. Here every point is
/// displaced by the same field: the curl of a gradient noise that evolves through time (curl noise,
/// Bridson et al. 2007). Neighbouring points therefore drift together like a current, the pattern
/// never repeats, and because a curl field neither converges nor spreads, mesh cells keep roughly
/// their size instead of squeezing one colour and stretching another.
struct ScreenSaverFlowField: Sendable {
    private let permutation: [Int]

    init(seed: UInt64 = 0x5EED_F10E) {
        var random = ScreenSaverRandomGenerator(state: seed)
        let shuffled = Array(0..<256).shuffled(using: &random)
        permutation = shuffled + shuffled
    }

    /// The displacement at a point in unit coordinates, with `time` in seconds of flow. Each
    /// component stays within about -1...1.
    func displacement(x: Double, y: Double, time: Double) -> SIMD2<Double> {
        // Two octaves: broad currents that turn over every eight seconds or so, plus a quieter,
        // quicker layer of detail.
        let broad = curl(x: x * 1.1, y: y * 1.1, z: time / 8)
        let detail = curl(x: x * 2.3 + 17, y: y * 2.3 + 5, z: time / 4.5)
        let flow = broad + detail * 0.35
        // Soft limit: strong spots ease toward the edge of the range instead of clipping.
        return SIMD2(tanh(flow.x), tanh(flow.y))
    }

    /// The curl of the noise as a 2D stream function: (∂ψ/∂y, -∂ψ/∂x).
    private func curl(x: Double, y: Double, z: Double) -> SIMD2<Double> {
        let step = 0.001
        let dx = (noise(x + step, y, z) - noise(x - step, y, z)) / (2 * step)
        let dy = (noise(x, y + step, z) - noise(x, y - step, z)) / (2 * step)
        return SIMD2(dy, -dx)
    }

    /// Improved Perlin noise (Perlin 2002), about -1...1.
    private func noise(_ x: Double, _ y: Double, _ z: Double) -> Double {
        let (fx, fy, fz) = (floor(x), floor(y), floor(z))
        let (xi, yi, zi) = (Int(fx) & 255, Int(fy) & 255, Int(fz) & 255)
        let (x, y, z) = (x - fx, y - fy, z - fz)
        let (u, v, w) = (fade(x), fade(y), fade(z))
        let p = permutation
        let a = p[xi] + yi
        let aa = p[a] + zi
        let ab = p[a + 1] + zi
        let b = p[xi + 1] + yi
        let ba = p[b] + zi
        let bb = p[b + 1] + zi
        return lerp(
            w,
            lerp(
                v, lerp(u, grad(p[aa], x, y, z), grad(p[ba], x - 1, y, z)),
                lerp(u, grad(p[ab], x, y - 1, z), grad(p[bb], x - 1, y - 1, z))),
            lerp(
                v, lerp(u, grad(p[aa + 1], x, y, z - 1), grad(p[ba + 1], x - 1, y, z - 1)),
                lerp(u, grad(p[ab + 1], x, y - 1, z - 1), grad(p[bb + 1], x - 1, y - 1, z - 1))))
    }

    private func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }

    private func lerp(_ t: Double, _ a: Double, _ b: Double) -> Double { a + t * (b - a) }

    private func grad(_ hash: Int, _ x: Double, _ y: Double, _ z: Double) -> Double {
        let h = hash & 15
        let u = h < 8 ? x : y
        let v = h < 4 ? y : (h == 12 || h == 14 ? x : z)
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v)
    }
}
