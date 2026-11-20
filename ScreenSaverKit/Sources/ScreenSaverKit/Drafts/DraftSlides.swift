//
//  DraftSlides.swift
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
            let block = stack(posterFocusLines(entry, details: details, width: width), width: width)
            place(block, x: (size.width - width) / 2, top: frame.minY - unit * 0.01, in: scene)
        } else {
            let x = frame.maxX + unit * 0.05
            let width = min(size.width - x - unit * 0.09, unit * 0.95)
            let block = stack(posterFocusLines(entry, details: details, width: width), width: width)
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

        // The info column, laid out first so the poster can be sized around it.
        let columnWidth = portrait ? size.width - margin * 2 : min(size.width * 0.34, unit * 0.62)
        let column = editorialColumn(entry, accent: accent, details: details, width: columnWidth)

        // The ghost title runs across the top, as large as it fits.
        let ghostWidth = size.width - margin * 2
        var ghostFrame = CGRect(x: margin, y: size.height - margin, width: ghostWidth, height: 0)
        var ghostSize: CGFloat = 0
        if let title = entry.title, !title.isEmpty,
            let ghost = ghostTitle(
                title, width: ghostWidth, maxHeight: size.height * (portrait ? 0.28 : 0.46),
                maxLines: portrait ? 3 : 2, color: accent)
        {
            ghost.layer.frame.origin = CGPoint(
                x: margin * 0.8, y: size.height - margin * 0.6 - ghost.layer.bounds.height)
            scene.addSublayer(ghost.layer)
            ghostFrame = ghost.layer.frame
            ghostSize = ghost.size
        }

        // The poster reaches up into the bottom of the ghost title's last line, so the two overlap but
        // the title stays readable to its end.
        let posterTop = ghostFrame.minY + ghostSize * 0.4
        let posterFrame: CGRect
        if portrait {
            let columnTop = margin + column.height
            let bottom = columnTop + unit * 0.09
            let height = min(max(posterTop - bottom, size.height * 0.22), size.height * 0.5)
            posterFrame = CGRect(
                x: (size.width - height * ratio) / 2, y: bottom, width: height * ratio, height: height)
            place(column, x: margin, top: columnTop, in: scene)
        } else {
            let height = min(max(posterTop - margin, size.height * 0.5), size.height * 0.74)
            posterFrame = CGRect(
                x: margin + size.width * 0.03, y: margin, width: height * ratio, height: height)
            let x = max(posterFrame.maxX + unit * 0.1, size.width - margin - columnWidth)
            place(column, x: x, top: margin + column.height, in: scene)
        }
        let card = posterCard(poster, frame: posterFrame)
        card.shadowOpacity = 0.6
        card.shadowRadius = unit * 0.04
        card.setAffineTransform(CGAffineTransform(rotationAngle: 2.2 * .pi / 180))
        scene.addSublayer(card)
        return scene
    }

    /// Huge, tight, translucent type in the poster's colour. One line is preferred while it stays
    /// large; otherwise the title wraps at the largest size that fits, without a stub last line.
    private func ghostTitle(
        _ title: String, width: CGFloat, maxHeight: CGFloat, maxLines: Int, color: ScreenSaverColor
    ) -> (layer: CALayer, size: CGFloat)? {
        let sizes = stride(from: 0.36, through: 0.08, by: -0.01).map { unit * $0 }
        func metrics(_ size: CGFloat) -> Metrics {
            measure(
                attributed(title, size: size, weight: .black, alpha: 1, lineSpacing: 0.88, tracking: -0.02),
                width: width)
        }
        let single = sizes.first { size in
            let value = metrics(size)
            return value.lines == 1 && value.height <= maxHeight
        }
        let wrapped = sizes.first { size in
            let value = metrics(size)
            return value.lines <= maxLines && value.height <= maxHeight
                && (value.lines == 1 || value.lastLineWidth >= width * 0.3)
        }
        let size: CGFloat =
            switch (single, wrapped) {
            case (let one?, let many?): one >= many * 0.7 ? one : many
            case (let one?, nil): one
            case (nil, let many?): many
            case (nil, nil): unit * 0.08
            }
        return textLayer(
            title, width: width, size: size, weight: .black, alpha: 0.5, lines: maxLines, lineSpacing: 0.88,
            color: color.cgColor, tracking: -0.02
        ).map { ($0, size) }
    }

    /// Title, season, an accent rule, then the facts set one per line like a cover's lines, the
    /// TMDb score large.
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

        if let title = entry.title, !title.isEmpty {
            let size = fittedTitle(title, width: width, largest: 0.046, smallest: 0.03)
            add(textLayer(title, width: width, size: size, weight: .bold, alpha: 0.97, lines: 3), space: 0)
        }
        if details.contains(.season), let season = entry.season, !season.isEmpty {
            add(
                textLayer(
                    season, width: width, size: unit * 0.022, weight: .semibold, alpha: 0.95, lines: 1, color: ink),
                space: unit * 0.008)
        }

        let rule = CALayer()
        rule.bounds = CGRect(x: 0, y: 0, width: unit * 0.07, height: max(unit * 0.004, 1))
        rule.backgroundColor = ink
        add(rule, space: unit * 0.03)

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
        if details.contains(.overview), let overview = entry.overview, !overview.isEmpty {
            add(
                textLayer(
                    overview, width: width, size: unit * 0.018, weight: .regular, alpha: 0.7, lines: 3,
                    lineSpacing: 1.3),
                space: unit * 0.03)
        }
        return result
    }
}
