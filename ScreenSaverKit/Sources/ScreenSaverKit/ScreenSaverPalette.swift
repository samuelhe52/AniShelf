//
//  ScreenSaverPalette.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import CoreGraphics
import Foundation

/// A colour in Oklab, where straight-line distance follows perceived difference.
struct ScreenSaverOklab: Sendable {
    var l: Float
    var a: Float
    var b: Float

    var chroma: Float { (a * a + b * b).squareRoot() }

    init(l: Float, a: Float, b: Float) {
        self.l = l
        self.a = a
        self.b = b
    }

    init(_ color: ScreenSaverColor) {
        func linear(_ value: CGFloat) -> Float {
            let value = Float(value)
            return value <= 0.04045 ? value / 12.92 : powf((value + 0.055) / 1.055, 2.4)
        }
        self.init(linearRed: linear(color.red), green: linear(color.green), blue: linear(color.blue))
    }

    init(linearRed r: Float, green g: Float, blue b: Float) {
        let long = cbrtf(0.412_221_5 * r + 0.536_332_5 * g + 0.051_445_99 * b)
        let medium = cbrtf(0.211_903_5 * r + 0.680_699_5 * g + 0.107_396_96 * b)
        let short = cbrtf(0.088_302_46 * r + 0.281_718_8 * g + 0.629_978_7 * b)
        l = 0.210_454_26 * long + 0.793_617_8 * medium - 0.004_072_047 * short
        a = 1.977_998_5 * long - 2.428_592_2 * medium + 0.450_593_7 * short
        self.b = 0.025_904_037 * long + 0.782_771_77 * medium - 0.808_675_77 * short
    }

    func squaredDistance(to other: ScreenSaverOklab) -> Float {
        let (dl, da, db) = (l - other.l, a - other.a, b - other.b)
        return dl * dl + da * da + db * db
    }

    var srgb: ScreenSaverColor {
        let long = l + 0.396_337_78 * a + 0.215_803_76 * b
        let medium = l - 0.105_561_346 * a - 0.063_854_17 * b
        let short = l - 0.089_484_18 * a - 1.291_485_5 * b
        let (lc, mc, sc) = (long * long * long, medium * medium * medium, short * short * short)
        func encoded(_ value: Float) -> CGFloat {
            let value = min(max(value, 0), 1)
            return CGFloat(value <= 0.003_130_8 ? value * 12.92 : 1.055 * powf(value, 1 / 2.4) - 0.055)
        }
        return ScreenSaverColor(
            red: encoded(4.076_741_7 * lc - 3.307_711_6 * mc + 0.230_969_94 * sc),
            green: encoded(-1.268_438 * lc + 2.609_757_4 * mc - 0.341_319_38 * sc),
            blue: encoded(-0.004_196_086_3 * lc - 0.703_418_6 * mc + 1.707_614_7 * sc))
    }
}

/// Picks the colours a poster is made of, rather than averages of them.
///
/// Averaging a region mixes its colours toward grey: a red coat against a blue sky averages to a
/// dull purple that appears nowhere in the poster. Instead the poster's pixels are clustered in
/// Oklab (k-means, seeded by farthest-point so small vivid areas get a cluster of their own), and
/// each region takes the cluster that best represents it: the one covering most of it, with vivid
/// clusters favoured over neutral ones, since the eye reads a poster by its colours more than by its
/// greys. Each cluster's colour is the mean of similar pixels only, so it keeps its saturation.
enum ScreenSaverPalette {
    /// Clusters per region set; enough to separate a poster's main colours without splitting one
    /// colour into shades.
    private static let clusterCount = 10
    /// Pixels per side of each region in the downsampled image.
    private static let cell = 16

    /// One representative colour for each cell of a grid laid over `region` of the poster (unit
    /// coordinates, top-left origin), row by row from the top; nil when the poster cannot be read.
    static func regionalColors(
        of poster: CGImage, columns: Int, rows: Int, region: CGRect
    ) -> [ScreenSaverColor]? {
        let width = columns * cell
        let height = rows * cell
        guard let pixels = pixels(of: poster, width: width, height: height, region: region) else { return nil }
        let (centers, labels) = cluster(pixels, count: clusterCount)

        // How much of each cell each cluster covers.
        var coverage = [[Int]](repeating: [Int](repeating: 0, count: centers.count), count: columns * rows)
        for y in 0..<height {
            for x in 0..<width {
                coverage[(y / cell) * columns + x / cell][labels[y * width + x]] += 1
            }
        }
        // A fully saturated cluster counts up to four times a grey one of the same size, so a vivid
        // area wins a cell once it covers about a quarter of it.
        let vividness = centers.map { 0.5 + min($0.chroma / 0.1, 1.5) }
        // Each reuse of a cluster makes it slightly less likely to win another cell, so a poster with
        // several colours spreads them across the wash instead of repeating its largest.
        var uses = [Int](repeating: 0, count: centers.count)
        return coverage.map { counts in
            var best = 0
            var bestScore: Float = -1
            for index in centers.indices where counts[index] > 0 {
                let score = Float(counts[index]) * vividness[index] * powf(0.85, Float(uses[index]))
                if score > bestScore {
                    best = index
                    bestScore = score
                }
            }
            uses[best] += 1
            return centers[best].srgb
        }
    }

    /// The poster's pixels in Oklab, drawn at `width` × `height`, row by row from the top.
    private static func pixels(of poster: CGImage, width: Int, height: Int, region: CGRect) -> [ScreenSaverOklab]? {
        let crop = CGRect(
            x: region.minX * CGFloat(poster.width), y: region.minY * CGFloat(poster.height),
            width: region.width * CGFloat(poster.width), height: region.height * CGFloat(poster.height)
        ).integral
        guard let source = poster.cropping(to: crop), let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // Only 256 values per channel, so convert each once.
        let table = (0..<256).map { value in
            let value = Float(value) / 255
            return value <= 0.04045 ? value / 12.92 : powf((value + 0.055) / 1.055, 2.4)
        }
        return stride(from: 0, to: bytes.count, by: 4).map { offset in
            ScreenSaverOklab(
                linearRed: table[Int(bytes[offset])], green: table[Int(bytes[offset + 1])],
                blue: table[Int(bytes[offset + 2])])
        }
    }

    /// K-means in Oklab.
    ///
    /// The first centre is the darkest-to-lightest median pixel; each further one
    /// is the pixel farthest from every centre so far, which gives a small but distinct area, such
    /// as a red title, a centre of its own. Deterministic, so a poster always gets the same palette.
    private static func cluster(
        _ points: [ScreenSaverOklab], count: Int, iterations: Int = 8
    ) -> (centers: [ScreenSaverOklab], labels: [Int]) {
        guard !points.isEmpty else { return ([], []) }
        var centers = [points.sorted { $0.l < $1.l }[points.count / 2]]
        var nearest = points.map { $0.squaredDistance(to: centers[0]) }
        while centers.count < min(count, points.count) {
            guard let far = nearest.indices.max(by: { nearest[$0] < nearest[$1] }), nearest[far] > 0.000_4 else {
                break
            }
            centers.append(points[far])
            for index in points.indices {
                nearest[index] = min(nearest[index], points[index].squaredDistance(to: points[far]))
            }
        }

        var labels = [Int](repeating: 0, count: points.count)
        for _ in 0..<iterations {
            var changed = false
            for (index, point) in points.enumerated() {
                var best = 0
                var bestDistance = Float.infinity
                for (center, candidate) in centers.enumerated() {
                    let distance = point.squaredDistance(to: candidate)
                    if distance < bestDistance {
                        best = center
                        bestDistance = distance
                    }
                }
                if labels[index] != best {
                    labels[index] = best
                    changed = true
                }
            }
            var sums = [(Float, Float, Float, Int)](repeating: (0, 0, 0, 0), count: centers.count)
            for (index, point) in points.enumerated() {
                let label = labels[index]
                sums[label] = (
                    sums[label].0 + point.l, sums[label].1 + point.a, sums[label].2 + point.b, sums[label].3 + 1
                )
            }
            for (index, sum) in sums.enumerated() where sum.3 > 0 {
                let total = Float(sum.3)
                centers[index] = ScreenSaverOklab(l: sum.0 / total, a: sum.1 / total, b: sum.2 / total)
            }
            if !changed { break }
        }
        return (centers, labels)
    }
}
