//
//  ScreenSaverLayouts.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import AppKit
import QuartzCore

@MainActor
struct ScreenSaverLayouts {
    let size: CGSize
    let scale: CGFloat

    private var bounds: CGRect { CGRect(origin: .zero, size: size) }
    private var unit: CGFloat { min(size.width, size.height) }
    private var ink: CGColor { CGColor(gray: 0.025, alpha: 1) }

    func posterFocus(
        _ entry: ScreenSaverManifest.Entry,
        poster: CGImage,
        background backdrop: CGImage?,
        details: Set<ScreenSaverManifest.Detail>
    ) -> CALayer {
        let scene = background()
        if let backdrop {
            let blur = imageLayer(backdrop, frame: bounds)
            blur.contentsGravity = .resizeAspectFill
            scene.addSublayer(blur)
            scene.addSublayer(fill(CGColor(gray: 0, alpha: 0.45)))
        }

        let lines = posterFocusLines(entry, details: details)
        let portrait = size.height > size.width
        let ratio = CGFloat(poster.width) / CGFloat(max(poster.height, 1))
        let posterHeight = min(
            size.height * (portrait ? (lines.isEmpty ? 0.62 : 0.5) : 0.72),
            size.width * (portrait ? 0.8 : 0.42) / ratio)
        let posterSize = CGSize(width: posterHeight * ratio, height: posterHeight)

        let posterFrame: CGRect
        if lines.isEmpty {
            posterFrame = CGRect(
                x: bounds.midX - posterSize.width / 2, y: bounds.midY - posterSize.height / 2,
                width: posterSize.width, height: posterSize.height)
        } else if portrait {
            // Poster above, text centred below; the pair is centred vertically.
            let textWidth = size.width * 0.8
            let block = stack(lines, width: textWidth, center: true)
            let gap = unit * 0.06
            let top = bounds.midY + (posterSize.height + gap + block.height) / 2
            posterFrame = CGRect(
                x: bounds.midX - posterSize.width / 2, y: top - posterSize.height,
                width: posterSize.width, height: posterSize.height)
            place(block, x: bounds.midX - textWidth / 2, top: posterFrame.minY - gap, in: scene)
        } else {
            // Poster and text form one group centred on the screen, so a short title never floats alone.
            let textWidth = min(size.width * 0.34, unit * 0.62)
            let gap = unit * 0.075
            let left = (size.width - posterSize.width - gap - textWidth) / 2
            posterFrame = CGRect(
                x: left, y: bounds.midY - posterSize.height / 2, width: posterSize.width,
                height: posterSize.height)
            let block = stack(lines, width: textWidth)
            place(block, x: posterFrame.maxX + gap, top: bounds.midY + block.height / 2, in: scene)
        }
        scene.insertSublayer(posterCard(poster, frame: posterFrame), at: UInt32(backdrop == nil ? 0 : 2))
        return scene
    }

    func backdrop(
        _ entry: ScreenSaverManifest.Entry,
        image backdrop: CGImage,
        logo: CGImage?,
        details: Set<ScreenSaverManifest.Detail>
    ) -> CALayer {
        let scene = background()
        let photo = imageLayer(backdrop, frame: bounds)
        photo.contentsGravity = .resizeAspectFill
        scene.addSublayer(photo)

        let meta = [
            details.contains(.season) ? entry.season.nonEmpty : nil,
            details.contains(.year) ? entry.year.nonEmpty : nil,
            details.contains(.genres) ? entry.genres?.prefix(2).joined(separator: ", ").nonEmpty : nil,
            details.contains(.status) ? entry.status.nonEmpty : nil,
            details.contains(.score) ? entry.score.nonEmpty : nil,
            details.contains(.watchStatus) ? entry.watchStatus.nonEmpty : nil
        ].compactMap(\.self).joined(separator: "  ·  ")

        // Shade only the corner that holds text; the rest of the still stays untouched.
        scene.addSublayer(
            gradient(
                colors: [CGColor(gray: 0, alpha: 0.72), CGColor(gray: 0, alpha: 0)],
                start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 0.5)))
        scene.addSublayer(
            gradient(
                colors: [CGColor(gray: 0, alpha: 0.4), CGColor(gray: 0, alpha: 0)],
                start: CGPoint(x: 0, y: 0.5), end: CGPoint(x: 0.6, y: 0.5)))

        let padding = unit * 0.07
        let width = min(size.width * 0.6, unit * 1.1)
        var y = padding
        if !meta.isEmpty,
            let label = textLayer(meta, width: width, size: unit * 0.024, weight: .medium, alpha: 0.88, lines: 1)
        {
            label.frame.origin = CGPoint(x: padding, y: y)
            addShadow(to: label)
            scene.addSublayer(label)
            y = label.frame.maxY + unit * 0.018
        }
        if let logo {
            let area = CGRect(
                x: padding, y: y, width: min(unit * 0.5, size.width * 0.42), height: size.height * 0.18)
            let fitted = aspectFit(logo, in: area)
            let mark = imageLayer(logo, frame: CGRect(origin: area.origin, size: fitted.size))
            addShadow(to: mark)
            scene.addSublayer(mark)
        } else if let label = textLayer(
            entry.title, width: width, size: unit * 0.062, weight: .bold, alpha: 0.97, lines: 2)
        {
            label.frame.origin = CGPoint(x: padding, y: y)
            addShadow(to: label)
            scene.addSublayer(label)
        }
        return scene
    }

    func notice(_ message: String) -> CALayer {
        let scene = background()
        let width = size.width * 0.8
        if let label = textLayer(
            message, width: width, size: max(7, unit * 0.028), weight: .medium, lines: 3, center: true)
        {
            label.position = CGPoint(x: bounds.midX, y: bounds.midY)
            scene.addSublayer(label)
        }
        return scene
    }

    private func background() -> CALayer {
        let layer = CALayer()
        layer.frame = bounds
        layer.backgroundColor = ink
        layer.masksToBounds = true
        return layer
    }

    private func gradient(colors: [CGColor], start: CGPoint, end: CGPoint) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.frame = bounds
        layer.colors = colors
        layer.startPoint = start
        layer.endPoint = end
        return layer
    }

    private func imageLayer(_ image: CGImage, frame: CGRect) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.contents = image
        return layer
    }

    private func aspectFit(_ image: CGImage, in frame: CGRect) -> CGRect {
        let ratio = min(frame.width / CGFloat(image.width), frame.height / CGFloat(image.height))
        let width = CGFloat(image.width) * ratio
        let height = CGFloat(image.height) * ratio
        return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
    }

    private struct Line {
        let text: String
        let size: CGFloat
        let weight: NSFont.Weight
        let alpha: CGFloat
        var lines = 1
        var tracking: CGFloat = 0
        var spaceBefore: CGFloat = 0
    }

    /// Poster Focus order: year and airing status as a small heading, then title, season, genres,
    /// score and watch status, and the overview.
    private func posterFocusLines(
        _ entry: ScreenSaverManifest.Entry, details: Set<ScreenSaverManifest.Detail>
    ) -> [Line] {
        var lines: [Line] = []
        let heading = [
            details.contains(.year) ? entry.year.nonEmpty : nil,
            details.contains(.status) ? entry.status.nonEmpty : nil
        ].compactMap(\.self).joined(separator: "  ·  ")
        if !heading.isEmpty {
            let size = unit * 0.021
            lines.append(
                Line(text: heading.uppercased(), size: size, weight: .semibold, alpha: 0.62, tracking: size * 0.08))
        }
        if let title = entry.title.nonEmpty {
            lines.append(
                Line(text: title, size: unit * 0.056, weight: .bold, alpha: 0.97, lines: 3, spaceBefore: unit * 0.014))
        }
        if details.contains(.season), let season = entry.season.nonEmpty {
            lines.append(
                Line(text: season, size: unit * 0.029, weight: .medium, alpha: 0.8, spaceBefore: unit * 0.008))
        }
        if details.contains(.genres), let genres = entry.genres?.joined(separator: "  ·  ").nonEmpty {
            lines.append(
                Line(
                    text: genres, size: unit * 0.021, weight: .regular, alpha: 0.62, lines: 2, spaceBefore: unit * 0.026
                ))
        }
        let facts = [
            details.contains(.score) ? entry.score.nonEmpty : nil,
            details.contains(.watchStatus) ? entry.watchStatus.nonEmpty : nil
        ].compactMap(\.self).joined(separator: "  ·  ")
        if !facts.isEmpty {
            let followsGenres = details.contains(.genres) && entry.genres?.isEmpty == false
            lines.append(
                Line(
                    text: facts, size: unit * 0.021, weight: .medium, alpha: 0.8,
                    spaceBefore: unit * (followsGenres ? 0.012 : 0.026)))
        }
        if details.contains(.overview), let overview = entry.overview.nonEmpty {
            // A fixed, readable size capped at five lines; long overviews end with an ellipsis.
            lines.append(
                Line(
                    text: overview, size: unit * 0.019, weight: .regular, alpha: 0.72, lines: 5,
                    spaceBefore: unit * 0.032))
        }
        return lines
    }

    private struct Stack {
        var layers: [(layer: CATextLayer, spaceBefore: CGFloat)]
        var height: CGFloat
    }

    private func stack(_ lines: [Line], width: CGFloat, center: Bool = false) -> Stack {
        var result = Stack(layers: [], height: 0)
        for line in lines {
            guard
                let layer = textLayer(
                    line.text, width: width, size: line.size, weight: line.weight, alpha: line.alpha,
                    lines: line.lines, tracking: line.tracking, center: center)
            else { continue }
            let space = result.layers.isEmpty ? 0 : line.spaceBefore
            result.layers.append((layer, space))
            result.height += space + layer.bounds.height
        }
        return result
    }

    /// Lays the stack out downward from `top`; layer coordinates grow upward.
    private func place(_ stack: Stack, x: CGFloat, top: CGFloat, in scene: CALayer) {
        var y = top
        for (layer, space) in stack.layers {
            y -= space + layer.bounds.height
            layer.frame.origin = CGPoint(x: x, y: y)
            scene.addSublayer(layer)
        }
    }

    private func posterCard(_ poster: CGImage, frame: CGRect) -> CALayer {
        let radius = unit * 0.01
        let card = CALayer()
        card.frame = frame
        card.shadowColor = CGColor(gray: 0, alpha: 1)
        card.shadowOpacity = 0.5
        card.shadowRadius = unit * 0.03
        card.shadowOffset = CGSize(width: 0, height: -unit * 0.01)
        card.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: frame.size), cornerWidth: radius, cornerHeight: radius,
            transform: nil)
        let art = imageLayer(poster, frame: CGRect(origin: .zero, size: frame.size))
        art.cornerRadius = radius
        art.masksToBounds = true
        card.addSublayer(art)
        return card
    }

    private func fill(_ color: CGColor) -> CALayer {
        let layer = CALayer()
        layer.frame = bounds
        layer.backgroundColor = color
        return layer
    }

    private func addShadow(to layer: CALayer) {
        layer.shadowColor = CGColor(gray: 0, alpha: 1)
        layer.shadowOpacity = 0.45
        layer.shadowRadius = unit * 0.012
        layer.shadowOffset = .zero
    }

    private func textLayer(
        _ text: String?,
        width: CGFloat,
        size: CGFloat,
        weight: NSFont.Weight,
        alpha: CGFloat = 0.96,
        lines: Int,
        tracking: CGFloat = 0,
        center: Bool = false
    ) -> CATextLayer? {
        guard let text, !text.isEmpty, width > 0, size > 0 else { return nil }
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = center ? .center : .natural
        paragraph.lineBreakMode = .byWordWrapping
        let string = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor(white: 1, alpha: alpha),
                .paragraphStyle: paragraph,
                .kern: tracking
            ])
        let measure = string.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let layer = CATextLayer()
        layer.string = string
        layer.contentsScale = scale
        layer.isWrapped = lines > 1
        layer.truncationMode = .end
        let measuredHeight = min(max(ceil(measure.height), lineHeight), lineHeight * CGFloat(lines))
        // CATextLayer needs a little room below the measured lines for descenders at preview sizes.
        layer.frame.size = CGSize(width: width, height: measuredHeight + ceil(size * 0.25))
        return layer
    }
}

extension Optional where Wrapped == String {
    fileprivate var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
