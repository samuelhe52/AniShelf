//
//  Timeline.swift
//  AniShelf
//
//  Created by Claude Code on behalf of Samuel He on 2026/11/21.
//

import CoreText
import Foundation
import QuartzCore

/// Posters are evenly spaced by order, not by date, so a busy year does not pile up.
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

enum TimelineMarker: Equatable, Sendable {
    case year(Int)
    case wrap(Int)

    var text: String {
        switch self {
        case .year(let year): year.formatted(.number.grouping(.never))
        case .wrap(let year): "↻ " + year.formatted(.number.grouping(.never))
        }
    }
}

struct TimelineSlot: Sendable {
    let position: Int
    let entry: ScreenSaverManifest.Entry
    /// The caption's date line; see `TimelineDateText`.
    let dateText: String
    let poster: CGImage
    let marker: TimelineMarker?
    /// The poster's colour in each cell of a 3 × 3 grid, for the wash.
    let samples: [ScreenSaverColor]
}

extension ScreenSaverManifest.TimelineDateSource {
    var timeZone: TimeZone { self == .airDate ? .gmt : .current }
}

extension ScreenSaverManifest.TimelineDatePrecision {
    func formatStyle(calendar: Calendar) -> Date.FormatStyle {
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        switch self {
        case .year: return style.year()
        case .yearAndMonth: return style.year().month(.abbreviated)
        case .fullDate: return style.year().month(.abbreviated).day()
        }
    }

    func intervalStyle(calendar: Calendar) -> Date.IntervalFormatStyle {
        let style = Date.IntervalFormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        switch self {
        case .year: return style.year()
        case .yearAndMonth: return style.year().month(.abbreviated)
        case .fullDate: return style.year().month(.abbreviated).day()
        }
    }
}

/// The caption's date: one air date, or the watch dates as a range. A range with one missing end
/// stays open on that side, such as "Jun 2, 2024 –".
struct TimelineDateText: Sendable {
    let source: ScreenSaverManifest.TimelineDateSource
    let date: Date.FormatStyle
    let interval: Date.IntervalFormatStyle

    init(source: ScreenSaverManifest.TimelineDateSource, precision: ScreenSaverManifest.TimelineDatePrecision) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = source.timeZone
        self.source = source
        date = precision.formatStyle(calendar: calendar)
        interval = precision.intervalStyle(calendar: calendar)
    }

    /// In the snapshot's information language.
    func text(for entry: ScreenSaverManifest.Entry) -> String? {
        let locale = entry.dateLocaleIdentifier.map(Locale.init(identifier:)) ?? .current
        let date = date.locale(locale)
        switch (source, entry.watchStartDate, entry.watchEndDate) {
        case (.airDate, _, _):
            return entry.airDate?.formatted(date)
        case (.watchDates, let start?, let end?):
            return (min(start, end)..<max(start, end)).formatted(interval.locale(locale))
        case (.watchDates, let start?, nil):
            return start.formatted(date) + String(separator(locale).reversed().drop(while: \.isWhitespace).reversed())
        case (.watchDates, nil, let end?):
            return String(separator(locale).drop(while: \.isWhitespace)) + end.formatted(date)
        case (.watchDates, nil, nil):
            return nil
        }
    }

    /// The language's own range separator, such as " – " or "～", read from a formatted range so
    /// open ranges match closed ones.
    private func separator(_ locale: Locale) -> String {
        // A year apart, so the formatter cannot merge the two ends.
        let range = Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 400 * 86_400)
        let whole = range.formatted(interval.locale(locale))
        let start = range.lowerBound.formatted(date.locale(locale))
        let end = range.upperBound.formatted(date.locale(locale))
        guard whole.hasPrefix(start), whole.hasSuffix(end), whole.count > start.count + end.count else {
            return " – "
        }
        return String(whole.dropFirst(start.count).dropLast(end.count))
    }
}

enum TimelineStep: ScreenSaverStageStep {
    static let panDuration: TimeInterval = 2.6

    case open(TimelineGeometry, [TimelineSlot], details: Set<ScreenSaverManifest.Detail>)
    /// The line moves one place left; `incoming` enters at the right.
    case advance(incoming: TimelineSlot)

    @MainActor func makeStage(size: CGSize, scale: CGFloat, wash: ScreenSaverWash) -> (any ScreenSaverStage)? {
        guard case .open(let geometry, let slots, let details) = self else { return nil }
        return TimelineStage(geometry: geometry, slots: slots, details: details, scale: scale, wash: wash)
    }
}

struct TimelineDirector: ScreenSaverStageDirector {
    private let entries: [ScreenSaverManifest.Entry]
    private struct DatedEntry {
        let index: Int
        let date: Date
        let year: Int
    }

    /// Indices into `entries`, in chronological order; entries without the chosen date are left out.
    private let order: [DatedEntry]
    private let geometry: TimelineGeometry
    private let details: Set<ScreenSaverManifest.Detail>
    private let dates: TimelineDateText
    private let hold: TimeInterval
    private let pixelSize: Int
    private var nextIndex: Int
    private var nextPosition: Int
    private var lastIndex: Int?
    private var unreadablePosters: Set<String> = []
    private var opened = false

    init(_ context: ScreenSaverStageContext) {
        entries = context.entries
        let source = context.settings.timelineDateSource
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = source.timeZone
        dates = TimelineDateText(source: source, precision: context.settings.timelineDatePrecision)
        order = context.entries.enumerated().compactMap { index, entry in
            source.date(for: entry).map {
                DatedEntry(index: index, date: $0, year: calendar.component(.year, from: $0))
            }
        }.sorted { ($0.date, context.entries[$0.index].id) < ($1.date, context.entries[$1.index].id) }
        geometry = TimelineGeometry(size: context.size)
        details = context.details
        hold = context.settings.timelineHold
        pixelSize = ScreenSaverSceneLoader.pixelLimit(
            geometry.posterSize.height * TimelineGeometry.emphasis * context.scale, 1_500)
        var random = ScreenSaverRandomGenerator(state: context.seed)
        nextIndex = order.isEmpty ? 0 : Int.random(in: order.indices, using: &random)
        nextPosition = -geometry.reach
    }

    private mutating func nextSlot(image: ScreenSaverImageLoader) -> TimelineSlot? {
        for _ in order.indices {
            guard !Task.isCancelled else { return nil }
            let index = nextIndex
            nextIndex = index + 1 == order.count ? 0 : index + 1
            let dated = order[index]
            let entry = entries[dated.index]
            guard !unreadablePosters.contains(entry.poster) else { continue }
            guard let poster = image(entry.poster, pixelSize) else {
                unreadablePosters.insert(entry.poster)
                continue
            }
            let marker: TimelineMarker?
            if let lastIndex, index < lastIndex {
                marker = .wrap(dated.year)
            } else if let lastIndex, dated.year != order[lastIndex].year {
                marker = .year(dated.year)
            } else {
                marker = nil
            }
            let position = nextPosition
            nextPosition += 1
            lastIndex = index
            return TimelineSlot(
                position: position, entry: entry,
                dateText: dates.text(for: entry) ?? "",
                poster: poster, marker: marker,
                samples: ScreenSaverArt.samples(of: poster, columns: 3, rows: 3))
        }
        return nil
    }

    mutating func next(image: ScreenSaverImageLoader) -> (step: any ScreenSaverStageStep, duration: TimeInterval)? {
        if opened {
            return nextSlot(image: image).map { (TimelineStep.advance(incoming: $0), TimelineStep.panDuration + hold) }
        }
        // Repeat a small library around the line so the pan never shows a gap.
        var slots: [TimelineSlot] = []
        slots.reserveCapacity(geometry.reach * 2 + 1)
        while nextPosition <= geometry.reach {
            guard let slot = nextSlot(image: image) else { return nil }
            slots.append(slot)
        }
        opened = true
        return (TimelineStep.open(geometry, slots, details: details), hold)
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
    }

    let layer = CALayer()
    private let geometry: TimelineGeometry
    private let details: Set<ScreenSaverManifest.Detail>
    private let layouts: ScreenSaverLayouts
    private let strip = CALayer()
    private var centre = 0
    private var placed: [Int: Placed] = [:]
    private let wash: ScreenSaverWash
    private var caption: CALayer?

    private var unit: CGFloat { min(geometry.size.width, geometry.size.height) }

    init(
        geometry: TimelineGeometry, slots: [TimelineSlot], details: Set<ScreenSaverManifest.Detail>,
        scale: CGFloat, wash: ScreenSaverWash
    ) {
        self.geometry = geometry
        self.wash = wash
        self.details = details.subtracting([.year])
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

        placed.reserveCapacity(slots.count + 1)
        for slot in slots { place(slot) }
        if let focused = placed[centre] {
            emphasize(focused, focused: true, animated: false)
            updateCaption(for: focused.slot)
        }
    }

    func apply(_ step: any ScreenSaverStageStep) {
        guard case .advance(let incoming) = step as? TimelineStep else { return }
        let outgoing = placed[centre]
        centre += 1
        // Keep one poster beyond the left edge for the length of the pan.
        placed.removeValue(forKey: centre - geometry.reach - 2)?.group.removeFromSuperlayer()
        place(incoming)
        strip.animate("position.x", to: -CGFloat(centre) * geometry.pitch, duration: TimelineStep.panDuration)
        if let outgoing { emphasize(outgoing, focused: false, animated: true) }
        if let focused = placed[centre] {
            emphasize(focused, focused: true, animated: true)
            updateCaption(for: focused.slot)
        }
    }

    private func place(_ slot: TimelineSlot) {
        let above = geometry.isAbove(slot.position)
        let x = geometry.size.width / 2 + CGFloat(slot.position) * geometry.pitch
        let group = CALayer()
        group.frame = strip.bounds

        let thin = max(unit * 0.0016, 0.5)
        let stem = CALayer()
        stem.backgroundColor = CGColor(gray: 1, alpha: 0.2)
        stem.frame = CGRect(
            x: x - thin / 2, y: above ? geometry.lineY : geometry.lineY - geometry.stem, width: thin,
            height: geometry.stem)
        group.addSublayer(stem)

        group.addSublayer(railMark(slot.marker, at: x))

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

        strip.addSublayer(group)
        placed[slot.position] = Placed(slot: slot, group: group, poster: poster, shade: shade)
    }

    private func railMark(_ marker: TimelineMarker?, at x: CGFloat) -> CALayer {
        let mark = CALayer()
        let position = CGPoint(x: x, y: geometry.lineY)
        let width = geometry.pitch * 0.85
        if let marker,
            let text = layouts.fittedText(
                marker.text, width: width, size: min(unit * 0.017, width * 0.19),
                weight: .semibold, lines: 1, center: true),
            let label = layouts.textLayer(text)
        {
            let height = label.bounds.height + unit * 0.006
            mark.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            mark.cornerRadius = height / 2
            mark.backgroundColor = CGColor(gray: 0.07, alpha: 1)
            mark.borderWidth = max(unit * 0.001, 0.5)
            if case .wrap = marker {
                mark.borderColor = CGColor(gray: 1, alpha: 0.65)
            } else {
                mark.borderColor = CGColor(gray: 1, alpha: 0.25)
            }
            label.position = CGPoint(x: width / 2, y: height / 2 + badgeInkOffsetY(text))
            mark.addSublayer(label)
        } else {
            let dotSize = unit * 0.009
            mark.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
            mark.cornerRadius = dotSize / 2
            mark.backgroundColor = CGColor(gray: 1, alpha: 0.7)
        }
        mark.position = position
        return mark
    }

    private func badgeInkOffsetY(_ text: ScreenSaverLayouts.FittedText) -> CGFloat {
        guard let lines = CTFrameGetLines(text.frame) as? [CTLine], lines.count == 1, let line = lines.first
        else { return 0 }
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        guard !ink.isEmpty else { return 0 }

        // Center the glyphs, not the line box with its descender padding.
        var origin = CGPoint.zero
        CTFrameGetLineOrigins(text.frame, CFRange(location: 0, length: 1), &origin)
        return text.height / 2 - (origin.y + ink.midY)
    }

    private func emphasize(_ item: Placed, focused: Bool, animated: Bool) {
        let scale = focused ? TimelineGeometry.emphasis : 1
        let transform = CATransform3DMakeScale(scale, scale, 1)
        let shade: Float = focused ? 0 : 0.5
        if animated {
            let delay: TimeInterval = 0.3
            let duration = TimelineStep.panDuration - delay
            item.poster.animate("transform", to: transform, duration: duration, delay: delay)
            item.shade.animate("opacity", to: shade, duration: duration, delay: delay)
        } else {
            item.poster.transform = transform
            item.shade.opacity = shade
        }
        // The emphasised poster overlaps its neighbours.
        item.group.zPosition = focused ? 1 : 0
    }

    private func updateCaption(for slot: TimelineSlot) {
        wash.show(.shaded(slot.samples, columns: 3, rows: 3, brightness: 0.4))

        let entry = slot.entry
        let band = geometry.captionBand
        let width = min(geometry.size.width * 0.8, unit * 1.2)
        var lines: [ScreenSaverLayouts.Line] = []
        if let title = entry.title, !title.isEmpty {
            lines.append(
                .init(
                    text: title, size: layouts.fittedTitle(title, width: width, largest: 0.042, smallest: 0.028),
                    weight: .bold, alpha: 0.97, lines: 2))
        }
        let tagline = layouts.captionTagline(entry, details: details, size: unit * 0.024)
        if let tagline {
            lines.append(tagline)
        }
        let date = slot.dateText
        let subtitle =
            if details.contains(.season), let season = entry.season, !season.isEmpty {
                date + ScreenSaverLayouts.separator + season
            } else {
                date
            }
        if tagline != nil {
            // Group the date and facts as metadata instead of giving the date a second headline weight.
            lines.append(
                .init(text: subtitle, size: unit * 0.018, weight: .regular, alpha: 0.65, spaceBefore: unit * 0.028))
        } else {
            lines.append(
                .init(text: subtitle, size: unit * 0.023, weight: .medium, alpha: 0.84, spaceBefore: unit * 0.006))
        }
        let facts = layouts.factsLine(entry, details: details)
        if !facts.isEmpty {
            lines.append(
                .init(
                    text: facts, size: unit * 0.018, weight: .regular, alpha: 0.65, lines: 2,
                    spaceBefore: unit * (tagline == nil ? 0.012 : 0.004))
            )
        }

        let block = layouts.stack(lines, width: width, center: true)
        let text = CALayer()
        text.bounds = CGRect(x: 0, y: 0, width: width, height: block.height)
        text.position = CGPoint(x: band.midX, y: band.midY)
        if block.height > band.height {
            let scale = band.height / block.height
            text.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
        layouts.place(block, x: 0, top: block.height, in: text)
        layer.addSublayer(text)
        if let caption { crossfade(from: caption, to: text) }
        caption = text
    }

    private func crossfade(from old: CALayer, to next: CALayer) {
        next.opacity = 0
        let delay: TimeInterval = 0.6
        next.animate("opacity", to: 1, duration: TimelineStep.panDuration - delay, delay: delay)
        CATransaction.begin()
        CATransaction.setCompletionBlock { old.removeFromSuperlayer() }
        old.animate("opacity", to: 0, duration: 0.9)
        CATransaction.commit()
    }
}
