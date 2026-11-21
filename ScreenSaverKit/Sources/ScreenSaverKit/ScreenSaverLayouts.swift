//
//  ScreenSaverLayouts.swift
//  AniShelf
//
//  Created by OpenAI Codex on behalf of Samuel He on 2026/11/20.
//

import AppKit
import CoreText
import QuartzCore

@MainActor
struct ScreenSaverLayouts {
    let size: CGSize
    let scale: CGFloat

    var bounds: CGRect { CGRect(origin: .zero, size: size) }
    var unit: CGFloat { min(size.width, size.height) }
    var ink: CGColor { CGColor(gray: 0.025, alpha: 1) }

    // MARK: - Poster Focus

    /// Drawn over the renderer's wash, which carries the poster's colours; the scene itself is clear.
    func posterFocus(
        _ entry: ScreenSaverManifest.Entry,
        poster: CGImage,
        details: Set<ScreenSaverManifest.Detail>
    ) -> CALayer {
        let scene = CALayer()
        scene.frame = bounds
        scene.masksToBounds = true

        let portrait = size.height > size.width
        let ratio = CGFloat(poster.width) / CGFloat(max(poster.height, 1))
        let posterHeight = min(size.height * (portrait ? 0.48 : 0.7), size.width * (portrait ? 0.7 : 0.4) / ratio)
        let posterSize = CGSize(width: posterHeight * ratio, height: posterHeight)

        let posterFrame: CGRect
        if portrait {
            // Poster above, text centred below; the pair is centred vertically.
            let textWidth = size.width * 0.78
            let block = stack(
                posterFocusLines(entry, details: details, width: textWidth), width: textWidth, center: true)
            let gap = unit * 0.07
            let top = bounds.midY + (posterSize.height + gap + block.height) / 2
            posterFrame = CGRect(
                x: bounds.midX - posterSize.width / 2, y: top - posterSize.height,
                width: posterSize.width, height: posterSize.height)
            place(block, x: bounds.midX - textWidth / 2, top: posterFrame.minY - gap, in: scene)
        } else {
            // Poster and text form one group centred on the screen. Its width does not depend on the
            // entry, so the poster stays in place from slide to slide.
            let textWidth = min(size.width * 0.4, unit * 0.74)
            let gap = unit * 0.08
            let left = (size.width - posterSize.width - gap - textWidth) / 2
            posterFrame = CGRect(
                x: left, y: bounds.midY - posterSize.height / 2, width: posterSize.width,
                height: posterSize.height)
            let block = stack(posterFocusLines(entry, details: details, width: textWidth), width: textWidth)
            place(block, x: posterFrame.maxX + gap, top: bounds.midY + block.height / 2, in: scene)
        }
        scene.insertSublayer(posterCard(poster, frame: posterFrame), at: 0)
        return scene
    }

    /// Three blocks: the title with its season, one line of facts, and the overview.
    func posterFocusLines(
        _ entry: ScreenSaverManifest.Entry, details: Set<ScreenSaverManifest.Detail>, width: CGFloat
    ) -> [Line] {
        var lines: [Line] = []
        if let title = entry.title.nonEmpty {
            let size = fittedTitle(title, width: width, largest: 0.06, smallest: 0.03)
            lines.append(Line(text: title, size: size, weight: .bold, alpha: 0.97, lines: 3))
        }
        if details.contains(.season), let season = entry.season.nonEmpty {
            lines.append(
                Line(text: season, size: unit * 0.024, weight: .medium, alpha: 0.8, spaceBefore: unit * 0.006))
        }
        let facts = factsLine(entry, details: details)
        if !facts.isEmpty {
            lines.append(
                Line(
                    text: facts, size: unit * 0.02, weight: .regular, alpha: 0.58, lines: 2,
                    spaceBefore: unit * 0.024))
        }
        if details.contains(.overview), let overview = entry.overview.nonEmpty {
            // A fixed, readable size capped at four lines; a longer overview ends with an ellipsis.
            lines.append(
                Line(
                    text: overview, size: unit * 0.022, weight: .regular, alpha: 0.84, lines: 4,
                    lineSpacing: 1.32, spaceBefore: unit * 0.036))
        }
        return lines
    }

    // MARK: - Backdrop

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
        var facts = factsLine(entry, details: details)
        if details.contains(.season), let season = entry.season.nonEmpty {
            facts = facts.isEmpty ? season : season + Self.separator + facts
        }
        // The facts sit back as a quiet secondary line; the logo or title leads.
        if let label = textLayer(facts, width: width, size: unit * 0.019, weight: .regular, alpha: 0.55, lines: 1) {
            label.frame.origin = CGPoint(x: padding, y: y)
            addShadow(to: label, opacity: 0.3)
            scene.addSublayer(label)
            y = label.frame.maxY + unit * 0.014
        }
        if let logo {
            let area = CGRect(
                x: padding, y: y, width: min(unit * 0.5, size.width * 0.42), height: size.height * 0.18)
            let fitted = aspectFit(logo, in: area)
            let mark = imageLayer(logo, frame: CGRect(origin: area.origin, size: fitted.size))
            addShadow(to: mark)
            scene.addSublayer(mark)
        } else if let title = entry.title.nonEmpty,
            case let titleSize = fittedTitle(title, width: width, largest: 0.068, smallest: 0.046),
            let label = textLayer(title, width: width, size: titleSize, weight: .bold, alpha: 0.97, lines: 2)
        {
            // The text box keeps descender room below the last line; let it overlap the gap above the facts.
            label.frame.origin = CGPoint(x: padding, y: y - titleSize * 0.2)
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

    // MARK: - Text

    static let separator = " · "
    static let textLayerName = "text"

    /// Year, genres, airing status, TMDb score, watch status, and the user's score, in that order, on one line of facts.
    func factsLine(_ entry: ScreenSaverManifest.Entry, details: Set<ScreenSaverManifest.Detail>) -> String {
        // Two genres at most: more turns the line into a list of tags.
        let genres = entry.genres.map { Array($0.prefix(2)) } ?? []
        return [
            details.contains(.year) ? entry.year.nonEmpty : nil,
            details.contains(.genres) && !genres.isEmpty ? Self.joinedGenres(genres) : nil,
            details.contains(.status) ? entry.status.nonEmpty : nil,
            details.contains(.score) ? entry.score.nonEmpty : nil,
            details.contains(.watchStatus) ? entry.watchStatus.nonEmpty : nil,
            details.contains(.userScore) ? entry.userScore.nonEmpty : nil
        ]
        // Lines break only between items, never inside one such as "TMDb 8.6" or 視聴済み: CJK text
        // can break between any two characters, so a word joiner holds each item together.
        .compactMap { $0.map(Self.unbreakable) }
        .joined(separator: Self.separator)
    }

    static func unbreakable(_ item: String) -> String {
        item.replacingOccurrences(of: " ", with: "\u{00A0}").map(String.init).joined(separator: "\u{2060}")
    }

    /// Genres are one item in the facts line, so they use their script's list separator. Japanese
    /// genre names such as アクション・アドベンチャー already contain a middle dot.
    static func joinedGenres(_ genres: [String]) -> String {
        let isCJK = genres.joined().unicodeScalars.contains {
            $0.properties.isIdeographic || (0x3040...0x30FF).contains($0.value)
        }
        return genres.joined(separator: isCJK ? "、" : ", ")
    }

    /// Shrinks the title to fit one line, down to `smallest`. A longer title wraps at `smallest`
    /// size, or a little larger when that still avoids a short last line.
    func fittedTitle(_ title: String, width: CGFloat, largest: CGFloat, smallest: CGFloat) -> CGFloat {
        let step = (largest - smallest) / 6
        let sizes = stride(from: largest, through: smallest - step / 2, by: -step).map { unit * $0 }
        func metrics(_ size: CGFloat) -> Metrics {
            measure(attributed(title, size: size, weight: .bold, alpha: 1), width: width)
        }
        if let single = sizes.first(where: { metrics($0).lines == 1 }) { return single }
        let wrapped = sizes.first {
            let value = metrics($0)
            return value.lines == 2 && value.lastLineWidth >= width * 0.4
        }
        return wrapped ?? unit * smallest
    }

    struct Line {
        let text: String
        let size: CGFloat
        let weight: NSFont.Weight
        let alpha: CGFloat
        var lines = 1
        var lineSpacing: CGFloat = 1
        var spaceBefore: CGFloat = 0
    }

    struct Stack {
        var layers: [(layer: CALayer, spaceBefore: CGFloat)]
        var height: CGFloat
    }

    func stack(_ lines: [Line], width: CGFloat, center: Bool = false) -> Stack {
        var result = Stack(layers: [], height: 0)
        for line in lines {
            guard
                let layer = textLayer(
                    line.text, width: width, size: line.size, weight: line.weight, alpha: line.alpha,
                    lines: line.lines, lineSpacing: line.lineSpacing, center: center)
            else { continue }
            let space = result.layers.isEmpty ? 0 : line.spaceBefore
            result.layers.append((layer, space))
            result.height += space + layer.bounds.height
        }
        return result
    }

    /// Lays the stack out downward from `top`; layer coordinates grow upward.
    func place(_ stack: Stack, x: CGFloat, top: CGFloat, in scene: CALayer) {
        var y = top
        for (layer, space) in stack.layers {
            y -= space + layer.bounds.height
            layer.frame.origin = CGPoint(x: x, y: y)
            scene.addSublayer(layer)
        }
    }

    func attributed(
        _ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, lineSpacing: CGFloat = 1,
        center: Bool = false, color: CGColor? = nil, tracking: CGFloat = 0
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = center ? .center : .natural
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = lineSpacing
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            // CoreText draws with its own colour key.
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                color?.copy(alpha: alpha) ?? CGColor(gray: 1, alpha: alpha),
            .paragraphStyle: paragraph
        ]
        if tracking != 0 { attributes[.kern] = tracking * size }
        return NSAttributedString(string: text, attributes: attributes)
    }

    struct Metrics {
        let lines: Int
        let height: CGFloat
        let lastLineWidth: CGFloat
        /// UTF-16 offset where each line ends.
        let lineEnds: [Int]
    }

    func measure(_ string: NSAttributedString, width: CGFloat) -> Metrics {
        measure(CTFramesetterCreateWithAttributedString(string), width: width)
    }

    private func measure(_ setter: CTFramesetter, width: CGFloat) -> Metrics {
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 100_000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(), path, nil)
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        let fitted = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        let last = lines.last.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) } ?? 0
        let ends = lines.map { CTLineGetStringRange($0) }.map { $0.location + $0.length }
        return Metrics(lines: lines.count, height: fitted.height, lastLineWidth: last, lineEnds: ends)
    }

    /// Text laid out and truncated, ready to draw.
    struct FittedText {
        let frame: CTFrame
        let width: CGFloat
        let height: CGFloat
    }

    /// Text is laid out, truncated, and drawn by CoreText into an image, so what is measured is
    /// exactly what is drawn. (CATextLayer ignores line spacing and cannot truncate wrapped text.)
    /// Text exceeding the line or height limit ends with an ellipsis.
    func textLayer(
        _ text: String?,
        width: CGFloat,
        size: CGFloat,
        weight: NSFont.Weight,
        alpha: CGFloat = 0.96,
        lines: Int = .max,
        maxHeight: CGFloat = .greatestFiniteMagnitude,
        lineSpacing: CGFloat = 1,
        center: Bool = false,
        color: CGColor? = nil,
        tracking: CGFloat = 0
    ) -> CALayer? {
        fittedText(
            text, width: width, size: size, weight: weight, alpha: alpha, lines: lines, maxHeight: maxHeight,
            lineSpacing: lineSpacing, center: center, color: color, tracking: tracking
        ).flatMap(textLayer)
    }

    func fittedText(
        _ text: String?,
        width: CGFloat,
        size: CGFloat,
        weight: NSFont.Weight,
        alpha: CGFloat = 0.96,
        lines: Int = .max,
        maxHeight: CGFloat = .greatestFiniteMagnitude,
        lineSpacing: CGFloat = 1,
        center: Bool = false,
        color: CGColor? = nil,
        tracking: CGFloat = 0
    ) -> FittedText? {
        let padding = size * 0.2  // Room below the last line for descenders.
        guard let text = text.nonEmpty, width > 0, size > 0, lines > 0, maxHeight > padding else { return nil }
        func make(_ text: String) -> NSAttributedString {
            attributed(
                text, size: size, weight: weight, alpha: alpha, lineSpacing: lineSpacing, center: center,
                color: color, tracking: tracking)
        }
        func fits(_ metrics: Metrics) -> Bool {
            metrics.lines <= lines && ceil(metrics.height + padding) <= maxHeight
        }
        var setter = CTFramesetterCreateWithAttributedString(make(text))
        var metrics = measure(setter, width: width)
        if !fits(metrics) {
            let source = text as NSString
            var end = metrics.lines > lines ? metrics.lineEnds[lines - 1] : source.length
            if ceil(metrics.height + padding) > maxHeight {
                let path = CGPath(
                    rect: CGRect(x: 0, y: 0, width: width, height: floor(maxHeight) - padding), transform: nil)
                let frame = CTFramesetterCreateFrame(setter, CFRange(), path, nil)
                end = min(end, CTFrameGetVisibleStringRange(frame).length)
            }
            guard end > 0 else { return nil }
            repeat {
                let kept = source.substring(to: end).trimmingCharacters(in: .whitespacesAndNewlines)
                setter = CTFramesetterCreateWithAttributedString(make(kept + "…"))
                metrics = measure(setter, width: width)
                if fits(metrics) { break }
                // Step back a whole character, so an emoji or accented letter is never split.
                end = source.rangeOfComposedCharacterSequence(at: end - 1).location
            } while end > 0
            guard fits(metrics) else { return nil }
        }
        let height = ceil(metrics.height + padding)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil)
        return FittedText(frame: CTFramesetterCreateFrame(setter, CFRange(), path, nil), width: width, height: height)
    }

    func textLayer(_ text: FittedText) -> CALayer? {
        guard
            let context = CGContext(
                data: nil, width: Int(ceil(text.width * scale)), height: Int(ceil(text.height * scale)),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        CTFrameDraw(text.frame, context)

        let layer = CALayer()
        layer.name = Self.textLayerName
        layer.contents = context.makeImage()
        layer.contentsScale = scale
        layer.frame.size = CGSize(width: text.width, height: text.height)
        return layer
    }

    // MARK: - Shapes

    func posterCard(_ poster: CGImage, frame: CGRect) -> CALayer {
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

    func background() -> CALayer {
        let layer = CALayer()
        layer.frame = bounds
        layer.backgroundColor = ink
        layer.masksToBounds = true
        return layer
    }

    func fill(_ color: CGColor) -> CALayer {
        let layer = CALayer()
        layer.frame = bounds
        layer.backgroundColor = color
        return layer
    }

    func gradient(colors: [CGColor], start: CGPoint, end: CGPoint) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.frame = bounds
        layer.colors = colors
        layer.startPoint = start
        layer.endPoint = end
        return layer
    }

    func imageLayer(_ image: CGImage, frame: CGRect) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.contents = image
        return layer
    }

    func aspectFit(_ image: CGImage, in frame: CGRect) -> CGRect {
        let ratio = min(frame.width / CGFloat(image.width), frame.height / CGFloat(image.height))
        let width = CGFloat(image.width) * ratio
        let height = CGFloat(image.height) * ratio
        return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
    }

    func addShadow(to layer: CALayer, opacity: Float = 0.45) {
        layer.shadowColor = CGColor(gray: 0, alpha: 1)
        layer.shadowOpacity = opacity
        layer.shadowRadius = unit * 0.012
        layer.shadowOffset = .zero
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
