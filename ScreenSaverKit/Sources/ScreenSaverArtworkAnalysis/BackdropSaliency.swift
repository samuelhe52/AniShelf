//
//  BackdropSaliency.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/22.
//

import Foundation
import ScreenSaverKit
import Vision

public enum BackdropSaliency {
    // Bump when the request or its input changes so old cache results are recomputed.
    public static let cacheRevision = 1
    private static let maximumPixelSize = 512

    /// Nil is a read or Vision failure. An empty array is a successful analysis with no regions.
    public static func regions(in directory: URL, backdrop path: String) -> [ScreenSaverManifest.Entry.SalientRegion]? {
        let reader = ScreenSaverSnapshotReader(directory: directory)
        guard let image = reader.image(at: path, maximumPixelSize: maximumPixelSize) else { return nil }
        return regions(in: image)
    }

    /// Analyze a small copy of the export bitmap while its pixels are already in memory.
    public static func regions(in image: CGImage) -> [ScreenSaverManifest.Entry.SalientRegion]? {
        let longest = max(image.width, image.height)
        let input: CGImage
        if longest > maximumPixelSize {
            let scale = CGFloat(maximumPixelSize) / CGFloat(longest)
            let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
            let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
            guard
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return nil }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let thumbnail = context.makeImage() else { return nil }
            input = thumbnail
        } else {
            input = image
        }
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        request.revision = VNGenerateObjectnessBasedSaliencyImageRequestRevision1
        do {
            try VNImageRequestHandler(cgImage: input).perform([request])
            return (request.results?.first?.salientObjects ?? []).map {
                .init(bounds: $0.boundingBox, confidence: $0.confidence)
            }
        } catch {
            return nil
        }
    }
}
