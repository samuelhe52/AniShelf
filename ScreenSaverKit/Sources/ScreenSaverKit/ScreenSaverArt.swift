//
//  ScreenSaverArt.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import CoreGraphics
import CoreImage

/// An sRGB colour that can travel between actors.
struct ScreenSaverColor: Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    static let paper = ScreenSaverColor(red: 0.9, green: 0.88, blue: 0.84)

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    /// Saturation scaled and brightness capped then scaled, for a wash behind light text.
    func graded(saturation factor: CGFloat = 1.1, brightness: CGFloat) -> ScreenSaverColor {
        let (hue, saturation, value) = ScreenSaverArt.hsv(red, green, blue)
        return ScreenSaverArt.color(
            hue: hue, saturation: min(saturation * factor, 0.85), value: min(value, 0.9) * brightness)
    }

    /// The colour mixed toward black, for grounds behind text.
    func shaded(_ amount: CGFloat) -> ScreenSaverColor {
        ScreenSaverColor(red: red * amount, green: green * amount, blue: blue * amount)
    }
}

/// Image processing shared by the layouts.
///
/// Everything here runs off the main actor.
enum ScreenSaverArt {
    // CIContext is thread-safe; one shared context avoids rebuilding its caches for every slide.
    static let context = CIContext(options: [.cacheIntermediates: false])
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The poster blurred with soft, transparent edges, for out-of-focus layers.
    ///
    /// - Parameters:
    ///   - poster: the poster to soften.
    ///   - blur: the blur radius as a fraction of the image width.
    ///   - brightness: the multiplier applied to each colour channel.
    /// - Returns: the image and its margin on each side, as a fraction of the poster width.
    static func softened(_ poster: CGImage, blur: CGFloat, brightness: CGFloat) -> (image: CGImage, margin: CGFloat)? {
        let input = CIImage(cgImage: poster)
        let dimmed = input.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: brightness, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: brightness, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: brightness, w: 0)
            ])
        guard blur > 0 else {
            return context.createCGImage(dimmed, from: input.extent).map { ($0, 0) }
        }
        let sigma = blur * input.extent.width
        let margin = ceil(sigma * 2.5)
        let extent = input.extent.insetBy(dx: -margin, dy: -margin)
        let output = dimmed.applyingGaussianBlur(sigma: sigma).cropped(to: extent)
        return context.createCGImage(output, from: extent).map { ($0, margin / input.extent.width) }
    }

    /// The poster's most prominent saturated colour, lifted to read on a dark ground.
    ///
    /// A greyscale
    /// poster gets a warm paper white.
    static func accent(of poster: CGImage) -> ScreenSaverColor {
        let width = 24
        let height = 36
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: sRGB,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(poster, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return .paper }

        // Hue buckets weighted by saturation and brightness; the heaviest bucket wins.
        let buckets = 18
        var weights = [CGFloat](repeating: 0, count: buckets)
        var sums = [(CGFloat, CGFloat, CGFloat)](repeating: (0, 0, 0), count: buckets)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = CGFloat(pixels[offset]) / 255
            let green = CGFloat(pixels[offset + 1]) / 255
            let blue = CGFloat(pixels[offset + 2]) / 255
            let (hue, saturation, value) = hsv(red, green, blue)
            guard saturation > 0.28, value > 0.25 else { continue }
            let bucket = min(Int(hue * CGFloat(buckets)), buckets - 1)
            let weight = saturation * value * saturation
            weights[bucket] += weight
            sums[bucket].0 += red * weight
            sums[bucket].1 += green * weight
            sums[bucket].2 += blue * weight
        }
        guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }),
            weights[best] > CGFloat(width * height) * 0.01
        else { return .paper }
        let mean = (sums[best].0 / weights[best], sums[best].1 / weights[best], sums[best].2 / weights[best])
        let (hue, saturation, _) = hsv(mean.0, mean.1, mean.2)
        return color(hue: hue, saturation: min(max(saturation, 0.35), 0.72), value: 0.95)
    }

    /// Where Cover Fusion puts the poster: full height on the left of a landscape screen, the top of
    /// a portrait one.
    ///
    /// Works in any unit.
    static func fusionPosterFrame(in canvas: CGSize, ratio: CGFloat) -> CGRect {
        if canvas.height > canvas.width {
            let height = min(canvas.width / ratio, canvas.height * 0.6)
            let width = min(canvas.width, height * ratio)
            return CGRect(x: (canvas.width - width) / 2, y: canvas.height - height, width: width, height: height)
        }
        let width = min(canvas.height * ratio, canvas.width * 0.5)
        return CGRect(x: 0, y: 0, width: width, height: canvas.height)
    }

    /// Cover Fusion's poster: sharp at first, then through a medium blur into transparency.
    ///
    /// Baked
    /// into one screen-sized image so the feather costs nothing to animate.
    static func fusion(poster: CGImage, canvas: CGSize) -> CGImage? {
        guard canvas.width >= 1, canvas.height >= 1 else { return nil }
        let bounds = CGRect(origin: .zero, size: canvas)
        let ratio = CGFloat(poster.width) / CGFloat(max(poster.height, 1))
        let frame = fusionPosterFrame(in: canvas, ratio: ratio)
        let unit = min(canvas.width, canvas.height)

        // The poster fills its frame; a capped frame crops it a little rather than leaving gaps.
        let source = CIImage(cgImage: poster)
        let fill = max(frame.width / source.extent.width, frame.height / source.extent.height)
        let scaled = source.transformed(by: CGAffineTransform(scaleX: fill, y: fill))
        let placed = scaled.transformed(
            by: CGAffineTransform(
                translationX: frame.midX - scaled.extent.midX, y: frame.midY - scaled.extent.midY)
        ).cropped(to: frame)

        let medium = placed.clampedToExtent().applyingGaussianBlur(sigma: unit * 0.008).cropped(to: frame)

        // Feather every edge that faces the screen, not the edges on the screen's border.
        let portrait = canvas.height > canvas.width
        var sharpMask: CIImage?
        var posterMask: CIImage?
        func feather(_ edge: CGRectEdge, depth: CGFloat) {
            // As in PR #28: fully sharp for most of the poster, the medium blur only in the last
            // strip, and the fade into the wash at the very edge.
            let (sharpStart, sharpEnd, posterStart, posterEnd) = (0.8, 0.98, 0.86, 1.0)
            func ramp(_ start: CGFloat, _ end: CGFloat) -> CIImage {
                let from: CGPoint
                let to: CGPoint
                switch edge {
                case .maxXEdge:
                    from = CGPoint(x: frame.maxX - depth * (1 - start), y: 0)
                    to = CGPoint(x: frame.maxX - depth * (1 - end), y: 0)
                case .minXEdge:
                    from = CGPoint(x: frame.minX + depth * (1 - start), y: 0)
                    to = CGPoint(x: frame.minX + depth * (1 - end), y: 0)
                case .minYEdge:
                    from = CGPoint(x: 0, y: frame.minY + depth * (1 - start))
                    to = CGPoint(x: 0, y: frame.minY + depth * (1 - end))
                case .maxYEdge:
                    from = CGPoint(x: 0, y: frame.maxY - depth * (1 - start))
                    to = CGPoint(x: 0, y: frame.maxY - depth * (1 - end))
                }
                return CIFilter(
                    name: "CISmoothLinearGradient",
                    parameters: [
                        "inputPoint0": CIVector(cgPoint: from), "inputPoint1": CIVector(cgPoint: to),
                        "inputColor0": CIColor.white, "inputColor1": CIColor.black
                    ])!.outputImage!.cropped(to: bounds)
            }
            func multiply(_ mask: CIImage?, _ next: CIImage) -> CIImage {
                mask.map { next.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: $0]) }
                    ?? next
            }
            sharpMask = multiply(sharpMask, ramp(sharpStart, sharpEnd))
            posterMask = multiply(posterMask, ramp(posterStart, posterEnd))
        }
        if portrait {
            feather(.minYEdge, depth: frame.height)
            if frame.minX > 1 {
                feather(.minXEdge, depth: frame.width * 0.5)
                feather(.maxXEdge, depth: frame.width * 0.5)
            }
        } else {
            feather(.maxXEdge, depth: frame.width)
        }

        let edge = placed.applyingFilter(
            "CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: medium, kCIInputMaskImageKey: sharpMask!])
        // Beyond the poster the image is transparent: the flowing wash behind it carries on in the
        // poster's own edge colours.
        let output = edge.applyingFilter(
            "CIBlendWithMask",
            parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: posterMask!]
        ).cropped(to: bounds)
        return context.createCGImage(output, from: bounds, format: .RGBA8, colorSpace: sRGB)
    }

    /// A representative colour for each cell of a grid laid over `region` of the poster (unit
    /// coordinates, top-left origin), row by row from the top.
    ///
    /// See `ScreenSaverPalette`.
    static func samples(
        of poster: CGImage, columns: Int, rows: Int, region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) -> [ScreenSaverColor] {
        ScreenSaverPalette.regionalColors(of: poster, columns: columns, rows: rows, region: region)
            ?? Array(repeating: ScreenSaverColor(red: 0.1, green: 0.1, blue: 0.1), count: columns * rows)
    }

    static func hsv(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let delta = high - low
        guard delta > 0 else { return (0, 0, high) }
        var hue: CGFloat
        if high == red {
            hue = (green - blue) / delta
        } else if high == green {
            hue = 2 + (blue - red) / delta
        } else {
            hue = 4 + (red - green) / delta
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, delta / high, high)
    }

    static func color(hue: CGFloat, saturation: CGFloat, value: CGFloat) -> ScreenSaverColor {
        let sector = hue * 6
        let index = Int(sector) % 6
        let fraction = sector - floor(sector)
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * fraction)
        let t = value * (1 - saturation * (1 - fraction))
        let (red, green, blue): (CGFloat, CGFloat, CGFloat) =
            switch index {
            case 0: (value, t, p)
            case 1: (q, value, p)
            case 2: (p, value, t)
            case 3: (p, q, value)
            case 4: (t, p, value)
            default: (value, p, q)
            }
        return ScreenSaverColor(red: red, green: green, blue: blue)
    }
}

extension ScreenSaverMesh {
    /// Cover Fusion's wash: the poster's inner edge colours next to it, then the same hues
    /// darkening away from the poster, where the text goes.
    static func fusion(poster: CGImage, frame: CGRect, canvas: CGSize) -> ScreenSaverMesh {
        if canvas.height > canvas.width {
            let edge = ScreenSaverArt.samples(
                of: poster, columns: 3, rows: 1, region: CGRect(x: 0, y: 0.8, width: 1, height: 0.2))
            let stop = Float((canvas.height - frame.minY) / canvas.height)
            let rows = [0.9, 0.9, 0.5, 0.3].flatMap { level in edge.map { $0.graded(brightness: level) } }
            return ScreenSaverMesh(
                columns: 3, rows: 4, colors: rows, rowStops: [0, stop, stop + (1 - stop) * 0.45, 1])
        }
        let edge = ScreenSaverArt.samples(
            of: poster, columns: 1, rows: 3, region: CGRect(x: 0.8, y: 0, width: 0.2, height: 1))
        let stop = Float(frame.maxX / canvas.width)
        let levels: [CGFloat] = [0.9, 0.9, 0.5, 0.3]
        let colors = edge.flatMap { color in levels.map { color.graded(brightness: $0) } }
        return ScreenSaverMesh(
            columns: 4, rows: 3, colors: colors, columnStops: [0, stop, stop + (1 - stop) * 0.45, 1])
    }

    /// A dark wash in the poster's own regional colours.
    static func shaded(_ samples: [ScreenSaverColor], columns: Int, rows: Int, brightness: CGFloat) -> ScreenSaverMesh {
        ScreenSaverMesh(
            columns: columns, rows: rows, colors: samples.map { $0.graded(saturation: 1.2, brightness: brightness) })
    }
}
