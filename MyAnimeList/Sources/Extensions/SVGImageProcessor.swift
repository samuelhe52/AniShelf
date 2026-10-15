//
//  SVGImageProcessor.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/7/4.
//

import Foundation
import Kingfisher
import SwiftDraw

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct SVGImageProcessor: ImageProcessor {
    private static let defaultRasterScale: CGFloat = 3

    let targetSize: CGSize?
    let scale: CGFloat
    let identifier: String

    init(targetSize: CGSize? = nil, scale: CGFloat = Self.defaultRasterScale) {
        self.targetSize = targetSize
        self.scale = scale
        self.identifier = Self.identifier(targetSize: targetSize, scale: scale)
    }

    func process(
        item: ImageProcessItem,
        options _: KingfisherParsedOptionsInfo
    ) -> KFCrossPlatformImage? {
        switch item {
        case .data(let data):
            guard let svg = SVG(data: data) else { return nil }
            #if os(macOS)
                let pointSize = targetSize.map { Self.aspectFitSize(for: svg, in: $0) } ?? svg.size
                return Self.bitmapImage(of: svg, pointSize: pointSize, scale: scale)
            #else
                if let targetSize {
                    return svg.rasterize(size: Self.aspectFitSize(for: svg, in: targetSize), scale: scale)
                }
                return svg.rasterize(scale: scale)
            #endif
        case .image(let image):
            return image
        }
    }

    #if os(macOS)
        /// SwiftDraw's macOS `rasterize` returns a lazily drawn image whose point size is the
        /// pixel size. Draw into a bitmap instead, so the image has the requested point size
        /// and `scale` pixels per point, like the iOS raster.
        private static func bitmapImage(of svg: SVG, pointSize: CGSize, scale: CGFloat) -> NSImage? {
            let pixelsWide = max(Int((pointSize.width * scale).rounded()), 1)
            let pixelsHigh = max(Int((pointSize.height * scale).rounded()), 1)
            guard
                let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: pixelsWide,
                    pixelsHigh: pixelsHigh,
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                ),
                let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext
            else { return nil }
            // SVG coordinates grow downward; bitmap contexts grow upward.
            context.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(pixelsHigh)))
            context.draw(svg, in: CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
            bitmap.size = pointSize
            let image = NSImage(size: pointSize)
            image.addRepresentation(bitmap)
            return image
        }
    #endif

    static func identifier(
        targetSize: CGSize? = nil,
        scale: CGFloat = Self.defaultRasterScale
    ) -> String {
        let sizeComponent = targetSize.map { "fit\(sizeIdentifier($0))" } ?? "intrinsic"
        return "com.anishelf.svg.\(sizeComponent)@\(scaleIdentifier(scale))"
    }

    private static func aspectFitSize(for svg: SVG, in bounds: CGSize) -> CGSize {
        let intrinsicSize = svg.size
        guard intrinsicSize.width > 0, intrinsicSize.height > 0 else {
            return bounds
        }

        let widthScale = bounds.width / intrinsicSize.width
        let heightScale = bounds.height / intrinsicSize.height
        let fitScale = min(widthScale, heightScale)

        return CGSize(
            width: intrinsicSize.width * fitScale,
            height: intrinsicSize.height * fitScale
        )
    }

    private static func sizeIdentifier(_ size: CGSize) -> String {
        "\(dimensionIdentifier(size.width))x\(dimensionIdentifier(size.height))"
    }

    private static func dimensionIdentifier(_ value: CGFloat) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.001 {
            return String(Int(rounded))
        }
        return String(format: "%.3f", Double(value))
    }

    private static func scaleIdentifier(_ scale: CGFloat) -> String {
        let rounded = scale.rounded()
        if abs(scale - rounded) < 0.001 {
            return String(Int(rounded))
        }
        return String(format: "%.3f", Double(scale))
    }
}

enum LibraryImageProcessorFactory {
    static func processor(for url: URL, targetSize: CGSize?) -> (any ImageProcessor)? {
        if url.isSVGImageURL {
            return SVGImageProcessor(targetSize: targetSize)
        }

        guard let targetSize else { return nil }
        return DownsamplingImageProcessor(size: targetSize)
    }

    static func downloadProcessor(for url: URL, targetSize: CGSize?) -> (any ImageProcessor)? {
        guard url.isSVGImageURL else { return nil }
        return SVGImageProcessor(targetSize: targetSize)
    }
}

extension URL {
    var isSVGImageURL: Bool {
        pathExtension.caseInsensitiveCompare("svg") == .orderedSame
    }
}
