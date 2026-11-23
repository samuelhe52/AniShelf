//
//  CoverFusionAndEditorial.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import AppKit
import QuartzCore

extension ScreenSaverLayouts {
    // MARK: - Cover Fusion

    func coverFusion(
        _ entry: ScreenSaverManifest.Entry,
        poster: CGImage,
        posterRatio: CGFloat,
        details: Set<ScreenSaverManifest.Detail>
    ) -> CALayer {
        // No ground: the renderer's wash flows behind, in the poster's edge colours.
        let scene = CALayer()
        scene.frame = bounds
        scene.masksToBounds = true
        let image = imageLayer(poster, frame: bounds)
        image.contentsGravity = .resize
        scene.addSublayer(image)

        let frame = ScreenSaverArt.fusionPosterFrame(in: size, ratio: posterRatio)
        if size.height > size.width {
            // Text below the poster, starting where its feathered edge has faded.
            let width = size.width * 0.84
            let top = frame.minY - unit * 0.01
            let block = posterFocusBlock(entry, details: details, width: width, maxHeight: top - unit * 0.03)
            place(block, x: (size.width - width) / 2, top: top, in: scene)
        } else {
            let x = frame.maxX + unit * 0.05
            let width = min(size.width - x - unit * 0.09, unit * 0.95)
            let block = posterFocusBlock(entry, details: details, width: width, maxHeight: size.height - unit * 0.14)
            place(block, x: x, top: bounds.midY + block.height / 2, in: scene)
        }
        return scene
    }

    // MARK: - Editorial Cover

    func editorialCover(
        _ entry: ScreenSaverManifest.Entry,
        poster: CGImage,
        accent: ScreenSaverColor,
        details: Set<ScreenSaverManifest.Detail>
    ) -> CALayer {
        // No ground: the renderer's wash flows behind, in dark shades of the poster.
        let scene = CALayer()
        scene.frame = bounds
        scene.masksToBounds = true

        let portrait = size.height > size.width
        let margin = unit * 0.07
        let ratio = CGFloat(poster.width) / CGFloat(max(poster.height, 1))

        let tilt = CGAffineTransform(rotationAngle: 2.2 * .pi / 180)
        // Work in the rotated footprint, with dimensions expressed per point of poster height.
        let footprint = CGRect(x: -ratio / 2, y: -0.5, width: ratio, height: 1).applying(tilt)
        let right = size.width - margin
        let preferredHeight = size.height * (portrait ? 0.55 : 0.76)
        let columnWidth = portrait ? size.width - margin * 2 : min(size.width * 0.34, unit * 0.62)
        var column = editorialColumn(entry, accent: accent, details: details, width: columnWidth)
        let overview = details.contains(.overview) ? entry.overview.nonEmpty : nil
        let overviewGap = unit * 0.03
        let overviewBase = margin + column.height + overviewGap + unit * 0.05 + (portrait ? margin : 0)
        let preferredArt = portrait ? min(preferredHeight, columnWidth / footprint.width) * footprint.height : 0
        let artShare: CGFloat = 0.8
        let headlineTop = size.height - margin
        let clearance = unit * 0.018
        let tagline: FittedText? =
            if details.contains(.tagline) {
                fittedText(
                    entry.tagline, width: columnWidth, size: unit * 0.03, weight: .medium,
                    alpha: Self.taglineAlpha, lines: 2)
            } else {
                nil
            }
        let taglineDepth = tagline.map { $0.height + unit * 0.014 } ?? 0
        var headlineDepth = min(
            size.height * (portrait ? 0.42 : 0.58), headlineTop - margin - column.height - clearance - taglineDepth)
        if overview != nil {
            // Reserve room for roughly three overview lines before fitting the headline.
            // On tight portrait screens the art can shrink, but gets most of the shared space.
            let excerpt = unit * 0.10
            let artReserve = min(preferredArt, excerpt * artShare / (1 - artShare))
            headlineDepth = min(
                headlineDepth, max(headlineDepth / 2, headlineTop - overviewBase - excerpt - artReserve))
        }
        var headlineBottom = headlineTop
        var headlineLines: [CGRect] = []
        if let title = entry.title, !title.isEmpty,
            let fitted = editorialHeadline(
                title, width: size.width - margin * 2, maxHeight: headlineDepth, maxLines: portrait ? 5 : 4,
                accent: accent),
            let headline = textLayer(fitted)
        {
            headlineLines = inkBounds(of: fitted)
            headlineBottom -= headline.bounds.height
            headline.frame.origin = CGPoint(x: margin, y: headlineBottom)
            scene.addSublayer(headline)
        }
        if let tagline, let layer = textLayer(tagline) {
            headlineBottom -= taglineDepth
            layer.frame.origin = CGPoint(x: margin, y: headlineBottom)
            scene.addSublayer(layer)
            let offset = headlineTop - headlineBottom - tagline.height
            headlineLines.append(contentsOf: inkBounds(of: tagline).map { $0.offsetBy(dx: 0, dy: offset) })
        }

        if let overview {
            let available = headlineBottom - overviewBase
            let artReserve = min(preferredArt, max(0, available * artShare))
            if let layer = textLayer(
                overview, width: columnWidth, size: unit * 0.018, weight: .regular, alpha: 0.7,
                lines: 6, maxHeight: available - artReserve, lineSpacing: 1.3)
            {
                column.layers.append((layer, overviewGap))
                column.height += overviewGap + layer.bounds.height
            }
        }

        let hasDetails = column.layers.count > 1  // A rule alone isn't a details column.
        if hasDetails {
            place(column, x: margin, top: margin + column.height, in: scene)
        }
        let left = !portrait && hasDetails ? margin + columnWidth + margin : margin
        let bottom = portrait && hasDetails ? margin + column.height + margin : margin
        var height = min((right - left) / footprint.width, (headlineTop - bottom) / footprint.height, preferredHeight)
        for line in headlineLines {
            // The card can sit below a line or grow beside it. It expands from the centre in
            // portrait and from the right edge otherwise.
            let below = (headlineTop - line.maxY - clearance - bottom) / footprint.height
            let beside =
                portrait
                ? 2 * max(bounds.midX - margin - line.maxX, margin + line.minX - bounds.midX)
                : right - margin - line.maxX
            height = min(height, max(below, (beside - clearance) / footprint.width))
        }
        guard height > 0 else { return scene }

        let centerX = portrait ? bounds.midX : right - height * footprint.width / 2
        let card = posterCard(
            poster,
            frame: CGRect(
                x: centerX - height * ratio / 2, y: bottom + height * (footprint.height - 1) / 2,
                width: height * ratio, height: height))
        card.setAffineTransform(tilt)
        card.shadowOpacity = 0.6
        card.shadowRadius = unit * 0.04
        scene.addSublayer(card)
        return scene
    }

    /// Prefer a single line if it can stay close to the size of the largest full, wrapped title.
    private func editorialHeadline(
        _ title: String, width: CGFloat, maxHeight: CGFloat, maxLines: Int, accent: ScreenSaverColor
    ) -> FittedText? {
        let smallest = 4
        var words: [Range<String.Index>]?
        var forcedWrap: CGFloat?
        var wrapped: CGFloat?
        var single: CGFloat?
        for percent in stride(from: 36, through: smallest, by: -1) {
            let size = unit * CGFloat(percent) / 100
            if let wrapped, size < wrapped * 0.7 { break }
            let metrics = measure(
                attributed(title, size: size, weight: .black, alpha: 1, lineSpacing: 0.96, tracking: -0.02),
                width: width)
            guard metrics.height + size * 0.2 + 1 <= maxHeight else { continue }
            if metrics.lines == 1 {
                single = size
                break
            }
            if wrapped == nil, metrics.lines <= maxLines {
                // Keep Latin words intact when possible; CJK can wrap between characters.
                if words == nil { words = title.ranges(of: /[\p{Latin}\p{M}\p{Nd}]+/) }
                let splitsWord = metrics.lineEnds.dropLast().contains { end in
                    let index = String.Index(utf16Offset: end, in: title)
                    return words?.contains { $0.lowerBound < index && index < $0.upperBound } == true
                }
                if splitsWord {
                    forcedWrap = forcedWrap ?? size
                } else {
                    wrapped = size
                }
            }
        }
        // Lift dark accent channels toward white while preserving the poster hue.
        let color = CGColor(
            srgbRed: accent.red * 0.75 + 0.25, green: accent.green * 0.75 + 0.25,
            blue: accent.blue * 0.75 + 0.25, alpha: 1)
        return fittedText(
            title, width: width, size: single ?? wrapped ?? forcedWrap ?? unit * CGFloat(smallest) / 100,
            weight: .black, alpha: 0.95, lines: maxLines, lineSpacing: 0.96, color: color, tracking: -0.02)
    }

    /// Each drawn line's ink, in top-left coordinates of the text's layer, so the poster can tuck under it.
    private func inkBounds(of text: FittedText) -> [CGRect] {
        let frame = text.frame
        guard let lines = CTFrameGetLines(frame) as? [CTLine] else { return [] }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(), &origins)
        return zip(lines, origins).map { line, origin in
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let typographic = CGRect(x: 0, y: -descent, width: width, height: ascent + descent)
            let ink = typographic.union(CTLineGetBoundsWithOptions(line, .useGlyphPathBounds))
            return CGRect(
                x: ink.minX + origin.x, y: text.height - origin.y - ink.maxY, width: ink.width, height: ink.height)
        }
    }

    /// An accent rule and the facts set like a cover's lines, with the TMDb score large.
    private func editorialColumn(
        _ entry: ScreenSaverManifest.Entry, accent: ScreenSaverColor, details: Set<ScreenSaverManifest.Detail>,
        width: CGFloat
    ) -> Stack {
        var result = Stack(layers: [], height: 0)
        func add(_ layer: CALayer?, space: CGFloat) {
            guard let layer else { return }
            let gap = result.layers.isEmpty ? 0 : space
            result.layers.append((layer, gap))
            result.height += gap + layer.bounds.height
        }
        let ink = accent.cgColor

        let rule = CALayer()
        rule.bounds = CGRect(x: 0, y: 0, width: unit * 0.07, height: max(unit * 0.004, 1))
        rule.backgroundColor = ink
        add(rule, space: 0)
        if details.contains(.season), let season = entry.season, !season.isEmpty {
            add(
                textLayer(
                    season, width: width, size: unit * 0.022, weight: .semibold, alpha: 0.95, lines: 1, color: ink),
                space: unit * 0.018)
        }

        if details.contains(.score), let score = entry.score, !score.isEmpty {
            let split = score.lastIndex(of: " ")
            let label = split.map { String(score[..<$0]) }
            let value = split.map { String(score[score.index(after: $0)...]) } ?? score
            add(
                textLayer(
                    label?.uppercased(), width: width, size: unit * 0.015, weight: .semibold, alpha: 0.6, lines: 1,
                    tracking: 0.14),
                space: unit * 0.03)
            add(
                textLayer(value, width: width, size: unit * 0.075, weight: .heavy, alpha: 1, lines: 1, color: ink),
                space: 0)
        }
        let facts: [String?] = [
            details.contains(.year) ? entry.year : nil,
            details.contains(.genres) ? entry.genres.map { Self.joinedGenres(Array($0.prefix(3))) } : nil,
            details.contains(.status) ? entry.status : nil,
            details.contains(.watchStatus) ? entry.watchStatus : nil,
            details.contains(.userScore) ? entry.userScore : nil
        ]
        for (index, fact) in facts.compactMap({ $0 }).filter({ !$0.isEmpty }).enumerated() {
            add(
                textLayer(fact, width: width, size: unit * 0.021, weight: .medium, alpha: 0.78, lines: 1),
                space: index == 0 ? unit * 0.026 : unit * 0.006)
        }
        return result
    }
}
