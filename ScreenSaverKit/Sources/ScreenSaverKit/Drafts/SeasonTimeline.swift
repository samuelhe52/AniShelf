//
//  SeasonTimeline.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import QuartzCore

/// Where the timeline's parts go. Posters are spaced evenly by order, not by date, so a busy year
/// does not pile up; the labels carry the real date.
struct TimelineGeometry: Equatable, Sendable {
    static let emphasis: CGFloat = 1.22

    let size: CGSize
    let lineY: CGFloat
    let posterSize: CGSize
    let stem: CGFloat
    let pitch: CGFloat
    /// Posters on each side of the centre, enough to cover the screen during a pan.
    let reach: Int
    /// The band under the timeline that only the caption uses.
    let captionBand: CGRect

    init(size: CGSize) {
        self.size = size
        let unit = min(size.width, size.height)
        let margin = unit * 0.05
        let captionHeight = size.height * (size.height > size.width ? 0.16 : 0.2)
        captionBand = CGRect(x: 0, y: margin, width: size.width, height: captionHeight)
        let bandBottom = captionBand.maxY + unit * 0.02
        let bandTop = size.height - margin
        lineY = (bandTop + bandBottom) / 2
        stem = unit * 0.035
        // The emphasised poster must fit between the line and the band's edge.
        let height = ((bandTop - bandBottom) / 2 - stem) / Self.emphasis
        posterSize = CGSize(width: height * 2 / 3, height: height)
        pitch = posterSize.width * 0.68
        reach = Int(ceil((size.width / 2 + posterSize.width) / pitch)) + 1
    }

    /// Even positions sit above the line, odd ones below.
    func isAbove(_ position: Int) -> Bool { position.isMultiple(of: 2) }
}

struct TimelineSlot: Sendable {
    let position: Int
    let entry: ScreenSaverManifest.Entry
    let poster: CGImage
    /// The poster's colour in each cell of a 3 × 3 grid, for the wash.
    let samples: [ScreenSaverColor]
}

enum TimelineStep: ScreenSaverStageStep {
    case open(TimelineGeometry, [TimelineSlot], centre: Int, details: Set<ScreenSaverManifest.Detail>)
    /// The line moves one place left; `incoming` enters at the right.
    case advance(incoming: TimelineSlot)

    @MainActor func makeStage(size: CGSize, scale: CGFloat, wash: ScreenSaverWash) -> (any ScreenSaverStage)? {
        guard case .open(let geometry, let slots, let centre, let details) = self else { return nil }
        return TimelineStage(
            geometry: geometry, slots: slots, centre: centre, details: details, scale: scale, wash: wash)
    }
}

struct TimelineDirector: ScreenSaverStageDirector {
    private let entries: [ScreenSaverManifest.Entry]
    /// Indices into `entries`, in airing order; entries without a year are left out.
    private let order: [Int]
    private let geometry: TimelineGeometry
    private let details: Set<ScreenSaverManifest.Detail>
    private let hold: TimeInterval
    private let pixelSize: Int
    private var centre: Int
    private var opened = false

    init(_ context: ScreenSaverDraftContext) {
        entries = context.entries
        order = context.entries.indices
            .compactMap { index in Self.year(of: context.entries[index]).map { (index, $0) } }
            .sorted { ($0.1, context.entries[$0.0].id) < ($1.1, context.entries[$1.0].id) }
            .map(\.0)
        geometry = TimelineGeometry(size: context.size)
        details = context.details.subtracting([.overview, .year])
        hold = ScreenSaverDraft.timelineHoldRange.clamp(context.draft.timelineHold)
        pixelSize = ScreenSaverSceneLoader.pixelLimit(
            geometry.posterSize.height * TimelineGeometry.emphasis * context.scale, 1_500)
        var random = ScreenSaverRandomGenerator(state: context.seed)
        centre = order.isEmpty ? 0 : Int.random(in: 0..<order.count, using: &random)
    }

    /// The first four-digit number in the year label, such as 2011 in "2011年".
    static func year(of entry: ScreenSaverManifest.Entry) -> Int? {
        guard let label = entry.year else { return nil }
        var digits = ""
        for character in label {
            if character.isASCII, character.isNumber {
                digits.append(character)
                if digits.count == 4 { return Int(digits) }
            } else {
                digits = ""
            }
        }
        return nil
    }

    mutating func next(image: ScreenSaverImageLoader) -> (step: any ScreenSaverStageStep, duration: TimeInterval)? {
        guard !order.isEmpty else { return nil }
        let size = pixelSize
        // A small library repeats around the line so the pan never shows a gap.
        func slot(_ position: Int) -> TimelineSlot? {
            let index = order[((position % order.count) + order.count) % order.count]
            guard let poster = image(entries[index].poster, size) else { return nil }
            return TimelineSlot(
                position: position, entry: entries[index], poster: poster,
                samples: ScreenSaverArt.samples(of: poster, columns: 3, rows: 3))
        }
        if opened {
            centre += 1
            return slot(centre + geometry.reach).map { (TimelineStep.advance(incoming: $0), hold) }
        }
        let slots = (centre - geometry.reach...centre + geometry.reach).compactMap(slot)
        guard !slots.isEmpty else { return nil }
        opened = true
        return (TimelineStep.open(geometry, slots, centre: centre, details: details), hold)
    }
}

@MainActor
final class TimelineStage: ScreenSaverStage {
    let usesWash = true
    private struct Placed {
        let slot: TimelineSlot
        let group: CALayer
        let poster: CALayer
        let shade: CALayer
        let label: CALayer?
    }

    let layer = CALayer()
    private let geometry: TimelineGeometry
    private let details: Set<ScreenSaverManifest.Detail>
    private let layouts: ScreenSaverLayouts
    private let strip = CALayer()
    private let firstCentre: Int
    private var centre: Int
    private var placed: [Placed] = []
    private let wash: ScreenSaverWash
    private var caption: CALayer?

    private var unit: CGFloat { min(geometry.size.width, geometry.size.height) }

    init(
        geometry: TimelineGeometry, slots: [TimelineSlot], centre: Int, details: Set<ScreenSaverManifest.Detail>,
        scale: CGFloat, wash: ScreenSaverWash
    ) {
        self.geometry = geometry
        self.wash = wash
        self.details = details
        self.centre = centre
        firstCentre = centre
        layouts = ScreenSaverLayouts(size: geometry.size, scale: scale)

        // No ground: the renderer's wash flows behind the line.
        layer.frame = CGRect(origin: .zero, size: geometry.size)
        layer.masksToBounds = true

        let line = CALayer()
        let thickness = max(unit * 0.0016, 0.5)
        line.frame = CGRect(x: 0, y: geometry.lineY - thickness / 2, width: geometry.size.width, height: thickness)
        line.backgroundColor = CGColor(gray: 1, alpha: 0.2)
        layer.addSublayer(line)

        strip.anchorPoint = .zero
        strip.bounds = layer.bounds
        strip.position = .zero
        layer.addSublayer(strip)

        for slot in slots { place(slot) }
        emphasize(animated: false)
        update(animated: false)
    }

    func apply(_ step: any ScreenSaverStageStep) {
        guard case .advance(let incoming) = step as? TimelineStep else { return }
        centre += 1
        place(incoming)
        // Keep one poster beyond the left edge for the length of the pan.
        let first = centre - geometry.reach - 1
        placed.removeAll { item in
            guard item.slot.position < first else { return false }
            item.group.removeFromSuperlayer()
            return true
        }
        strip.animate(
            "position.x", to: -CGFloat(centre - firstCentre) * geometry.pitch, duration: 2.6)
        emphasize(animated: true)
        update(animated: true)
    }

    private func place(_ slot: TimelineSlot) {
        let above = geometry.isAbove(slot.position)
        let x = geometry.size.width / 2 + CGFloat(slot.position - firstCentre) * geometry.pitch
        let group = CALayer()
        group.frame = strip.bounds

        let thin = max(unit * 0.0016, 0.5)
        let stem = CALayer()
        stem.backgroundColor = CGColor(gray: 1, alpha: 0.2)
        stem.frame = CGRect(
            x: x - thin / 2, y: above ? geometry.lineY : geometry.lineY - geometry.stem, width: thin,
            height: geometry.stem)
        group.addSublayer(stem)

        let dotSize = unit * 0.009
        let dot = CALayer()
        dot.frame = CGRect(x: x - dotSize / 2, y: geometry.lineY - dotSize / 2, width: dotSize, height: dotSize)
        dot.cornerRadius = dotSize / 2
        dot.backgroundColor = CGColor(gray: 1, alpha: 0.7)
        group.addSublayer(dot)

        // Posters grow away from the line, from the end of their stem.
        let poster = CALayer()
        poster.bounds = CGRect(origin: .zero, size: geometry.posterSize)
        poster.anchorPoint = CGPoint(x: 0.5, y: above ? 0 : 1)
        poster.position = CGPoint(
            x: x, y: above ? geometry.lineY + geometry.stem : geometry.lineY - geometry.stem)
        let radius = geometry.posterSize.width * 0.03
        poster.shadowColor = CGColor(gray: 0, alpha: 1)
        poster.shadowOpacity = 0.45
        poster.shadowRadius = unit * 0.015
        poster.shadowPath = CGPath(
            roundedRect: poster.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let art = CALayer()
        art.frame = poster.bounds
        art.contents = slot.poster
        art.contentsGravity = .resizeAspectFill
        art.cornerRadius = radius
        art.masksToBounds = true
        poster.addSublayer(art)
        let shade = CALayer()
        shade.frame = poster.bounds
        shade.cornerRadius = radius
        shade.backgroundColor = CGColor(gray: 0, alpha: 1)
        shade.opacity = 0.5
        poster.addSublayer(shade)
        group.addSublayer(poster)

        // The date sits across the line from its poster, inside the stem's gap.
        let label = layouts.textLayer(
            slot.entry.year, width: geometry.pitch * 1.4, size: unit * 0.017, weight: .medium, alpha: 0.9,
            lines: 1, center: true)
        if let label {
            let gap = unit * 0.008
            label.frame.origin = CGPoint(
                x: x - label.bounds.width / 2,
                y: above ? geometry.lineY - gap - label.bounds.height : geometry.lineY + gap)
            label.opacity = 0.45
            group.addSublayer(label)
        }

        strip.addSublayer(group)
        placed.append(Placed(slot: slot, group: group, poster: poster, shade: shade, label: label))
    }

    private func emphasize(animated: Bool) {
        for item in placed {
            let focused = item.slot.position == centre
            let scale = focused ? TimelineGeometry.emphasis : 1
            let transform = CATransform3DMakeScale(scale, scale, 1)
            let shade: Float = focused ? 0 : 0.5
            let label: Float = focused ? 1 : 0.45
            if animated {
                item.poster.animate("transform", to: transform, duration: 2.2, delay: 0.3)
                item.shade.animate("opacity", to: shade, duration: 2.2, delay: 0.3)
                item.label?.animate("opacity", to: label, duration: 1.6, delay: 0.6)
            } else {
                item.poster.transform = transform
                item.shade.opacity = shade
                item.label?.opacity = label
            }
            // The emphasised poster overlaps its neighbours.
            item.group.zPosition = focused ? 1 : 0
        }
    }

    private func update(animated: Bool) {
        guard let slot = placed.first(where: { $0.slot.position == centre })?.slot else { return }
        wash.show(.shaded(slot.samples, columns: 3, rows: 3, brightness: 0.4))

        let text = CALayer()
        text.frame = layer.bounds
        let width = min(geometry.size.width * 0.8, unit * 1.2)
        var lines = layouts.posterFocusLines(slot.entry, details: details, width: width)
        if let title = lines.first, title.weight == .bold {
            lines[0] = .init(
                text: title.text,
                size: layouts.fittedTitle(title.text, width: width, largest: 0.042, smallest: 0.028),
                weight: .bold, alpha: title.alpha, lines: 2)
        }
        let block = layouts.stack(lines, width: width, center: true)
        let band = geometry.captionBand
        layouts.place(block, x: (geometry.size.width - width) / 2, top: band.midY + block.height / 2, in: text)
        crossfade(from: caption, to: text, at: nil, animated: animated)
        caption = text
    }

    private func crossfade(from old: CALayer?, to next: CALayer, at index: UInt32?, animated: Bool) {
        if let index { layer.insertSublayer(next, at: index) } else { layer.addSublayer(next) }
        guard let old else { return }
        guard animated else {
            old.removeFromSuperlayer()
            return
        }
        next.opacity = 0
        next.animate("opacity", to: 1, duration: 1.2, delay: 0.9)
        CATransaction.begin()
        CATransaction.setCompletionBlock { old.removeFromSuperlayer() }
        old.animate("opacity", to: 0, duration: 0.8)
        CATransaction.commit()
    }
}
