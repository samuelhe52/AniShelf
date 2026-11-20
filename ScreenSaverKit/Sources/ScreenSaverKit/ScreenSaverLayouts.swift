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
        wash: CGColor?,
        showsTitles: Bool
    ) -> CALayer {
        let scene = background()
        let portrait = size.height > size.width
        let hasText = showsTitles && [entry.title, entry.subtitle].contains { $0?.isEmpty == false }
        let padding = unit * 0.07
        let colorWash = gradient(
            colors: [wash ?? ink, ink],
            start: portrait ? CGPoint(x: 0.5, y: 0.95) : CGPoint(x: 0.12, y: 0.55),
            end: portrait ? CGPoint(x: 0.5, y: 0.04) : CGPoint(x: 0.90, y: 0.45)
        )
        scene.addSublayer(colorWash)

        var posterArea = bounds.insetBy(dx: padding, dy: padding)
        if hasText {
            if portrait {
                posterArea.origin.y = size.height * 0.28
                posterArea.size.height = size.height - posterArea.minY - padding
            } else {
                posterArea.size.width = size.width * 0.47 - padding
            }
        }
        let art = imageLayer(poster, frame: aspectFit(poster, in: posterArea))
        art.cornerRadius = min(12, unit * 0.009)
        art.masksToBounds = true
        scene.addSublayer(art)

        if hasText {
            let textArea: CGRect
            if portrait {
                textArea = CGRect(x: padding, y: padding, width: size.width - padding * 2, height: size.height * 0.18)
            } else {
                textArea = CGRect(
                    x: size.width * 0.52, y: padding, width: size.width * 0.48 - padding,
                    height: size.height - padding * 2)
            }
            addText(
                title: entry.title, subtitle: entry.subtitle, area: textArea, to: scene, center: portrait)
        }
        return scene
    }

    func heroStill(
        _ entry: ScreenSaverManifest.Entry,
        backdrop: CGImage,
        logo: CGImage?,
        showsTitles: Bool
    ) -> CALayer {
        let scene = background()
        let photo = imageLayer(backdrop, frame: bounds)
        photo.contentsGravity = .resizeAspectFill
        scene.addSublayer(photo)

        let shade = gradient(
            colors: [CGColor(gray: 0, alpha: 0.87), CGColor(gray: 0, alpha: 0)],
            start: CGPoint(x: 0.25, y: 0),
            end: CGPoint(x: 0.53, y: 0.72)
        )
        scene.addSublayer(shade)

        let padding = unit * 0.07
        let textWidth = min(size.width * 0.8, unit * 1.2)
        let meta = textLayer(entry.meta, width: textWidth, size: max(6, unit * 0.027), weight: .medium, lines: 1)
        if let meta {
            meta.frame.origin = CGPoint(x: padding, y: padding)
            scene.addSublayer(meta)
        }

        if showsTitles {
            let y = (meta?.frame.maxY ?? padding) + unit * 0.018
            if let logo {
                let area = CGRect(x: padding, y: y, width: min(textWidth, unit * 0.60), height: size.height * 0.24)
                let fitted = aspectFit(logo, in: area)
                let frame = CGRect(origin: area.origin, size: fitted.size)
                scene.addSublayer(imageLayer(logo, frame: frame))
            } else {
                let textArea = CGRect(x: padding, y: y, width: textWidth, height: size.height * 0.28)
                addText(title: entry.title, subtitle: entry.subtitle, area: textArea, to: scene, bottom: true)
            }
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

    private func addText(
        title: String?,
        subtitle: String?,
        area: CGRect,
        to scene: CALayer,
        center: Bool = false,
        bottom: Bool = false
    ) {
        let headlineSize = min(max(8, unit * 0.06), area.height * 0.21)
        let layers = [
            textLayer(title, width: area.width, size: headlineSize, weight: .semibold, lines: 2, center: center),
            textLayer(
                subtitle, width: area.width, size: headlineSize * 0.52, weight: .regular, lines: 1, center: center)
        ].compactMap { $0 }
        let gap = layers.count > 1 ? headlineSize * 0.17 : 0
        let height = layers.reduce(0) { $0 + $1.bounds.height } + gap
        var y = bottom ? area.minY : area.midY - height / 2
        for label in layers.reversed() {
            label.frame.origin = CGPoint(x: area.minX, y: y)
            scene.addSublayer(label)
            y += label.bounds.height + gap
        }
    }

    private func textLayer(
        _ text: String?,
        width: CGFloat,
        size: CGFloat,
        weight: NSFont.Weight,
        lines: Int,
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
                .foregroundColor: NSColor(white: 0.96, alpha: 1),
                .paragraphStyle: paragraph
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
        layer.frame.size = CGSize(width: width, height: min(ceil(measure.height), lineHeight * CGFloat(lines)) + 1)
        return layer
    }
}
