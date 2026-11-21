//
//  BackdropPlacement.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/22.
//

import Foundation

package struct BackdropPlacement {
    package enum Side: String {
        case left, right
    }

    package struct Region {
        package let frame: CGRect
        package let confidence: Float
    }

    static let minimumConfidence: Float = 0.65
    static let minimumLeftCoverage: CGFloat = 0.32
    static let maximumRightCoverage: CGFloat = 0.18
    static let minimumCoverageDifference: CGFloat = 0.22

    package let side: Side
    package let leftFrame: CGRect
    package let rightFrame: CGRect
    package let regions: [Region]
    package let leftCoverage: CGFloat
    package let rightCoverage: CGFloat

    init(
        regions: [ScreenSaverManifest.Entry.SalientRegion]?, imageSize: CGSize, screen: CGRect, leftFrame: CGRect,
        subjectAwareText: Bool = ScreenSaverManifest.Settings.defaultBackdropSubjectAwareText
    ) {
        let rightFrame = Self.mirror(leftFrame, in: screen)
        let crop = Self.aspectFill(imageSize, in: screen)
        let visible = (regions ?? []).compactMap { region -> Region? in
            let imageBounds = region.bounds.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !imageBounds.isEmpty, (0...1).contains(region.confidence) else { return nil }
            let frame = CGRect(
                x: crop.minX + imageBounds.minX * crop.width, y: crop.minY + imageBounds.minY * crop.height,
                width: imageBounds.width * crop.width, height: imageBounds.height * crop.height
            ).intersection(screen)
            return frame.isEmpty ? nil : Region(frame: frame, confidence: region.confidence)
        }
        let left =
            visible.lazy.filter { $0.confidence >= Self.minimumConfidence }
            .map { Self.coverage(of: leftFrame, by: $0.frame) }.max() ?? 0
        // Count every visible box on the right. The sum is a conservative upper bound if boxes overlap.
        let right = min(1, visible.reduce(0) { $0 + Self.coverage(of: rightFrame, by: $1.frame) })
        side =
            subjectAwareText && left >= Self.minimumLeftCoverage && right <= Self.maximumRightCoverage
                && left - right >= Self.minimumCoverageDifference ? .right : .left
        self.leftFrame = leftFrame
        self.rightFrame = rightFrame
        self.regions = visible
        leftCoverage = left
        rightCoverage = right
    }

    static func mirror(_ frame: CGRect, in screen: CGRect) -> CGRect {
        guard !frame.isNull else { return .null }
        return CGRect(
            x: screen.minX + screen.maxX - frame.maxX, y: frame.minY, width: frame.width, height: frame.height)
    }

    private static func aspectFill(_ image: CGSize, in screen: CGRect) -> CGRect {
        let scale = max(screen.width / image.width, screen.height / image.height)
        let filled = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: screen.midX - filled.width / 2, y: screen.midY - filled.height / 2,
            width: filled.width, height: filled.height)
    }

    private static func coverage(of frame: CGRect, by region: CGRect) -> CGFloat {
        let intersection = frame.intersection(region)
        guard !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height / (frame.width * frame.height)
    }
}
